"""Reading the lines the game really printed.

The fixture holds every line of each command's reply, the closing "enter
.lookup next" line included, which is why a page of fifty results is fifty-one
lines and one of them reads as nothing.
"""

from __future__ import annotations

import re
from collections import Counter
from collections.abc import Callable
from typing import cast

import pytest
from support import LuaRuntime, evaluate, lines, plain

LINES = lines()

#: What each captured command's lines read as: kind to count, with None for lines left alone.
EXPECTED: dict[str, dict[str | None, int]] = {
    "lookup object inn": {"object": 42, "wmo": 8, None: 1},
    "lookup object 9ori_": {"object": 11, None: 1},
    "lookup object 6dr_draenei_chair02": {"object": 50, None: 1},
    "lookup tile stone": {"object": 50, None: 1},
    "lookup plane stone": {"object": 50, None: 1},
    "gobject near": {"object": 26, None: 1},
    "gobject spawn": {"object": 1, None: 1},
    "gobject delete": {"object": 1, None: 1},
    "lookup detaildoodad grass": {"doodad": 50, None: 1},
    "lookup creature wolf": {"creature": 50, None: 1},
    "npc near": {"creature": 2, None: 1},
    "lookup displayid creature wolf": {"display": 50, None: 1},
    "lookup item sword": {"item": 50, None: 1},
    "lookup itemforge sword": {"item": 43, None: 1},
    "lookup spell frostbolt": {"spell": 50, None: 1},
    "lookup enchant fire": {"enchant": 8, None: 1},
    "lookup emote dance": {"emote": 30, None: 1},
    "lookup music tavern": {"music": 14, None: 1},
    "lookup intromusic storm": {"intro": 38, None: 1},
    "lookup ambience forest": {"ambience": 50, None: 1},
    "lookup tiletexture stone": {"texture": 50, None: 1},
    "lookup area elwynn": {"area": 5, None: 1},
    "lookup map kalimdor": {"map": 3, None: 1},
    "lookup tele stormwind": {"teleport": 8, None: 1},
    "lookup faction storm": {"faction": 25, None: 1},
    "lookup skill fire": {"skill": 1, None: 1},
    "lookup title king": {"title": 13, None: 1},
    "lookup wmodata inn": {"wmoarea": 50, None: 1},
    "lookup blueprintpublic house": {"blueprint": 50, None: 1},
    "lookup spell": {None: 4},
    "npc info": {None: 1},
    "gobject info": {None: 1},
    "npc info of a creature": {"creature": 1, None: 1},
    "npc info of an outfit": {None: 2},
}


def reader(addon: LuaRuntime) -> Callable[[str], dict[str, object] | None]:
    """`Lines.Read` as a Python function returning the read as a dict, or None."""
    read = cast(Callable[[bytes], object], addon.eval(b"NS.Lines.Read"))

    def call(line: str) -> dict[str, object] | None:
        return cast("dict[str, object] | None", plain(read(line.encode("utf-8"))))

    return call


@pytest.mark.parametrize("command", sorted(EXPECTED))
def test_every_line_of_a_reply_reads_as_expected(addon: LuaRuntime, command: str) -> None:
    read = reader(addon)
    kinds = Counter((read(line) or {}).get("kind") for line in LINES[command])
    assert dict(kinds) == EXPECTED[command]


#: Captured commands with no expectation of their own: a partial page, two usage replies, and
#: a second item page that reads like the first.
UNCOVERED = {
    "lookup object chair",
    "lookup displayid",
    "lookup displayid item sword",
    "lookup item potion",
}


def test_every_captured_command_is_covered() -> None:
    assert set(LINES) - set(EXPECTED) == UNCOVERED


def test_a_read_line_is_one_maybe_admits(addon: LuaRuntime) -> None:
    read = reader(addon)
    maybe = cast(Callable[[bytes], bool], addon.eval(b"NS.Lines.Maybe"))
    for found in LINES.values():
        for line in found:
            if read(line):
                assert maybe(line.encode("utf-8")), line


def test_an_object_name_loses_its_tag_and_its_entry(addon: LuaRuntime) -> None:
    read = reader(addon)
    tagged = next(line for line in LINES["gobject near"] if "[bfa 8.0]" in line)
    assert read(tagged) == {"kind": "object", "id": 876586, "name": "8zul_tallgrass_b01.m2"}


def test_an_object_is_named_alike_when_spawned_and_when_deleted(addon: LuaRuntime) -> None:
    read = reader(addon)
    fern = {"kind": "object", "id": 801862, "name": "6ar_fern_b02.m2"}
    assert read(LINES["gobject spawn"][0]) == fern, "a link left open stops at its label"
    assert read(LINES["gobject delete"][0]) == fern, "a label in parentheses"


def test_a_creature_in_an_outfit_is_not_read_since_it_cannot_be_drawn(addon: LuaRuntime) -> None:
    read = reader(addon)
    plain = read(LINES["npc info of a creature"][0])
    assert plain == {"kind": "creature", "id": 16998, "name": "Mr. Bigglesworth"}, (
        "its entry left off"
    )
    assert read(LINES["npc info of an outfit"][0]) is None, "58232 drawn, 11455984 worn"


def test_an_object_whose_model_is_a_wmo_is_a_wmo(addon: LuaRuntime) -> None:
    read = reader(addon)
    wmo = [line for line in LINES["lookup object inn"] if ".wmo]" in line]
    assert len(wmo) == 8
    assert all(cast(dict[str, object], read(line))["kind"] == "wmo" for line in wmo)


def test_a_line_with_no_link_is_read_by_its_shape(addon: LuaRuntime) -> None:
    read = reader(addon)
    faction = read(LINES["lookup faction storm"][0])
    assert faction == {"kind": "faction", "id": 11, "name": "Stormwind"}, "the template, not 72"
    texture = read(LINES["lookup tiletexture stone"][0])
    assert texture == {"kind": "texture", "id": 331455, "name": "durotarflagstonesa_s.blp"}
    group = read(LINES["lookup wmodata inn"][1])
    assert group == {"kind": "wmoarea", "id": 53, "name": "goldshireinn.wmo"}, (
        "a group is its root's"
    )


def test_names_are_read_clean(addon: LuaRuntime) -> None:
    read = reader(addon)
    spell = next(line for line in LINES["lookup spell frostbolt"] if "Hspell:116|" in line)
    assert read(spell) == {"kind": "spell", "id": 116, "name": "Frostbolt"}
    enchant = read(LINES["lookup enchant fire"][0])
    assert enchant == {"kind": "enchant", "id": 303, "name": "Orb of Fire"}
    display = read(LINES["lookup displayid creature wolf"][0])
    assert display == {"kind": "display", "id": 73, "name": "creature/direwolf/direwolf.m2"}
    coloured = next(line for line in LINES["lookup itemforge sword"] if "Blazing Sword" in line)
    assert cast(dict[str, object], read(coloured))["name"] == "Blazing Sword"


def test_an_object_line_is_read_whatever_it_is_named(addon: LuaRuntime) -> None:
    read = reader(addon)

    def line(entry: int, label: str) -> str:
        return f"{entry} - |cffffffff|Hgameobject_entry:{entry}|h[{label}]|h|r "

    assert read(line(253044, "Pillow")) == {"kind": "object", "id": 253044, "name": "Pillow"}
    assert read(line(700296, "6dr_draenei_karabor_bigdoor [door]")) == {
        "kind": "object",
        "id": 700296,
        "name": "6dr_draenei_karabor_bigdoor",
    }, "the server's own kinds of object say what they are after the name"
    assert read(line(946806, "6hu_outpost_inn_v2.wmo")) == {
        "kind": "wmo",
        "id": 946806,
        "name": "6hu_outpost_inn_v2.wmo",
    }


def test_an_emote_the_server_adds_is_read_with_its_whole_name(addon: LuaRuntime) -> None:
    read = reader(addon)
    added = read("|cff00CCFF4069 - |cffADFFFF|HemoteID:4069|h[EmoteDance [Loop]]|h|r")
    assert added == {"kind": "emote", "id": 4069, "name": "EmoteDance [Loop]"}


def test_a_doodad_carries_its_distinct_models(addon: LuaRuntime) -> None:
    read = reader(addon)
    one = cast(dict[str, object], read(LINES["lookup detaildoodad grass"][0]))
    assert one["names"] == ["hofgrassyd01.m2"]
    four = cast(dict[str, object], read(LINES["lookup detaildoodad grass"][2]))
    assert four["names"] == ["itkflower01.m2", "itkgrass04.m2", "itkgrass03.m2", "itkmoss01.m2"]


def test_a_sound_line_needs_its_id_and_its_name_to_agree(addon: LuaRuntime) -> None:
    read = reader(addon)
    assert read("|cff00CCFF156|r - Zone-TavernAlliance") == {
        "kind": "music",
        "id": 156,
        "name": "Zone-TavernAlliance",
    }
    assert read("|cff00CCFF156|r - Some other line with a number") is None
    assert read("|cff00CCFF407|r - bladesedgeforest") == {
        "kind": "ambience",
        "id": 407,
        "name": "bladesedgeforest",
    }
    assert read("|cff00CCFF407|r - not this entry's sound") is None


#: What GLink appends to a line, for each link type it knows: its buttons as links of that
#: same type, each after a pale dash.
GLINK_BUTTONS = {
    "gameobject_entry": ("[Spawn]", "[Copy Entry]"),
    "creature_entry": ("[Spawn]",),
    "item": ("[Add]",),
    "spell": ("[Learn]", "[Cast]", "[Aura]", "[Gobject]"),
    "enchantID": ("[Mainhand]", "[Off-Hand]"),
    "emoteID": ("[Emote]", "[Anim]"),
    "creatureDisplayID": ("[Native]", "[Morph]", "[Mount]"),
}


def after_glink(line: str) -> str:
    """A line as it reaches a filter that runs after GLink's: GLink's buttons on its end."""
    for link, buttons in GLINK_BUTTONS.items():
        found = re.search(rf"\|H{link}:(\d+)", line)
        if found:
            return line + "".join(
                f"|cffADFFFF -|r |cff00CCFF|H{link}:{found.group(1)}|h{button}|h|r"
                for button in buttons
            )
    return line


@pytest.mark.parametrize(
    "command",
    [
        "lookup object inn",
        "gobject near",
        "lookup creature wolf",
        "lookup item sword",
        "lookup spell frostbolt",
        "lookup enchant fire",
        "lookup emote dance",
        "lookup displayid creature wolf",
    ],
)
def test_a_line_reads_the_same_with_glinks_buttons_on_it(addon: LuaRuntime, command: str) -> None:
    read = reader(addon)
    changed = 0
    for line in LINES[command]:
        suffixed = after_glink(line)
        changed += suffixed != line
        assert read(suffixed) == read(line), line
    assert changed >= len(LINES[command]) - 9, "the lines really did gain buttons"


def test_text_that_is_no_line_of_ours_reads_as_nothing(addon: LuaRuntime) -> None:
    read = reader(addon)
    for text in ("", "hello", "|Hplayer:Someone|h[Someone]|h says hi", "|Hgameobject_entry:|h[]|h"):
        assert read(text) is None
    assert evaluate(addon, 'NS.Lines.Maybe("an ordinary system line")') is False
