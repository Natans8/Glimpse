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
--
-- A read says what a line would have said of the thing: its `kind`, its `id` and its
-- `name`, and for the `models` kind the list `models = { { file = , count = }, ... }`,
-- most numerous first. Only those fields are read, each checked, and the table is not
-- kept. The player's choices hold: a kind turned off shows nothing, and neither does a
-- peek while the hover is turned off. A fault in the door is this addon's own; it is
-- reported once and never raised into the addon that called.
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

-- A read of this addon's own from the one another addon gave, or nil where it names
-- no kind this addon knows.
local function readOf(given)
	if type(given) ~= "table" or not Kinds.Known(given.kind) then
		return nil
	end
	local read = { kind = given.kind, id = 0, name = "", models = modelsOf(given.models) }
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

_G.Glimpse = {
	Provide = ns.Providers.Provide,
	Peek = Safely.Wrap(peek),
	Unpeek = Safely.Wrap(function()
		ns.Peek.Hide()
	end),
	Open = Safely.Wrap(open),
}
