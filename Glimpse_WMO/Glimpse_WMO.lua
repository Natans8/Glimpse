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

-- A picture is square and stays so whatever shape the frame takes, centred at
-- the largest square that fits.
local function fit(picture, width, height)
	local side = math.min(width, height)
	picture:SetSize(side, side)
end

-- The picture this addon draws on a lent frame, made once for each frame.
local function pictureFor(frame)
	if frame.glimpseWmo then
		return frame.glimpseWmo
	end
	local picture = frame:CreateTexture(nil, "ARTWORK")
	picture:SetPoint("CENTER")
	frame:HookScript("OnSizeChanged", function(_, width, height)
		fit(picture, width, height)
	end)
	frame.glimpseWmo = picture
	return picture
end

-- The picture of a thing: by its gameobject entry where the index knows the
-- entry, which a stock object named in words has, and otherwise by the WMO's
-- file name, which every other line prints. A WMO that draws nothing from
-- outside is 0, a watertile among them; the index keeps a watertile's liquid
-- type (`liquids`), so a preview of its surface can come here later without the
-- pictures being rendered again.
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

--- What is said of a picture of a WMO the client shows nothing of, which shows its
-- collision shape in its place; the index lists those pictures by number. Glimpse
-- puts the words after the kind, on the line under the name: "Object, invisible:
-- its collision shape".
local COLLISION = "invisible: its collision shape"

-- The words said of a picture, or nil for a picture of what the client shows.
local function wordsOf(index, number)
	if index.collision and numbered(index.collision, string.format("%09d", number)) then
		return COLLISION
	end
	return nil
end

-- The number of a thing's picture, or nil where there is none to show: the index
-- is not loaded, does not know the thing, or knows it draws nothing.
local function shownOf(index, id, context)
	local number = index and pictureOf(index, id, context and context.name)
	if number == 0 then
		return nil
	end
	return number
end

-- A line gains a button only where there is a picture to show.
local function shows(id, context)
	return shownOf(_G[addonName], id, context) ~= nil
end

local function show(frame, id, context)
	local index = _G[addonName]
	local number = shownOf(index, id, context)
	if not number then
		return false
	end
	local picture = pictureFor(frame)
	fit(picture, frame:GetSize())
	picture:SetTexture(pathOf(number))
	picture:Show()
	return true, wordsOf(index, number)
end

local function hide(frame)
	local picture = frame.glimpseWmo
	if picture then
		picture:SetTexture(nil)
		picture:Hide()
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

-- A WMO is named by an object line through its display, and by a line of
-- `.lookup wmo` through its file; both carry the file's name, so one provider
-- serves both kinds.
if _G.Glimpse and _G.Glimpse.Provide then
	local provider = { name = "Glimpse WMO pictures", Shows = shows, Show = show, Hide = hide }
	_G.Glimpse.Provide("wmo", provider)
	_G.Glimpse.Provide("wmoarea", provider)
end
