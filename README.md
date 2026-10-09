# Glimpse

Previews for the results of Epsilon's `.lookup`: a `[Preview]` or `[Play]` button on each line that has something
to show. A World of Warcraft 9.2.7 addon for the Epsilon server.

To install, download the zip from [Releases](https://github.com/Natans8/Glimpse/releases) and unpack it into the
game's `_retail_/Interface/AddOns` folder. It holds two folders, `Glimpse` and `Glimpse_Data`, and both are needed.

No model frame can draw a WMO, so WMOs are previewed from pictures, a separate download in the same release: take
`Glimpse_WMO-<version>-256.7z` (256-pixel pictures, about 110 MB) or `Glimpse_WMO-<version>-512.7z` (512-pixel
pictures, about 395 MB), and unpack its `Glimpse_WMO` folder beside the other two. Use the pictures of the same
version as the addon. Without them, a WMO's line gains no button.

Licensed under AGPL-3.0-or-later; `NOTICE` says what that does and does not cover. Made by Nataari, with the help
of AI.

## Map

| Path | What it is |
|---|---|
| `Glimpse/` | the addon |
| `Glimpse_Data/` | the data addon: objects, models and creatures, generated, loaded on demand |
| `Glimpse_WMO/` | the WMO pictures' addon, its toc and Lua; the pictures and their index are generated and ship as their own download |
| `.pkgmeta` | what a release holds, for the BigWigs packager |
| `.github/workflows/` | the check on every push, and the release on every pushed tag |
| `generator/` | builds the data tables from Epsilon's client tables |
| `generator/epsilon-build.txt` | the Epsilon client build the data was made from |
| `tools/check.py` | guards, formatters, linters, types and tests in one run |
| `tools/update.py` | says whether the data is behind Epsilon's client, and rebuilds it |
| `tools/install.py` | copies the two addon folders into a game's AddOns folder |
| `tools/art.py` | draws the icon sheet, `Glimpse/Art/Icons.tga` |
| `tools/client_globals.py` | lists what the 9.2.7 client offers an addon, as `tools/client-9.2.7.json` |
| `test/tools/` | tests of the guards and tools |
| `test/generator/` | tests of the generator and its data |
| `test/lua/` | the addon's tests, run under Lua 5.1 |
| `test/fixtures/` | lines the game really printed, and the patterns of the addon Glimpse sits beside |
| `docs/DESIGN.md` | what it does and how it is put together |
| `docs/STANDARDS.md` | the invariants and how work is done |

## Commands

```bash
uv sync
```

```bash
uv run python tools/check.py
```

```bash
uv run python tools/check.py --fast
```

```bash
uv run python generator/build.py
```

```bash
uv run python tools/update.py
```

```bash
uv run python tools/update.py --rebuild
```

```bash
uv run python tools/art.py
```

`stylua` and `selene` are expected on the path.

The generator reads Epsilon's client tables from the exploration database
[Epsilook](https://github.com/Natans8/Epsilook) builds, named by the `GLIMPSE_DATABASE` environment variable, and
the emotes Epsilon adds to the client's own from a file named by `GLIMPSE_EPSILON_EMOTES`. The data files under
`Glimpse/Data/` and `Glimpse_Data/` are committed, so the addon and its tests work without the database; only
regenerating the data needs it.

A release is a pushed tag, `v0.1` and on: the release workflow packs the two folders with the tag as their version
and attaches the zip to a GitHub release. The two WMO picture archives are built outside this repository, from
pictures rendered off the client, with the same tag stamped into `Glimpse_WMO.toc`, and attached to the same
release.
