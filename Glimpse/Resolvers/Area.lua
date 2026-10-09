local _, ns = ...

--- Areas and maps: a `[Map]` button that opens the client's world map where the
-- line's place is drawn. An area opens on its own map where it has one, its
-- zone's where it is part of a zone, and in an instance the floor of the dungeon
-- map it is on. A map, as `.lookup map` lists them, opens on the world map at its
-- top: a continent's, an instance's first floor. Resting on the button says so in
-- a line of text. A line with no world map gains no button.
local Kinds = ns.Kinds

-- A kind whose line opens the world map at the map `mapOf(read)` names, or nil.
local function opener(word, code, mapOf)
	return {
		word = word,
		code = code,
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
	}
end

Kinds.Add(
	"area",
	opener("Area", "z", function(read)
		return ns.Data.AreaMaps[read.id]
	end)
)

Kinds.Add(
	"map",
	opener("Map", "p", function(read)
		return ns.Data.MapMaps[read.id]
	end)
)
