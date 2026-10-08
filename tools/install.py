#!/usr/bin/env python3
"""Copy the addon into a game client's AddOns folder.

    uv run python tools/install.py "C:/Games/Epsilon/_retail_/Interface/AddOns"

Copies exactly the addon's own folders, replacing what was there, and touches
nothing else in the AddOns folder. The data addon is copied where it has been
built.
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

#: The folders this tool may write or replace, and no others.
OWNED = ("Glimpse", "Glimpse_Data", "Glimpse_WMO")


def main() -> int:
    """Install the addon's folders; non-zero where the destination is not an AddOns folder."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("addons", type=Path, help="the client's Interface/AddOns folder")
    args = parser.parse_args()

    addons: Path = args.addons
    if not addons.is_dir() or addons.name.lower() != "addons":
        print(f"{addons} is not an AddOns folder")
        return 1
    for name in OWNED:
        source, landing = ROOT / name, addons / name
        if not (source / f"{name}.toc").is_file():
            print(f"skip  {name}: not built")
            continue
        if landing.exists():
            shutil.rmtree(landing)
        shutil.copytree(source, landing)
        print(f"ok    {name}: {sum(1 for path in landing.rglob('*') if path.is_file())} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
