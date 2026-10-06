"""The small core modules: the packed reader, the guard, and latest-wins asking."""

from __future__ import annotations

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
