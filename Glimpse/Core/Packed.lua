local _, ns = ...

--- Reading a packed table: fixed-width decimal records in one sorted string.
--
-- The generator writes large tables this way because a string costs its own
-- length in memory, where a Lua table of the same rows costs several times
-- more. A packed table is `{ widths, offsets, records }`: each field's width
-- in digits, the amount each field was stored with added, and the records,
-- ascending by their first field.
local Packed = {}
ns.Packed = Packed

local function field(packed, record, index, from)
	local start = record * packed.size + from
	local stored = string.sub(packed.records, start + 1, start + packed.widths[index])
	return tonumber(stored) - packed.offsets[index]
end

-- The first record whose key is not below `key`, counting records from nought.
local function lowerBound(packed, key)
	if not packed.size then
		local size = 0
		for _, width in ipairs(packed.widths) do
			size = size + width
		end
		packed.size = size
		packed.count = #packed.records / size
	end
	local low, high = 0, packed.count
	while low < high do
		local middle = math.floor((low + high) / 2)
		if field(packed, middle, 1, 0) < key then
			low = middle + 1
		else
			high = middle
		end
	end
	return low
end

local function matches(packed, record, key)
	return record < packed.count and field(packed, record, 1, 0) == key
end

local function row(packed, record)
	local fields, from = {}, packed.widths[1]
	for index = 2, #packed.widths do
		fields[index - 1] = field(packed, record, index, from)
		from = from + packed.widths[index]
	end
	return fields
end

--- The first record whose first field is `key`.
-- @param packed a packed table
-- @param key the number to look for
-- @return the record's remaining fields in order, or nil where no record matches
function Packed.First(packed, key)
	local record = lowerBound(packed, key)
	if matches(packed, record, key) then
		return row(packed, record)
	end
	return nil
end

--- Every record whose first field is `key`.
-- @param packed a packed table
-- @param key the number to look for
-- @return an array of rows, each the record's remaining fields in order; empty where none match
function Packed.Find(packed, key)
	local found = {}
	local record = lowerBound(packed, key)
	while matches(packed, record, key) do
		found[#found + 1] = row(packed, record)
		record = record + 1
	end
	return found
end
