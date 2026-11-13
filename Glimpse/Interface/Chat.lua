local _, ns = ...

--- The chat side: buttons on the lines the server prints, and clicks on them.
--
-- One filter on system messages puts a button on each line that has something
-- to show, or on its first row where the server breaks it into rows, and one on
-- each later row that names a thing of its own, where the player has chosen: at
-- the row's start, just before or after its link, at its end, or nowhere.
-- The filter is added at login, after every other addon has added its own, so
-- theirs stay where players are used to finding them: at a row's end, this
-- addon's buttons come after theirs.
--
-- The chat frames and the client's link handler belong to the client and are
-- shared with other addons, so they are hooked here and never replaced.
local Lines, Kinds, Links, Safely, Async = ns.Lines, ns.Kinds, ns.Links, ns.Safely, ns.Async

local Chat = {}
ns.Chat = Chat

--- What parts a button from the text beside it: the dash the other buttons on these lines use.
local SEPARATOR = "|cffADFFFF -|r "

--- The colour of this addon's buttons. Every other button on these lines
-- changes something; these only show, and the colour says so.
Chat.COLOUR = "|cffC8A8FF"

--- Who previews a read, where the player has not turned its kind off.
-- @param read a settled read
-- @return "provider", "own", or nil where nothing is shown for it
function Chat.Drawer(read)
	if not ns.Settings.On(read.kind) then
		return nil
	end
	return Kinds.Drawer(read)
end

--- Buttons as text to put beside what they belong to.
-- @param buttons each button's text, in order
-- @param lead true where they come before what they belong to, each then followed
-- by a dash; otherwise each follows a dash
-- @return the buttons joined
function Chat.Join(buttons, lead)
	local joined = {}
	for index, button in ipairs(buttons) do
		if lead then
			joined[index] = button .. SEPARATOR
		else
			joined[index] = SEPARATOR .. button
		end
	end
	return table.concat(joined)
end

-- The buttons a read gains, joined as `Chat.Join` joins them, or nil.
local function buttonsOf(read, lead)
	local words = Chat.Drawer(read) and Kinds.Buttons(read)
	if not words then
		return nil
	end
	local buttons = {}
	for index, word in ipairs(words) do
		buttons[index] = Chat.COLOUR .. "|H" .. Links.Write(read, index) .. "|h[" .. word .. "]|h|r"
	end
	return Chat.Join(buttons, lead)
end

--- Put buttons on a row where the player has chosen them to go.
-- @param text the row
-- @param placement "start" of the row, "before" or "after" its link, or anything else
-- for its end; a link the row lacks, or one it leaves open, puts them at its end
-- @param from where the row's link begins, or nil
-- @param to where the row's link ends, or nil
-- @param buttons a function of whether they lead (see `Chat.Join`) answering the
-- buttons as text, or nil where there are none
-- @return the row with its buttons, or nil where there are none
function Chat.Place(text, placement, from, to, buttons)
	local at, lead = #text + 1, false
	if placement == "start" then
		at, lead = 1, true
	elseif placement == "before" and from and from <= #text then
		at, lead = from, true
	elseif placement == "after" and to and to <= #text then
		at = to
	end
	local put = buttons(lead)
	if not put then
		return nil
	end
	return text:sub(1, at - 1) .. put .. text:sub(at)
end

-- The line with its buttons where the player has chosen. A line the server breaks
-- into rows names what it is on the first, so the line's own buttons go on that
-- row, and a later row that names a thing of its own, as a detail doodad lists a
-- model on each, gains that thing's.
local function shownOf(message, placement)
	local read, from, to = Lines.Locate(message)
	if not read then
		return nil
	end
	local reads, spans = Lines.Rows(message, read)
	reads, spans = reads or {}, spans or {}
	reads[1], spans[1] = read, { from = from, to = to }
	local shown = {}
	for index, row in ipairs(Lines.Split(message)) do
		local each, span = reads[index], spans[index]
		local text = each
			and Chat.Place(row.text, placement, span.from, span.to, function(lead)
				return buttonsOf(Kinds.Settle(each), lead)
			end)
		if index == 1 and not text then
			return nil
		end
		shown[index] = (text or row.text) .. row.ending
	end
	return table.concat(shown)
end

local lastMessage, lastOff, lastPlacement, lastShown

-- The client runs a filter once for each chat frame showing the line, with
-- the same text each time, so the last line as shown is kept, for as long as
-- the kinds turned off are the same table and the buttons stand where they did;
-- turning a kind on or off makes another table. A fault leaves the line as it came,
-- and so does a player who wants the buttons nowhere.
local filter = Safely.Wrap(function(_, _, message, ...)
	local placement = ns.Settings.Get("buttons")
	if type(message) ~= "string" or placement == "none" then
		return false
	end
	local off = ns.Settings.Get("off")
	if message ~= lastMessage or off ~= lastOff or placement ~= lastPlacement then
		lastMessage, lastOff, lastPlacement = message, off, placement
		lastShown = shownOf(message, placement)
	end
	if not lastShown then
		return false
	end
	return false, lastShown, ...
end)

--- Act on a read as a click on its button does: a button that draws opens the
-- window, unless its kind does something of its own, and a sound's button plays
-- it, or with the right button stops the sound playing. A kind the player has turned
-- off since the line was printed does nothing.
-- @param read a read from a line or a link
-- @param index which of the read's buttons, counted from one
-- @param button optional; the mouse button, as the client names it ("RightButton")
-- @return true where anything was done
function Chat.Open(read, index, button)
	local drawer = Chat.Drawer(read)
	if not drawer then
		return false
	end
	if drawer == "own" and Kinds.Open(read) then
		return true
	end
	if drawer == "provider" or Kinds.Draws(read) then
		ns.Window.Toggle(read, drawer == "provider")
		return true
	end
	if button == "RightButton" then
		ns.Playback.Stop()
		return true
	end
	Async.Ask("click", read, function(subject)
		if subject and subject.sounds then
			ns.Playback.Toggle(subject, index)
		end
	end)
	return true
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
	local drawer = read and Chat.Drawer(read)
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
		Safely.Wrap(function(link, _, button)
			local read, index = Links.Read(link)
			if read then
				Chat.Open(read, index, button)
			end
		end)
	)
end
