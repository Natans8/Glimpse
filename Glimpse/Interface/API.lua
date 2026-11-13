local _, ns = ...

--- What other addons may call: the one global this addon creates.
--
--   Glimpse.Provide(kind, provider)   offer previews of a kind in this addon's
--                                     frames; `Providers` says what a provider is
--   Glimpse.Peek(read)                show a thing at the pointer, as resting on its
--                                     button does; true where the hover frame shows
--   Glimpse.Unpeek()                  take the hover frame down
--   Glimpse.Open(read)                do what a click on its button does: open the
--                                     window, or close the window showing it; true where
--                                     anything was done
--   Glimpse.View(frame)               a view filling a frame of the caller's own, which
--                                     draws a thing with nothing of this addon's around it;
--                                     nil where `frame` is no frame. Its methods:
--     view:Show(read, index, done)    draw a thing as the hover frame would, still; `index`
--                                     picks one of its looks (a creature's displays, a set's
--                                     models), the first where it has fewer; `done`, where
--                                     given, is called with how many looks it has, 0 for
--                                     nothing to show; true where the kind is drawn
--     view:Looks()                    how many looks the thing shown has
--     view:Clear()                    draw nothing
--
-- A read says what a line would have said of the thing: its `kind`, its `id` and its
-- `name`; where a kind's line carries more, its `names` (the models a detail doodad's
-- row names) and its `ids` (a spawned object's GUID, a spawned creature's display); and
-- for the `models` kind the list `models = { { file = , count = }, ... }`, most numerous
-- first. Only those fields are read, each checked, and the table is not kept. The
-- player's choices hold: a kind turned off shows nothing, and neither does a peek while
-- the hover is turned off. A fault in the door is this addon's own; it is reported once
-- and never raised into the addon that called.
--
-- An addon calling at its own load lists this one in its `OptionalDeps`, so this one
-- has loaded first.
local Kinds, Safely = ns.Kinds, ns.Safely

-- Whether a value is a whole number of one or more.
local function whole(value)
	return type(value) == "number" and value >= 1 and value == math.floor(value)
end

-- The models a list names, each `{ file, count }` of whole numbers; nil for no list.
local function modelsOf(list)
	if type(list) ~= "table" then
		return nil
	end
	local models = {}
	for _, each in ipairs(list) do
		if type(each) == "table" and whole(each.file) and whole(each.count) then
			models[#models + 1] = { file = each.file, count = each.count }
		end
	end
	return models
end

-- The values of a list that are of one type and pass a check; nil where none are, as a
-- line that names none leaves the field out.
local function listOf(list, kind, check)
	if type(list) ~= "table" then
		return nil
	end
	local kept = {}
	for _, value in ipairs(list) do
		if type(value) == kind and check(value) then
			kept[#kept + 1] = value
		end
	end
	if kept[1] == nil then
		return nil
	end
	return kept
end

local function anything()
	return true
end

-- A read of this addon's own from the one another addon gave, or nil where it names
-- no kind this addon knows.
local function readOf(given)
	if type(given) ~= "table" or not Kinds.Known(given.kind) then
		return nil
	end
	local read = {
		kind = given.kind,
		id = 0,
		name = "",
		names = listOf(given.names, "string", anything),
		ids = listOf(given.ids, "number", whole),
		models = modelsOf(given.models),
	}
	if type(given.id) == "number" then
		read.id = given.id
	end
	if type(given.name) == "string" then
		read.name = given.name
	end
	return Kinds.Settle(read)
end

-- Show a thing at the pointer where the player has hovers on, its kind is drawn rather
-- than played, and something previews it.
local function peek(given)
	local read = readOf(given)
	local drawer = read and ns.Chat.Drawer(read)
	if not (drawer and ns.Settings.Get("hover")) then
		return false
	end
	if drawer == "own" and not Kinds.Draws(read) then
		return false
	end
	ns.Peek.Show(read, drawer == "provider", true)
	return true
end

local function open(given)
	local read = readOf(given)
	return read ~= nil and ns.Chat.Open(read, 1)
end

-- A view of the caller's, its methods called with a colon: the first argument is the
-- handle itself, which they do not read.
local function view(frame)
	local isFrame = type(frame) == "table"
		and type(frame.IsObjectType) == "function"
		and frame:IsObjectType("Frame")
	if not isFrame then
		return nil
	end
	local drawn = ns.View.New(frame)
	return {
		Show = Safely.Wrap(function(_, given, index, done)
			if type(done) ~= "function" then
				done = nil
			end
			local read = readOf(given)
			if read == nil then
				drawn:Clear()
				if done then
					pcall(done, 0)
				end
				return false
			end
			if type(index) ~= "number" then
				index = 1
			end
			return drawn:Show(read, index, done)
		end),
		Looks = Safely.Wrap(function()
			return drawn:Looks()
		end),
		Clear = Safely.Wrap(function()
			drawn:Clear()
		end),
	}
end

_G.Glimpse = {
	Provide = ns.Providers.Provide,
	Peek = Safely.Wrap(peek),
	Unpeek = Safely.Wrap(function()
		ns.Peek.Hide()
	end),
	Open = Safely.Wrap(open),
	View = Safely.Wrap(view),
}
