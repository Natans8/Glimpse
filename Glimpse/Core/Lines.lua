local _, ns = ...

--- Reading a system line the server printed.
--
-- A line does not say which command produced it, so a line is recognised by
-- the typed link the server put on it, whichever command that was. The few
-- kinds that carry no link are recognised by the whole line's shape, and for
-- sounds also by the printed id and name agreeing with the shipped table,
-- since three kinds and any number of unrelated lines print that shape.
--
-- Every kind of line `.lookup` prints is read, including those only another
-- addon previews, so such an addon can offer any of them.
--
-- A read is `{ kind, id, name }`, with `names` for a detail doodad. A read is
-- shared between callers and is not changed.
local Lines = {}
ns.Lines = Lines

-- Text without colour codes or surrounding spaces.
local function plain(text)
	if text:find("|", 1, true) then
		text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	end
	return text:match("^%s*(.-)%s*$")
end

-- A label without its brackets, or the parentheses a deleted object's line uses.
local function unbracket(label)
	return plain(label:match("^%[(.*)%]$") or label:match("^%((.*)%)$") or label)
end

-- A link's label as far as its closing bracket. A link the server leaves open, as
-- on a spawned object's line, would otherwise run on into the next link.
local function closed(label)
	return label:match("^%b[]") or label:match("^%b()") or label
end

--- A model's name without the tag some carry in front of it. The server
-- marks the objects of a later patch so, and the client's own object table
-- holds the same names with the same tag: "[9270100] 9ori_sky02.m2".
-- @param name a model's name as the server or the client gives it
-- @return the name alone
function Lines.Untagged(name)
	return (name:gsub("^%[.-%]%s*", ""))
end

-- An object's name as its line prints it: an optional tag before it, on a
-- nearby-object line its entry after it, and on the server's own kinds of
-- object what kind it is in brackets after it: "6dr_draenei_karabor_bigdoor [door]".
local function objectName(label)
	local name = Lines.Untagged(unbracket(label)):gsub("%s+%-%s+%d+$", "")
	return (name:gsub("%s+%[[^%]]*%]$", ""))
end

-- A reader for a link whose label is the name.
local function named(kind)
	return function(payload, label)
		return { kind = kind, id = tonumber(payload), name = unbracket(label) }
	end
end

-- A reader for a link whose label is its id, a dash, and the name.
local function numbered(kind)
	return function(payload, label)
		local name = unbracket(label)
		return { kind = kind, id = tonumber(payload), name = name:match("^%d+ %- (.+)$") or name }
	end
end

local LINKS = {
	-- An object whose model is a WMO is read as the WMO kind, since no model frame
	-- draws one and another addon does; to the player it is still an object.
	gameobject_entry = function(payload, label)
		local name = objectName(label)
		local kind = "object"
		if name:lower():find("%.wmo$") then
			kind = "wmo"
		end
		return { kind = kind, id = tonumber(payload), name = name }
	end,
	-- A creature's line may print its entry after its name, as `.npc info` does.
	creature_entry = function(payload, label)
		local name = unbracket(label):gsub("%s+%-%s+" .. payload .. "$", "")
		return { kind = "creature", id = tonumber(payload), name = name }
	end,
	creatureDisplayID = numbered("display"),
	enchantID = numbered("enchant"),
	item = function(payload, label)
		return { kind = "item", id = tonumber(payload:match("^%d+")), name = unbracket(label) }
	end,
	-- A spell's link in a line carries its id; one from the spellbook carries more after it.
	spell = function(payload, label)
		local name = unbracket(label):gsub(", rank %d+$", "")
		return { kind = "spell", id = tonumber(payload:match("^%d+")), name = name }
	end,
	emoteID = named("emote"),
	area = named("area"),
	MapID = named("map"),
	tele = named("teleport"),
	skill = named("skill"),
	title = named("title"),
	blueprint_name = named("blueprint"),
}

-- The start of each link this file reads, for asking of a line without reading it.
local PREFIXES = {}
for linkType in pairs(LINKS) do
	PREFIXES[#PREFIXES + 1] = "|H" .. linkType .. ":"
end

local function sameName(a, b)
	return a:lower() == b:lower()
end

local function doodad(message)
	local id = message:match("^Detail ID: |cff00CCFF(%d+)|r:")
	if not id then
		return nil
	end
	local names, seen = {}, {}
	for name in message:gmatch("|cff00CCFF([%w_%-%.]+%.m2)|r") do
		if not seen[name] then
			seen[name] = true
			names[#names + 1] = name
		end
	end
	if #names == 0 then
		return nil
	end
	return { kind = "doodad", id = tonumber(id), name = names[1], names = names }
end

-- An ambience line names its day sound, its night sound, both, or one sound
-- that serves for both. It is accepted only where every name it prints is the
-- shipped entry's own.
local function ambience(id, row, rest)
	local day, night = rest:match("^%[DAY%] (.-), %[NIGHT%] (.-)$")
	if not day then
		day = rest:match("^%[DAY%] (.-)$")
	end
	if not day then
		night = rest:match("^%[NIGHT%] (.-)$")
	end
	if not day and not night then
		local name = plain(rest)
		if sameName(name, row.names[1]) or sameName(name, row.names[2]) then
			return { kind = "ambience", id = id, name = name }
		end
		return nil
	end
	day, night = day and plain(day), night and plain(night)
	if day and not sameName(day, row.names[1]) then
		return nil
	end
	if night and not sameName(night, row.names[2]) then
		return nil
	end
	return { kind = "ambience", id = id, name = day or night }
end

local function sound(message)
	local id, rest = message:match("^|cff00CCFF(%d+)|r %- (.+)$")
	if not id then
		return nil
	end
	id = tonumber(id)
	local data = ns.Data
	local music, intro, around = data.Music[id], data.Intro[id], data.Ambience[id]
	if not (music or intro or around) then
		return nil
	end
	local name = plain(rest)
	if music and sameName(music.name, name) then
		return { kind = "music", id = id, name = name }
	end
	if intro and sameName(intro.name, name) then
		return { kind = "intro", id = id, name = name }
	end
	if around then
		return ambience(id, around, rest)
	end
	return nil
end

-- A faction line: the faction template's id, then the faction's name and id.
local function faction(message)
	local id, name = message:match("^(%d+) %- |cff00CCFF%[(.+) %- %d+%]|r$")
	if not id then
		return nil
	end
	return { kind = "faction", id = tonumber(id), name = name }
end

-- A tile texture line: its picture, its file's name, then the file's id.
local function texture(message)
	local name, id = message:match("^|T%d+:%d+:%d+|t|h|r |cff00CCFF([^|]+)|r: |cff00CCFF(%d+)|r")
	if not id then
		return nil
	end
	return { kind = "texture", id = tonumber(id), name = name }
end

-- A line of a WMO's area data: its file, then its root id, the WMO's own id. The
-- root and each of its groups print a line, all one WMO's.
local function wmoArea(message)
	local name, id = message:match("|cff00CCFF([^|]+%.wmo)|r %- RootId: |cff00CCFF(%d+)|r")
	if not id then
		return nil
	end
	return { kind = "wmoarea", id = tonumber(id), name = name }
end

--- Whether a line could be one this addon reads. Cheap, and creates nothing,
-- so it can be asked of every system line before the line is read.
-- @param message the line
-- @return true where reading it is worth the work
function Lines.Maybe(message)
	for i = 1, #PREFIXES do
		if message:find(PREFIXES[i], 1, true) then
			return true
		end
	end
	return message:find("^|cff00CCFF%d") ~= nil
		or message:find("^Detail ID: ") ~= nil
		or message:find("^%d+ %- |cff00CCFF%[") ~= nil
		or message:find("^|T%d") ~= nil
		or message:find(".wmo|r - RootId: ", 1, true) ~= nil
end

-- Whether a line is `.npc info`'s of a creature in an outfit: it prints the display
-- the creature is drawn from, then in brackets what it wears, which for an outfit
-- is the server's own number. An outfit's face, hair and gear are the server's
-- alone and no preview frame can be given them, so such a line gains nothing
-- rather than a likeness that is wrong.
local function inOutfit(message)
	local drawn, wearing = message:match("|HdisplayID:%d+|h(%d+) %((%d+)%)|h")
	return drawn ~= nil and drawn ~= wearing
end

local function read(message)
	for linkType, payload, label in message:gmatch("|H([%a_]+):([^|]*)|h(.-)|h") do
		local reader = LINKS[linkType]
		if reader then
			local found = reader(payload, closed(label))
			if found and found.id and not (found.kind == "creature" and inOutfit(message)) then
				return found
			end
			return nil
		end
	end
	return doodad(message)
		or sound(message)
		or faction(message)
		or texture(message)
		or wmoArea(message)
end

--- Read a system line.
-- @param message the line as the server sent it
-- @return the read, or nil where the line is not one the addon previews
Lines.Read = read
