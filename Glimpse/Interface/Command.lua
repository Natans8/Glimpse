local _, ns = ...

--- The `/glimpse` command: the settings, or a preview of one thing a player
-- already has the id or the link of.
--
--   /glimpse                 opens the settings
--   /glimpse <kind> <id>     previews one thing as its button on a line would:
--                            /glimpse emote 10, /glimpse npc 184093
--   /glimpse <link>          the same, from a link pasted from chat or a tooltip
--
-- It searches for nothing. An object is known by its entry alone only where it is
-- a stock one; any other carries its model in the link of its `.lookup` line.
local Command = {}
ns.Command = Command

--- Words a player may use for a kind besides the kind's own name: the server's
-- own words for objects and creatures.
local ALIASES = { gob = "object", npc = "creature" }

local USAGE = "/glimpse opens the settings. /glimpse <kind> <id> previews one thing, "
	.. "as /glimpse emote 10 or /glimpse npc 184093, and a link pasted after /glimpse does too."

local NOTHING = "Nothing to preview. An object is known by its id only where it is a stock "
	.. "one; paste the link of its .lookup line instead."

-- The read a command's text names, or nil where it names none.
local function readOf(text)
	if text:find("|H", 1, true) then
		local read = ns.Lines.Read(text)
		if read then
			return ns.Kinds.Settle(read)
		end
		return nil
	end
	local word, id = text:match("^(%a+)%s+(%d+)$")
	if not word then
		return nil
	end
	local kind = ALIASES[word:lower()] or word:lower()
	if not ns.Kinds.Known(kind) then
		return nil
	end
	return ns.Kinds.Settle({ kind = kind, id = tonumber(id), name = "" })
end

--- Act on the text after `/glimpse`.
-- @param text what the player typed after the command
function Command.Run(text)
	text = text:match("^%s*(.-)%s*$")
	if text == "" then
		ns.Options.Open()
		return
	end
	local read = readOf(text)
	if not read then
		ns.Start.Say(USAGE)
	elseif not ns.Chat.Open(read, 1) then
		ns.Start.Say(NOTHING)
	end
end

--- Add the command to the client's. Called once, at login.
function Command.Install()
	_G.SLASH_GLIMPSE1 = "/glimpse"
	_G.SlashCmdList.GLIMPSE = ns.Safely.Wrap(Command.Run)
end
