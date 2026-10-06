"""The generated data, loaded under Lua 5.1 and held against what the game showed.

Each expected value below was observed in game: the id is what a `.lookup`
line printed, and the sound kit, visual kit or animation is what then played
or drew when it was handed to the client.

The packed tables are decoded here in Python, apart from the addon's own
reader, so the two are checked against each other by the addon's tests.
"""

from __future__ import annotations

from collections.abc import Callable, Iterator
from typing import cast

import build
import pytest
import tables
from support import ROOT, LuaRuntime, evaluate, load_addon, new_runtime

DATA_FILE = ROOT / build.DATA_ADDON / "Data.lua"

#: The loaded data addon may take this much memory; packed, everything it holds takes about 4.4.
MEMORY_BUDGET_MB = 5.0


@pytest.fixture(scope="module")
def data() -> LuaRuntime:
    """The addon, loaded the way the client loads it, with its data under `NS.Data`."""
    return load_addon()


def test_music_plays_what_the_game_played(data: LuaRuntime) -> None:
    assert evaluate(data, "NS.Data.Music[156]") == {
        "day": 4516,
        "night": 4516,
        "name": "Zone-TavernAlliance",
    }


def test_intro_is_told_from_music_by_name(data: LuaRuntime) -> None:
    assert evaluate(data, "NS.Data.Intro[122]") == {
        "day": 6837,
        "night": 0,
        "name": "Stormwind-Southseas",
    }
    clashes = evaluate(
        data,
        """(function()
            local shared, same = 0, 0
            for id, music in pairs(NS.Data.Music) do
                local intro = NS.Data.Intro[id]
                if intro then
                    shared = shared + 1
                    if intro.name:lower() == music.name:lower() then same = same + 1 end
                end
            end
            return { shared = shared, same = same }
        end)()""",
    )
    assert isinstance(clashes, dict)
    assert cast(int, clashes["shared"]) > 100, "the id spaces overlap, so the name has to decide"
    assert clashes["same"] == 0


def test_ambience_has_day_and_night_and_their_printed_names(data: LuaRuntime) -> None:
    assert evaluate(data, "NS.Data.Ambience[28]") == {
        "day": 4170,
        "night": 4171,
        "names": ["forestdarkenchantedday", "forestdarkenchantednight"],
    }


def test_the_addon_is_told_how_many_animations_there_are(data: LuaRuntime) -> None:
    count = evaluate(data, "NS.Data.AnimationCount")
    assert isinstance(count, int) and count > 1700, "the emote rule believes in these and no more"


def test_a_flying_animation_names_its_ground_twin(data: LuaRuntime) -> None:
    grounded = "NS.Data.GroundedAnimations"
    assert evaluate(data, f"{grounded}[246]") == 17, "FlyAttack1H"
    assert evaluate(data, f"{grounded}[1067]") == 1066, "FlyArtLoop"
    assert evaluate(data, f"{grounded}[17]") is None, "a ground animation is its own"


def test_emotes_reach_their_animation(data: LuaRuntime) -> None:
    animations = "NS.Data.EmoteAnimations"
    assert evaluate(data, f"{{ {animations}[10], {animations}[94], {animations}[400] }}") == [
        69,
        69,
        211,
    ]


def test_only_the_emotes_the_rule_gets_wrong_are_shipped() -> None:
    animations = {7, 69, 1909}
    emotes = {10: 69, 2069: 69, 4069: 69, 5909: 7}
    assert tables.ruled_animation(4069, animations) == 69
    assert tables.ruled_animation(2069, animations) == 69
    assert tables.ruled_animation(10, animations) is None, "below every base: the client's own"
    assert tables.ruled_animation(4500, animations) is None, "no such animation"
    assert tables.unruled_emotes(emotes, animations) == {10: 69, 5909: 7}


def test_the_shipped_emotes_and_the_rule_give_every_emote_its_animation(data: LuaRuntime) -> None:
    assert evaluate(data, "NS.Data.EmoteBases") == [4000, 2000]
    animations = "NS.Data.EmoteAnimations"
    assert evaluate(data, f"{animations}[4426]") is None, "the rule gives it, so it is not shipped"
    assert evaluate(data, f"{animations}[10]") == 69


def test_an_area_is_shown_on_its_own_map_or_else_its_zones(data: LuaRuntime) -> None:
    assert evaluate(data, "NS.Data.AreaMaps[12]") == 37, "Elwynn Forest, its own map"
    assert evaluate(data, "NS.Data.AreaMaps[1519]") == 84, "Stormwind City, not the continent"
    assert evaluate(data, "NS.Data.AreaMaps[87]") == 37, "Goldshire, on Elwynn Forest's"
    assert evaluate(data, "NS.Data.AreaMaps[6510]") == 52, "the Deadmines' way in, in Westfall"


def test_an_instance_area_is_shown_on_its_dungeon_floor(data: LuaRuntime) -> None:
    assert evaluate(data, "NS.Data.AreaMaps[1581]") == 291, "the Deadmines, its first floor"
    assert evaluate(data, "NS.Data.AreaMaps[1582]") == 292, "Ironclad Cove, the floor named so"
    assert evaluate(data, "NS.Data.AreaMaps[2437]") == 213, "Ragefire Chasm"


def test_an_enchant_with_a_visual_is_not_denied(data: LuaRuntime) -> None:
    assert evaluate(data, "NS.Data.EnchantsWithoutVisual[803]") is None, "Fiery Weapon drew"
    assert evaluate(data, "NS.Data.EnchantsWithoutVisual[9001]") is None, "not a stock enchant"


@pytest.fixture(scope="module")
def built() -> tuple[dict[str, object], float]:
    """The data addon's table, and the megabytes of memory loading it took."""
    if not DATA_FILE.is_file():
        pytest.skip("the data addon is missing: run generator/build.py")
    runtime = new_runtime()
    count = cast(
        Callable[[], float],
        runtime.eval(
            b'function() collectgarbage() collectgarbage() return collectgarbage("count") end'
        ),
    )
    before = count()
    runtime.execute(DATA_FILE.read_bytes())
    used = (count() - before) / 1024
    return cast(dict[str, object], evaluate(runtime, build.DATA_ADDON)), used


def rows(table: object) -> Iterator[tuple[int, ...]]:
    """A packed table's records, decoded as its widths and offsets say."""
    packed = cast(dict[str, object], table)
    widths = cast(list[int], packed["widths"])
    offsets = cast(list[int], packed["offsets"])
    records = cast(str, packed["records"])
    size = sum(widths)
    assert len(records) % size == 0
    for start in range(0, len(records), size):
        at, row = start, []
        for width, offset in zip(widths, offsets, strict=True):
            row.append(int(records[at : at + width]) - offset)
            at += width
        yield tuple(row)


def test_the_data_fits_its_memory_budget(built: tuple[dict[str, object], float]) -> None:
    assert built[1] < MEMORY_BUDGET_MB


def test_a_characters_display_is_listed_and_a_beasts_is_not(
    built: tuple[dict[str, object], float],
) -> None:
    characters = {display for (display,) in rows(built[0]["characters"])}
    assert {16199, 16200} <= characters, "a draenei's displays, male and female"
    assert 17697 not in characters, "a golden gryphon's"


def test_both_addons_carry_the_same_data_format(
    data: LuaRuntime, built: tuple[dict[str, object], float]
) -> None:
    assert built[0]["format"] == evaluate(data, "NS.Data.Format") == build.DATA_FORMAT


def test_a_creature_spawning_with_several_displays_has_them(
    built: tuple[dict[str, object], float],
) -> None:
    guard = [display for creature, display in rows(built[0]["creatures"]) if creature == 68]
    assert guard == [3167, 5446, 99389, 99391]


def test_packed_records_are_sorted_for_searching(built: tuple[dict[str, object], float]) -> None:
    for name in build.PACKED:
        found = list(rows(built[0][name]))
        assert found == sorted(found), name
