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
-- `ids` for the other ids a line gives: a replaced doodad its replacement's
-- file, a spawned object its GUID, a spawned creature the display it stands in.
-- A read is shared between callers and is not changed.
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
		return {
			kind = kind,
			id = tonumber(payload),
			name = name:match("^%d+ %- (.+)$") or name:match("^(%d+) %(%d+%)$") or name,
		}
	end
end

-- A doodad placed on the map: its model's name, then a number that is not the
-- model's file (it names terrain files), kept as the read's id; and in the link the
-- file that replaced it, 0 where none did; a deleted one carries -1 there.
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
	-- A creature display under the other names the server links it by: what a
	-- creature is drawn from, and what it is natively.
	displayID = numbered("display"),
	nativeID = numbered("display"),
	skyboxID = numbered("skybox"),
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
	local id, from, rest, to = message:match("^|cff00CCFF(%d+)|r %- ()(.+)()$")
	if not id then
		return nil
	end
	id = tonumber(id)
	local data = ns.Data
	local music, intro, around = data.Music[id], data.Intro[id], data.Ambience[id]
	if not (music or intro or around) then
		return nil
	end
	local name, place = plain(rest), { id = 1, from = from, to = to }
	if music and sameName(music.name, name) then
		return { kind = "music", id = id, name = name }, place
	end
	if intro and sameName(intro.name, name) then
		return { kind = "intro", id = id, name = name }, place
	end
	if around then
		return ambience(id, around, rest), place
	end
	return nil
end

-- A faction line: the faction template's id, then the faction's name and id.
local function faction(message)
	local id, from, name, to = message:match("^(%d+) %- ()|cff00CCFF%[(.+) %- %d+%]|r()$")
	if not id then
		return nil
	end
	return { kind = "faction", id = tonumber(id), name = name }, { id = 1, from = from, to = to }
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
	local from, name, to, id =
		message:match("^|T%d+:%d+:%d+|t|h|r ()|cff00CCFF([^|]+)|r(): |cff00CCFF(%d+)|r")
	if not id then
		return nil
	end
	return { kind = "texture", id = tonumber(id), name = name }, { from = from, to = to }
end

-- A line of a WMO's area data: its file, then its root id, the WMO's own id. The
-- root and each of its groups print a line, all one WMO's.
local function wmoArea(message)
	local from, name, to, id =
		message:match("()|cff00CCFF([^|]+%.wmo)|r() %- RootId: |cff00CCFF(%d+)|r")
	if not id then
		return nil
	end
	return { kind = "wmoarea", id = tonumber(id), name = name }, { from = from, to = to }
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

-- Where a link begins on its line: at the colour code that opens it, where one
-- does, so that text put there leaves the link its colour.
local function opening(message, at)
	if at > 10 and message:sub(at - 10, at - 1):find("^|c%x%x%x%x%x%x%x%x$") then
		return at - 10
	end
	return at
end

-- Where a link ends on its line, given where its label ends: past the code closing
-- it and the colour's end after that. A link the server leaves open, as a spawned
-- object's reply does, ends with its label and is said to be open, so that whatever
-- is put after it closes it first rather than standing inside it.
local function ending(message, at)
	if message:sub(at, at + 1) ~= "|h" then
		return at, true
	end
	at = at + 2
	if message:sub(at, at + 1) == "|r" then
		return at + 2, false
	end
	return at, false
end

-- Where a line prints the read's own id before its link: the id as a whole number with
-- nothing after it but spaces, dashes and colour codes, or a bracketed note as
-- `.lookup title` prints (`174 (idx:139) - `). A time or a tag another addon put in
-- front is not the id and is passed over.
local function idBefore(message, from, id)
	local before, digits = message:sub(1, from - 1), tostring(id)
	for at in before:gmatch("()%f[%d]" .. digits:gsub("%p", "%%%0") .. "%f[%D]") do
		local rest = plain(before:sub(at + #digits))
		if rest:find("^[%s%-]*$") or rest:find("^%b()[%s%-]*$") then
			return opening(message, at)
		end
	end
	return nil
end

-- The lines that name what they are about with no link of it, tried in turn. Each
-- answers its read and, where it prints a name for it, where its id and that name
-- are, as `Lines.Locate` does.
local SHAPES = { doodad, sound, faction, texture, wmoArea, worn, enchanted, forgedDisplay }

local function locate(message)
	local shaped = overrides(message) or setSound(message)
	if shaped then
		return shaped
	end
	for at, linkType, payload, labelAt, label in message:gmatch("()|H([%a_]+):([^|]*)|h()(.-)|h") do
		local reader = LINKS[linkType]
		if reader then
			label = closed(label)
			local found = reader(payload, label)
			if found and found.id and not (found.kind == "creature" and inOutfit(message)) then
				-- A line of a spawned object names it too, and its GUID finds what the
				-- server says of how that object stands.
				local guid = found.kind == "object" and message:match("|Hgameobject_GUID:(%d+)|h")
				if guid then
					found.ids = { tonumber(guid) }
				end
				-- A line of a spawned creature says, after naming it, which display it
				-- stands in: the creature as it is rather than as its entry might spawn it.
				-- `.npc info` links it; the spawn reply prints it plain.
				local display = found.kind == "creature"
					and (
						message:match("|Hcreature_entry:%d+|h.-|HdisplayID:(%d+)|h")
						or message:match(
							"|Hcreature_entry:%d+|h.-%(DisplayID: |c%x%x%x%x%x%x%x%x(%d+)|r%)"
						)
					)
				if display then
					found.ids = { tonumber(display) }
				end
				local from = opening(message, at)
				local to, open = ending(message, labelAt + #label)
				return found,
					{
						id = idBefore(message, from, found.id),
						from = from,
						to = to,
						open = open,
						link = linkType .. ":" .. payload,
						label = label,
					}
			end
			return nil
		end
	end
	for _, shape in ipairs(SHAPES) do
		local found, place = shape(message)
		if found then
			return found, place
		end
	end
	return nil
end

--- Read a system line, and find where on it the thing read is named.
-- @param message the line as the server sent it
-- @return the read, or nil where the line is not one the addon previews
-- @return where on the line it is named, as `{ id, from, to, open, link, label }`:
-- where the id printed before its name begins, where the name or its link begins, and
-- where that ends, past the codes closing it; each at the colour code opening it where
-- one does, each nil where the line prints none; `open` true where the server leaves
-- the link open, its end then being its label's; the link as the client hands it to a
-- hover or a click, and its label, which tells it from another addon's button carrying
-- the same link; nil where the line names it nowhere
Lines.Locate = locate

--- Whether a link is of a type a line is read by.
-- @param link a link as the client hands it over, `type:payload`
-- @return true where a line carrying it could be read
function Lines.Knows(link)
	return LINKS[link:match("^([%a_]+):") or ""] ~= nil
end

--- The label a link shows, out of its text as the client hands it to a hover or a
-- click, colour codes and all, as far as its closing bracket, as `Lines.Locate` gives it.
-- A link the server leaves open, as a spawned object's reply does, has no code after
-- its label, and its label runs to the text's end.
-- @param text a link's text
-- @return the label, or nil where the text carries no link
function Lines.Label(text)
	local label = type(text) == "string" and (text:match("|h(.-)|h") or text:match("|h(.*)$"))
	if label then
		return closed(label)
	end
	return nil
end

--- Read a system line.
-- @param message the line as the server sent it
-- @return the read, or nil where the line is not one the addon previews
function Lines.Read(message)
	return (locate(message))
end

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
-- each model a detail doodad lists, on every row that lists it.
-- @param message the line as the server sent it
-- @param own the line's own read
-- @return a read for each such row, by its number in `Lines.Split`, or nil
-- where the line has no such rows
-- @return where on each such row its model's name is, as `Lines.Locate` gives it,
-- by the same numbers
function Lines.Rows(message, own)
	if own.kind ~= "doodad" then
		return nil
	end
	local reads, places = {}, {}
	for index, row in ipairs(Lines.Split(message)) do
		local from, name, to
		if index > 1 then
			from, name, to = row.text:match("()|cff00CCFF([%w_%-%.]+%.m2)|r()")
		end
		if name then
			reads[index] = { kind = "doodad", id = own.id, name = name, names = { name } }
			places[index] = { from = from, to = to }
		end
	end
	return reads, places
end
