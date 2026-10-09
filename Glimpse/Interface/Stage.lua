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

--- How often, and how many times, a creature is asked for again. Asked for a
-- creature it has not seen, the client draws the frame's earlier display
-- again and reports that display as the frame's own; asked again a moment
-- later, it draws the creature.
local RETRY_SECONDS, RETRIES = 0.1, 5

local MAIN_HAND = 16

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
		self:Fit()
	end))

	self.model = _G.CreateFrame("DressUpModel", nil, parent)
	self.model:SetAllPoints()
	self.model:SetLight(unpack(LIGHT))

	-- An emote waits for the body to load. Set on a body still loading, the
	-- client takes a staff in hand with the wrong one.
	self.model:SetScript(
		"OnModelLoaded",
		ns.Safely.Wrap(function()
			self.loaded = true
			local pose = self.pose
			if pose then
				self.pose = nil
				self.model:SetAnimation(pose.animation)
				self.model:SetSheathed(not pose.wields)
			end
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

local function stopRetrying(self)
	if self.retry then
		self.retry:Cancel()
		self.retry = nil
	end
end

-- Whether a model frame holds a model, which a creature the client has not been
-- told about yet does not.
local function holdsModel(model)
	local file = model:GetModelFileID()
	return file ~= nil and file ~= 0
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
	-- The frame is emptied first and stays unseen until it holds a model, so an
	-- earlier creature is never shown under the new one's name, and one the client
	-- never loads, as a forged creature in an outfit, shows nothing at all.
	creature = function(self, entry)
		local model = self.model
		model:ClearModel()
		model:SetCreature(entry)
		if holdsModel(model) then
			return
		end
		model:SetAlpha(0)
		local asked = 0
		self.retry = _G.C_Timer.NewTicker(
			RETRY_SECONDS,
			ns.Safely.Wrap(function()
				asked = asked + 1
				model:SetCreature(entry)
				if holdsModel(model) then
					stopRetrying(self)
					model:SetAlpha(1)
				elseif asked == RETRIES then
					stopRetrying(self)
				end
			end),
			RETRIES
		)
	end,
	-- A display is drawn again a moment later, for the same reason a creature is
	-- asked for again, and the frame is unseen until then.
	character = function(self, display)
		local model = self.model
		model:SetAlpha(0)
		model:SetDisplayInfo(display)
		self.retry = _G.C_Timer.NewTimer(
			RETRY_SECONDS * 2,
			ns.Safely.Wrap(function()
				self.retry = nil
				model:SetDisplayInfo(display)
				model:SetAlpha(1)
			end)
		)
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
	stopRetrying(self)
	self.pose = nil
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
