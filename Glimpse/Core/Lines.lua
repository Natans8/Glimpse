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
-- A read is `{ kind, id, name }`, with `names` for a detail doodad's models and
-- `ids` for the other ids a line gives, as a replaced doodad its replacement's
-- file. A read is shared between callers and is not changed.
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

-- A doodad placed on the map: its model's name and file, and in the link the file
-- that replaced it, 0 where none did; a deleted one carries -1 there.
local function placed(payload, label)
	local name, file = unbracket(label):match("^(.-) %- (%d+)$")
	if not file then
		return nil
	end
	local read = { kind = "mapdoodad", id = tonumber(file), name = name }
	local replacement = tonumber(payload:match(":(%d+)$"))
	if replacement and replacement > 0 then
		read.ids = { replacement }
	end
	return read
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
	-- A creature a phase forged, as its list of them names it.
	phase_npc = named("creature"),
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
	doodad_uid = placed,
	doodad_deleted_uid = placed,
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

-- What a phase overrides of an area or a WMO, as its lists print it: the thing,
-- then the ambience, music and intro it now has, each 0 for none.
local function overrides(message)
	if not message:find("(Ambience: ", 1, true) then
		return nil
	end
	local id, name = message:match("|Harea:(%d+)|h%[(.-)%]|h")
	if not id then
		id, name = message:match("|HWMO:(%d+)[^|]*|h%[(.-)%]|h")
	end
	local around = message:match("Ambience: |c%x%x%x%x%x%x%x%x(%d+)|r")
	local music = message:match("Music: |c%x%x%x%x%x%x%x%x(%d+)|r")
	local intro = message:match("Intro: |c%x%x%x%x%x%x%x%x(%d+)|r")
	if not (id and around and music and intro) then
		return nil
	end
	local ids = { tonumber(around), tonumber(music), tonumber(intro) }
	return { kind = "areasounds", id = tonumber(id), name = name, ids = ids }
end

--- The table each kind of sound is listed in.
local SOUND_TABLES = { ambience = "Ambience", music = "Music", intro = "Intro" }

-- A reply naming the sound a phase now gives an area: "set to use music ID 156".
local function setSound(message)
	local kind, id = message:match("set to use (%a+) ID |cff00CCFF(%d+)|r")
	local listed = kind and SOUND_TABLES[kind]
	local row = listed and ns.Data[listed][tonumber(id)]
	if not row then
		return nil
	end
	return { kind = kind, id = tonumber(id), name = row.name or row.names[1] }
end

-- A reply naming the creature display it put on the player: a mount or a morph.
local function worn(message)
	local id = message:match("^You have mounted |cff00CCFF(%d+)|r%.$")
		or message:match("^You have morphed |cff00CCFF.-|r to |cff00CCFF(%d+)|r%.$")
	if not id then
		return nil
	end
	return { kind = "display", id = tonumber(id), name = id }
end

-- A reply naming the enchant it put on the player's weapon.
local function enchanted(message)
	local id = message:match("^|cff00CCFFEnchantment (%d+) applied%.|r$")
	if not id then
		return nil
	end
	return { kind = "enchant", id = tonumber(id), name = id }
end

-- A row of a forged creature's displays. A row naming an outfit is left alone: an
-- outfit is the server's, not a display the client has.
local function forgedDisplay(message)
	local id = message:match("^ID: |cff00CCFF%d+|r %- Display (%d+)|r |")
	if not id then
		return nil
	end
	return { kind = "display", id = tonumber(id), name = id }
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
		or message:find("^You have m") ~= nil
		or message:find("^|cff00CCFFEnchantment %d") ~= nil
		or message:find("^ID: |cff00CCFF%d") ~= nil
		or message:find("(Ambience: ", 1, true) ~= nil
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
	local shaped = overrides(message) or setSound(message)
	if shaped then
		return shaped
	end
	for linkType, payload, label in message:gmatch("|H([%a_]+):([^|]*)|h(.-)|h") do
		local reader = LINKS[linkType]
		if reader then
			local found = reader(payload, closed(label))
			if found and found.id and not (found.kind == "creature" and inOutfit(message)) then
				-- A line of a spawned object names it too, and its GUID finds what the
				-- server says of how that object stands.
				local guid = found.kind == "object" and message:match("|Hgameobject_GUID:(%d+)|h")
				if guid then
					found.ids = { tonumber(guid) }
				end
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
		or worn(message)
		or enchanted(message)
		or forgedDisplay(message)
end

--- Read a system line.
-- @param message the line as the server sent it
-- @return the read, or nil where the line is not one the addon previews
Lines.Read = read

--- A line's rows, as the server breaks it.
-- @param message the line as the server sent it
-- @return a list of `{ text, ending }`, each row's text and the break after it,
-- the last row's break empty, so that joining them gives the line again
function Lines.Split(message)
	local rows, from = {}, 1
	while true do
		local at = message:find("[\r\n]", from)
		if not at then
			rows[#rows + 1] = { text = message:sub(from), ending = "" }
			return rows
		end
		rows[#rows + 1] = { text = message:sub(from, at - 1), ending = message:sub(at, at) }
		from = at + 1
	end
end

--- What a line names on rows of their own, after the row that names the line:
-- each model a detail doodad lists, read on the first row that lists it.
-- @param message the line as the server sent it
-- @param own the line's own read
-- @return a read for each such row, by its number in `Lines.Split`, or nil
-- where the line has no such rows
function Lines.Rows(message, own)
	if own.kind ~= "doodad" then
		return nil
	end
	local reads, seen = {}, {}
	for index, row in ipairs(Lines.Split(message)) do
		local name = index > 1 and row.text:match("|cff00CCFF([%w_%-%.]+%.m2)|r")
		if name and not seen[name] then
			seen[name] = true
			reads[index] = { kind = "doodad", id = own.id, name = name, names = { name } }
		end
	end
	return reads
end
