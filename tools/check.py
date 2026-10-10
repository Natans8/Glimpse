#!/usr/bin/env python3
"""The repository's one definition of "does this pass".

    uv run python tools/check.py          # guards, formatters, linters, tests
    uv run python tools/check.py --fast   # guards only

A guard is a rule about the addon that no linter can decide: what it may send,
what it may replace, which file may hand a file to a model loader, which layer
may reach the client. Each guard is a function from source text to a list of
violations, so the tests can show it a violation and watch it fire.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDON = "Glimpse"

#: Every global the addon may write: its saved settings and saved faults, its door for other
#: addons, and the name of its slash command.
GLOBALS = frozenset({"GlimpseSettings", "GlimpseFaults", "Glimpse", "SLASH_GLIMPSE1"})

#: Calls that put anything on the wire. The addon previews; it never speaks.
SENDS = (
    "SendChatMessage",
    "SendAddonMessage",
    "SendAddonMessageLogged",
    "BNSendWhisper",
    "BNSendGameData",
    "RunMacroText",
)

#: Calls that hand a file, a display or an item to the client's model loader.
LOADERS = (
    "SetModelByFileID",
    "SetModelByCreatureDisplayID",
    "SetModelByUnit",
    "SetModelByPath",
    "SetDisplayInfo",
    "SetCreature",
    "SetItem",
    "SetModel",
    "SetUnit",
    "TryOn",
)

#: The one file allowed to call a loader, so the gate on what is loaded has one door.
LOADER_HOME = "Interface/Stage.lua"

#: Files that work on frames the addon does not own; they may hook and never set.
FOREIGN = frozenset({"Interface/Chat.lua"})

#: The modules of the interface layer, which nothing below it may name: one to a file,
#: each named for its file.
INTERFACE = tuple(sorted(path.stem for path in (ROOT / ADDON / "Interface").glob("*.lua")))

#: What the 9.2.7 client offers, vendored by `tools/client_globals.py`: its functions, its
#: events, and the globals its own interface code defines that the addon uses.
CLIENT = json.loads((ROOT / "tools" / "client-9.2.7.json").read_text(encoding="utf-8"))
KNOWN = frozenset(CLIENT["apis"]) | frozenset(CLIENT["interface"])
EVENTS = frozenset(CLIENT["events"])

#: Epsilon's own namespace, which Blizzard's list cannot hold. It is read only behind a check
#: that it is there, so a client without it loses a kind of preview and nothing else.
OPTIONAL = frozenset({"C_Epsilon"})

Sources = Mapping[str, str]


def strip_comments(text: str) -> str:
    """Lua source with its comments blanked, line numbers kept.

    Long comments are removed first, then anything after `--` on a line. A `--`
    inside a string is rare enough in this addon that the guards accept reading
    such a line short over carrying a Lua lexer.
    """
    text = re.sub(r"--\[(=*)\[.*?\]\1\]", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    return "\n".join(line.split("--", 1)[0] for line in text.split("\n"))


def _matches(sources: Sources, pattern: str, where: Callable[[str], bool]) -> list[str]:
    found = []
    for name, text in sources.items():
        if not where(name):
            continue
        for number, line in enumerate(strip_comments(text).split("\n"), start=1):
            hit = re.search(pattern, line)
            if hit:
                found.append(f"{name}:{number}: {hit.group(0).strip()}")
    return found


def send_violations(sources: Sources) -> list[str]:
    """Places where the addon would send chat, a command or an addon message."""
    names = "|".join(SENDS)
    return _matches(sources, rf"\b({names})\b|C_ChatInfo\.Send\w*", lambda _: True)


def global_violations(sources: Sources) -> list[str]:
    """Writes to a global other than the declared ones.

    A bare assignment to an undeclared name is selene's to catch; this guard
    covers the spellings selene reads as deliberate.
    """
    found = []
    for hit in _matches(sources, r"_G\.(\w+)\s*=[^=]|rawset\(\s*_G\b|setglobal\(", lambda _: True):
        name = re.search(r"_G\.(\w+)", hit)
        if name is None or name.group(1) not in GLOBALS:
            found.append(hit)
    return found


def foreign_script_violations(sources: Sources) -> list[str]:
    """`SetScript` in a file that works on other addons' or the client's frames."""
    return _matches(sources, r"[:.]SetScript\s*\(", lambda name: name in FOREIGN)


def loader_violations(sources: Sources) -> list[str]:
    """Model-loader calls outside the one file that gates what is loaded."""
    names = "|".join(LOADERS)
    return _matches(sources, rf"[:.]({names})\s*\(", lambda name: name != LOADER_HOME)


def layer_violations(sources: Sources) -> list[str]:
    """Reaches from a lower layer into a higher one, or past the client seam.

    Core is pure Lua. Resolvers reach the client only through `ns.Client`.
    Neither names an interface module, each of which is named for its file.
    """
    interface = "|".join(INTERFACE)
    low = lambda name: name.startswith(("Core/", "Resolvers/"))  # noqa: E731
    return [
        *_matches(sources, r"\b_G\b", low),
        *_matches(sources, rf"\bns\.({interface})\b", low),
        *_matches(sources, r"\bns\.(Resolvers|Client)\b", lambda name: name.startswith("Core/")),
    ]


def client_violations(sources: Sources) -> list[str]:
    """Client functions, hooked functions and events the 9.2.7 client does not have.

    A function that exists on a later client reads as correct, type-checks as
    nothing and faults the first time it runs in game. Every `_G.Name` and
    `_G.Namespace.Name` the addon reads, every function it hooks by name and
    every event it registers is held against the client's own list.
    """
    found = []
    for name, text in sources.items():
        for number, line in enumerate(strip_comments(text).split("\n"), start=1):
            for hit in re.finditer(r"_G\.([A-Za-z_]\w*)(?:\.([A-Za-z_]\w*))?", line):
                root, member = hit.group(1), hit.group(2)
                full = f"{root}.{member}" if member else root
                if not (root in GLOBALS or root in OPTIONAL or root in KNOWN or full in KNOWN):
                    found.append(f"{name}:{number}: {full} is not on the 9.2.7 client")
            for hit in re.finditer(r'hooksecurefunc\(\s*"(\w+)"', line):
                if hit.group(1) not in KNOWN:
                    found.append(f"{name}:{number}: {hit.group(1)} is not on the 9.2.7 client")
            for hit in re.finditer(r'RegisterEvent\(\s*"(\w+)"', line):
                if hit.group(1) not in EVENTS:
                    found.append(f"{name}:{number}: {hit.group(1)} is not a 9.2.7 event")
    return found


#: A function the client calls into, written inline where it is handed over.
HANDED = (
    r'[:.](?:SetScript|HookScript)\(\s*"\w+"\s*,\s*function\b',
    r"C_Timer\.\w+\(\s*[^,()]+,\s*function\b",
    r'hooksecurefunc\(\s*"\w+"\s*,\s*function\b',
    r"AddMessageEventFilter\(\s*\"\w+\"\s*,\s*function\b",
)


def callback_violations(sources: Sources) -> list[str]:
    """Functions handed to the client written inline, which is how one escapes `Safely.Wrap`.

    Every function the client calls into runs under `Safely`, so one handed over
    is wrapped or is a name bound to a wrapped function; an inline `function`
    in the handing-over call cannot be either.
    """
    found = []
    for name, text in sources.items():
        stripped = strip_comments(text)
        for pattern in HANDED:
            for hit in re.finditer(pattern, stripped):
                number = stripped.count("\n", 0, hit.start()) + 1
                found.append(f"{name}:{number}: {hit.group(0).split('(')[0]} given a bare function")
    return found


def toc_violations(addon: Path) -> list[str]:
    """Files the toc names that do not exist, and Lua or XML files it does not name."""
    toc = addon / f"{addon.name}.toc"
    if not toc.is_file():
        return [f"{toc.name}: missing"]
    listed = {
        line.strip().replace("\\", "/")
        for line in toc.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }
    present = {
        path.relative_to(addon).as_posix()
        for pattern in ("*.lua", "*.xml")
        for path in addon.rglob(pattern)
    }
    return [
        *(f"{toc.name}: lists {name}, which does not exist" for name in sorted(listed - present)),
        *(f"{name}: not listed in {toc.name}" for name in sorted(present - listed)),
    ]


#: The WMO pictures' module as the pictures players have were released with it, in
#: v0.3: the SHA-256 of each file, its line breaks read as LF. The module is downloaded
#: with the pictures, hundreds of megabytes, so a change to it reaches no player
#: without them; it changes only in a release of new pictures, and these change with it.
WMO_RELEASED = {
    "Glimpse_WMO.lua": "eb73a777463ca70ba5abe7b87faeb26e516fe05dbdf7acc7dd12bb24562790c2",
    "Glimpse_WMO.toc": "e97b13097ee82b7ce41ac3fa586bc2e07a11d7ba7f905543ca481d7ab588b821",
}


def module_release_violations(files: Mapping[str, bytes], released: Mapping[str, str]) -> list[str]:
    """Where the WMO pictures' module is not the one released with the pictures.

    A fix of how Glimpse shows a WMO belongs in Glimpse, which players download in a
    moment, never in the module, which would have them download every picture again.
    """
    violations = []
    for name, digest in sorted(released.items()):
        content = files.get(name)
        if content is None:
            violations.append(f"{name}: missing")
        elif hashlib.sha256(content.replace(b"\r\n", b"\n")).hexdigest() != digest:
            violations.append(
                f"{name}: not as released with the pictures; a fix belongs in Glimpse, and only "
                "a release of new pictures changes the module and WMO_RELEASED with it"
            )
    unreleased = sorted(set(files) - set(released))
    violations += [f"{name}: not released with the pictures" for name in unreleased]
    return violations


def module_version_violations(addon_toc: str, module_toc: str) -> list[str]:
    """Where the WMO pictures' toc does not declare a version the way the addon's does.

    The pictures ship in a release of their own, which stamps its toc as the addon's
    release stamps the addon's, so the two tocs must declare a version the same way.
    """
    declared = [
        re.search(r"^## Version:[ \t]*(\S+)[ \t]*$", toc, flags=re.M)
        for toc in (addon_toc, module_toc)
    ]
    if not declared[1]:
        return ["Glimpse_WMO.toc: no ## Version"]
    if not declared[0] or declared[0].group(1) != declared[1].group(1):
        theirs = declared[0].group(1) if declared[0] else "none"
        return [f"Glimpse_WMO.toc: version {declared[1].group(1)}, the addon's {theirs}"]
    return []


def icon_violations(drawn: str, named: str) -> list[str]:
    """Where the icons the sheet is drawn with and the icons the addon names disagree.

    The addon finds an icon by its place in the sheet and the sheet's width in
    places, so the two must name the same icons in the same order and agree on
    how many places the sheet has, or icons show as one another.

    `drawn` is the source of `tools/art.py`, `named` that of the addon's
    `Interface/Tools.lua`.
    """
    sheet = re.search(r"^ICONS: .*?^\)", drawn, flags=re.S | re.M)
    table = re.search(r"^local ICONS = \{(.*?)^\}", named, flags=re.S | re.M)
    drawn_slots = re.search(r"^SLOTS = (\d+)", drawn, flags=re.M)
    named_slots = re.search(r"^local SLOTS = (\d+)", named, flags=re.M)
    if not (sheet and table and drawn_slots and named_slots):
        return ["the icon list or slot count was not found in tools/art.py or Interface/Tools.lua"]
    found = []
    in_sheet = re.findall(r'\("(\w+)",', sheet.group(0))
    in_addon = re.findall(r'"(\w+)"', table.group(1))
    if in_sheet != in_addon:
        found += [f"tools/art.py draws {in_sheet}", f"Interface/Tools.lua names {in_addon}"]
    if drawn_slots.group(1) != named_slots.group(1):
        found.append(
            f"tools/art.py has {drawn_slots.group(1)} slots, Tools.lua {named_slots.group(1)}"
        )
    return found


GUARDS: Sequence[tuple[str, Callable[[Sources], list[str]]]] = (
    ("sends nothing", send_violations),
    ("declared globals only", global_violations),
    ("hooks, never replaces", foreign_script_violations),
    ("one door to the model loader", loader_violations),
    ("layers", layer_violations),
    ("only what the 9.2.7 client has", client_violations),
    ("every callback guarded", callback_violations),
)

#: The WMO pictures, an addon of their own beside this one. Its hand-written Lua is held to the
#: guards that concern any addon here; the rest are about this addon's own layers and files.
MODULE = "Glimpse_WMO"
MODULE_GUARDS = frozenset(
    {
        "sends nothing",
        "declared globals only",
        "one door to the model loader",
        "only what the 9.2.7 client has",
    }
)

#: The module's index, generated beside its Lua and never written by hand.
MODULE_GENERATED = frozenset({"Index.lua"})

#: Where hand-written Lua lives. Fixtures hold the game's own output and are left as they came.
LUA_PATHS = (ADDON, f"{MODULE}/{MODULE}.lua", "test/lua")


#: The external checks, each with its command.
TOOLS: Sequence[tuple[str, tuple[str, ...]]] = (
    ("ruff format", ("uv", "run", "ruff", "format", "--check", ".")),
    ("ruff check", ("uv", "run", "ruff", "check", ".")),
    ("mypy", ("uv", "run", "mypy")),
    ("stylua", ("stylua", "--check", *LUA_PATHS)),
    ("selene", ("selene", *LUA_PATHS)),
    ("pytest", ("uv", "run", "pytest", "-q")),
)


def addon_sources(addon: Path) -> dict[str, str]:
    """The addon's hand-written Lua, keyed by path under the addon folder."""
    return {
        path.relative_to(addon).as_posix(): path.read_text(encoding="utf-8")
        for path in sorted(addon.rglob("*.lua"))
        if "Data" not in path.relative_to(addon).parts
    }


def main() -> int:
    """Run every guard, then every tool unless `--fast`; non-zero when anything fails."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--fast", action="store_true", help="guards only")
    args = parser.parse_args()

    addon = ROOT / ADDON
    failed = False
    sources = addon_sources(addon)
    results = [(name, guard(sources)) for name, guard in GUARDS]
    results.append(("toc", toc_violations(addon)))
    module = ROOT / MODULE
    module_sources = {
        f"{MODULE}/{name}": text
        for name, text in addon_sources(module).items()
        if name not in MODULE_GENERATED
    }
    results += [
        (f"{name}, {MODULE}", guard(module_sources))
        for name, guard in GUARDS
        if name in MODULE_GUARDS
    ]
    module_toc = module / f"{MODULE}.toc"
    addon_toc = (addon / f"{ADDON}.toc").read_text(encoding="utf-8")
    results.append(
        (
            "WMO pictures share the addon's version",
            module_version_violations(addon_toc, module_toc.read_text(encoding="utf-8"))
            if module_toc.is_file()
            else [f"{module_toc.name}: missing"],
        )
    )
    tracked = subprocess.run(
        ["git", "ls-files", "--", MODULE], cwd=ROOT, capture_output=True, text=True, check=False
    ).stdout.split()
    module_files = {Path(path).name: (ROOT / path).read_bytes() for path in tracked}
    results.append(
        ("WMO pictures' module as released", module_release_violations(module_files, WMO_RELEASED))
    )
    drawn = (ROOT / "tools" / "art.py").read_text(encoding="utf-8")
    results.append(("icons", icon_violations(drawn, sources["Interface/Tools.lua"])))
    for name, violations in results:
        print(f"{'FAIL' if violations else 'ok  '}  {name}")
        for violation in violations:
            print(f"        {violation}")
        failed = failed or bool(violations)

    if not args.fast:
        for name, command in TOOLS:
            done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
            print(f"{'FAIL' if done.returncode else 'ok  '}  {name}")
            if done.returncode:
                print((done.stdout + done.stderr).rstrip())
                failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
