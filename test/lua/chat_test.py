"""Links, the chat filter, clicks and sound playback, over a stand-in for the client."""

from __future__ import annotations

import json
from collections.abc import Callable
from typing import cast

import pytest
from support import FIXTURES, LuaRuntime, evaluate, lines, load_addon, plain

LINES = lines()

#: A client that records what the addon installs and plays, in place of the real one.
CLIENT = b"""
    FILTERS, HOOKS, PLAYED, STOPPED, ASKED = {}, {}, {}, {}, {}
    ChatFrame_AddMessageEventFilter = function(event, filter) FILTERS[event] = filter end
    hooksecurefunc = function(name, hook) HOOKS[name] = hook end
    -- One chat frame, keeping the scripts hooked on it, and a hover frame that records.
    SCRIPTS, PEEKED = {}, {}
    ChatFrame1 = { HookScript = function(_, script, hook) SCRIPTS[script] = hook end }
    CHAT_FRAMES = { "ChatFrame1" }
    NS.Peek = {
        Show = function(read, lent)
            PEEKED[#PEEKED + 1] = read.kind .. " " .. read.id .. (lent and " lent" or "")
        end,
        Hide = function() PEEKED[#PEEKED + 1] = "hidden" end,
    }
    WINDOWED = {}
    NS.Window = {
        Toggle = function(read, lent)
            WINDOWED[#WINDOWED + 1] = read.kind .. " " .. read.id .. (lent and " lent" or "")
        end,
    }
    NS.Client.ItemKind = function(id) return "equipment", "INVTYPE_WEAPON" end
    NS.Client.Data = function() return nil end
    -- The client's two sound calls as 9.2.7 has them: a handle back from playing, and a
    -- "finished" event for whoever asked for one in the fourth argument.
    PlaySound = function(kit, channel, noDuplicates, tellWhenFinished)
        PLAYED[#PLAYED + 1] = kit
        ASKED[#PLAYED] = tellWhenFinished
        return true, #PLAYED
    end
    StopSound = function(handle) STOPPED[#STOPPED + 1] = handle end
    -- The client's tooltip: its lines while it is up, nil once it is hidden.
    GameTooltip = {
        SetOwner = function() TOOLTIP = {} end,
        SetText = function(_, text) TOOLTIP[1] = text end,
        AddLine = function(_, text) TOOLTIP[#TOOLTIP + 1] = text end,
        Show = function() end,
        Hide = function() TOOLTIP = nil end,
    }
    NS.Chat.Install()
    function FILTER(message)
        return FILTERS.CHAT_MSG_SYSTEM(nil, "CHAT_MSG_SYSTEM", message, "author", "rest")
    end
    function LINKS(message)
        local found = {}
        local _, shown = FILTER(message)
        for link, word in (shown or ""):gmatch("|H(garrmission:[^|]+)|h%[(.-)%]|h") do
            found[#found + 1] = { link = link, word = word }
        end
        return found
    end
"""


@pytest.fixture
def chat(addon: LuaRuntime) -> LuaRuntime:
    """The addon installed over the stand-in client."""
    addon.execute(CLIENT)
    return addon


def call(runtime: LuaRuntime, name: str, text: str) -> object:
    """A Lua global called with one string, its first result as plain Python."""
    function = cast(Callable[[bytes], object], runtime.eval(name.encode()))
    return plain(function(text.encode("utf-8")))


def test_the_filter_appends_one_button_after_the_line(chat: LuaRuntime) -> None:
    line = LINES["lookup creature wolf"][0]
    result = evaluate(chat, f"{{ FILTER({json.dumps(line)}) }}")
    assert isinstance(result, list)
    keep, shown, author, rest = result
    assert keep is False
    assert isinstance(shown, str) and shown.startswith(line), "the line itself is untouched"
    assert shown[len(line) :].startswith(
        "|cffADFFFF -|r |cffC8A8FF|Hgarrmission:glimpse:c/184093/1/"
    )
    assert shown.endswith("|h[Preview]|h|r")
    assert (author, rest) == ("author", "rest"), "the event's other arguments pass through"


def test_the_filter_gives_the_same_answer_each_time_it_is_asked(chat: LuaRuntime) -> None:
    line = json.dumps(LINES["lookup object inn"][0])
    assert evaluate(chat, f"select(2, FILTER({line})) == select(2, FILTER({line}))") is True


def test_a_line_that_is_not_ours_is_left_alone(chat: LuaRuntime) -> None:
    for line in ("You are now AFK.", LINES["lookup title king"][0], LINES["lookup wmodata inn"][0]):
        assert evaluate(chat, f"{{ FILTER({json.dumps(line)}) }}") == [False]


def test_a_sound_with_day_and_night_gains_a_button_for_each(chat: LuaRuntime) -> None:
    both = call(
        chat,
        "LINKS",
        "|cff00CCFF28|r - [DAY] forestdarkenchantedday, [NIGHT] forestdarkenchantednight",
    )
    assert [button["word"] for button in cast(list[dict[str, str]], both)] == ["Day", "Night"]
    one = call(chat, "LINKS", "|cff00CCFF156|r - Zone-TavernAlliance")
    assert [button["word"] for button in cast(list[dict[str, str]], one)] == ["Play"]


@pytest.mark.parametrize("command", sorted(LINES))
def test_a_link_reads_back_as_the_read_it_was_written_from(chat: LuaRuntime, command: str) -> None:
    chat.execute(b"""
        function ROUND(message)
            local read = NS.Lines.Read(message)
            if not read or not NS.Kinds.Buttons(read) then return "no button" end
            local back, index = NS.Links.Read(NS.Links.Write(read, 2))
            return { read = read, back = back, index = index }
        end
    """)
    for line in LINES[command]:
        result = call(chat, "ROUND", line)
        if result != "no button":
            trip = cast(dict[str, object], result)
            assert (trip["back"], trip["index"]) == (trip["read"], 2), line


def test_no_link_matches_a_pattern_another_addon_claims_clicks_by(chat: LuaRuntime) -> None:
    patterns = json.loads((FIXTURES / "glink-patterns.json").read_text(encoding="utf-8"))
    chat.globals()[b"PATTERNS"] = chat.eval(
        ("{" + ",".join(json.dumps(row["pattern"]) for row in patterns) + "}").encode()
    )
    chat.execute(b"""
        WORDS = { "lookup next", "gameobject_GPS", "GLink_Toggle", "item:%d*" }
        function CLAIMED(message)
            local claimed = {}
            for _, button in ipairs(LINKS(message)) do
                for _, pattern in ipairs(PATTERNS) do
                    local bare = pattern:gsub("%(", ""):gsub("%)", "")
                    for _, tried in ipairs({ pattern, bare }) do
                        local ok, at = pcall(string.find, button.link, tried)
                        if ok and at then claimed[#claimed + 1] = button.link .. " by " .. tried end
                    end
                end
                for _, word in ipairs(WORDS) do
                    if button.link:find(word) then
                        claimed[#claimed + 1] = button.link .. " by " .. word
                    end
                end
            end
            return claimed
        end
    """)
    checked = 0
    for found in LINES.values():
        for line in found:
            assert call(chat, "CLAIMED", line) == [], line
            checked += 1
    awkward = "9 - |cffffffff|Hspell:9|h[Counterspell: item: tele: lookup next, rank 1]|h|r"
    assert call(chat, "LINKS", awkward) == [], "no spell data here, so no button to check"
    assert checked > 900


def test_a_name_survives_a_link_whatever_it_holds(chat: LuaRuntime) -> None:
    name = "Counterspell: item:25 tele: |cff lookup next / ~ ,"
    chat.globals()[b"AWKWARD"] = name.encode()
    back = evaluate(
        chat,
        '(NS.Links.Read(NS.Links.Write({ kind = "creature", id = 7, name = AWKWARD }, 1)))',
    )
    assert back == {"kind": "creature", "id": 7, "name": name}
    link = evaluate(chat, 'NS.Links.Write({ kind = "creature", id = 7, name = AWKWARD }, 1)')
    assert isinstance(link, str)
    tail = link.removeprefix("garrmission:glimpse:")
    assert ":" not in tail and "|" not in tail and " " not in tail


def test_a_link_that_is_not_ours_reads_as_nothing(chat: LuaRuntime) -> None:
    for link in (
        "item:25:0:0",
        "garrmission:123",
        "garrmission:glimpse:",
        "garrmission:glimpse:q/1/1//",
    ):
        assert evaluate(chat, f"NS.Links.Read({json.dumps(link)})") is None


def click(chat: LuaRuntime, line: str, button: int) -> None:
    """Click one of a line's buttons the way the client reports a click."""
    found = cast(list[dict[str, str]], call(chat, "LINKS", line))
    chat.globals()[b"CLICKED"] = found[button - 1]["link"].encode()
    chat.execute(b'HOOKS.SetItemRef(CLICKED, "[Play]", "LeftButton")')


MUSIC = "|cff00CCFF156|r - Zone-TavernAlliance"
AMBIENCE = "|cff00CCFF28|r - [DAY] forestdarkenchantedday, [NIGHT] forestdarkenchantednight"


def test_clicking_play_plays_and_clicking_again_stops(chat: LuaRuntime) -> None:
    click(chat, MUSIC, 1)
    assert evaluate(chat, "PLAYED") == [4516]
    click(chat, MUSIC, 1)
    assert evaluate(chat, "STOPPED") == [1]
    assert evaluate(chat, "PLAYED") == [4516], "stopped, not started again"


def test_clicking_a_preview_button_opens_the_window_and_plays_nothing(chat: LuaRuntime) -> None:
    click(chat, LINES["lookup creature wolf"][0], 1)
    assert evaluate(chat, "WINDOWED") == ["creature 184093"]
    assert evaluate(chat, "PLAYED") == []


def test_clicking_a_sound_button_opens_no_window(chat: LuaRuntime) -> None:
    click(chat, MUSIC, 1)
    assert evaluate(chat, "WINDOWED") == []


def test_another_sound_stops_the_one_before(chat: LuaRuntime) -> None:
    click(chat, AMBIENCE, 1)
    click(chat, AMBIENCE, 2)
    assert evaluate(chat, "PLAYED") == [4170, 4171]
    assert evaluate(chat, "STOPPED") == [1]


def test_a_sound_that_ended_by_itself_plays_again(chat: LuaRuntime) -> None:
    click(chat, MUSIC, 1)
    assert evaluate(chat, "ASKED[1]") is True, "the client is asked to say when it finishes"
    chat.execute(b'HANDLERS.SOUNDKIT_FINISHED(nil, "SOUNDKIT_FINISHED", 1)')
    click(chat, MUSIC, 1)
    assert evaluate(chat, "PLAYED") == [4516, 4516]
    assert evaluate(chat, "STOPPED") == [], "nothing was playing, so nothing was stopped"


def test_a_finished_event_for_someone_elses_sound_changes_nothing(chat: LuaRuntime) -> None:
    click(chat, MUSIC, 1)
    chat.execute(b'HANDLERS.SOUNDKIT_FINISHED(nil, "SOUNDKIT_FINISHED", 999)')
    click(chat, MUSIC, 1)
    assert evaluate(chat, "STOPPED") == [1], "ours was still playing, so the click stopped it"


def test_a_sound_still_playing_is_stopped_when_the_interface_goes(chat: LuaRuntime) -> None:
    click(chat, MUSIC, 1)
    click(chat, AMBIENCE, 1)
    chat.execute(b'HANDLERS.SOUNDKIT_FINISHED(nil, "SOUNDKIT_FINISHED", 1)')
    chat.execute(b"STOPPED = {}")
    chat.execute(b'HANDLERS.PLAYER_LOGOUT(nil, "PLAYER_LOGOUT")')
    assert evaluate(chat, "STOPPED") == [2], "the one still playing, and not the one that ended"


def test_a_sound_the_client_refuses_is_not_taken_as_playing(chat: LuaRuntime) -> None:
    chat.execute(b"PlaySound = function(kit) PLAYED[#PLAYED + 1] = kit return false end")
    click(chat, MUSIC, 1)
    click(chat, MUSIC, 1)
    assert evaluate(chat, "PLAYED") == [4516, 4516], "each click tries again"
    assert evaluate(chat, "STOPPED") == []


def hover(chat: LuaRuntime, line: str, button: int) -> None:
    """Rest the pointer on one of a line's buttons, then move it away."""
    found = cast(list[dict[str, str]], call(chat, "LINKS", line))
    chat.globals()[b"HOVERED"] = found[button - 1]["link"].encode()
    chat.execute(b'SCRIPTS.OnHyperlinkEnter(ChatFrame1, HOVERED, "[Preview]")')
    chat.execute(b"SCRIPTS.OnHyperlinkLeave(ChatFrame1)")


def test_resting_on_a_preview_button_shows_it_and_leaving_hides_it(chat: LuaRuntime) -> None:
    hover(chat, LINES["lookup creature wolf"][0], 1)
    assert evaluate(chat, "PEEKED") == ["creature 184093", "hidden"]


def test_a_kind_turned_off_gains_no_button_and_an_old_one_does_nothing(chat: LuaRuntime) -> None:
    wolf = LINES["lookup creature wolf"][0]
    found = cast(list[dict[str, str]], call(chat, "LINKS", wolf))
    chat.globals()[b"OLD"] = found[0]["link"].encode()
    chat.execute(b'NS.Settings.Turn("creature", false)')
    assert call(chat, "LINKS", wolf) == [], "a line printed now gains nothing"
    chat.execute(b'SCRIPTS.OnHyperlinkEnter(ChatFrame1, OLD, "[Preview]")')
    chat.execute(b'HOOKS.SetItemRef(OLD, "[Preview]", "LeftButton")')
    assert evaluate(chat, "PEEKED") == [] and evaluate(chat, "WINDOWED") == []
    chat.execute(b'NS.Settings.Turn("music", false)')
    assert call(chat, "LINKS", MUSIC) == [], "a sound too"


def test_an_area_has_a_map_button_that_opens_the_world_map_at_its_map(chat: LuaRuntime) -> None:
    chat.execute(b"""
        OPENED = {}
        OpenWorldMap = function(map) OPENED[#OPENED + 1] = map end
        C_Map = { GetMapInfo = function(id) return ({ [37] = { name = "Elwynn Forest" } })[id] end }
    """)
    goldshire = "87 - |cffffffff|Harea:87|h[Goldshire]|h|r"
    found = cast(list[dict[str, str]], call(chat, "LINKS", goldshire))
    assert [button["word"] for button in found] == ["Map"]
    rest(chat, goldshire, 1)
    assert evaluate(chat, "TOOLTIP") == ["Goldshire", "In Elwynn Forest", "Click to open the map"]
    assert evaluate(chat, "PEEKED") == [], "no picture"
    chat.execute(b"SCRIPTS.OnHyperlinkLeave(ChatFrame1)")
    assert evaluate(chat, "TOOLTIP") is None, "leaving takes it down"
    click(chat, goldshire, 1)
    assert evaluate(chat, "OPENED") == [37], "Elwynn Forest's map, the zone Goldshire is in"
    assert evaluate(chat, "WINDOWED") == [], "and no window of this addon's"


def test_a_kind_another_addon_offers_is_lent_to_it(chat: LuaRuntime) -> None:
    chat.execute(b"""
        Glimpse.Provide("creature", { Show = function() return true end, Hide = function() end })
    """)
    hover(chat, LINES["lookup creature wolf"][0], 1)
    click(chat, LINES["lookup creature wolf"][0], 1)
    assert evaluate(chat, "PEEKED") == ["creature 184093 lent", "hidden"]
    assert evaluate(chat, "WINDOWED") == ["creature 184093 lent"]


def rest(chat: LuaRuntime, line: str, button: int) -> None:
    """Rest the pointer on one of a line's buttons and leave it there."""
    found = cast(list[dict[str, str]], call(chat, "LINKS", line))
    chat.globals()[b"HOVERED"] = found[button - 1]["link"].encode()
    chat.execute(b'SCRIPTS.OnHyperlinkEnter(ChatFrame1, HOVERED, "[Play]")')


def test_resting_on_a_sound_button_says_what_a_click_does(chat: LuaRuntime) -> None:
    rest(chat, MUSIC, 1)
    assert evaluate(chat, "TOOLTIP") == ["Zone-TavernAlliance", "Click to play"]
    assert evaluate(chat, "PEEKED") == [], "a sound has nothing to draw"
    click(chat, MUSIC, 1)
    assert evaluate(chat, "TOOLTIP") == ["Zone-TavernAlliance", "Click to stop"]
    chat.execute(b'HANDLERS.SOUNDKIT_FINISHED(nil, "SOUNDKIT_FINISHED", 1)')
    assert evaluate(chat, "TOOLTIP") == ["Zone-TavernAlliance", "Click to play"]
    chat.execute(b"SCRIPTS.OnHyperlinkLeave(ChatFrame1)")
    assert evaluate(chat, "TOOLTIP") is None


def test_a_sound_with_a_day_and_a_night_names_which_the_button_is(chat: LuaRuntime) -> None:
    rest(chat, AMBIENCE, 2)
    assert evaluate(chat, "TOOLTIP[2]") == "Night"
    assert evaluate(chat, "TOOLTIP[3]") == "Click to play"


def test_resting_on_someone_elses_link_shows_nothing(chat: LuaRuntime) -> None:
    chat.execute(b'SCRIPTS.OnHyperlinkEnter(ChatFrame1, "item:25:0:0", "[Worn Shortsword]")')
    assert evaluate(chat, "PEEKED") == []


def test_a_look_takes_the_presentation_of_how_it_is_drawn(chat: LuaRuntime) -> None:
    def of(draw: str) -> dict[str, object]:
        row = evaluate(chat, f'NS.Presentations.Of({{ draw = "{draw}" }})')
        return cast(dict[str, object], row)

    assert of("file") == {
        "drawer": "scene",
        "yaw": 30,
        "pitch": 20,
    }
    assert of("creature")["drawer"] == "model", "only a model frame draws from an entry"
    assert of("creature")["pitch"] == of("display")["pitch"], "a creature is a figure otherwise"
    assert of("display")["drawer"] == "scene", "a display's camera is fitted to its size"
    assert of("character")["drawer"] == "model", "a character is drawn whole by a model frame"
    assert "inherits" not in of("enchant")


def test_a_worn_thing_is_turned_to_where_it_is_carried(chat: LuaRuntime) -> None:
    def yaw(slot: str) -> object:
        return evaluate(chat, f'NS.Presentations.Of({{ draw = "tryon", slot = "{slot}" }}).yaw')

    assert yaw("INVTYPE_2HWEAPON") == 92
    assert yaw("INVTYPE_SHIELD") == -40
    assert yaw("INVTYPE_CLOAK") == 195
    assert yaw("INVTYPE_CHEST") == yaw("INVTYPE_HEAD") == 25, "seen from the front otherwise"


def test_a_caption_says_what_a_thing_is_and_which_look_is_shown() -> None:
    runtime = load_addon()

    def caption(subject: str, index: int) -> object:
        return evaluate(runtime, f"NS.Presentations.Caption({subject}, {index})")

    creature = '{ kind = "creature", looks = { { draw = "creature" } } }'
    assert caption(creature, 1) == "Creature"
    mounts = (
        '{ kind = "item", looks = { { draw = "display", value = 17697 },'
        ' { draw = "display", value = 17698 } } }'
    )
    assert caption(mounts, 2) == "Item, display 17698, 2 of 2", "a display named by its id"
    mount = '{ kind = "item", id = 25470, looks = { { draw = "display", value = 17697 } } }'
    assert caption(mount, 1) == "Item, display 17697", "the id the line did not give"
    display = '{ kind = "display", id = 73, looks = { { draw = "display", value = 73 } } }'
    assert caption(display, 1) == "Display", "not the id the line already gives"
    spell = '{ kind = "spell", looks = { { draw = "sequence", name = "all stages" }, {} } }'
    assert caption(spell, 1) == "Spell, all stages"


def test_a_thing_another_addon_shows_is_captioned_as_every_kind_is() -> None:
    runtime = load_addon()
    assert evaluate(runtime, 'NS.Presentations.Lent({ kind = "spell", id = 116 })') == "Spell"
    assert (
        evaluate(
            runtime, 'NS.Presentations.Lent({ kind = "wmo" }, "invisible: its collision shape")'
        )
        == "Object, invisible: its collision shape"
    ), "the words the addon said follow the kind, and a WMO is an object to the player"


def test_every_kind_has_a_word_and_a_letter_of_its_own() -> None:
    runtime = load_addon()
    kinds = [
        cast(dict[str, str], row)["kind"]
        for row in cast(list[object], evaluate(runtime, "NS.Kinds.List()"))
    ]
    assert "spell" in kinds and "area" in kinds and "object" in kinds
    letters = set()
    for kind in kinds:
        word = evaluate(runtime, f'NS.Kinds.Word({{ kind = "{kind}" }})')
        assert isinstance(word, str) and word[0].isupper(), kind
        letter = evaluate(runtime, f'NS.Kinds.Code("{kind}")')
        assert evaluate(runtime, f'NS.Kinds.Named("{letter}")') == kind
        letters.add(letter)
    assert len(letters) == len(kinds), "no two kinds share a letter"


def test_the_hover_frame_takes_the_side_with_more_room() -> None:
    runtime = load_addon()
    assert evaluate(runtime, "NS.Peek.Side(430, 1920)") == "RIGHT"
    assert evaluate(runtime, "NS.Peek.Side(1500, 1920)") == "LEFT"


def test_side_by_side_cards_are_as_many_as_the_room_holds() -> None:
    runtime = load_addon()
    assert evaluate(runtime, "NS.Peek.Fit(1480, 230, 4)") == 4, "every one, with room to spare"
    assert evaluate(runtime, "NS.Peek.Fit(1480, 230, 82)") == 6, "the rest are counted on the last"
    assert evaluate(runtime, "NS.Peek.Fit(100, 230, 4)") == 1, "the first always shows"


def test_a_click_on_someone_elses_link_does_nothing(chat: LuaRuntime) -> None:
    chat.execute(b'HOOKS.SetItemRef("item:25:0:0:0", "[Worn Shortsword]", "LeftButton")')
    assert evaluate(chat, "PLAYED") == []


#: The command's surroundings: the settings and what the addon says, recorded.
COMMAND = b"""
    OPTIONS, SAID = 0, {}
    NS.Options.Open = function() OPTIONS = OPTIONS + 1 end
    NS.Start.Say = function(text) SAID[#SAID + 1] = text end
"""


def test_the_command_alone_opens_the_settings(chat: LuaRuntime) -> None:
    chat.execute(COMMAND)
    chat.execute(b'NS.Command.Run("")')
    chat.execute(b'NS.Command.Run("   ")')
    assert evaluate(chat, "OPTIONS") == 2
    assert evaluate(chat, "SAID") == []


def test_the_command_previews_a_kind_by_its_id(chat: LuaRuntime) -> None:
    chat.execute(COMMAND)
    chat.execute(
        b'NS.Command.Run("emote 10") NS.Command.Run("NPC 184093") NS.Command.Run("item 25")'
    )
    assert evaluate(chat, "WINDOWED") == ["emote 10", "creature 184093", "item 25"]
    assert evaluate(chat, "SAID") == []


def test_the_command_previews_a_pasted_link(chat: LuaRuntime) -> None:
    chat.execute(COMMAND)
    chat.execute(b"""
        Glimpse.Provide("spell", { Show = function() return true end, Hide = function() end })
        NS.Command.Run("|cff71d5ff|Hspell:116:0|h[Frostbolt]|h|r")
    """)
    assert evaluate(chat, "WINDOWED") == ["spell 116 lent"], (
        "a spellbook link carries more after the id"
    )


def test_the_command_says_what_it_takes_and_when_there_is_nothing(chat: LuaRuntime) -> None:
    chat.execute(COMMAND)
    chat.execute(b'NS.Command.Run("hello") NS.Command.Run("dragon 5")')
    said = cast(list[str], evaluate(chat, "SAID"))
    assert len(said) == 2 and all(line.startswith("/glimpse opens the settings") for line in said)
    chat.execute(b'SAID = {} NS.Command.Run("gob 941883")')
    said = cast(list[str], evaluate(chat, "SAID"))
    assert len(said) == 1 and said[0].startswith("Nothing to preview"), "not a stock object"
    assert evaluate(chat, "WINDOWED") == []


def test_the_command_is_added_to_the_clients(chat: LuaRuntime) -> None:
    chat.execute(b"SlashCmdList = {} NS.Command.Install()")
    assert evaluate(chat, "SLASH_GLIMPSE1") == "/glimpse"
    assert evaluate(chat, "type(SlashCmdList.GLIMPSE)") == "function"
