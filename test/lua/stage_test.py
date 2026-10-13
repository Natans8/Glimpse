"""The stage's animation route, and the client's animation limit it is chosen by."""

from support import LuaRuntime, evaluate

#: A model frame as the tests need it: it records what it was told, refuses `HasAnimation`
#: past the limit the way the client does, and answers its facing.
MODEL = b"""
    LIMIT = 1726
    CALLS = {}
    FACING = 1.5
    function CreateFrame()
        local model = {}
        function model:Hide() end
        function model:HasAnimation(animation)
            if animation >= LIMIT then
                error("HasAnimation(animation) exceeds valid range of 0 - " .. LIMIT)
            end
            return true
        end
        function model:GetFacing() return FACING end
        for _, name in ipairs({ "SetAnimation", "SetSequenceTime", "SetRotation", "SetScript" }) do
            model[name] = function(_, ...) CALLS[#CALLS + 1] = { name, ... } end
        end
        MODEL = model
        return model
    end
"""


def stage(game: LuaRuntime) -> None:
    game.execute(MODEL)
    game.execute(b"STAGE = setmetatable({ model = CreateFrame() }, NS.Stage)")


def test_the_limit_is_read_from_the_clients_refusal(addon: LuaRuntime) -> None:
    addon.execute(MODEL)
    assert evaluate(addon, "NS.Client.AnimationLimit()") == 1726
    addon.execute(b"LIMIT = 1858")
    assert evaluate(addon, "NS.Client.AnimationLimit()") == 1726, "read once"


def test_a_client_refusing_nothing_has_no_limit(addon: LuaRuntime) -> None:
    addon.execute(MODEL)
    addon.execute(b"LIMIT = math.huge")
    assert evaluate(addon, "NS.Client.AnimationLimit() == math.huge") is True


def test_an_unreadable_refusal_falls_back_to_the_tables_count(addon: LuaRuntime) -> None:
    addon.execute(MODEL)
    addon.execute(
        b"""
        function CreateFrame()
            return { Hide = function() end, HasAnimation = function() error("no") end }
        end
        """
    )
    assert evaluate(addon, "NS.Client.AnimationLimit() == NS.Data.AnimationCount") is True


def test_an_animation_within_the_limit_is_set_plainly(addon: LuaRuntime) -> None:
    stage(addon)
    addon.execute(b"STAGE:Perform(69)")
    assert evaluate(addon, "CALLS") == [["SetAnimation", 69]]


def test_an_animation_past_the_limit_runs_on_the_sequence_clock_with_the_idle_held_off(
    addon: LuaRuntime,
) -> None:
    stage(addon)
    addon.execute(
        b"""
        MODEL.SetScript = function(_, name, handler) SCRIPT, ON_UPDATE = name, handler end
        STAGE:Perform(1744)
        """
    )
    assert evaluate(addon, "CALLS") == [["SetSequenceTime", 1744, 0]]
    assert evaluate(addon, "SCRIPT") == "OnUpdate", "the hold runs every frame"
    addon.execute(b"CALLS = {}; FACING = 2.5; ON_UPDATE(MODEL)")
    assert evaluate(addon, "CALLS") == [["SetRotation", 2.5]], "at the facing it already has"
