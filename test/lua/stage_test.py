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
        local told = { "SetAnimation", "SetSequenceTime", "SetRotation", "SetScript" }
        for _, name in ipairs({ "SetSheathed", "SetAlpha", "SetCamDistanceScale", "ClearModel" }) do
            told[#told + 1] = name
        end
        for _, name in ipairs(told) do
            model[name] = function(_, ...) CALLS[#CALLS + 1] = { name, ... } end
        end
        MODEL = model
        return model
    end
"""


def stage(game: LuaRuntime) -> None:
    game.execute(MODEL)
    game.execute(
        b"""
        local nothing = { ClearModel = function() end, Hide = function() end }
        STAGE = setmetatable({ model = CreateFrame(), actor = nothing, scene = nothing }, NS.Stage)
        """
    )


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
    addon.execute(b"STAGE:Perform(69, true)")
    assert evaluate(addon, "CALLS") == [["SetAnimation", 69], ["SetSheathed", False]]
    assert evaluate(addon, "CALLS[1][1]") == "SetAnimation", "the animation before the weapons"


def test_an_animation_past_the_limit_runs_on_the_sequence_clock_with_the_idle_held_off(
    addon: LuaRuntime,
) -> None:
    stage(addon)
    addon.execute(
        b"""
        MODEL.SetScript = function(_, name, handler) SCRIPT, ON_UPDATE = name, handler end
        STAGE:Perform(1744, false)
        """
    )
    assert evaluate(addon, "CALLS") == [], "nothing until the frames"
    assert evaluate(addon, "SCRIPT") == "OnUpdate", "the rest happens on the frames"
    addon.execute(b"CALLS = {}; ON_UPDATE(MODEL); ON_UPDATE(MODEL); ON_UPDATE(MODEL)")
    assert evaluate(addon, "CALLS") == [
        ["SetRotation", 1.5],
        ["SetSequenceTime", 1744, 0],
        ["SetRotation", 1.5],
        ["SetSheathed", True],
        ["SetRotation", 1.5],
    ], "the hold every frame, the animation once after the first, the weapons once after it"
    addon.execute(b"CALLS = {}; FACING = 2.5; STAGE:Loaded(); ON_UPDATE(MODEL); ON_UPDATE(MODEL)")
    assert evaluate(addon, "CALLS") == [
        ["SetRotation", 2.5],
        ["SetSequenceTime", 1744, 0],
        ["SetRotation", 2.5],
    ], "a load again starts it again at the facing the body has, and leaves the weapons"


def test_clearing_the_stage_ends_the_sequence_clock_route(addon: LuaRuntime) -> None:
    stage(addon)
    addon.execute(b"STAGE:Perform(1744, false); CALLS = {}; STAGE:Clear()")
    assert evaluate(addon, "CALLS[1]") == ["SetScript", "OnUpdate"], "the per-frame hold is dropped"
    assert evaluate(addon, "STAGE.clock") is None
    addon.execute(b"CALLS = {}; STAGE:Loaded()")
    assert evaluate(addon, "CALLS") == [], "a later load starts nothing"


def test_a_load_with_nothing_held_starts_nothing(addon: LuaRuntime) -> None:
    stage(addon)
    addon.execute(b"STAGE:Loaded()")
    assert evaluate(addon, "STAGE.loaded") is True
    assert evaluate(addon, "STAGE.clock") is None
