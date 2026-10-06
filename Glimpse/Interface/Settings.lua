local _, ns = ...

--- What the player has chosen, and what holds where they have not.
--
-- Only a choice that differs from its default is saved, so a default can
-- change in a later version without overriding anyone. A saved value of the
-- wrong type is read as the default: the saved file is the player's to edit
-- and may hold anything.
local Settings = {}
ns.Settings = Settings

--- Every setting and its default.
--   hover           whether resting on a button shows a preview
--   hoverSize       the side of the hover preview's picture, in pixels
--   hoverSpin       whether the hover preview turns by itself
--   sideBySide      whether the hover preview gives each of several looks of a kind a card
--   manyWindows     whether each click opens a window of its own rather than reusing one
--   windowPlace     where the window stands and its size, `{ left, top, width, height }`;
--                   empty until the player has moved or sized it
--   off             the kinds the player has turned off, as a set: their lines gain no button
Settings.DEFAULTS = {
	hover = true,
	hoverSize = 300,
	hoverSpin = true,
	sideBySide = false,
	manyWindows = false,
	windowPlace = {},
	off = {},
}

--- A setting's value.
-- @param key a key of `Settings.DEFAULTS`
-- @return the player's choice, or the default where there is none
function Settings.Get(key)
	local default = Settings.DEFAULTS[key]
	local saved = _G.GlimpseSettings
	if type(saved) == "table" and type(saved[key]) == type(default) then
		return saved[key]
	end
	return default
end

--- Choose a setting's value.
-- @param key a key of `Settings.DEFAULTS`
-- @param value the choice; the default's own value clears the choice
function Settings.Set(key, value)
	if type(_G.GlimpseSettings) ~= "table" then
		_G.GlimpseSettings = {}
	end
	if value == Settings.DEFAULTS[key] then
		_G.GlimpseSettings[key] = nil
	else
		_G.GlimpseSettings[key] = value
	end
end

--- Whether the player wants a kind previewed.
-- @param kind a kind
-- @return false where the player has turned it off
function Settings.On(kind)
	return Settings.Get("off")[kind] ~= true
end

--- Turn a kind's previews on or off.
-- @param kind a kind
-- @param on false to turn it off
function Settings.Turn(kind, on)
	local off = {}
	for each, value in pairs(Settings.Get("off")) do
		off[each] = value
	end
	off[kind] = nil
	if not on then
		off[kind] = true
	end
	if next(off) == nil then
		off = Settings.DEFAULTS.off
	end
	Settings.Set("off", off)
end

--- Clear every choice.
function Settings.Reset()
	_G.GlimpseSettings = {}
end
