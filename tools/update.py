#!/usr/bin/env python3
"""Rebuild the addon's data after Epsilon has changed.

    uv run python tools/update.py            # say whether the data is behind
    uv run python tools/update.py --rebuild  # regenerate it and record what it was made from

Items are asked of the client as they are previewed, so they need nothing, and
spells are previewed by Epsilook. Objects, creatures, zone sounds, emotes,
enchants and the animation tables are generated here, and they are as old as
the client tables they were generated from.

Epsilon names each build of its client by a key, which its version service
publishes. `generator/epsilon-build.txt` records the key the data was last
generated at. Where the two differ, the data is behind.

Regenerating reads the exploration database another project keeps (see
`generator/source.py`), so that database has to be refreshed from the new
client first; this tool cannot tell whether it has been, and says so.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RECORD = ROOT / "generator" / "epsilon-build.txt"

#: Where Epsilon publishes the build its client is on.
VERSIONS = "http://tact.epsilonwow.net/wow/versions"
#: The column of that document holding the build's key.
KEY = "BuildConfig"


def live_build() -> str:
    """The key of the build Epsilon's client is on now.

    The document is a header line of `Name!TYPE:size` columns, then a row for
    each region, all bar-separated; every region is on one build.
    """
    request = urllib.request.Request(VERSIONS, headers={"User-Agent": "glimpse-update"})
    with urllib.request.urlopen(request, timeout=30) as response:
        text: str = response.read().decode("utf-8")
    lines = text.splitlines()
    rows = [line.split("|") for line in lines if line and not line.startswith("#")]
    names = [column.split("!")[0] for column in rows[0]]
    if KEY not in names or len(rows) < 2:
        raise ValueError(f"{VERSIONS} did not answer with a {KEY} column and a row")
    return rows[1][names.index(KEY)]


def recorded_build() -> str | None:
    """The key the data was last generated at, or None where none is recorded."""
    return RECORD.read_text(encoding="utf-8").strip() if RECORD.is_file() else None


def main() -> int:
    """Report, or rebuild and record; non-zero where the data is behind and was not rebuilt."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--rebuild", action="store_true", help="regenerate the data and record it")
    args = parser.parse_args()

    live, recorded = live_build(), recorded_build()
    print(f"Epsilon is on   {live}")
    print(f"data made from  {recorded or 'nothing recorded'}")
    if not args.rebuild:
        if live == recorded:
            print("The data is current.")
            return 0
        print(
            "The data is behind. Refresh the exploration database from the new client,\n"
            "then run this again with --rebuild."
        )
        return 1

    if live != recorded:
        print(
            "Regenerating from the exploration database as it stands. If that database has\n"
            "not been refreshed from the new client, this records old data as new."
        )
    done = subprocess.run(("uv", "run", "python", "generator/build.py"), cwd=ROOT, check=False)
    if done.returncode:
        return done.returncode
    RECORD.write_text(live + "\n", encoding="utf-8", newline="\n")
    print(f"recorded {live}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
