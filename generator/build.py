#!/usr/bin/env python3
"""Build the addon's generated files.

    uv run python generator/build.py            # write every generated file
    uv run python generator/build.py --check    # fail if a committed file would change

Writes the data files and the toc of the addon, and the whole of the data
addon, which holds the large tables and loads only when first needed. The
addon's name is declared here once, and the folders and tocs follow from it.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import duckdb
import lua
import tables
from source import ROOT, connect, epsilon_emotes

#: The addon's name: its folder, its toc, and the stem of every global it creates.
ADDON = "Glimpse"
DATA_ADDON = f"{ADDON}_Data"
INTERFACE = 90207
#: Where the version goes in each toc: the release packager writes the tag there.
VERSION = "@project-version@"

#: The addon's hand-written files in load order. A layer loads after the ones it may use.
CODE: tuple[str, ...] = (
    "Core/Safely.lua",
    "Core/Packed.lua",
    "Core/Lines.lua",
    "Core/Subject.lua",
    "Core/Providers.lua",
    "Core/Kinds.lua",
    "Core/Links.lua",
    "Core/Async.lua",
    "Client.lua",
    "Resolvers/Object.lua",
    "Resolvers/Item.lua",
    "Resolvers/Direct.lua",
    "Resolvers/Sound.lua",
    "Resolvers/Area.lua",
    "Resolvers/Offered.lua",
    "Interface/Settings.lua",
    "Interface/Tools.lua",
    "Interface/Presentations.lua",
    "Interface/Stage.lua",
    "Interface/Peek.lua",
    "Interface/Window.lua",
    "Interface/Playback.lua",
    "Interface/Chat.lua",
    "Interface/Options.lua",
    "Interface/Start.lua",
    "Interface/API.lua",
)

#: The generated data files of the main addon, in load order.
DATA = (
    "Data/Formats.lua",
    "Data/Sounds.lua",
    "Data/Enchants.lua",
    "Data/Emotes.lua",
    "Data/Areas.lua",
)

#: The layout of the data addon. Both addons carry it, and the main one uses the data only
#: where the two agree, so a folder updated without the other is ignored rather than misread.
#: Raise it whenever the packed tables or their fields change.
DATA_FORMAT = 14

#: The packed tables: each field's width in digits, and the offset it is stored with. A value
#: that outgrows its width fails the build.
PACKED: dict[str, tuple[tuple[int, ...], tuple[int, ...]]] = {
    "objects": ((6, 7), (0, 0)),  # gameobject entry, model file
    "creatures": ((6, 6), (0, 0)),  # creature entry, display
    "characters": ((7,), (0,)),  # display
}


def main_toc() -> str:
    """The main addon's toc: its metadata, then data before the code that reads it.

    GLink is named as an optional dependency so that, where it is installed, it
    loads first and its buttons stay where players are used to finding them.
    Epsilook, which previews spells, is read when a spell line is seen, so its
    order does not matter and it is not named.
    """
    lines = [
        f"## Interface: {INTERFACE}",
        f"## Title: {ADDON}",
        "## Notes: Previews for the results of .lookup.",
        f"## Version: {VERSION}",
        "## Author: Nataari",
        "## X-License: AGPL-3.0-or-later",
        "## OptionalDeps: GLink",
        f"## SavedVariables: {ADDON}Settings, {ADDON}Faults",
        "",
        *(name.replace("/", "\\") for name in (*DATA, *CODE)),
    ]
    return "\n".join(lines) + "\n"


def data_toc() -> str:
    """The data addon's toc; it loads only when the main addon asks for it."""
    lines = [
        f"## Interface: {INTERFACE}",
        f"## Title: {ADDON} data",
        f"## Notes: Objects and creatures for {ADDON}. Loaded on demand.",
        f"## Version: {VERSION}",
        f"## Dependencies: {ADDON}",
        "## LoadOnDemand: 1",
        "",
        "Data.lua",
    ]
    return "\n".join(lines) + "\n"


def main_data(con: duckdb.DuckDBPyConnection) -> dict[str, str]:
    """The main addon's data files by path under the addon folder."""
    head = lua.HEADER + "local _, ns = ...\nns.Data = ns.Data or {}\n"
    sounds = (
        f"ns.Data.Music = {lua.plain(tables.music())}\n"
        f"ns.Data.Intro = {lua.plain(tables.intro())}\n"
        f"ns.Data.Ambience = {lua.plain(tables.ambience(con))}\n"
    )
    enchants = dict.fromkeys(tables.enchants_without_visual(con), True)
    animations = tables.animations(con)
    wielding = dict.fromkeys(tables.wielding_animations(con), True)
    unruled = tables.unruled_emotes(tables.emotes(con, epsilon_emotes()), animations)
    return {
        "Data/Formats.lua": head + f"ns.Data.Format = {DATA_FORMAT}\n",
        "Data/Sounds.lua": head + sounds,
        "Data/Enchants.lua": head + f"ns.Data.EnchantsWithoutVisual = {lua.plain(enchants)}\n",
        "Data/Areas.lua": head + f"ns.Data.AreaMaps = {lua.plain(tables.area_maps(con))}\n",
        "Data/Emotes.lua": head
        + f"ns.Data.EmoteAnimations = {lua.plain(unruled)}\n"
        + f"ns.Data.EmoteBases = {lua.plain(list(tables.EMOTE_BASES))}\n"
        + f"ns.Data.AnimationCount = {len(animations)}\n"
        + f"ns.Data.WieldingAnimations = {lua.plain(wielding)}\n"
        + f"ns.Data.GroundedAnimations = {lua.plain(tables.grounded_animations(con))}\n",
    }


def data_rows(con: duckdb.DuckDBPyConnection) -> dict[str, list[tuple[int, ...]]]:
    """The packed tables as rows: the objects, the creatures and the characters' displays."""
    return {
        "objects": list(tables.object_files(con).items()),
        "creatures": tables.creature_displays(con),
        "characters": list(tables.character_displays(con)),
    }


def data_file(con: duckdb.DuckDBPyConnection) -> str:
    """The data addon's one Lua file: the models by name and the packed tables."""
    rows = data_rows(con)
    body = ",\n".join(
        f"\t{name} = {lua.packed_table(rows[name], widths, offsets)}"
        for name, (widths, offsets) in PACKED.items()
    )
    models = lua.keyed(tables.model_files(con))
    head = f"\tformat = {DATA_FORMAT},\n\tmodels = {models},\n"
    return f"{lua.HEADER}{DATA_ADDON} = {{\n{head}{body},\n}}\n"


def outputs() -> dict[Path, str]:
    """Every generated file by its path, with the text it should hold."""
    con = connect()
    files = {ROOT / ADDON / name: text for name, text in main_data(con).items()}
    files[ROOT / ADDON / f"{ADDON}.toc"] = main_toc()
    files[ROOT / DATA_ADDON / f"{DATA_ADDON}.toc"] = data_toc()
    files[ROOT / DATA_ADDON / "Data.lua"] = data_file(con)
    return files


def main() -> int:
    """Write the generated files, or with `--check` report the committed ones that are stale."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail if a committed file is stale")
    args = parser.parse_args()

    stale = []
    for path, text in outputs().items():
        shown = path.relative_to(ROOT).as_posix()
        if args.check:
            if not path.is_file() or path.read_text(encoding="utf-8") != text:
                stale.append(shown)
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")
        print(f"{len(text.encode('utf-8')):>9,} bytes  {shown}")
    for shown in stale:
        print(f"stale: {shown}")
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
