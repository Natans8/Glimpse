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


#: A model frame that draws a creature once the client has it: `HAS` names the creatures the
#: client holds and `FILES` the model file each draws, 124640 being the invisible stalker an
#: NPC in an outfit stands in. Its frame script is kept as `ON_UPDATE`, nil once taken off.
DRAWING = b"""
    CALLS, HAS, FILES, SAID = {}, {}, { [32] = 126077, [2372187] = 124640 }, 0
    function CreateFrame()
        local model = { file = 0 }
        function model:SetScript(name, handler)
            if name == "OnUpdate" then ON_UPDATE = handler end
        end
        function model:SetCreature(entry)
            CALLS[#CALLS + 1] = { "SetCreature", entry }
            if HAS[entry] then self.file = FILES[entry] end
        end
        function model:GetModelFileID() return self.file end
        function model:ClearModel() self.file = 0 end
        function model:SetAlpha(alpha) ALPHA = alpha end
        function model:SetModel(file) CALLS[#CALLS + 1] = { "SetModel", file } end
        function model:ApplySpellVisualKit(kit, oneShot)
            CALLS[#CALLS + 1] = { "ApplySpellVisualKit", kit, oneShot }
        end
        for _, name in ipairs({ "Show", "Hide", "SetFacing", "SetCamDistanceScale" }) do
            model[name] = function() end
        end
        return model
    end
    local nothing = { ClearModel = function() end, Hide = function() end }
    STAGE = setmetatable({ model = CreateFrame(), actor = nothing, scene = nothing }, NS.Stage)
    STAGE:WhenNothing(function() SAID = SAID + 1 end)
"""


#: A scene whose actor records what it was told, Epsilon's `ClearAllEffects` among it, and whose
#: drawn frames are `STAGE:Drawn()`, called by hand. Its bounding box answers nothing, so the
#: camera is left where it is. `KIT_CALLS()` is what the actor was told about kits and effects.
TINTING = b"""
    CALLS = {}
    local function told(name)
        return function(_, ...) CALLS[#CALLS + 1] = { name, ... } end
    end
    local actor = { GetModelFileID = function() return 875053 end }
    function actor.GetActiveBoundingBox() end
    for _, name in ipairs({ "SetModelByFileID", "SetSpellVisualKit", "ClearModel", "SetYaw" }) do
        actor[name] = told(name)
    end
    actor.ClearAllEffects = told("ClearAllEffects")
    ACTOR = actor
    local frame = {}
    for _, name in ipairs({ "Show", "Hide", "SetScript", "SetAlpha", "SetCamDistanceScale" }) do
        frame[name] = function() end
    end
    frame.ClearModel = function() end
    function KIT_CALLS()
        local calls = {}
        for _, call in ipairs(CALLS) do
            if call[1] == "SetSpellVisualKit" or call[1] == "ClearAllEffects" then
                calls[#calls + 1] = call
            end
        end
        return calls
    end
    STAGE = setmetatable({ model = frame, actor = actor, scene = frame }, NS.Stage)
    STAGE:Show({ draw = "tinted", value = 875053, kit = 167021 })
"""

#: A tinted look loaded and given its tint, two drawn frames after the load.
TINTED = b"STAGE:ActorLoaded(); STAGE:Drawn(); STAGE:Drawn(); CALLS = {}"


def test_a_tint_is_given_on_a_frame_drawn_after_the_model_loads(addon: LuaRuntime) -> None:
    addon.execute(TINTING)
    assert evaluate(addon, "CALLS[2]") == ["SetModelByFileID", 875053], "drawn by the scene"
    addon.execute(b"STAGE:Drawn()")
    assert evaluate(addon, "KIT_CALLS()") == [], "no kit before the model loads"
    addon.execute(b"STAGE:ActorLoaded(); STAGE:Drawn()")
    assert evaluate(addon, "KIT_CALLS()") == [], "the frame it is asked in may be the load's own"
    addon.execute(b"STAGE:Drawn(); STAGE:Drawn()")
    assert evaluate(addon, "KIT_CALLS()") == [["SetSpellVisualKit", 167021, False]], "once"


def test_a_look_cleared_before_its_tint_is_not_tinted(addon: LuaRuntime) -> None:
    addon.execute(TINTING)
    addon.execute(b"STAGE:ActorLoaded(); STAGE:Clear(); STAGE:Drawn(); STAGE:Drawn()")
    assert evaluate(addon, "KIT_CALLS()") == [], "never tinted, so nothing to take off either"


def test_clearing_a_tinted_look_takes_off_what_the_tint_painted(addon: LuaRuntime) -> None:
    addon.execute(TINTING)
    addon.execute(TINTED + b"; STAGE:Clear()")
    assert evaluate(addon, "CALLS") == [
        ["SetSpellVisualKit"],
        ["ClearAllEffects"],
        ["ClearModel"],
    ], "the kit off, then what it painted, then the model"
    addon.execute(b"CALLS = {}; STAGE:Clear()")
    assert evaluate(addon, "KIT_CALLS()") == [], "once"


def test_a_client_without_epsilons_call_takes_the_kit_off_alone(addon: LuaRuntime) -> None:
    addon.execute(TINTING)
    addon.execute(b"ACTOR.ClearAllEffects = nil; " + TINTED + b"; STAGE:Clear()")
    assert evaluate(addon, "KIT_CALLS()") == [["SetSpellVisualKit"]]


def test_a_creature_the_client_has_not_seen_is_asked_for_each_frame_until_it_is_held(
    addon: LuaRuntime,
) -> None:
    addon.execute(DRAWING)
    addon.execute(b'STAGE:Show({ draw = "creature", value = 32 })')
    assert evaluate(addon, "ALPHA") == 0, "unseen while it is not held"
    addon.execute(b"ON_UPDATE(); ON_UPDATE()")
    assert evaluate(addon, "#CALLS") == 3, "asked again on each frame"
    addon.execute(b"HAS[32] = true; ON_UPDATE()")
    assert evaluate(addon, "ALPHA") == 1
    assert evaluate(addon, "ON_UPDATE") is None, "and no more once held"
    assert evaluate(addon, "SAID") == 0


def test_a_creature_the_client_draws_as_the_invisible_stalker_shows_nothing(
    addon: LuaRuntime,
) -> None:
    addon.execute(DRAWING)
    addon.execute(b'HAS[2372187] = true; STAGE:Show({ draw = "creature", value = 2372187 })')
    assert evaluate(addon, "SAID") == 1, "said at once, with nothing counted down"
    assert evaluate(addon, "ALPHA") == 0
    assert evaluate(addon, "ON_UPDATE") is None


#: A scene for the camera's fit: every call it is given is a no-op but the zoom distances, which
#: are kept, its field of view 60 degrees, and its model's bounds a cube two units across.
FITTING = b"""
    ZOOM = {}
    local quiet = setmetatable({}, { __index = function() return function() end end })
    local camera = setmetatable({
        SetZoomDistance = function(_, d) ZOOM.at = d end,
        SetMinZoomDistance = function(_, d) ZOOM.nearest = d end,
        SetMaxZoomDistance = function(_, d) ZOOM.farthest = d end,
    }, { __index = quiet })
    local scene = setmetatable({
        GetActiveCamera = function() return camera end,
        GetCameraFieldOfView = function() return math.rad(60) end,
    }, { __index = quiet })
    local actor = setmetatable({
        GetActiveBoundingBox = function() return -1, -1, -1, 1, 1, 1 end,
    }, { __index = quiet })
    STAGE = setmetatable({ model = quiet, actor = actor, scene = scene }, NS.Stage)
    STAGE.presentation = { pitch = 0, yaw = 0, drawer = "scene" }
    STAGE.turned, STAGE.tilted, STAGE.zoom = 0, 0, 1
"""


def test_the_camera_stands_where_the_model_fills_the_view_at_any_turn(addon: LuaRuntime) -> None:
    addon.execute(FITTING)
    addon.execute(b"STAGE:Fit()")
    radius = 12**0.5 / 2
    at = evaluate(addon, "ZOOM.at")
    assert isinstance(at, float)
    assert abs(at - radius / 0.5 * 1.08) < 1e-9, (
        "half the diagonal over the sine of half the field of view, with a little room"
    )
    assert evaluate(addon, "ZOOM.nearest") == at * 0.5
