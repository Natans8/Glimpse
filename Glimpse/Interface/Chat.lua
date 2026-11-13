local _, ns = ...

--- The chat side: buttons on the lines the server prints, and clicks on them.
--
-- One filter on system messages puts a button on each line that has something
-- to show, or on its first row where the server breaks it into rows, and one on
-- each later row that names a thing of its own, where the player has chosen: before
-- the id the row prints, just before or after its link, at its end, or nowhere.
-- The filter is added at login, after every other addon has added its own, so
-- theirs stay where players are used to finding them: whatever another addon put
-- in front of a row stays in front, and at a row's end this addon's buttons come
-- after theirs. Where the player asks, resting on the server's own link previews it
-- too and an Alt-click on it opens the window; a plain or a right click on it, and any
-- tooltip shown for it, stay the client's and other addons'.
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

-- Whether a kind, by the drawer `Chat.Drawer` names, is drawn rather than heard or named.
local function draws(read, drawer)
	return drawer == "provider" or (drawer == "own" and Kinds.Draws(read))
end

-- The buttons a read gains, each as its text, or nil where it gains none.
local function buttonsOf(read)
	read = Kinds.Settle(read)
	local words = Chat.Drawer(read) and Kinds.Buttons(read)
	if not words then
		return nil
	end
	local buttons = {}
	for index, word in ipairs(words) do
		buttons[index] = Chat.COLOUR .. "|H" .. Links.Write(read, index) .. "|h[" .. word .. "]|h|r"
	end
	return buttons
end

--- The place of a row that names its thing nowhere: its buttons go at its end.
local NOWHERE = {}

-- Whether a place on a row is somewhere on it.
local function on(text, at)
	return at ~= nil and at <= #text
end

-- A row with its buttons where the player has chosen them to go, as `withButtons` says.
-- Buttons before a thing are each followed by a dash, and buttons after it each follow
-- one; a link the server leaves open is closed after its name before buttons go there.
local function put(text, placement, place, buttons)
	local at, lead, close = #text + 1, false, false
	if placement == "beforeId" and on(text, place.id) then
		at, lead = place.id, true
	elseif (placement == "beforeId" or placement == "beforeLink") and on(text, place.from) then
		at, lead = place.from, true
	elseif placement == "afterLink" and on(text, place.to) then
		at, close = place.to, place.open
	end
	local joined = {}
	for index, button in ipairs(buttons) do
		if lead then
			joined[index] = button .. SEPARATOR
		else
			joined[index] = SEPARATOR .. button
		end
	end
	if close then
		joined[1] = "|h" .. joined[1]
	end
	return text:sub(1, at - 1) .. table.concat(joined) .. text:sub(at)
end

-- A line as the filter shows it, or nil where it gains no buttons. They go before the id
-- the row prints before its link, before the link, or after it, as `placement` says, and
-- at the row's end otherwise or where the row has no such place; before the id is before
-- the link where the row prints none. A line the server breaks into rows names what it
-- is on the first, so the line's own buttons go on that row, and a later row that names
-- a thing of its own, as a detail doodad lists a model on each, gains that thing's.
local function withButtons(message, placement)
	local read, place = Lines.Locate(message)
	local own = read and buttonsOf(read)
	if not own then
		return nil
	end
	local reads, places = Lines.Rows(message, read)
	reads, places = reads or {}, places or {}
	reads[1], places[1] = read, place
	local shown = {}
	for index, row in ipairs(Lines.Split(message)) do
		local buttons = index == 1 and own or (reads[index] and buttonsOf(reads[index]))
		local text = row.text
		if buttons then
			text = put(text, placement, places[index] or NOWHERE, buttons)
		end
		shown[index] = text .. row.ending
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
		lastShown = withButtons(message, placement)
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
	if draws(read, drawer) then
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

local pointed -- the link under the pointer and its read, while it is the server's own and previewed

-- The pointer came to rest on a link of the server's own, where the player wants that
-- previewed: the link a line names its thing by, read off the whole line the chat frame
-- drew it on as the line's buttons are, and never a GUID, a display or another addon's
-- button, which may carry the very same link, as GLink's `[Spawn]` after a creature's
-- name does, and only its label tells apart. Glimpse only adds to what the link does: a
-- tooltip shown for it is the client's or another addon's, and the hover frame stands
-- beside it.
local function enteredLink(link, text, region)
	if not (ns.Settings.Get("linkHover") and Lines.Knows(link)) then
		return
	end
	local line = region and region.GetText and region:GetText()
	local read, place = Lines.Locate(type(line) == "string" and line or "")
	if not (read and place and place.link == link and Lines.Label(text) == place.label) then
		return
	end
	read = Kinds.Settle(read)
	local drawer = Chat.Drawer(read)
	if draws(read, drawer) then
		pointed = { link = link, read = read }
		ns.Peek.Show(read, drawer == "provider", false, true)
	end
end

-- The pointer came to rest on a link in a chat frame.
local function entered(chat, link, text, region)
	local read, index = Links.Read(link)
	if not read then
		enteredLink(link, text, region)
		return
	end
	local drawer = Chat.Drawer(read)
	if not drawer then
		return
	end
	if draws(read, drawer) then
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
	pointed = nil
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
	-- A click on this addon's button, or an Alt-click on the server's own link while it is
	-- previewed: on these links nothing else answers Alt, neither the client nor the
	-- addons that act on them.
	_G.hooksecurefunc(
		"SetItemRef",
		Safely.Wrap(function(link, _, button)
			local read, index = Links.Read(link)
			if read then
				Chat.Open(read, index, button)
			elseif
				pointed
				and pointed.link == link
				and button ~= "RightButton"
				and _G.IsAltKeyDown()
			then
				Chat.Open(pointed.read, 1)
			end
		end)
	)
end
