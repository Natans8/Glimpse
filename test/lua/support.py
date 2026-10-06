"""What the addon's tests share: the Lua runtime's shape, and loading the addon into it.

`lupa` ships no type stubs, so the runtime and its tables are described here as
protocols of exactly the calls the tests make.
"""

from __future__ import annotations

import json
from collections.abc import Iterable
from pathlib import Path
from typing import Protocol, cast

import pytest

lua51 = pytest.importorskip("lupa.lua51")

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "Glimpse"
FIXTURES = ROOT / "test" / "fixtures"

Plain = None | bool | int | float | str | list["Plain"] | dict[str, "Plain"]


class LuaTable(Protocol):
    """A Lua table as the runtime proxies it."""

    def keys(self) -> Iterable[object]: ...

    def __getitem__(self, key: object) -> object: ...

    def __setitem__(self, key: object, value: object) -> None: ...


class LuaRuntime(Protocol):
    """The one Lua 5.1 state a test drives."""

    def execute(self, source: bytes) -> object: ...

    def eval(self, source: bytes) -> object: ...

    def globals(self) -> LuaTable: ...


def toc_files() -> list[Path]:
    """The addon's Lua files in the order its toc loads them, its XML left out."""
    toc = ADDON / "Glimpse.toc"
    return [
        ADDON.joinpath(*line.strip().split("\\"))
        for line in toc.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#") and line.strip().endswith(".lua")
    ]


def new_runtime() -> LuaRuntime:
    """A bare Lua 5.1 state, with strings passed as bytes."""
    return cast(LuaRuntime, lua51.LuaRuntime(encoding=None))


#: What the harness itself defines: the addon's table, and the one client function the addon
#: calls while its files load. A frame keeps the handler set on it under each event it was
#: registered for, in `HANDLERS`, so a test can fire the event.
HARNESS = b"""
    NS = {}
    HANDLERS = {}
    function CreateFrame()
        local events = {}
        return {
            RegisterEvent = function(_, event) events[#events + 1] = event end,
            SetScript = function(_, _, handler)
                for _, event in ipairs(events) do HANDLERS[event] = handler end
            end,
        }
    end
"""

#: The global names the harness leaves behind, which are not the addon's.
HARNESS_GLOBALS = {"NS", "CreateFrame", "HANDLERS", "SOURCE", "NAME"}


def load_addon() -> LuaRuntime:
    """A fresh runtime with the addon loaded the way the client loads it.

    Each file runs with the addon's name and its private table, which the tests
    reach as the global `NS`. Of the client there is only a frame to register
    events on; a test gives the addon the rest of the client it needs, as globals
    where the addon's own reading of the client is under test, or by replacing
    `NS.Client`.
    """
    runtime = new_runtime()
    runtime.execute(HARNESS)
    for path in toc_files():
        name = path.relative_to(ADDON).as_posix().encode()
        runtime.globals()[b"SOURCE"] = path.read_bytes()
        runtime.globals()[b"NAME"] = name
        runtime.execute(b'assert(loadstring(SOURCE, "@" .. NAME))("Glimpse", NS)')
    return runtime


def plain(value: object) -> Plain:
    """A Lua value as plain Python: a table is a list where its keys run 1..n, a dict otherwise."""
    if lua51.lua_type(value) == "table":
        table = cast(LuaTable, value)
        keys = list(table.keys())
        if all(isinstance(key, int) for key in keys) and sorted(cast(list[int], keys)) == list(
            range(1, len(keys) + 1)
        ):
            return [plain(table[i]) for i in range(1, len(keys) + 1)]
        return {
            (key.decode("utf-8") if isinstance(key, bytes) else str(key)): plain(table[key])
            for key in keys
        }
    if isinstance(value, bytes):
        return value.decode("utf-8")
    return cast(Plain, value)


def evaluate(runtime: LuaRuntime, expression: str) -> Plain:
    """A Lua expression's value as plain Python."""
    return plain(runtime.eval(expression.encode("utf-8")))


def lines() -> dict[str, list[str]]:
    """The lines the game printed, by the command that produced them."""
    return cast(
        dict[str, list[str]], json.loads((FIXTURES / "lines.json").read_text(encoding="utf-8"))
    )
