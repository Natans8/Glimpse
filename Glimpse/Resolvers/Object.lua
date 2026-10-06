local _, ns = ...

--- Objects, tiles, planes and detail doodads: the model an object draws.
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

Kinds.Add("object", {
	word = "Object",
	code = "o",
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
			Subject.Look(subject, "file", file)
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
