# Standards

Glimpse runs inside other people's games. A fault in it is a fault in their evening, so the bar is that it cannot
break a client: no crash, no error spam, no interference with another addon, nothing sent to the server.

## Invariants

Each one is enforced by a guard in `tools/check.py` or by a test, and each guard has a test that shows it a
violation. A rule that lives only in this file does not hold.

| Invariant | Enforced by |
|---|---|
| The addon sends nothing: no chat, no command, no addon message | `send_violations` |
| It writes only its saved globals, `GlimpseSettings` and `GlimpseFaults`, and its door for other addons, `Glimpse`; loading it creates only the door; its windows are named `GlimpseWindow`, `GlimpseWindow2` and on, because Escape closes a frame only by its name | `global_violations`, selene, the clean-state test |
| It hooks and never replaces: no `SetScript` on a frame it does not own, no assignment over a global function | `foreign_script_violations`, `global_violations` |
| Every function the client calls into (an event, a hook, a script, a timer) runs under `Safely` | `callback_violations` |
| Only `Interface/Stage.lua` hands anything to a model loader, and only from a display id, the client's object search, or a generated table gated on `.m2` | `loader_violations`, the generator's `.m2` test |
| No link the addon writes matches a GLink pattern | the links test against `test/fixtures/glink-patterns.json` |
| The chat filter is pure and idempotent | the filter tests |
| Core is pure Lua; resolvers reach the client only through `ns.Client`; nothing below the interface names it | `layer_violations` |
| The toc lists every Lua file, and every file it lists exists | `toc_violations` |

Under `Safely` a fault is reported once per place, saved, and never raised again into the client.

A wrong file type handed to a model loader crashes the client outright, and `pcall` does not catch a native
crash. That is why the loader has one door and the data behind it is gated when it is generated.

## Lua

- Lua 5.1. `selene` with `std = "lua51"`, `stylua` with tabs and a width of 100.
- Everything lives in the addon's private table (`local _, ns = ...`).
- A client global is read as `_G.Name`, and only in `Client.lua` and the interface layer.
- An object with methods is a table whose metatable's `__index` is its module, as `Stage` is.
- One responsibility per file. A line pattern is anchored and names exactly the line it reads.
- Never `a and b or c` where `b` can be nil or false; write the `if`.
- No debug prints, no commented-out code.

## Python

- `uv`, with `pyproject.toml` and `uv.lock` pinning the toolchain.
- `mypy --strict` for everything, tests included. `ruff format` and `ruff check`.
- A record with a known shape is a `TypedDict`, a dataclass or a `NamedTuple`, not a bare tuple or dict.
- No `assert` for validation outside tests.

## Documentation

- A doc block on every function another file calls: what it is, what it guarantees, what `nil` means.
- Comments describe the code as it is. No dates, no names, no quotes, no history, no notes about work not done.
  Work that is required and missing is a `TODO:` naming what unblocks it.
- `README.md` is a file map and the commands. It is not a manual.

## Each increment

1. Write the change and its tests together.
2. `uv run python tools/check.py`: guards, formatters, linters, types, tests.
3. A simplification pass over the change.
4. A review pass when logic changed.
5. A simulator pass when the interface changed, and an in-game judgment for anything the client draws.
6. Commit by named paths.

## Tests

| Tier | Instrument | It answers |
|---|---|---|
| Declaration | `tools/check.py` | Are the invariants intact? Do two statements of one fact agree? |
| Law | `pytest` with `lupa`, the addon loaded in toc order over a stubbed client | Does a unit obey its rule, against the lines the game really prints? |
| Law | `pytest` over the generator | Are the tables shaped and gated as stated? |
| Interaction | the headless client simulator | Does it load clean, and do hover and click arrive through the client's own path? |
| In game | a person | Everything the client draws: models, effects, framing, sound |

Reach for the cheapest tier that can answer the question. A test ships in the commit of what it covers. A guard
is finished only once it has been seen to fail.
