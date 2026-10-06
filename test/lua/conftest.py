"""Fixtures for the addon's tests: the addon loaded under the client's own Lua."""

from __future__ import annotations

import pytest
from support import LuaRuntime, load_addon


@pytest.fixture
def addon() -> LuaRuntime:
    """A fresh runtime holding the addon, its private table as the global `NS`."""
    return load_addon()
