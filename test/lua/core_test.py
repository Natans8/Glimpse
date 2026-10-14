"""The small core modules: the packed reader, the guard, and latest-wins asking."""

from typing import cast

import lua as emit
from support import HARNESS_GLOBALS, LuaRuntime, evaluate, load_addon, new_runtime


def test_packed_finds_every_row_of_a_key(addon: LuaRuntime) -> None:
    table = emit.packed_table([(5, 1, 10), (7, 2, 20), (7, 3, 30), (900, 4, 40)], (3, 2, 2))
    addon.execute(f"T = {table}".encode())
    assert evaluate(addon, "NS.Packed.Find(T, 7)") == [[2, 20], [3, 30]]
    assert evaluate(addon, "NS.Packed.Find(T, 5)") == [[1, 10]]
    assert evaluate(addon, "NS.Packed.Find(T, 900)") == [[4, 40]]


def test_packed_finds_nothing_for_an_absent_key(addon: LuaRuntime) -> None:
    table = emit.packed_table([(5, 1), (7, 2)], (3, 2))
    addon.execute(f"T = {table}".encode())
    for key in (1, 6, 8, 999):
        assert evaluate(addon, f"NS.Packed.Find(T, {key})") == []
    addon.execute(f"EMPTY = {emit.packed_table([], (3, 2))}".encode())
    assert evaluate(addon, "NS.Packed.Find(EMPTY, 5)") == []
    assert evaluate(addon, "NS.Packed.First(EMPTY, 5)") is None


def test_packed_first_is_the_first_row_and_offsets_are_taken_off(addon: LuaRuntime) -> None:
    table = emit.packed_table([(7, -1, 20), (7, 3, 30)], (3, 2, 2), (0, 1, 0))
    addon.execute(f"T = {table}".encode())
    assert evaluate(addon, "NS.Packed.First(T, 7)") == [-1, 20]
    assert evaluate(addon, "NS.Packed.Find(T, 7)") == [[-1, 20], [3, 30]]
    assert evaluate(addon, "NS.Packed.First(T, 8)") is None


def test_a_guarded_function_returns_what_it_returns(addon: LuaRuntime) -> None:
    addon.execute(b"GUARDED = NS.Safely.Wrap(function(a, b) return a + b, nil, 'third' end)")
    assert evaluate(addon, "{ GUARDED(2, 3) }") == {"1": 5, "3": "third"}


def test_a_fault_is_swallowed_counted_and_announced_once(addon: LuaRuntime) -> None:
    addon.execute(b"""
        ANNOUNCED = {}
        NS.Safely.Announce = function(place, line) ANNOUNCED[#ANNOUNCED + 1] = place end
        BROKEN = NS.Safely.Wrap(function() error("it broke") end)
        BROKEN() BROKEN() BROKEN()
    """)
    assert evaluate(addon, "#ANNOUNCED") == 1
    assert evaluate(addon, "NS.Safely.faults[ANNOUNCED[1]].count") == 3
    assert evaluate(addon, "{ BROKEN() }") == []


def test_a_faulting_announcer_does_not_escape(addon: LuaRuntime) -> None:
    addon.execute(b"""
        NS.Safely.Announce = function() error("the announcer broke too") end
        NS.Safely.Wrap(function() error("first") end)()
    """)


#: Two kinds for asking about: one whose answer a test releases, one that answers at once,
#: with a subject for id 1 and with nothing for any other.
ASKING = b"""
    ANSWERS, CANCELLED, PENDING, CALLS = {}, {}, {}, 0
    NS.Kinds.Add("held", { code = "h", resolve = function(read, answer)
        PENDING[read.id] = answer
        return function() CANCELLED[#CANCELLED + 1] = read.id end
    end })
    NS.Kinds.Add("instant", { code = "j", resolve = function(read, answer)
        CALLS = CALLS + 1
        if read.id == 1 then answer({ id = 1 }) else answer(nil) end
    end })
    function ASK(slot, id, kind)
        NS.Async.Ask(slot, { kind = kind or "held", id = id }, function(subject)
            ANSWERS[#ANSWERS + 1] = subject and subject.id or "nothing"
        end)
    end
"""


def test_the_latest_question_in_a_slot_wins(addon: LuaRuntime) -> None:
    addon.execute(ASKING)
    addon.execute(b'ASK("peek", 1) ASK("peek", 2)')
    assert evaluate(addon, "CANCELLED") == [1]
    addon.execute(b"PENDING[1]({ id = 1 }) PENDING[2]({ id = 2 })")
    assert evaluate(addon, "ANSWERS") == [2]


def test_slots_do_not_disturb_each_other(addon: LuaRuntime) -> None:
    addon.execute(ASKING)
    addon.execute(b'ASK("peek", 1) ASK("window", 2) PENDING[1]({ id = 1 }) PENDING[2]({ id = 2 })')
    assert evaluate(addon, "ANSWERS") == [1, 2]
    assert evaluate(addon, "CANCELLED") == []


def test_cancelling_drops_the_answer(addon: LuaRuntime) -> None:
    addon.execute(ASKING)
    addon.execute(b'ASK("peek", 1) NS.Async.Cancel("peek") PENDING[1]({ id = 1 })')
    assert evaluate(addon, "ANSWERS") == []
    assert evaluate(addon, "CANCELLED") == [1]


def test_a_found_subject_is_kept_and_nothing_is_not(addon: LuaRuntime) -> None:
    addon.execute(ASKING)
    addon.execute(b"""
        ASK("peek", 1, "instant") ASK("peek", 1, "instant")
        ASK("peek", 9, "instant") ASK("peek", 9, "instant")
    """)
    assert evaluate(addon, "ANSWERS") == [1, 1, "nothing", "nothing"]
    assert evaluate(addon, "CALLS") == 3


def test_a_kind_nobody_added_has_nothing_to_show(addon: LuaRuntime) -> None:
    addon.execute(ASKING)
    addon.execute(b'ASK("peek", 1, "unheard of")')
    assert evaluate(addon, "ANSWERS") == ["nothing"]


GLOBAL_NAMES = (
    "(function() local t = {} for k in pairs(_G) do t[#t + 1] = tostring(k) end return t end)()"
)


def test_loading_the_addon_creates_only_its_door() -> None:
    before = set(cast(list[str], evaluate(new_runtime(), GLOBAL_NAMES)))
    after = set(cast(list[str], evaluate(load_addon(), GLOBAL_NAMES)))
    assert after - before == HARNESS_GLOBALS | {"Glimpse"}, "the harness's names and the door"


#: The server's record of a fern spawned on the Infinite Flatlands and given `.gobject tint
#: 20 40 60 80 60`, as its addon message carried it: its fields parted by byte 31.
TINTED_FERN = "".join(
    [
        *("96105", "801862", "6ar_fern_b02.m2", "979607", "-607.532", "276.995", "8.71196e-05"),
        *("1.83547", "0", "-0", "105.165", "1", "20", "40", "60", "60", "0", "1", "0", "5", "80"),
        *("203676832464111111", "3170539788286497152", "1", ""),
    ]
)


def test_the_servers_record_of_an_object_is_kept_by_its_guid() -> None:
    runtime = load_addon()
    runtime.globals()[b"RECORD"] = TINTED_FERN.encode()
    runtime.execute(b"""
        HANDLERS.CHAT_MSG_ADDON(nil, "CHAT_MSG_ADDON", "EPSILON_OBJ_INFO", RECORD, "WHISPER", "x")
        HANDLERS.CHAT_MSG_ADDON(nil, "CHAT_MSG_ADDON", "OTHER", "7" .. "1", "WHISPER", "x")
    """)
    assert evaluate(runtime, "NS.Client.ObjectRecord(96105)") == {
        "file": 979607,
        "scale": 1,
        "spell": 0,
        "tint": {"red": 20, "green": 40, "blue": 60, "transparency": 60, "saturation": 80},
    }, "the percentages typed, and saturation from the far end of the record"
    assert evaluate(runtime, "NS.Client.ObjectRecord(7)") is None, "another prefix is not heard"
    assert evaluate(runtime, "NS.Client.ObjectRecord(1)") is None, "nothing came for it"


#: The server's record of a chair spawned and given `.gob overlay 100 0 0`, captured in game:
#: the field that reads 1 for a tint reads 2 for an overlay, with the colour after it.
OVERLAID_CHAIR = "".join(
    [
        *("96172", "716709", "6dr_draenei_chair02.m2", "875053", "3302.94", "3111.85", "32.064"),
        *("2.21472", "0", "-0", "126.894", "2", "100", "0", "0", "0", "0", "1", "0", "5", "100"),
        *("203676832464112986", "3170539134909147456", "1", ""),
    ]
)


def test_an_overlay_is_not_taken_for_a_tint() -> None:
    runtime = load_addon()
    runtime.globals()[b"RECORD"] = OVERLAID_CHAIR.encode()
    runtime.execute(b"""
        HANDLERS.CHAT_MSG_ADDON(nil, "CHAT_MSG_ADDON", "EPSILON_OBJ_INFO", RECORD, "WHISPER", "x")
    """)
    assert evaluate(runtime, "NS.Client.ObjectRecord(96172)") == {
        "file": 875053,
        "scale": 1,
        "spell": 0,
    }, "no frame draws an overlay, so the object is its model alone"


def test_a_subject_that_depends_on_the_servers_word_is_found_afresh() -> None:
    runtime = load_addon()
    runtime.execute(b"""
        ASKED = 0
        NS.Kinds.Resolve = function(read, done)
            ASKED = ASKED + 1
            done({ kind = read.kind, id = read.id, looks = { { draw = "file", value = 1 } } })
        end
        local function ask(read) NS.Async.Ask("peek", read, function() end) end
        ask({ kind = "object", id = 801862, name = "fern" })
        ask({ kind = "object", id = 801862, name = "fern" })
        ask({ kind = "object", id = 801862, name = "fern", ids = { 96105 } })
        ask({ kind = "object", id = 801862, name = "fern", ids = { 96105 } })
    """)
    assert evaluate(runtime, "ASKED") == 3, "an entry's model is kept, a spawned object's is not"


#: The client's item wait as the client gives it: it calls back once the item has loaded and
#: says nothing where the server has no such item. `LOADED` keeps each callback by item.
ITEMS = b"""
    LOADED, GOT = {}, {}
    Item = {
        CreateFromItemID = function(_, id)
            return {
                ContinueWithCancelOnItemLoad = function(_, fn)
                    LOADED[id] = fn
                    return function() LOADED[id] = nil end
                end,
            }
        end,
    }
    local function wait(id)
        return NS.Client.WhenItemLoads(id, function() GOT[#GOT + 1] = "loaded " .. id end,
            function() GOT[#GOT + 1] = "refused " .. id end)
    end
    WAIT = wait
"""


def test_an_item_wait_hears_the_server_refuse_the_item() -> None:
    runtime = load_addon()
    runtime.execute(ITEMS)
    runtime.execute(b"""
        WAIT(5); WAIT(6); WAIT(7)()
        HANDLERS.ITEM_DATA_LOAD_RESULT(nil, "ITEM_DATA_LOAD_RESULT", 5, false)
        LOADED[6]()
        HANDLERS.ITEM_DATA_LOAD_RESULT(nil, "ITEM_DATA_LOAD_RESULT", 6, false)
        HANDLERS.ITEM_DATA_LOAD_RESULT(nil, "ITEM_DATA_LOAD_RESULT", 7, false)
    """)
    assert evaluate(runtime, "GOT") == ["refused 5", "loaded 6"], (
        "a refusal ends its wait; a wait already over or cancelled hears nothing"
    )
