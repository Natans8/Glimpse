local _, ns = ...

--- Objects, tiles, planes, doodads and detail doodads: the model a thing draws.
--
-- No client call takes a gameobject entry, so a model is found by what the
-- line names. A name is a model's where it ends in the file's extension or,
-- as the server's own objects are often named, is one word with no spaces.
-- Such a name is looked up among the models the client's own displays name,
-- then in the client's object search, which holds the server's own models
-- too; from the search a record is taken only where its own file is the one
-- named. Any other name is a stock object's, and its entry leads to its model
-- through a table built from the stock server's objects and the client's
-- displays. A named model is believed over the entry, since the server may
-- have changed what an entry draws.
local Subject, Kinds, Packed = ns.Subject, ns.Kinds, ns.Packed

-- A model file's name without folder, tag, extension or trailing space, in lower case.
local function stem(name)
	local file = name:match("([^/\\]+)$") or name
	return ns.Lines.Untagged(file):match("^(.-)%s*$"):lower():gsub("%.m2$", "")
end

-- Whether a name is a model file's: only such a file may reach a model loader.
local function namesFile(name)
	return name:lower():find("%.m2%s*$") ~= nil
end

-- The file a model's name names among the models the client's displays name, or
-- nil. They are one string, `;name=file;` after another in sorted order, so the
-- search halves it: each step reads the first whole entry at or after its middle.
local function listed(models, wanted)
	local low, high = 1, #models
	while low < high do
		local middle = math.floor((low + high) / 2)
		local start = models:find(";", middle, true)
		local name, file = models:match("^([^=;]*)=(%d+)", start + 1)
		if name == wanted then
			return tonumber(file)
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

local found = {} -- stem -> the row a name led to, or false where it led nowhere

-- The model a name names, as `{ file }`, or nil. Each name is looked for once.
local function searched(name)
	local wanted = stem(name)
	if found[wanted] == nil then
		local data = ns.Client.Data()
		local file = data and listed(data.models, wanted)
		local row = file and { file = file }
		if not row then
			for _, record in ipairs(ns.Client.SearchObjects(wanted)) do
				if record.file and record.name and namesFile(record.name) then
					if stem(record.name) == wanted then
						row = record
						break
					end
				end
			end
		end
		found[wanted] = row or false
	end
	return found[wanted] or nil
end

-- The model file a stock entry draws, or nil.
local function stocked(entry)
	local data = ns.Client.Data()
	local row = data and Packed.First(data.objects, entry)
	return row and row[1]
end

-- Whether a name may be a model's: a file's name, or one word. An empty name, as
-- a read made from an id alone has, is none.
local function namesModel(name)
	return name ~= "" and (namesFile(name) or not name:find(" ", 1, true))
end

-- A percentage on a scale of `steps`, rounded, and held within it.
local function step(percent, steps)
	return math.max(0, math.min(steps, math.floor(percent * steps / 100 + 0.5)))
end

-- The kit Epsilon plays on an object to tint it. Its tints are one grid: each colour
-- on 21 steps, the transparency and the saturation on fifths, and the kit is the
-- place in the grid; an object made wholly transparent is the grid's first kit.
local function tintKit(tint)
	local alpha = step(tint.transparency, 5)
	if alpha == 0 then
		return 167000
	end
	local colour = step(tint.red, 20) + 21 * step(tint.green, 20) + 441 * step(tint.blue, 20)
	return 167001 + (5 - alpha) * 46305 + step(100 - tint.saturation, 5) * 9261 + colour
end

-- An object's look as the server says the spawned object stands: tinted, drawn with
-- the kit that tints it, or carrying a spell, named after its kind. An object no
-- record has come for is drawn as its model alone.
local function standing(look, read)
	local record = read.ids and ns.Client.ObjectRecord(read.ids[1])
	if not record then
		return
	end
	if record.tint then
		look.draw, look.kit = "tinted", tintKit(record.tint)
	end
	if record.spell ~= 0 then
		look.name = "with " .. (ns.Client.SpellName(record.spell) or ("spell " .. record.spell))
	end
end

-- Whether whoever previews WMOs has one by a name. Only the name is asked of, so
-- an entry is never taken for one.
local function aWmo(name)
	return ns.Providers.Shows({ kind = "wmo", id = 0, name = name })
end

Kinds.Add("object", {
	word = "Object",
	code = "o",
	-- A spawned object may be tinted or given a spell at any moment.
	live = function(read)
		return read.ids ~= nil
	end,
	-- A stock entry whose display is a WMO is a WMO's line under another name,
	-- for whoever previews WMOs; no model frame draws one. So is a line naming no
	-- file but a WMO's, as Epsilon names its own WMO objects after the file without
	-- its extension: a name the WMO pictures have is a WMO's.
	recast = function(read)
		local data = ns.Client.Data()
		if data and Packed.First(data.wmoObjects, read.id) then
			return { kind = "wmo", id = read.id, name = read.name }
		end
		if not namesFile(read.name) and aWmo(read.name) then
			return { kind = "wmo", id = read.id, name = read.name }
		end
		return nil
	end,
	-- A line naming a model file is worth trying, and so is a known entry. A
	-- name that is one word is searched for at once; such lines are few.
	shows = function(read)
		return namesFile(read.name)
			or stocked(read.id) ~= nil
			or (namesModel(read.name) and searched(read.name) ~= nil)
	end,
	resolve = function(read, done)
		local subject = Subject.New(read)
		local row = namesModel(read.name) and searched(read.name) or nil
		local file = (row and row.file) or stocked(read.id)
		if file then
			standing(Subject.Look(subject, "file", file), read)
		end
		Subject.Answer(subject, done)
	end,
})

-- Whether a file is one of the models the client's displays name: an id from a
-- line says nothing of what its file is, and only a model may reach a model loader.
local function aModel(file)
	local data = ns.Client.Data()
	return data ~= nil and data.models:find("=" .. file .. ";", 1, true) ~= nil
end

-- A doodad placed on the map, drawn from the file its line names; a replaced one
-- beside what replaced it, where that is a model. A WMO is left to whoever
-- previews WMOs, so a doodad here is a model by its name.
Kinds.Add("mapdoodad", {
	word = "Doodad",
	code = "l",
	-- A doodad that is a WMO is shown by whoever previews WMOs, by its name alone:
	-- its id is its file's, which is no entry, so the read carries it aside.
	recast = function(read)
		if read.name:lower():find("%.wmo$") and aWmo(read.name) then
			return { kind = "wmo", id = 0, name = read.name, ids = { read.id } }
		end
		return nil
	end,
	shows = function(read)
		return namesFile(read.name)
	end,
	resolve = function(read, done)
		local subject = Subject.New(read)
		local before = Subject.Look(subject, "file", read.id)
		local replacement = read.ids and read.ids[1]
		if replacement and aModel(replacement) then
			before.name = "before"
			Subject.Look(subject, "file", replacement).name = "after"
		elseif replacement then
			before.name = "replaced by file " .. replacement
		end
		Subject.Answer(subject, done)
	end,
})

Kinds.Add("doodad", {
	word = "Detail doodad",
	code = "d",
	resolve = function(read, done)
		local subject = Subject.New(read)
		for _, name in ipairs(read.names) do
			local row = searched(name)
			if row then
				Subject.Look(subject, "file", row.file).name = name
			end
		end
		Subject.Answer(subject, done)
	end,
})
