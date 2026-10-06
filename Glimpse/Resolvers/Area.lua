local _, ns = ...

--- Areas: a `[Map]` button that opens the client's world map at the area's map,
-- the area's own where it has one, its zone's where it is part of a zone, and in
-- an instance the floor of the dungeon map it is on. Resting on it says so in a
-- line of text. An area with no map gains no button.
local Kinds = ns.Kinds

-- The map an area is shown on, or nil.
local function mapOf(read)
	return ns.Data.AreaMaps[read.id]
end

Kinds.Add("area", {
	word = "Area",
	code = "z",
	button = "Map",
	draws = false,
	shows = function(read)
		return mapOf(read) ~= nil
	end,
	hint = function(read)
		local lines = { read.name }
		local name = ns.Client.MapName(mapOf(read))
		if name and name ~= read.name then
			lines[#lines + 1] = "In " .. name
		end
		lines[#lines + 1] = "Click to open the map"
		return lines
	end,
	opens = function(read)
		ns.Client.OpenWorldMap(mapOf(read))
	end,
})
