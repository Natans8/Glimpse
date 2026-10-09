"""The tables the addon ships, read from the client's own and the stock server's."""

from __future__ import annotations

from collections import Counter
from collections.abc import Iterable, Mapping, Set
from typing import NamedTuple

import duckdb
from source import SCHEMA, wago_rows


class ZoneSound(NamedTuple):
    """A zone music or intro entry: its day and night sound kits, and the name the server prints.

    `night` is 0 where the entry has one sound for both.
    """

    day: int
    night: int
    name: str


class Ambience(NamedTuple):
    """A zone ambience entry: its day and night sound kits, and the name printed for each.

    The server prints a kit's sound file name without folder or extension. A
    name is empty where the kit is unset or its file has no known name.
    """

    day: int
    night: int
    names: tuple[str, str]


def music() -> dict[int, ZoneSound]:
    """`.lookup music` id to its sound kits and set name.

    An entry with nothing to play is left out.
    """
    return {
        int(row["ID"]): ZoneSound(int(row["Sounds_0"]), int(row["Sounds_1"]), row["SetName"])
        for row in wago_rows("ZoneMusic")
        if int(row["Sounds_0"]) or int(row["Sounds_1"])
    }


def intro() -> dict[int, ZoneSound]:
    """`.lookup intromusic` id to its one sound kit and its name."""
    return {
        int(row["ID"]): ZoneSound(int(row["SoundID"]), 0, row["Name"])
        for row in wago_rows("ZoneIntroMusicTable")
        if int(row["SoundID"])
    }


def ambience(con: duckdb.DuckDBPyConnection) -> dict[int, Ambience]:
    """`.lookup ambience` id to its sound kits and their printed names.

    An entry with nothing to play is left out. A kit's printed name is that of
    its first sound file.
    """
    rows = [
        (int(row["ID"]), int(row["AmbienceID_0"]), int(row["AmbienceID_1"]))
        for row in wago_rows("SoundAmbience")
        if int(row["AmbienceID_0"]) or int(row["AmbienceID_1"])
    ]
    kits = sorted({kit for _, day, night in rows for kit in (day, night) if kit})
    named = con.execute(
        f"""
        SELECT e."SoundKitID", regexp_extract(lower(l.path), '([^/]+)[.][a-z0-9]+$', 1)
        FROM {SCHEMA}."SoundKitEntry" e
        JOIN ref.listfile l ON l.fid = e."FileDataID"
        WHERE e."SoundKitID" IN ({", ".join(map(str, kits))})
        QUALIFY row_number() OVER (PARTITION BY e."SoundKitID" ORDER BY e."ID") = 1
        """
    ).fetchall()
    names = {int(kit): str(name) for kit, name in named}
    return {
        entry: Ambience(day, night, (names.get(day, ""), names.get(night, "")))
        for entry, day, night in rows
    }


def enchants_without_visual(con: duckdb.DuckDBPyConnection) -> list[int]:
    """Stock enchant ids that draw nothing on a weapon, ascending.

    Only these are denied a preview. An id the client table does not hold is one
    of the server's own enchants, about which the table says nothing.
    """
    rows = con.execute(
        f'SELECT "ID" FROM {SCHEMA}."SpellItemEnchantment" WHERE "ItemVisual" = 0 ORDER BY 1'
    ).fetchall()
    return [int(row[0]) for row in rows]


#: The kinds of map an area may be shown on, by `UiMap.Type`, in the order they are preferred
#: where an area names several: a zone, a dungeon, a micro-dungeon, an orphan. A continent or
#: the world is no area's map, so an area that names only one of those is left out.
MAP_PREFERENCE = {3: 0, 4: 1, 5: 2, 6: 3}


#: The kind of map a dungeon's floors are, by `UiMap.Type`.
DUNGEON = 4

#: The kind of map an outdoor zone is.
ZONE = 3


def instance_floors(con: duckdb.DuckDBPyConnection) -> dict[int, list[tuple[int, str, int]]]:
    """The floors of each instance's dungeon map, by the instance's world map id, as
    `(floor index, floor name, map id)` in floor order.

    A world map is an instance's where the client assigns it dungeon maps and no zone
    map; an outdoor world map with a cave or a crypt drawn as a dungeon is not one.
    """
    rows = con.execute(
        f'SELECT DISTINCT a."MapID", a."UiMapID", m."Type" FROM {SCHEMA}."UiMapAssignment" a '
        f'JOIN {SCHEMA}."UiMap" m ON m."ID" = a."UiMapID"'
    ).fetchall()
    zoned = {int(world) for world, _, kind in rows if int(kind) == ZONE}
    named = {
        int(row["UiMapID"]): (int(row["FloorIndex"]), row["Name_lang"])
        for row in wago_rows("UiMapGroupMember")
    }
    floors: dict[int, list[tuple[int, str, int]]] = {}
    for world, ui_map, kind in rows:
        if int(kind) != DUNGEON or int(world) in zoned:
            continue
        index, name = named.get(int(ui_map), (0, ""))
        floors.setdefault(int(world), []).append((index, name, int(ui_map)))
    return {world: sorted(set(found)) for world, found in floors.items()}


def area_maps(con: duckdb.DuckDBPyConnection) -> dict[int, int]:
    """Each area's map, by area id. In order: the map the client assigns the area to; the
    map of the nearest area above it that has one, as a subzone is drawn on its zone's
    map; and in an instance, the floor of its dungeon map named as the area is, or else
    the first floor, as Ironclad Cove is the Deadmines' second floor.

    An area with none of these has no entry, and so gains no button.
    """
    assigned = con.execute(
        f'SELECT a."AreaID", a."UiMapID", m."Type" FROM {SCHEMA}."UiMapAssignment" a '
        f'JOIN {SCHEMA}."UiMap" m ON m."ID" = a."UiMapID" WHERE a."AreaID" > 0'
    ).fetchall()
    best: dict[int, tuple[int, int]] = {}
    for area, ui_map, kind in assigned:
        if int(kind) not in MAP_PREFERENCE:
            continue
        rank = (MAP_PREFERENCE[int(kind)], int(ui_map))
        if int(area) not in best or rank < best[int(area)]:
            best[int(area)] = rank
    areas = con.execute(
        f'SELECT "ID", "ParentAreaID", "ContinentID", "AreaName_lang" FROM {SCHEMA}."AreaTable"'
    ).fetchall()
    parents = {int(area): int(parent or 0) for area, parent, _, _ in areas}
    floors = instance_floors(con)
    maps: dict[int, int] = {}
    for area, _, world, name in areas:
        seen, at = set(), int(area)
        while at and at not in best and at not in seen:
            seen.add(at)
            at = parents.get(at, 0)
        if at in best:
            maps[int(area)] = best[at][1]
            continue
        found = floors.get(int(world))
        if found:
            same = [ui_map for _, floor, ui_map in found if floor.lower() == str(name).lower()]
            maps[int(area)] = (same or [found[0][2]])[0]
    return dict(sorted(maps.items()))


#: The kinds of map a whole map may open on, by `UiMap.Type`, in the order they are preferred
#: where two hold as much of it: a continent, a zone, a map outside any continent, a dungeon,
#: a micro-dungeon. The world itself is no map's own.
WHOLE_MAP_PREFERENCE = {2: 0, 3: 1, 6: 2, 4: 3, 5: 4}


def map_maps(con: duckdb.DuckDBPyConnection) -> dict[int, int]:
    """Each map's world map, by map id: of the world maps the client assigns the map, one at
    the top, with no ancestor among them, holding the most of the others beneath it, as
    Outland's holds its zones where the Eastern Kingdoms holds only the Blood Elf ones on the
    same map. Ties go by kind, then to the lowest floor, as a dungeon opens on its first.

    A map the client assigns no world map has no entry, and so gains no button.
    """
    parents = {
        int(ui_map): int(parent or 0)
        for ui_map, parent in con.execute(
            f'SELECT "ID", "ParentUiMapID" FROM {SCHEMA}."UiMap"'
        ).fetchall()
    }
    rows = con.execute(
        f'SELECT DISTINCT a."MapID", a."UiMapID", m."Type" FROM {SCHEMA}."UiMapAssignment" a '
        f'JOIN {SCHEMA}."UiMap" m ON m."ID" = a."UiMapID"'
    ).fetchall()
    kinds: dict[int, dict[int, int]] = {}
    for world, ui_map, kind in rows:
        if int(kind) in WHOLE_MAP_PREFERENCE:
            kinds.setdefault(int(world), {})[int(ui_map)] = int(kind)
    floors = {int(row["UiMapID"]): int(row["FloorIndex"]) for row in wago_rows("UiMapGroupMember")}

    maps: dict[int, int] = {}
    for world, assigned in kinds.items():
        held: Counter[int] = Counter()
        for ui_map in assigned:
            top, at, seen = ui_map, parents.get(ui_map, 0), {ui_map}
            while at and at not in seen:
                seen.add(at)
                if at in assigned:
                    top = at
                at = parents.get(at, 0)
            held[top] += 1
        maps[world] = min(
            held,
            key=lambda ui_map: (
                -held[ui_map],
                WHOLE_MAP_PREFERENCE[assigned[ui_map]],
                floors.get(ui_map, 0),
                ui_map,
            ),
        )
    return dict(sorted(maps.items()))


def emotes(
    con: duckdb.DuckDBPyConnection, added: Mapping[int, Mapping[str, int]]
) -> dict[int, int]:
    """`.lookup emote` id to the animation it plays; emotes with no animation are left out.

    The client's own emotes come first. `added` is what Epsilon adds, by
    animation: a one-shot emote and a looping one for nearly every animation the
    client has, which is most of what the command lists; those fill in around them.
    """
    rows = con.execute(
        f'SELECT "ID", "AnimID" FROM {SCHEMA}."Emotes" WHERE "AnimID" > 0 ORDER BY 1'
    ).fetchall()
    found = {int(emote): int(animation) for emote, animation in rows}
    for animation, pair in added.items():
        for emote in pair.values():
            found.setdefault(emote, animation)
    return dict(sorted(found.items()))


#: Where the emotes Epsilon adds begin: an animation's looping emote is the first of
#: these plus the animation, its one-shot emote the second plus it. Highest first.
EMOTE_BASES = (4000, 2000)


def ruled_animation(emote: int, animations: Set[int]) -> int | None:
    """The animation the rule gives an emote, or None where the rule gives none.

    This is the rule the addon applies to an emote its table does not hold, so
    an emote Epsilon adds later is previewed without new data.
    """
    for base in EMOTE_BASES:
        if emote >= base:
            return emote - base if emote - base in animations else None
    return None


def unruled_emotes(emotes: Mapping[int, int], animations: Iterable[int]) -> dict[int, int]:
    """The emotes the rule does not give rightly: the client's own, and the exceptions.

    Only these are shipped; the addon reaches the rest by the rule.
    """
    known = set(animations)
    return {
        emote: animation
        for emote, animation in emotes.items()
        if ruled_animation(emote, known) != animation
    }


#: Every gameobject display whose model is an `.m2`: its id, its file, and the file's name
#: without folder or extension in lower case. A file reaches the addon's model loader only
#: through this, since a file of another kind handed to the loader crashes the client.
M2_DISPLAYS = f"""
    SELECT d."ID" AS display, d."FileDataID" AS file,
           lower(regexp_extract(l.path, '([^/]+)\\.[mM]2$', 1)) AS stem
    FROM {SCHEMA}."GameObjectDisplayInfo" d
    JOIN ref.listfile l ON l.fid = d."FileDataID"
    WHERE lower(l.path) LIKE '%.m2'
"""


def object_files(con: duckdb.DuckDBPyConnection) -> dict[int, int]:
    """Gameobject entry to the model file it draws, for every stock entry whose model is an `.m2`.

    The entries and their displays are the stock server's; the file each display
    names is the client's. Epsilon renames many stock entries after their model
    but keeps the display, which is what makes the entry a sound key.
    """
    rows = con.execute(
        f"""
        SELECT t.entry, m.file
        FROM {SCHEMA}.tdb_gameobject_template t
        JOIN ({M2_DISPLAYS}) m ON m.display = t.displayId
        ORDER BY 1
        """
    ).fetchall()
    return {int(entry): int(file) for entry, file in rows}


def wmo_objects(con: duckdb.DuckDBPyConnection) -> list[tuple[int, ...]]:
    """Every stock gameobject entry whose display is a WMO root, which no model frame draws.

    Such an entry's line reads as an object, and this is what tells the addon to
    hand it to whoever previews WMOs instead. A group file is named `_NNN` after
    its root and is never a display's.
    """
    rows = con.execute(
        f"""
        SELECT DISTINCT t.entry
        FROM {SCHEMA}.tdb_gameobject_template t
        JOIN {SCHEMA}."GameObjectDisplayInfo" d ON d."ID" = t.displayId
        JOIN ref.listfile l ON l.fid = d."FileDataID"
        WHERE lower(l.path) LIKE '%.wmo'
          AND NOT regexp_matches(lower(l.path), '_[0-9]{{3}}(_lod[0-9])?\\.wmo$')
        ORDER BY 1
        """
    ).fetchall()
    return [(int(entry),) for (entry,) in rows]


def model_files(con: duckdb.DuckDBPyConnection) -> dict[str, int]:
    """Every `.m2` model the client's gameobject displays name, by its file name, to its file.

    No two of these files share a name, which this raises on rather than guess.
    """
    rows = con.execute(f"SELECT DISTINCT stem, file FROM ({M2_DISPLAYS})").fetchall()
    found: dict[str, int] = {}
    for name, file in rows:
        if found.setdefault(str(name), int(file)) != int(file):
            raise ValueError(f"two models are named {name}")
    return found


def creature_displays(con: duckdb.DuckDBPyConnection) -> list[tuple[int, ...]]:
    """`(creature, display)` for every stock creature that spawns with one of several displays.

    A display the server never chooses, at a chance of nought, is left out; so is a
    creature with only one, which the client draws from its entry as it is.
    """
    rows = con.execute(
        f"""
        SELECT "CreatureID", "CreatureDisplayID"
        FROM {SCHEMA}.tdb_creature_template_model
        WHERE "Probability" > 0
        QUALIFY count(*) OVER (PARTITION BY "CreatureID") > 1
        ORDER BY 1, 2
        """
    ).fetchall()
    return [(int(creature), int(display)) for creature, display in rows]


#: The animation flags under which the client takes a body's weapons in hand: melee weapons,
#: then a bow. The table shows which: the first is on every attack, parry, block and ready
#: stance with a weapon, and on fishing, and on no unarmed one; the second on the bow's.
WIELDS = 0x1000 | 0x20000


def wielding_animations(con: duckdb.DuckDBPyConnection) -> list[int]:
    """Animations during which the client takes the body's weapons in hand, ascending."""
    rows = con.execute(
        f'SELECT "ID" FROM {SCHEMA}."AnimationData" WHERE "Flags_0" & {WIELDS} <> 0 ORDER BY 1'
    ).fetchall()
    return [int(animation) for (animation,) in rows]


def character_displays(con: duckdb.DuckDBPyConnection) -> list[tuple[int]]:
    """Every creature display of a character's body, ascending.

    A display dressed as a character names its looks through
    `ExtendedDisplayInfoID`, and its model is a playable race's body or one built
    the same way; every display of such a body is taken, dressed or not. A
    scene's actor leaves pieces out of some of these, a model frame of none.
    """
    rows = con.execute(
        f"""
        WITH bodies AS (
            SELECT DISTINCT m."FileDataID" AS file
            FROM {SCHEMA}."CreatureDisplayInfo" d
            JOIN {SCHEMA}."CreatureModelData" m ON m."ID" = d."ModelID"
            WHERE d."ExtendedDisplayInfoID" > 0
        )
        SELECT d."ID"
        FROM {SCHEMA}."CreatureDisplayInfo" d
        JOIN {SCHEMA}."CreatureModelData" m ON m."ID" = d."ModelID"
        WHERE m."FileDataID" IN (SELECT file FROM bodies)
        ORDER BY 1
        """
    ).fetchall()
    return [(int(display),) for (display,) in rows]


def grounded_animations(con: duckdb.DuckDBPyConnection) -> dict[int, int]:
    """Each flying animation to the one a body on the ground plays for it.

    A flying animation names its ground twin as its behaviour; a body on the
    ground plays the twin, and a model frame, which has no flying animations to
    draw, plays nothing for the flying one.
    """
    rows = con.execute(
        f'SELECT "ID", "BehaviorID" FROM {SCHEMA}."AnimationData" '
        'WHERE "BehaviorID" <> "ID" ORDER BY 1'
    ).fetchall()
    return {int(flying): int(ground) for flying, ground in rows}


def animations(con: duckdb.DuckDBPyConnection) -> range:
    """The client's animations, which it numbers from nought with no gaps.

    The addon is told only how many there are, so a gap would make it believe
    in an animation that does not exist; one raises here instead.
    """
    row = con.execute(
        f'SELECT count(*), min("ID"), max("ID") FROM {SCHEMA}."AnimationData"'
    ).fetchone()
    if row is None or row[1] != 0 or row[2] != row[0] - 1:
        raise ValueError(f"the client's animations are not numbered 0 to n-1: {row}")
    return range(int(row[0]))
