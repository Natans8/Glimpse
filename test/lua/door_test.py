"""The door other addons ask this one to show a thing through: Peek, Unpeek and Open."""

import pytest
from support import LuaRuntime, evaluate

#: A stand-in client: a hover frame and a window that record what they are asked to show,
#: and a data addon naming three models. `PEEKED` keeps each read the hover frame was given.
CLIENT = b"""
    PEEKED, HIDDEN, WINDOWED = {}, 0, {}
    NS.Peek = {
        Show = function(read, lent, asked)
            PEEKED[#PEEKED + 1] = { read = read, lent = lent == true, asked = asked == true }
        end,
        Hide = function() HIDDEN = HIDDEN + 1 end,
    }
    NS.Window = {
        Toggle = function(read, lent)
            WINDOWED[#WINDOWED + 1] = read.kind .. " " .. read.name .. (lent and " lent" or "")
        end,
    }
    DATA = {
        models = ";6dr_draenei_barrel02=876957;6dr_draenei_chair01=875053;"
            .. "6td_treestump_b01=920823;",
        -- No stock objects, and none whose display is a WMO.
        objects = { widths = { 6, 7 }, offsets = { 0, 0 }, records = "" },
        wmoObjects = { widths = { 6 }, offsets = { 0 }, records = "" },
    }
    NS.Client.Data = function() return DATA end
    SET = {
        kind = "models",
        name = "6dr_draenei_house2's Set_Restaurant",
        models = {
            { file = 875053, count = 9 }, { file = 123, count = 4 }, { file = 876957, count = 1 },
        },
    }
    function RESOLVE(models)
        RESOLVED = nil
        NS.Kinds.Resolve({ kind = "models", id = 0, name = "", models = models },
            function(subject) RESOLVED = subject end)
    end
"""


@pytest.fixture
def door(addon: LuaRuntime) -> LuaRuntime:
    """The addon over the stand-in client."""
    addon.execute(CLIENT)
    return addon


def test_another_addon_peeks_at_a_list_of_models(door: LuaRuntime) -> None:
    assert evaluate(door, "Glimpse.Peek(SET)") is True
    peeked = evaluate(door, "PEEKED[1]")
    assert peeked == {
        "read": {
            "kind": "models",
            "id": 0,
            "name": "6dr_draenei_house2's Set_Restaurant",
            "models": [
                {"file": 875053, "count": 9},
                {"file": 123, "count": 4},
                {"file": 876957, "count": 1},
            ],
        },
        "lent": False,
        "asked": True,
    }, "the hover frame is told another addon asked, so it does not say a click opens it"
    door.execute(b"Glimpse.Unpeek()")
    assert evaluate(door, "HIDDEN") == 1


def test_only_the_models_the_clients_displays_name_are_drawn(door: LuaRuntime) -> None:
    door.execute(b"RESOLVE(SET.models)")
    assert evaluate(door, "RESOLVED.looks") == [
        {"draw": "file", "value": 875053, "count": 9},
        {"draw": "file", "value": 876957, "count": 1},
    ], "123 is no model the data names, so it never reaches a model loader"
    door.execute(b"RESOLVE({ { file = 123, count = 4 } })")
    assert evaluate(door, "RESOLVED") is None, "a list naming no model has nothing to show"


def test_a_list_is_cut_at_its_most_and_each_model_counts_once(door: LuaRuntime) -> None:
    door.execute(b"""
        DATA.models, LONG = ";", { { file = 1001, count = 99 } }
        for i = 1, 70 do
            DATA.models = DATA.models .. "m" .. i .. "=" .. (1000 + i) .. ";"
            LONG[#LONG + 1] = { file = 1000 + i, count = 71 - i }
        end
        RESOLVE(LONG)
    """)
    assert evaluate(door, "#RESOLVED.looks") == 64
    assert evaluate(door, "RESOLVED.looks[1].count") == 99, "the first given, once"
    assert evaluate(door, "RESOLVED.looks[2].value") == 1002


def test_a_read_is_copied_and_checked(door: LuaRuntime) -> None:
    assert evaluate(door, "Glimpse.Peek(nil)") is False
    assert evaluate(door, 'Glimpse.Peek("models")') is False
    assert evaluate(door, 'Glimpse.Peek({ kind = "nothing like it" })') is False
    broken = (
        '{ kind = "models", models = { { file = "875053", count = 1 }, '
        "{ file = 875053.5, count = 1 }, { file = 875053, count = 0 }, 7 } }"
    )
    assert evaluate(door, f"Glimpse.Peek({broken})") is False, "no model in the list holds"
    door.execute(b"Glimpse.Peek(SET); SET.name = 'changed after'; SET.models[1].file = 1")
    assert evaluate(door, "PEEKED[1].read.name") == "6dr_draenei_house2's Set_Restaurant"
    assert evaluate(door, "PEEKED[1].read.models[1].file") == 875053, "the table is not kept"


def test_a_read_carries_the_names_and_ids_a_line_would(door: LuaRuntime) -> None:
    names = '{ "6dr_draenei_chair01.m2", 7, "6td_treestump_b01.m2" }'
    assert evaluate(door, f'Glimpse.Peek({{ kind = "doodad", id = 5, names = {names} }})') is True
    assert evaluate(door, "PEEKED[1].read.names") == [
        "6dr_draenei_chair01.m2",
        "6td_treestump_b01.m2",
    ], "only the names that are text"
    spawned = (
        '{ kind = "object", id = 1, name = "6dr_draenei_chair01.m2", ids = { 81024, -1, "x" } }'
    )
    assert evaluate(door, f"Glimpse.Peek({spawned})") is True
    assert evaluate(door, "PEEKED[2].read.ids") == [81024], "only whole numbers"
    assert (
        evaluate(
            door,
            'Glimpse.Peek({ kind = "object", name = "6dr_draenei_chair01.m2", ids = { "x" } })',
        )
        is True
    )
    assert evaluate(door, "PEEKED[3].read.ids") is None, "a list of nothing is left out"


def test_a_detail_doodad_asked_for_without_names_has_nothing_to_show(door: LuaRuntime) -> None:
    door.execute(b"""
        NS.Client.SearchObjects = function() return {} end
        NS.Kinds.Resolve({ kind = "doodad", id = 5, name = "" },
            function(subject) RESOLVED = subject end)
    """)
    assert evaluate(door, "RESOLVED") is None


def test_the_players_choices_hold(door: LuaRuntime) -> None:
    door.execute(b"GlimpseSettings = { off = { models = true } }")
    assert evaluate(door, "Glimpse.Peek(SET)") is False, "a kind turned off shows nothing"
    assert evaluate(door, "Glimpse.Open(SET)") is False
    door.execute(b"GlimpseSettings = { hover = false }")
    assert evaluate(door, "Glimpse.Peek(SET)") is False, "no peek while the hover is off"
    assert evaluate(door, "Glimpse.Open(SET)") is True, "a click still opens the window"
    assert evaluate(door, "WINDOWED") == ["models 6dr_draenei_house2's Set_Restaurant"]


def test_a_kind_another_addon_previews_is_lent_through_the_door(door: LuaRuntime) -> None:
    door.execute(b"""
        Glimpse.Provide("wmo", {
            Shows = function(id, context) return context.name == "6dr_draenei_house2" end,
            Show = function() return true end,
            Hide = function() end,
        })
    """)
    house = '{ kind = "wmo", id = 0, name = "6dr_draenei_house2" }'
    assert evaluate(door, f"Glimpse.Peek({house})") is True
    assert evaluate(door, "PEEKED[1].lent") is True
    assert evaluate(door, 'Glimpse.Peek({ kind = "wmo", name = "a lake tile" })') is False


#: An addon's own provider for a kind of its own, recording the frames it fills.
SCENE = b"""
    FILLED = {}
    SCENE = {
        name = "Another addon",
        word = "Set",
        Show = function(frame, id, context)
            FILLED[#FILLED + 1] = context.place .. " " .. context.name
            return true
        end,
        Hide = function() end,
    }
"""


def test_an_addon_draws_a_kind_of_its_own_in_this_addons_frame(door: LuaRuntime) -> None:
    door.execute(SCENE)
    assert evaluate(door, 'Glimpse.Provide("scene", SCENE)') is True
    assert evaluate(door, 'NS.Kinds.Word({ kind = "scene" })') == "Set"
    assert evaluate(door, 'Glimpse.Peek({ kind = "scene", name = "Restaurant" })') is True
    assert evaluate(door, "PEEKED[1].lent") is True, (
        "the frame is lent, nothing of this addon's drawn"
    )
    assert evaluate(door, 'NS.Kinds.Code("scene")') is None, "no line names it, so no letter"


def test_a_kind_is_declared_only_with_a_word_and_a_whole_provider(door: LuaRuntime) -> None:
    door.execute(SCENE)
    door.execute(b"WORDLESS = { Show = SCENE.Show, Hide = SCENE.Hide }")
    assert evaluate(door, 'Glimpse.Provide("scene", WORDLESS)') is False
    assert evaluate(door, 'Glimpse.Provide("scene", { word = "Set" })') is False
    assert evaluate(door, 'NS.Kinds.Known("scene")') is False
    assert evaluate(door, 'Glimpse.Provide("object", SCENE)') is True
    assert evaluate(door, 'NS.Kinds.Word({ kind = "object" })') == "Object", (
        "a kind this addon knows keeps its own word"
    )


def test_a_fault_in_the_door_is_never_raised_into_the_caller(door: LuaRuntime) -> None:
    door.execute(b"""
        ANNOUNCED = 0
        NS.Safely.Announce = function() ANNOUNCED = ANNOUNCED + 1 end
        NS.Peek.Show = function() error("the hover frame broke") end
    """)
    assert evaluate(door, "Glimpse.Peek(SET)") is None
    assert evaluate(door, "ANNOUNCED") == 1


def test_two_lists_of_models_are_two_subjects(door: LuaRuntime) -> None:
    one = '{ kind = "models", id = 0, name = "set", models = { { file = 1, count = 2 } } }'
    two = '{ kind = "models", id = 0, name = "set", models = { { file = 1, count = 3 } } }'
    assert evaluate(door, f"NS.Subject.Key({one}) ~= NS.Subject.Key({two})") is True


def test_a_models_caption_says_how_many_of_each_there_are(door: LuaRuntime) -> None:
    door.execute(b"""
        SUBJECT = { kind = "models", looks = {
            { draw = "file", value = 875053, count = 9 },
            { draw = "file", value = 876957, count = 1 },
        } }
    """)
    times = chr(0xD7)
    assert (
        evaluate(door, "NS.Presentations.Caption(SUBJECT, 1)") == f"Object, model 1 of 2, {times}9"
    )
    assert (
        evaluate(door, "NS.Presentations.Place(SUBJECT.looks[1], 1, 2)")
        == f"Model 1 of 2, {times}9"
    )
    assert evaluate(door, "NS.Presentations.Place(SUBJECT.looks[2], 2, 2)") == "Model 2 of 2", (
        "one of a model is not counted"
    )
