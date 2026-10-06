local _, ns = ...

--- The chat side: buttons on the lines the server prints, and clicks on them.
--
-- One filter on system messages appends a button to each line that has
-- something to show. The filter is added at login, after every other addon
-- has added its own, so this addon's buttons come after theirs and theirs
-- stay where players are used to finding them.
--
-- The chat frames and the client's link handler belong to the client and are
-- shared with other addons, so they are hooked here and never replaced.
local Lines, Kinds, Links, Safely, Async = ns.Lines, ns.Kinds, ns.Links, ns.Safely, ns.Async

local Chat = {}
ns.Chat = Chat

--- What parts a button from the text before it: the dash the other buttons on these lines use.
local SEPARATOR = "|cffADFFFF -|r "

--- The colour of this addon's buttons. Every other button on these lines
-- changes something; these only show, and the colour says so.
Chat.COLOUR = "|cffC8A8FF"

-- Who previews a read, where the player has not turned its kind off.
local function drawerOf(read)
	if not ns.Settings.On(read.kind) then
		return nil
	end
	return Kinds.Drawer(read)
end

-- The buttons a line gains, as text to append to it, or nil.
local function buttonsOf(message)
	local read = Lines.Read(message)
	local words = read and drawerOf(read) and Kinds.Buttons(read)
	if not words then
		return nil
	end
	local buttons = {}
	for index, word in ipairs(words) do
		local link = "|H" .. Links.Write(read, index) .. "|h[" .. word .. "]|h|r"
		buttons[index] = SEPARATOR .. Chat.COLOUR .. link
	end
	return table.concat(buttons)
end

local lastMessage, lastOff, lastButtons

-- The client runs a filter once for each chat frame showing the line, with
-- the same text each time, so the last line's buttons are kept, for as long as
-- the kinds turned off are the same table; turning one on or off makes another.
-- A fault leaves the line as it came.
local filter = Safely.Wrap(function(_, _, message, ...)
	if type(message) ~= "string" or not Lines.Maybe(message) then
		return false
	end
	local off = ns.Settings.Get("off")
	if message ~= lastMessage or off ~= lastOff then
		lastMessage, lastOff, lastButtons = message, off, buttonsOf(message)
	end
	if not lastButtons then
		return false
	end
	return false, message .. lastButtons, ...
end)

-- Act on a click on one of this addon's buttons: a button that draws opens the
-- window, unless its kind does something of its own, and a sound's button plays
-- it. A kind the player has turned off since the line was printed does nothing.
local function clicked(read, index)
	local drawer = drawerOf(read)
	if not drawer then
		return
	end
	if drawer == "own" and Kinds.Open(read) then
		return
	end
	if drawer == "provider" or Kinds.Draws(read) then
		ns.Window.Toggle(read, drawer == "provider")
		return
	end
	Async.Ask("click", read, function(subject)
		if subject and subject.sounds then
			ns.Playback.Toggle(subject, index)
		end
	end)
end

local said -- true while a kind's text tooltip is up

-- Show a kind's text tooltip at the pointer, its first line the title.
local function say(chat, lines)
	local tooltip = _G.GameTooltip
	tooltip:SetOwner(chat, "ANCHOR_CURSOR_RIGHT")
	tooltip:SetText(lines[1], 1, 1, 1)
	for i = 2, #lines do
		tooltip:AddLine(lines[i])
	end
	tooltip:Show()
	said = true
end

-- The pointer came to rest on a link in a chat frame.
local function entered(chat, link)
	local read, index = Links.Read(link)
	local drawer = read and drawerOf(read)
	if not drawer then
		return
	end
	if drawer == "provider" or Kinds.Draws(read) then
		if ns.Settings.Get("hover") then
			ns.Peek.Show(read, drawer == "provider")
		end
		return
	end
	local lines = Kinds.Hint(read)
	if lines then
		say(chat, lines)
		return
	end
	Async.Ask("hint", read, function(subject)
		if subject then
			ns.Playback.Hint(subject, index, chat)
		end
	end)
end

-- The pointer left a link in a chat frame.
local function left()
	if said then
		said = false
		_G.GameTooltip:Hide()
	end
	ns.Peek.Hide()
	Async.Cancel("hint")
	ns.Playback.Unhint()
end

local function hookFrame(chat)
	if chat and not chat.glimpseHooked then
		chat.glimpseHooked = true
		chat:HookScript("OnHyperlinkEnter", Safely.Wrap(entered))
		chat:HookScript("OnHyperlinkLeave", Safely.Wrap(left))
	end
end

local function hookFrames()
	for _, name in ipairs(_G.CHAT_FRAMES) do
		hookFrame(_G[name])
	end
end

--- Add the filter, the hover hooks and the click hook. Called once, at login.
function Chat.Install()
	_G.ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", filter)
	hookFrames()
	-- A whisper or a pet-battle log opens a chat frame of its own, later.
	_G.hooksecurefunc("FCF_OpenTemporaryWindow", Safely.Wrap(hookFrames))
	_G.hooksecurefunc(
		"SetItemRef",
		Safely.Wrap(function(link)
			local read, index = Links.Read(link)
			if read then
				clicked(read, index)
			end
		end)
	)
end
