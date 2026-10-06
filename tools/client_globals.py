#!/usr/bin/env python3
"""Vendor the list of what the 9.2.7 client offers an addon.

    uv run python tools/client_globals.py <path-to-wowless>

Reads a wowless checkout whose `wow` product is the client's build: its list
of the client's functions and events, and its extract of the client's own
interface code. Writes `tools/client-9.2.7.json`, which `tools/check.py` holds
the addon's calls against, so a call the client does not have fails the check
instead of faulting in someone's game.

A function the client implements natively is in its function list. A global
the client defines in its own Lua or XML is not, so each of those the addon
uses is named below with the definition to look for, and the file it was found
in is recorded. A name whose definition is not found stops the run.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "tools" / "client-9.2.7.json"

#: The build the list must be of: the one Epsilon's client is cut from.
BUILD, TOC = "45745", 90207

#: Globals the client's own interface code defines, by the text of the definition.
INTERFACE = {
    "C_Timer.NewTicker": r"^function C_Timer\.NewTicker\b",
    "C_Timer.NewTimer": r"^function C_Timer\.NewTimer\b",
    "CHAT_FRAMES": r"^CHAT_FRAMES = ",
    "ChatFrame_AddMessageEventFilter": r"^function ChatFrame_AddMessageEventFilter\b",
    "FCF_OpenTemporaryWindow": r"^function FCF_OpenTemporaryWindow\b",
    "GameTooltip": r'<GameTooltip name="GameTooltip"',
    "InterfaceOptions_AddCategory": r"^function InterfaceOptions_AddCategory\b",
    "InterfaceOptionsFrame_OpenToCategory": r"^function InterfaceOptionsFrame_OpenToCategory\b",
    "Item": r"^Item = ",
    "OpenWorldMap": r"^function OpenWorldMap\b",
    "SetItemRef": r"^function SetItemRef\b",
    "SlashCmdList": r"^SlashCmdList = ",
    "UIParent": r'<Frame name="UIParent"',
    "UISpecialFrames": r"^UISpecialFrames = ",
    "print": r"^function print\b",
}

TOP_LEVEL_KEY = re.compile(r"^([A-Za-z_][\w.]*):", re.M)


def keys(path: Path) -> list[str]:
    """The top-level keys of a YAML mapping, in file order."""
    return TOP_LEVEL_KEY.findall(path.read_text(encoding="utf-8"))


def defined_in(interface: Path, pattern: str) -> str | None:
    """The first interface file with a matching line, as a path under the interface folder."""
    wanted = re.compile(pattern, re.M)
    for path in sorted(interface.rglob("*")):
        if path.suffix.lower() in (".lua", ".xml") and wanted.search(
            path.read_text(encoding="utf-8", errors="replace")
        ):
            return path.relative_to(interface).as_posix()
    return None


def main() -> int:
    """Write the vendored list; non-zero where the checkout is not of the right build."""
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    checkout = Path(sys.argv[1])
    product = checkout / "data" / "products" / "wow"
    build = (product / "build.yaml").read_text(encoding="utf-8")
    if f"build: '{BUILD}'" not in build or f"tocversion: {TOC}" not in build:
        print(f"{product} is not build {BUILD}")
        return 1

    interface = checkout / "extracts" / "wow" / "Interface"
    found: dict[str, str] = {}
    for name, pattern in INTERFACE.items():
        path = defined_in(interface, pattern)
        if path is None:
            print(f"{name}: no definition found in the client's interface code")
            return 1
        found[name] = path

    listed = {
        "build": f"9.2.7.{BUILD}",
        "apis": sorted(keys(product / "apis.yaml")),
        "events": sorted(keys(product / "events.yaml")),
        "interface": dict(sorted(found.items())),
    }
    TARGET.write_text(json.dumps(listed, indent=1) + "\n", encoding="utf-8", newline="\n")
    print(
        f"{len(listed['apis'])} functions, {len(listed['events'])} events, {len(found)} interface"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
