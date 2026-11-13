local _, ns = ...

--- How each kind of look is presented: which drawer draws it and from what
-- angle.
--
-- A look's question decides its presentation. A prop is seen from slightly
-- above, because its footprint is what a builder places. A figure is seen at
-- eye level. The canonical view of a presentation is what the hover frame
-- shows, since the hover frame takes no input.
--
-- Angles are in degrees.
--
--   drawer    "scene" or "model": the widget that draws it
--   yaw       how far the subject is turned from facing the viewer
--   pitch     how far the view looks down on it; the scene drawer only
--   varies    true where drawing the look again may show another: the client chooses
--   body      true where the look is the player's body, whose weapons may be put away
--   still     true where the look is something happening, watched from one side rather
--             than turned by itself
local Presentations = {}
ns.Presentations = Presentations

local ROWS = {
	prop = { drawer = "scene", yaw = 30, pitch = 20 },
	-- A tinted thing is drawn as a prop is, its tint a kit on the scene's actor,
	-- which Epsilon's client can take off again.
	tinted = { drawer = "scene", yaw = 30, pitch = 20 },
	-- A creature display is a figure, drawn by a model frame: the one widget that
	-- draws every playable race's body whole, and that frames a display as large as
	-- the creature it belongs to.
	figure = { drawer = "model", yaw = 25, pitch = 5 },
	creature = { drawer = "model", yaw = 25, pitch = 5, varies = true },
	wearable = { drawer = "model", yaw = 25, pitch = 5, body = true },
	-- Worn things are turned so the part of the body that carries them faces
	-- the viewer: the weapon hand, the shield arm, the back.
	held = { drawer = "model", yaw = 92, pitch = 5, body = true },
	offhand = { drawer = "model", yaw = -40, pitch = 5, body = true },
	back = { drawer = "model", yaw = 195, pitch = 5, body = true },
	motion = { drawer = "model", yaw = 0, pitch = 5, body = true, still = true },
}

--- Which presentation each way of drawing a look takes.
local BY_DRAW = {
	file = "prop",
	tinted = "tinted",
	display = "figure",
	creature = "creature",
	tryon = "wearable",
	animation = "motion",
	enchant = "held",
}

--- Which presentation a worn thing takes, by the slot the client says it goes in.
-- A slot not named here is seen from the front.
local BY_SLOT = {
	INVTYPE_WEAPON = "held",
	INVTYPE_2HWEAPON = "held",
	INVTYPE_WEAPONMAINHAND = "held",
	INVTYPE_RANGED = "held",
	INVTYPE_RANGEDRIGHT = "held",
	INVTYPE_THROWN = "held",
	INVTYPE_WEAPONOFFHAND = "offhand",
	INVTYPE_SHIELD = "offhand",
	INVTYPE_HOLDABLE = "offhand",
	INVTYPE_CLOAK = "back",
}

--- The presentation of a look.
-- @param look a look from a subject
-- @return its presentation row
function Presentations.Of(look)
	-- Only a worn thing is turned by its slot; a slot never changes how a look is drawn.
	if look.draw == "tryon" and BY_SLOT[look.slot] then
		return ROWS[BY_SLOT[look.slot]]
	end
	return ROWS[BY_DRAW[look.draw]]
end

--- What is said where a subject has nothing to draw.
Presentations.NOTHING = "Nothing to preview"

--- What several looks drawn the same way are counted as.
local COUNTED = { display = "display", file = "model", tinted = "model" }

-- A display is named by its id, which is what a morph takes.
local function place(look, index, count)
	local counted = COUNTED[look.draw] or "look"
	if counted == "display" then
		return "display " .. look.value .. ", " .. index .. " of " .. count
	end
	return counted .. " " .. index .. " of " .. count
end

-- How many of a look its subject holds, where it holds several: "×12".
local function howMany(look)
	if look.count and look.count > 1 then
		return "×" .. look.count
	end
	return nil
end

--- Where a look stands among several of a kind, and how many of it there are.
-- @param look the look
-- @param index its place among the subject's looks
-- @param count how many looks the subject has
-- @return the words: "Display 5446, 2 of 3", "Model 2 of 3", "Model 2 of 18, ×12"
function Presentations.Place(look, index, count)
	local words = place(look, index, count):gsub("^%l", string.upper)
	local many = howMany(look)
	if many then
		words = words .. ", " .. many
	end
	return words
end

--- What is said of a look beside its picture: what kind of thing it is, then
-- the look's own name where it has one, its place among several, or the display
-- it is where the line did not name it, then how many of it there are.
-- @param subject the subject shown
-- @param index which of its looks is shown
-- @return the line: "Creature", "Emote", "Item, display 5446, 2 of 3",
--   "Item, display 17697", "Object, model 1 of 18, ×12"
function Presentations.Caption(subject, index)
	local look, count = subject.looks[index], #subject.looks
	local parts = { ns.Kinds.Word(subject) }
	if look.name then
		parts[2] = look.name
	elseif count > 1 then
		parts[2] = place(look, index, count)
	elseif COUNTED[look.draw] == "display" and look.value ~= subject.id then
		parts[2] = "display " .. look.value
	end
	parts[#parts + 1] = howMany(look)
	return table.concat(parts, ", ")
end

--- What is said beside a thing another addon shows: what kind of thing it is,
-- then the words that addon said of it.
-- @param read the read shown
-- @param words what the addon said of the thing, or nil
-- @return the line: "Spell", "Object, invisible: its collision shape"
function Presentations.Lent(read, words)
	if words then
		return ns.Kinds.Word(read) .. ", " .. words
	end
	return ns.Kinds.Word(read)
end
