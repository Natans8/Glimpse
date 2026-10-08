local addonName = ...

--- Pictures of WMOs for Glimpse, which no model frame can draw.
--
-- Glimpse reads the line and lends the inside of its hover frame or window;
-- this addon fills it with the picture. A line names a WMO by its file, so
-- the name Glimpse passes along is what the index is searched for: without
-- folder, tag, extension or trailing space, in lower case. A picture is named
-- by its WMO's file id, which never changes, so a later set adds and replaces
-- pictures without renaming the rest; a hundred thousand ids share a folder.
local FOLDER = "Interface\\AddOns\\" .. addonName .. "\\Pictures\\"
local PER_FOLDER = 100000

-- A WMO file's name as the index keys it.
local function stem(name)
	local file = name:match("([^/\\]+)$") or name
	file = file:gsub("^%[.-%]%s*", "")
	return (file:match("^(.-)%s*$"):lower():gsub("%.wmo$", ""))
end

-- The number a name is paired with in the index, `;name=number;` after another
-- in sorted order. The search halves the string; each step reads the first
-- whole entry at or after its middle.
local function numbered(keyed, wanted)
	local low, high = 1, #keyed
	while low < high do
		local middle = math.floor((low + high) / 2)
		local start = keyed:find(";", middle, true)
		local name, value = keyed:match("^([^=;]*)=(%d+)", start + 1)
		if name == wanted then
			return tonumber(value)
		end
		-- Past the last entry there is no name, which counts as above every name.
		if name and name < wanted then
			low = start + 1
		else
			high = middle
		end
	end
	return nil
end

-- The path of a picture, by its number.
local function pathOf(number)
	return string.format("%s%03d\\%d.blp", FOLDER, math.floor(number / PER_FOLDER), number)
end

-- The texture this addon draws on a lent frame, made once for each frame. A
-- picture is square and stays so whatever shape the frame takes, centred at
-- the largest square that fits.
local function pictureOn(frame)
	if frame.glimpseWmoPicture then
		return frame.glimpseWmoPicture
	end
	local picture = frame:CreateTexture(nil, "ARTWORK")
	picture:SetPoint("CENTER")
	frame.glimpseWmoPicture = picture
	frame:HookScript("OnSizeChanged", function(_, width, height)
		local side = math.min(width, height)
		picture:SetSize(side, side)
	end)
	return picture
end

-- The picture of a thing: by its gameobject entry where the index knows the
-- entry, which a stock object named in words has, and otherwise by the WMO's
-- file name, which every other line prints.
local function pictureOf(index, id, name)
	local number = nil
	if type(id) == "number" and index.entries then
		number = numbered(index.entries, string.format("%09d", id))
	end
	if not number and type(name) == "string" then
		number = numbered(index.pictures, stem(name))
	end
	return number
end

--- What is said of a WMO that draws nothing from outside, which the index
-- marks with 0 in place of a picture.
local NOTHING =
	"Nothing to see from outside: this WMO draws nothing, as collision, trigger and liquid WMOs do."

-- The line of text this addon says on a lent frame, made once for each frame.
local function noteOn(frame)
	if frame.glimpseWmoNote then
		return frame.glimpseWmoNote
	end
	local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	note:SetPoint("CENTER")
	note:SetWidth(240)
	note:SetJustifyH("CENTER")
	frame.glimpseWmoNote = note
	return note
end

local function show(frame, id, context)
	local index = _G[addonName]
	if not index then
		return false
	end
	local number = pictureOf(index, id, context and context.name)
	if not number then
		return false
	end
	if number == 0 then
		local note = noteOn(frame)
		note:SetText(NOTHING)
		note:Show()
		return true
	end
	local picture = pictureOn(frame)
	local side = math.min(frame:GetSize())
	picture:SetSize(side, side)
	picture:SetTexture(pathOf(number))
	picture:Show()
	return true
end

local function hide(frame)
	local picture = frame.glimpseWmoPicture
	if picture then
		picture:SetTexture(nil)
		picture:Hide()
	end
	if frame.glimpseWmoNote then
		frame.glimpseWmoNote:Hide()
	end
end

--- The picture of a WMO, for any addon: by its gameobject entry, its file name,
-- or both. The index is this addon's one global, so `Glimpse_WMO.Picture`
-- exists exactly while the pictures are installed.
-- @param id optional; a gameobject entry
-- @param name optional; a WMO's file name, with or without folder, tag or extension
-- @return the texture's path; false for a WMO that draws nothing from outside;
--   nil where there is no picture
_G[addonName].Picture = function(id, name)
	local number = pictureOf(_G[addonName], id, name)
	if number == 0 then
		return false
	end
	if number then
		return pathOf(number)
	end
	return nil
end

if _G.Glimpse and _G.Glimpse.Provide then
	_G.Glimpse.Provide("wmo", { name = "Glimpse WMO pictures", Show = show, Hide = hide })
end
