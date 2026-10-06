"""Where the generator reads from.

Three sources. Epsilon's client tables, with the community listfile and the
stock server's world tables, come from the exploration database Epsilook builds
(https://github.com/Natans8/Epsilook), named by `GLIMPSE_DATABASE`; the
generator imports none of Epsilook's code. The emotes Epsilon adds to the
client's own, one pair for each animation, come from a file Epsilook keeps,
read out of Epsilon's `Emotes.db2` and named by `GLIMPSE_EPSILON_EMOTES`. Three
zone sound tables the database does not hold are downloaded once from
wago.tools for the same build and kept under `.cache/`.
"""

from __future__ import annotations

import csv
import json
import os
import urllib.request
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]

#: The environment variable naming the exploration database.
DATABASE_ENV = "GLIMPSE_DATABASE"
#: Where the database is looked for when the variable is unset: a sibling checkout.
DEFAULT_DATABASE = ROOT.parent / "Epsilook" / ".cache" / "epsilook.duckdb"

#: The environment variable naming the file of Epsilon's own emotes.
EMOTES_ENV = "GLIMPSE_EPSILON_EMOTES"
#: Where that file is looked for when the variable is unset: the same sibling checkout.
DEFAULT_EMOTES = ROOT.parent / "Epsilook" / "build" / "enums" / "epsilon_emotes.json"

#: The schema holding Epsilon's own client tables.
SCHEMA = "v9_2_7_epsilon"

#: The retail build Epsilon's client is cut from, which is what wago.tools serves.
BUILD = "9.2.7.45745"


def located(variable: str, default: Path) -> Path:
    """The file an environment variable names, or `default` where it is unset.

    Raises `FileNotFoundError` naming the variable when the file is absent, since a
    missing source would otherwise surface as an empty table several calls later.
    """
    path = Path(os.environ.get(variable, str(default)))
    if not path.is_file():
        raise FileNotFoundError(f"{path} does not exist; set {variable} to where it is")
    return path


def connect() -> duckdb.DuckDBPyConnection:
    """A read-only connection to the exploration database."""
    return duckdb.connect(str(located(DATABASE_ENV, DEFAULT_DATABASE)), read_only=True)


def epsilon_emotes() -> dict[int, dict[str, int]]:
    """Animation id to the emotes Epsilon gives it: `oneshot`, `loop`, or both."""
    path = located(EMOTES_ENV, DEFAULT_EMOTES)
    held = json.loads(path.read_text(encoding="utf-8"))
    values = held.get("values") if isinstance(held, dict) else None
    if not isinstance(values, dict):
        raise ValueError(f"{path} holds no `values` table; is {EMOTES_ENV} the emote file?")
    return {int(animation): dict(emotes) for animation, emotes in values.items()}


def wago_rows(table: str) -> list[dict[str, str]]:
    """Every row of one client table at `BUILD`, as wago.tools exports it.

    Downloaded on first use and read from `.cache/wago/<build>/` afterwards.
    """
    cached = ROOT / ".cache" / "wago" / BUILD / f"{table}.csv"
    if not cached.is_file():
        cached.parent.mkdir(parents=True, exist_ok=True)
        url = f"https://wago.tools/db2/{table}/csv?build={BUILD}"
        request = urllib.request.Request(url, headers={"User-Agent": "glimpse-generator"})
        with urllib.request.urlopen(request, timeout=60) as response:
            cached.write_bytes(response.read())
    with cached.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))
