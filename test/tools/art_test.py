"""The icon sheet: the committed file is what the drawing gives, and its order is guarded."""

from __future__ import annotations

import art
import check
from PIL import Image


def test_the_committed_sheet_is_what_the_drawing_gives() -> None:
    committed = Image.open(art.TARGET).convert("RGBA")
    assert committed.size == (art.SLOTS * art.SIDE, art.SIDE)
    assert committed.tobytes() == art.sheet().tobytes(), "run tools/art.py"


def test_the_sheet_and_the_addon_name_the_same_icons_in_order() -> None:
    drawn = (check.ROOT / "tools" / "art.py").read_text(encoding="utf-8")
    named = (check.ROOT / "Glimpse" / "Interface" / "Tools.lua").read_text(encoding="utf-8")
    assert check.icon_violations(drawn, named) == []


def test_icons_out_of_order_are_a_violation() -> None:
    drawn = 'SLOTS = 8\nICONS: tuple = (\n    ("turnLeft", a),\n    ("turnRight", b),\n)\n'
    named = 'local ICONS = {\n\t"turnRight",\n\t"turnLeft",\n}\nlocal SLOTS = 8\n'
    assert len(check.icon_violations(drawn, named)) == 2
    ordered = 'local ICONS = {\n\t"turnLeft",\n\t"turnRight",\n}\nlocal SLOTS = 8\n'
    assert check.icon_violations(drawn, ordered) == []
    assert check.icon_violations("nothing", named) != []


def test_sheets_of_different_widths_are_a_violation() -> None:
    drawn = 'SLOTS = 16\nICONS: tuple = (\n    ("turnLeft", a),\n)\n'
    named = 'local ICONS = {\n\t"turnLeft",\n}\nlocal SLOTS = 8\n'
    assert check.icon_violations(drawn, named) == ["tools/art.py has 16 slots, Tools.lua 8"]
