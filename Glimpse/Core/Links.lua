local addonName, ns = ...

--- The links this addon writes into chat, and reading them back.
--
-- A link carries the whole read it was made from, so a click on a line that
-- scrolled past long ago still knows what the line was about.
--
-- The client shows a link of a type it does not know in the item tooltip,
-- which fails before any hook runs. Its garrison-mission branch returns early
-- for anything that is not a mission, so the link rides that type. Another
-- addon on this client scans every clicked link for fragments such as
-- `spell:` and keeps the click when it finds one, so after the type nothing
-- here is a word followed by a colon: kinds are single letters, fields are
-- parted by slashes, and names are written in a safe alphabet.
local Links = {}
ns.Links = Links

local Kinds = ns.Kinds

local PREFIX = "garrmission:" .. addonName:lower() .. ":"

-- Text in letters, digits, underscores, dots and dashes; anything else as a
-- tilde and its two hex digits.
local function encode(text)
	return (
		text:gsub("[^%w_%.%-]", function(character)
			return string.format("~%02X", character:byte())
		end)
	)
end

local function decode(text)
	return (text:gsub("~(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end

--- The link for one of a read's buttons.
-- @param read a read from `Lines.Read`, of a kind that has been added
-- @param index which of the read's buttons this is, counted from one
-- @return the link, to go between `|H` and `|h`
function Links.Write(read, index)
	local extra = ""
	if read.names then
		local names = {}
		for i, name in ipairs(read.names) do
			names[i] = encode(name)
		end
		extra = table.concat(names, ",")
	end
	return PREFIX
		.. table.concat(
			{ Kinds.Code(read.kind), read.id, index, encode(read.name or ""), extra },
			"/"
		)
end

--- Read a link back.
-- @param link a link as the client hands it to a click or a hover
-- @return the read it was written from, or nil where the link is not this addon's
-- @return which of the read's buttons it is
function Links.Read(link)
	if link:sub(1, #PREFIX) ~= PREFIX then
		return nil
	end
	local code, id, index, name, extra = link:sub(#PREFIX + 1)
		:match("^(%a)/(%d+)/(%d+)/([^/]*)/([^/]*)$")
	local kind = code and Kinds.Named(code)
	if not kind then
		return nil
	end
	local read = { kind = kind, id = tonumber(id), name = decode(name) }
	if extra ~= "" then
		read.names = {}
		for encoded in extra:gmatch("[^,]+") do
			read.names[#read.names + 1] = decode(encoded)
		end
	end
	return read, tonumber(index)
end
