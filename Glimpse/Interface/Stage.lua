local _, ns = ...

--- The stage: where a look is drawn.
--
-- A stage fills the frame it is given and draws one look at a time under the
-- look's presentation. It has two drawers. The scene draws an object's model
-- file or a creature display with a camera fitted to the model's bounds, as
-- the client's own mount list does. The model drawer draws what a model frame
-- draws best: a creature from its entry, a character's display, which a scene
-- leaves pieces out of, and the player's body wearing something or performing
-- an animation.
--
-- This is the only file that hands anything to the client's model loader. A
-- file reaches it only from a display id, the client's object search, or a
-- generated table gated on `.m2`; everything else it loads is an id the client
-- resolves itself.
local Presentations = ns.Presentations

local Stage = {}
Stage.__index = Stage
ns.Stage = Stage

--- The item an enchant is shown on where the player holds no weapon.
local PLAIN_SWORD = 25

local MAIN_HAND = 16

--- The model files the client draws for a creature with nothing to show: the
-- invisible stalker, which is what an NPC dressed in an outfit stands in as far
-- as any client but the server's own view of it is concerned.
local NOTHING_SHOWN = { [124640] = true, [124642] = true }

--- The client's model scene whose camera the scene takes: an orbit camera.
local SCENE_CAMERA = 114

--- The light a model frame's body stands in: from the front and a little above, bright enough
-- to read against a dark panel. In order: lit, not from every side, the light's direction,
-- how strong and what colour its ambient part is, then its direct part.
local LIGHT = { true, false, 0, 0.8, -1, 1, 1, 1, 1, 0.3, 1, 1, 1 }

--- How near and how far the wheel may take the view, as a share of the fitted distance.
local NEAREST, FARTHEST, ZOOM_STEP = 0.5, 2, 0.9

--- How far the scene's camera may look down on a model or up at it: short of
-- straight down and straight up, where the view would turn over.
local STEEPEST = math.rad(85)

--- A stage filling a frame.
-- @param parent the frame to fill
-- @return the stage
function Stage.New(parent)
	local self = setmetatable({}, Stage)

	self.scene = _G.CreateFrame("ModelScene", nil, parent, "ModelSceneMixinTemplate")
	self.scene:SetAllPoints()
	self.scene:SetCameraNearClip(0.01)
	self.scene:SetCameraFarClip(2 ^ 64)
	self.scene:CreateCameraFromScene(SCENE_CAMERA)
	self.actor = self.scene:CreateActor(nil, "ModelSceneActorTemplate")
	self.actor:SetUseCenterForOrigin(true, true, true)
	self.actor:SetOnModelLoadedCallback(ns.Safely.Wrap(function()
		self.loaded = true
		if NOTHING_SHOWN[self.actor:GetModelFileID()] then
			self:Nothing()
			return
		end
		self:Fit()
	end))

	self.model = _G.CreateFrame("DressUpModel", nil, parent)
	self.model:SetAllPoints()
	self.model:SetLight(unpack(LIGHT))

	self.model:SetScript(
		"OnModelLoaded",
		ns.Safely.Wrap(function()
			self:Loaded()
		end)
	)

	self:Clear()
	return self
end

-- How far the scene's camera stands from the fitted model, at a share of the
-- distance that holds it.
local function distance(self, share)
	return self.size * 1.1 * share
end

--- Frame the scene's model: the camera far enough to hold its bounds, at the
-- presentation's angle.
function Stage:Fit()
	local x1, y1, z1, x2, y2, z2 = self.actor:GetActiveBoundingBox()
	if not x2 or not self.presentation then
		return
	end
	self.size = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2 + (z2 - z1) ^ 2) * 1.5
	local camera = self.scene:GetActiveCamera()
	camera:SetPitch(math.rad(self.presentation.pitch) - self.tilted)
	camera:SetYaw(0)
	camera:SetRoll(0)
	camera:SetTarget(0, 0, 0)
	camera:SetMinZoomDistance(distance(self, NEAREST))
	camera:SetMaxZoomDistance(distance(self, FARTHEST))
	camera:SetZoomDistance(distance(self, self.zoom))
	camera:SnapAllInterpolatedValues()
	self.actor:SetPosition(0, 0, 0)
	self:Turn(0)
end

--- Bring what is drawn nearer, or send it back.
-- @param steps how many steps nearer; negative for farther
function Stage:Zoom(steps)
	if not self.presentation then
		return
	end
	self.zoom = math.max(NEAREST, math.min(FARTHEST, self.zoom * ZOOM_STEP ^ steps))
	if self.presentation.drawer == "model" then
		self.model:SetCamDistanceScale(self.zoom)
	elseif self.size then
		local camera = self.scene:GetActiveCamera()
		camera:SetZoomDistance(distance(self, self.zoom))
		camera:SnapAllInterpolatedValues()
	end
end

--- Put the view back as the look was first drawn: its own angle and distance.
function Stage:Reset()
	self.turned, self.zoom, self.tilted = 0, 1, 0
	self:Turn(0)
	self:Tilt(0)
	self:Zoom(0)
end

--- Tilt what the scene draws, so its top or its bottom comes round. A model
-- frame turns about the upright axis alone, so a body is not tilted.
-- @param radians how far; positive brings the bottom into view
function Stage:Tilt(radians)
	if not (self.presentation and self.presentation.drawer == "scene" and self.size) then
		return
	end
	local level = math.rad(self.presentation.pitch)
	self.tilted = math.max(level - STEEPEST, math.min(level + STEEPEST, self.tilted + radians))
	local camera = self.scene:GetActiveCamera()
	camera:SetPitch(level - self.tilted)
	camera:SnapAllInterpolatedValues()
end

--- Put the body's weapons away, or take them in hand, whichever they are not.
-- Only a look of the player's body has weapons to move.
function Stage:Sheathe()
	if self.presentation and self.presentation.body then
		self.model:SetSheathed(not self.model:GetSheathed())
	end
end

--- Turn what is drawn about its upright axis, from wherever it now faces. A
-- model that has not appeared yet is not turned, so a turn starts where it can
-- be seen.
-- @param radians how far to turn it
function Stage:Turn(radians)
	if not self.presentation then
		return
	end
	if self.loaded then
		self.turned = self.turned + radians
	end
	local facing = math.rad(self.presentation.yaw) + self.turned
	if self.presentation.drawer == "scene" then
		self.actor:SetYaw(math.pi + facing)
	elseif self.presentation.drawer == "model" then
		self.model:SetFacing(facing)
	end
end

--- Have the body perform an animation, once it has loaded, with its weapons
-- in hand or away as the animation asks. The animation is set before the
-- weapons move: in the other order, a staff is taken in hand with the wrong one.
--
-- An animation at or past the client's limit is refused by `SetAnimation`, so it
-- is started through the sequence clock, which has no such check. The frame
-- then replays its idle over anything else it finds itself playing, unless it
-- was just told its facing: `SetRotation` holds that replay off for a tenth of
-- a second, so it is told again each frame. It is told the facing it already
-- has, since a different one would turn the body with a turning animation. On
-- this route the animation starts on the first frame after the body loads, the
-- weapons move on the frame after that, and the animation starts again whenever
-- the body loads again, since a load puts it back at rest.
-- @param animation an animation id
-- @param wields whether the animation takes the weapons in hand
function Stage:Perform(animation, wields)
	local model = self.model
	if animation < ns.Client.AnimationLimit() then
		model:SetAnimation(animation)
		model:SetSheathed(not wields)
		return
	end
	local clock = { animation = animation, sheathed = not wields, starting = true }
	self.clock = clock
	model:SetScript(
		"OnUpdate",
		ns.Safely.Wrap(function()
			model:SetRotation(model:GetFacing())
			if clock.starting then
				clock.starting = false
				model:SetSequenceTime(clock.animation, 0)
			elseif clock.sheathed ~= nil then
				model:SetSheathed(clock.sheathed)
				clock.sheathed = nil
			end
		end)
	)
end

-- Call `step` on each frame the model frame draws until it answers true. What
-- the stage waits for is always something the client does, a load or a frame
-- drawn, never a length of time.
local function everyFrame(self, step)
	local model = self.model
	model:SetScript(
		"OnUpdate",
		ns.Safely.Wrap(function()
			if step() then
				model:SetScript("OnUpdate", nil)
			end
		end)
	)
end

--- Take up what waited for the model to load. An emote waits for the body: set
-- on a body still loading, the client takes a staff in hand with the wrong one.
-- A body holding an animation the frame refuses starts it afresh. A tint waits
-- for the frame after the load: a kit given to a model not yet drawn is dropped.
function Stage:Loaded()
	self.loaded = true
	local pose, kit = self.pose, self.kit
	if pose then
		self.pose = nil
		self:Perform(pose.animation, pose.wields)
	elseif self.clock then
		self.clock.starting = true
	elseif kit then
		self.kit = nil
		everyFrame(self, function()
			self.model:ApplySpellVisualKit(kit, false)
			return true
		end)
	end
end

-- Whether a model frame holds a model, which a creature the client has not been
-- told about yet does not.
local function holdsModel(model)
	local file = model:GetModelFileID()
	return file ~= nil and file ~= 0
end

-- Ask the model frame for something until it holds a model, unseen meanwhile.
-- Asked for a creature it has not seen, the client sends for it and draws
-- nothing until it is asked again once it has it, so it is asked again on each
-- frame until then. The frame was emptied before, so an earlier creature is
-- never shown under the new one's name. A model that shows nothing stays unseen,
-- and the stage says so.
local function untilHeld(self, ask)
	local model = self.model
	model:SetAlpha(0)
	local function held()
		if not holdsModel(model) then
			return false
		end
		if NOTHING_SHOWN[model:GetModelFileID()] then
			self:Nothing()
		else
			model:SetAlpha(1)
		end
		return true
	end
	ask(model)
	if held() then
		return
	end
	everyFrame(self, function()
		ask(model)
		return held()
	end)
end

-- The player's body, wearing only what the look puts on it.
local function body(model)
	model:SetUnit("player")
	model:Undress()
end

--- How each way of drawing a look draws it, on the drawer its presentation names.
local DRAW = {
	file = function(self, file)
		self.actor:SetModelByFileID(file)
	end,
	display = function(self, display)
		self.actor:SetModelByCreatureDisplayID(display)
	end,
	-- The model is shown as it is and tinted once it has loaded and been drawn,
	-- since a model not seen is not drawn and a kit given to one undrawn is dropped.
	tinted = function(self, file, look)
		self.kit = look.kit
		self.model:SetModel(file)
	end,
	creature = function(self, entry)
		untilHeld(self, function(model)
			model:SetCreature(entry)
		end)
	end,
	character = function(self, display)
		untilHeld(self, function(model)
			model:SetDisplayInfo(display)
		end)
	end,
	tryon = function(self, item)
		body(self.model)
		self.model:SetSheathed(false)
		self.model:TryOn("item:" .. item)
	end,
	enchant = function(self, enchant)
		local weapon = _G.GetInventoryItemID("player", MAIN_HAND) or PLAIN_SWORD
		self.model:SetUnit("player")
		self.model:TryOn("item:" .. weapon .. ":" .. enchant, "MAINHANDSLOT")
	end,
	-- An emote is shown as a player at rest performs it, weapons away, but for
	-- the attacks, stances and the like that the client takes them in hand for.
	-- The emote is set before the weapons move, once the body has loaded: in
	-- any other order, a staff is taken in hand with the wrong one.
	animation = function(self, animation, look)
		self.pose = { animation = animation, wields = look.wields }
		self.model:SetUnit("player")
	end,
}

--- Say what is done when a look turns out to show nothing at all, as an NPC in an
-- outfit does, so whoever shows the stage can say so.
-- @param nothing a function called with no arguments
function Stage:WhenNothing(nothing)
	self.nothing = nothing
end

--- The look shows nothing: say so, where anyone asked.
function Stage:Nothing()
	if self.nothing then
		self.nothing()
	end
end

--- Draw a look, replacing whatever was drawn.
-- @param look a look from a subject
-- @param turned optional; how far from its presentation's angle it starts, in radians
function Stage:Show(look, turned)
	self:Clear()
	local presentation = Presentations.Of(look)
	self.presentation = presentation
	self.turned = turned or 0
	-- A model frame applies nothing while hidden, so the drawer is shown first.
	if presentation.drawer == "scene" then
		self.scene:Show()
	else
		self.model:Show()
	end
	DRAW[look.draw](self, look.value, look)
	self:Turn(0)
end

--- Draw nothing.
function Stage:Clear()
	self.pose, self.clock, self.kit = nil, nil, nil
	self.model:SetScript("OnUpdate", nil)
	self.model:SetAlpha(1)
	self.model:SetCamDistanceScale(1)
	self.presentation = nil
	self.turned, self.tilted, self.zoom, self.size = 0, 0, 1, nil
	self.loaded = false
	self.actor:ClearModel()
	self.model:ClearModel()
	self.scene:Hide()
	self.model:Hide()
end
