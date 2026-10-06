"""The Lua writers: literals, and the packed table's ordering and width guard."""

from __future__ import annotations

import lua
import pytest


def test_plain_literals() -> None:
    assert lua.plain(7) == "7"
    assert lua.plain(True) == "true"
    assert lua.plain([1, "a"]) == '{1,"a"}'
    assert lua.plain({3: [1, 2], 9: "x"}) == '{[3]={1,2},[9]="x"}'


def test_plain_escapes_what_a_lua_string_must() -> None:
    assert lua.plain('a"b\\c\nd') == '"a\\"b\\\\c\\nd"'


def test_packed_sorts_and_pads() -> None:
    assert lua.packed([(12, 3), (5, 40)], (3, 2)) == "0054001203"


def test_packed_refuses_a_value_too_wide() -> None:
    with pytest.raises(ValueError, match="does not fit 2 digits"):
        lua.packed([(1, 100)], (3, 2))


def test_packed_refuses_a_negative_value() -> None:
    with pytest.raises(ValueError, match="does not fit"):
        lua.packed([(1, -1)], (3, 2))


def test_packed_refuses_a_row_of_the_wrong_length() -> None:
    with pytest.raises(ValueError, match="does not have 2 fields"):
        lua.packed([(1, 2, 3)], (3, 2))


def test_keyed_entries_are_found_by_name_and_refuse_a_separator() -> None:
    assert lua.keyed({"b": 2, "a": 1}) == '";a=1;b=2;"'
    with pytest.raises(ValueError):
        lua.keyed({"a;b": 1})
