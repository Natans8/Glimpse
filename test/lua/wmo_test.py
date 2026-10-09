"""The WMO pictures' provider: what it draws on a lent frame for each kind of index entry."""

from __future__ import annotations

from typing import cast

from support import ROOT, LuaRuntime, Plain, evaluate, new_runtime, plain

MODULE = ROOT / "Glimpse_WMO" / "Glimpse_WMO.lua"

#: A client of regions and frames that record what is done to them, a small index, and
#: Glimpse's door keeping what is offered through it.
CLIENT = b"""
    local function region()
        local r = { shown = false }
        function r:SetPoint() end
        function r:SetWidth() end
        function r:SetJustifyH() end
        function r:SetSize(w, h) self.size = w .. "x" .. h end
        function r:SetTexture(path) self.texture = path end
        function r:SetText(text) self.text = text end
        function r:Show() self.shown = true end
        function r:Hide() self.shown = false end
        return r
    end
    FRAME = { width = 300, height = 200 }
    function FRAME:CreateTexture() return region() end
    function FRAME:CreateFontString() return region() end
    function FRAME:HookScript(_, handler) self.sized = handler end
    function FRAME:GetSize() return self.width, self.height end
    Glimpse_WMO = {
        pictures = ";castle=1234;deleteme_box=1500;laketile_1_water=0;wall=1600;",
        entries = ";000000042=1234;",
        liquids = ";laketile_1_water=1;",
        collision = ";000001600=1;",
        interiors = ";000001500=1;",
    }
    OFFERED = {}
    Glimpse = { Provide = function(kind, provider) OFFERED[kind] = provider end }
"""


def module() -> LuaRuntime:
    """A runtime with the module loaded as the client loads it, after its index."""
    runtime = new_runtime()
    runtime.execute(CLIENT)
    runtime.globals()[b"SOURCE"] = MODULE.read_bytes()
    runtime.execute(b'assert(loadstring(SOURCE, "@Glimpse_WMO.lua"))("Glimpse_WMO")')
    return runtime


def show(runtime: LuaRuntime, call: str) -> Plain:
    """Every answer the provider gives when lent the frame for a thing: whether it filled the
    frame, then the words it says of the thing where it says any."""
    return evaluate(runtime, f"{{OFFERED.wmo.Show(FRAME, {call})}}")


def shows(runtime: LuaRuntime, call: str) -> Plain:
    """Whether the provider says it has anything to show for a thing, which decides its button."""
    return evaluate(runtime, f"OFFERED.wmo.Shows({call})")


#: What the frame shows: the picture's path, false while hidden, and its size.
DRAWN = b"""
    return (function(p)
        return { picture = p.shown and p.texture or false, size = p.size or false }
    end)(FRAME.glimpseWmo)
"""


def drawn(runtime: LuaRuntime) -> dict[str, Plain]:
    """What the frame shows, as DRAWN reads it."""
    return cast(dict[str, Plain], plain(runtime.execute(DRAWN)))


def test_both_wmo_kinds_are_offered() -> None:
    runtime = module()
    assert evaluate(runtime, "OFFERED.wmo ~= nil and OFFERED.wmo == OFFERED.wmoarea") is True


def test_a_picture_by_name_is_drawn_square_and_said_nothing_of() -> None:
    runtime = module()
    assert show(runtime, 'nil, { name = "World\\\\wmo\\\\Castle.wmo " }') == [True]
    assert drawn(runtime) == {
        "picture": "Interface\\AddOns\\Glimpse_WMO\\Pictures\\000\\1234.blp",
        "size": "200x200",
    }


def test_a_picture_is_found_by_entry_before_name() -> None:
    runtime = module()
    assert show(runtime, '42, { name = "wall" }') == [True]
    assert evaluate(runtime, "FRAME.glimpseWmo.texture") == (
        "Interface\\AddOns\\Glimpse_WMO\\Pictures\\000\\1234.blp"
    )


def test_collision_and_interior_pictures_say_so_for_glimpse_to_put_after_the_kind() -> None:
    runtime = module()
    assert show(runtime, 'nil, { name = "wall" }') == [True, "invisible: its collision shape"]
    assert show(runtime, 'nil, { name = "deleteme_box" }') == [True, "seen only from inside"]


def test_only_a_wmo_with_a_picture_gains_a_button() -> None:
    runtime = module()
    assert shows(runtime, 'nil, { name = "castle.wmo" }') is True
    assert shows(runtime, '42, { name = "nowhere" }') is True, "known by its entry"
    assert shows(runtime, 'nil, { name = "laketile_1_water.wmo" }') is False, "a watertile"
    assert shows(runtime, 'nil, { name = "nowhere" }') is False, "not in the index"


def test_a_wmo_with_nothing_to_show_fills_nothing() -> None:
    runtime = module()
    assert show(runtime, 'nil, { name = "laketile_1_water.wmo" }') == [False]
    assert show(runtime, 'nil, { name = "nowhere" }') == [False]
    assert evaluate(runtime, "FRAME.glimpseWmo") is None


def test_hide_takes_down_the_picture() -> None:
    runtime = module()
    show(runtime, 'nil, { name = "wall" }')
    evaluate(runtime, "OFFERED.wmo.Hide(FRAME)")
    assert drawn(runtime) == {"picture": False, "size": "200x200"}
    assert evaluate(runtime, "FRAME.glimpseWmo.texture") is None


def test_the_picture_stays_square_when_the_frame_is_resized() -> None:
    runtime = module()
    show(runtime, 'nil, { name = "castle" }')
    evaluate(runtime, "FRAME:sized(500, 320)")
    assert evaluate(runtime, "FRAME.glimpseWmo.size") == "320x320"
