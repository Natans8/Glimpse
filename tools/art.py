#!/usr/bin/env python3
"""Draw the addon's icon sheet.

    uv run python tools/art.py

Writes `Glimpse/Art/Icons.tga`: every icon the interface uses, white on clear,
in one row of a sheet whose sides are powers of two, which is what the client
loads. The addon tints them, so one drawing serves an icon at rest, under the
pointer and switched on. `ICONS` is the order; `Glimpse/Interface/Tools.lua`
names the same icons in the same order, and the check holds the two together.

Each icon is drawn several times its size and scaled down, which is what
smooths its edges.
"""

from __future__ import annotations

import math
from collections.abc import Callable
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "Glimpse" / "Art" / "Icons.tga"

#: An icon's side in the sheet, and how many times larger it is drawn.
SIDE, OVERSAMPLE = 64, 8
#: How many icons the sheet has room for: its width is `SLOTS * SIDE`.
SLOTS = 8

WHITE = (255, 255, 255, 255)
CLEAR = (255, 255, 255, 0)

Pen = ImageDraw.ImageDraw
BIG = SIDE * OVERSAMPLE
#: The stroke every icon is drawn with, and the margin it keeps from its slot's edge.
STROKE, MARGIN = BIG // 11, BIG // 6
MIDDLE = BIG / 2


def point(angle: float, radius: float) -> tuple[float, float]:
    """A point at an angle in degrees, clockwise from the right, about the slot's middle."""
    turn = math.radians(angle)
    return MIDDLE + radius * math.cos(turn), MIDDLE + radius * math.sin(turn)


def line(pen: Pen, *points: tuple[float, float]) -> None:
    """A stroke through points, with round ends and joints."""
    pen.line(points, fill=WHITE, width=STROKE, joint="curve")
    for x, y in points:
        pen.ellipse((x - STROKE / 2, y - STROKE / 2, x + STROKE / 2, y + STROKE / 2), fill=WHITE)


def arc(pen: Pen, start: float, end: float, radius: float) -> None:
    """A stroke along a circle about the middle, from one angle to another, clockwise."""
    steps = max(2, int(abs(end - start) / 4))
    line(pen, *(point(start + (end - start) * i / steps, radius) for i in range(steps + 1)))


def reset(pen: Pen) -> None:
    radius = MIDDLE - MARGIN
    arc(pen, 0, 360, radius)
    dot = STROKE * 1.1
    pen.ellipse((MIDDLE - dot, MIDDLE - dot, MIDDLE + dot, MIDDLE + dot), fill=WHITE)


def weapon(pen: Pen) -> None:
    low, high = MARGIN, BIG - MARGIN
    line(pen, (low + BIG * 0.16, high - BIG * 0.16), (high, low))
    guard = BIG * 0.15
    cross = (low + BIG * 0.27, high - BIG * 0.27)
    line(pen, (cross[0] - guard, cross[1] - guard), (cross[0] + guard, cross[1] + guard))
    line(pen, (low, high), (low + BIG * 0.1, high - BIG * 0.1))


def speaker(pen: Pen) -> None:
    left, top, bottom = MARGIN, MIDDLE - BIG * 0.12, MIDDLE + BIG * 0.12
    cone = MIDDLE - BIG * 0.05
    pen.polygon(
        [
            (left, top),
            (left + BIG * 0.14, top),
            (cone, MARGIN + BIG * 0.06),
            (cone, BIG - MARGIN - BIG * 0.06),
            (left + BIG * 0.14, bottom),
            (left, bottom),
        ],
        fill=WHITE,
    )


def sound_on(pen: Pen) -> None:
    speaker(pen)
    arc(pen, -38, 38, BIG * 0.2)
    arc(pen, -42, 42, BIG * 0.34)


def sound_off(pen: Pen) -> None:
    speaker(pen)
    near, far, reach = MIDDLE + BIG * 0.1, BIG - MARGIN, BIG * 0.13
    line(pen, (near, MIDDLE - reach), (far, MIDDLE + reach))
    line(pen, (near, MIDDLE + reach), (far, MIDDLE - reach))


def close(pen: Pen) -> None:
    low, high = MARGIN + BIG * 0.04, BIG - MARGIN - BIG * 0.04
    line(pen, (low, low), (high, high))
    line(pen, (low, high), (high, low))


def grip(pen: Pen) -> None:
    edge = BIG - MARGIN * 0.6
    for step in (0.75, 0.5, 0.25):
        reach = (BIG - MARGIN) * step
        line(pen, (edge - reach, edge), (edge, edge - reach))


def previous(pen: Pen) -> None:
    reach = BIG * 0.2
    line(pen, (MIDDLE + reach * 0.5, MIDDLE - reach), (MIDDLE - reach * 0.5, MIDDLE))
    line(pen, (MIDDLE - reach * 0.5, MIDDLE), (MIDDLE + reach * 0.5, MIDDLE + reach))


def following(pen: Pen) -> None:
    reach = BIG * 0.2
    line(pen, (MIDDLE - reach * 0.5, MIDDLE - reach), (MIDDLE + reach * 0.5, MIDDLE))
    line(pen, (MIDDLE + reach * 0.5, MIDDLE), (MIDDLE - reach * 0.5, MIDDLE + reach))


#: Every icon, in the order it stands in the sheet.
ICONS: tuple[tuple[str, Callable[[Pen], None]], ...] = (
    ("reset", reset),
    ("weapon", weapon),
    ("soundOn", sound_on),
    ("soundOff", sound_off),
    ("close", close),
    ("grip", grip),
    ("previous", previous),
    ("following", following),
)


def sheet() -> Image.Image:
    """The whole sheet, drawn."""
    if len(ICONS) > SLOTS:
        raise ValueError(f"{len(ICONS)} icons do not fit a sheet of {SLOTS}")
    whole = Image.new("RGBA", (SLOTS * SIDE, SIDE), CLEAR)
    for slot, (_, draw) in enumerate(ICONS):
        large = Image.new("RGBA", (BIG, BIG), CLEAR)
        draw(ImageDraw.Draw(large))
        whole.paste(large.resize((SIDE, SIDE), Image.Resampling.LANCZOS), (slot * SIDE, 0))
    return whole


def main() -> None:
    """Write the sheet."""
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    sheet().save(TARGET, format="TGA", compression=None)
    print(f"{len(ICONS)} icons  {TARGET.relative_to(ROOT).as_posix()}")


if __name__ == "__main__":
    main()
