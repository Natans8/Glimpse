local _, ns = ...

--- The hover frame: what a button shows while the pointer rests on it.
--
-- It is for recognising a thing at a glance, so the picture is all of it: a
-- square card in the addon's own dress, the first look in its presentation's
-- view. Where the player has asked, each of several looks of a kind gets a
-- card of its own, glued in a row the way the game glues its comparison
-- tooltips, as many as the screen has room for; the last says how many more
-- there are. A thing turns so every side comes round, unless the player has
-- turned that off; an emote is watched from the front. The name lies over the
-- first card's lower edge, with one quieter line under it saying what the
-- thing is, and the quietest line says that a click opens it. The cards take
-- no input. They stand at the pointer as a tooltip does, a corner just above
-- the button or, without the room there, just below it, and the row runs
-- whichever way the screen has more room. Resting on the server's own link, where
-- the client or another addon may put up the game tooltip for it, they are glued to
-- that tooltip's side instead and move with it, and are not seen until they stand there.
--
-- A kind another addon previews gets the first card's inside, empty, and the
-- card shows only where that addon fills it.
local Async, Stage, Presentations, Tools = ns.Async, ns.Stage, ns.Presentations, ns.Tools
local Providers = ns.Providers

local Peek = {}
ns.Peek = Peek

local MARGIN = 5

--- How far from the pointer the nearest corner stands, so the line under it stays readable.
local LIFT = 16

--- How tall the shade under the words is, and how dark at the picture's edge.
local SHADE_HEIGHT, SHADE = 64, 0.9

--- How fast the look turns, in radians a second: once round in about six.
local SPIN = 1

--- Where a turning look starts: 45 degrees clockwise of its own angle, against the
-- turn, so the turn carries its front past the viewer first.
local START = -math.rad(45)

local cards = {} -- every card made so far; the first is the hover frame itself
local shown = 0 -- how many of them hold a look
local side -- "RIGHT" or "LEFT": which way from the pointer the row runs
local reach -- how wide the screen is from the pointer that way

-- A card: a panel, a stage filling it, the words over its lower edge, and an
-- inside to lend in their place.
local function card()
	local frame = _G.CreateFrame("Frame", nil, _G.UIParent)
	Tools.Panel(frame)
	frame:SetFrameStrata("TOOLTIP")
	frame:Hide()

	local holder = _G.CreateFrame("Frame", nil, frame)
	holder:SetPoint("TOPLEFT", MARGIN, -MARGIN)

	-- The words stand on a frame of their own, above whatever is drawn.
	local over = _G.CreateFrame("Frame", nil, holder)
	over:SetAllPoints()
	over:SetFrameLevel(holder:GetFrameLevel() + 10)

	local shade = over:CreateTexture(nil, "BACKGROUND")
	shade:SetPoint("BOTTOMLEFT")
	shade:SetPoint("BOTTOMRIGHT")
	shade:SetHeight(SHADE_HEIGHT)
	shade:SetColorTexture(1, 1, 1)
	shade:SetGradientAlpha("VERTICAL", 0, 0, 0, SHADE, 0, 0, 0, 0)

	local hint = over:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMRIGHT", -6, 6)
	hint:SetAlpha(0.7)

	local caption = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	caption:SetPoint("BOTTOMLEFT", 6, 6)
	caption:SetPoint("RIGHT", hint, "LEFT", -6, 0)
	caption:SetJustifyH("LEFT")
	caption:SetWordWrap(false)
	caption:SetAlpha(0.8)

	local name = over:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	name:SetPoint("BOTTOMLEFT", caption, "TOPLEFT", 0, 2)
	name:SetPoint("RIGHT", over, "RIGHT", -6, 0)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)

	local inside = _G.CreateFrame("Frame", nil, holder)
	inside:SetAllPoints()
	inside:Hide()

	local stage = Stage.New(holder)
	stage:WhenNothing(function()
		caption:SetText(Presentations.NOTHING)
	end)

	return {
		frame = frame,
		holder = holder,
		over = over,
		inside = inside,
		stage = stage,
		name = name,
		caption = caption,
		hint = hint,
	}
end

--- What the first card says a click does: on the button, and on the server's own link.
local OPEN, OPEN_LINK = "Click to open", "Alt-click to open"

local function build()
	local first = card()
	first.frame:SetClampedToScreen(true)
	first.spinner = _G.CreateFrame("Frame", nil, first.over, "LoadingSpinnerTemplate")
	first.spinner:SetSize(36, 36)
	first.spinner:SetPoint("CENTER")
	first.spinner:Hide()
	-- One clock turns every card that holds a look, so they stay alike to compare.
	first.spin = ns.Safely.Wrap(function(_, elapsed)
		for index = 1, shown do
			cards[index].stage:Turn(SPIN * elapsed)
		end
	end)
	cards[1] = first
end

--- Which way from the pointer the hover frame has more room.
-- @param x the pointer's distance from the screen's left
-- @param width the screen's width
-- @return "RIGHT" or "LEFT"
function Peek.Side(x, width)
	if width - x >= x then
		return "RIGHT"
	end
	return "LEFT"
end

--- How many cards stand in a row in the room beside the pointer.
-- @param room the width from the pointer to the screen's edge, on the row's side
-- @param width one card's width
-- @param wanted how many looks there are to show
-- @return at least one, and at most `wanted`
function Peek.Fit(room, width, wanted)
	return math.max(1, math.min(wanted, math.floor(room / width)))
end

-- One card's width and height, from the size the player chose for the picture.
local function extent()
	return ns.Settings.Get("hoverSize") + 2 * MARGIN
end

local function size(found)
	local picture = ns.Settings.Get("hoverSize")
	found.holder:SetSize(picture, picture)
	found.frame:SetSize(extent(), extent())
end

-- Stand the first card with a corner just above the pointer, on the side with
-- more room, as the client stands a tooltip at the pointer.
local function place()
	local first = cards[1].frame
	size(cards[1])
	local scale = _G.UIParent:GetEffectiveScale()
	local x, y = _G.GetCursorPosition()
	x, y = x / scale, y / scale
	local width = _G.UIParent:GetWidth()
	side = Peek.Side(x, width)
	reach = side == "RIGHT" and width - x or x
	-- Above the pointer where there is room for it, as near the foot of the screen
	-- where chat usually is; below it otherwise.
	local up = y + LIFT + extent() <= _G.UIParent:GetHeight()
	local vertical, lifted = "TOP", y - LIFT
	if up then
		vertical, lifted = "BOTTOM", y + LIFT
	end
	local corner = vertical .. (side == "RIGHT" and "LEFT" or "RIGHT")
	first:ClearAllPoints()
	first:SetPoint(corner, _G.UIParent, "BOTTOMLEFT", x, lifted)
end

-- Glue a card to the one before it, away from the pointer. Their borders
-- overlap by a pixel, so two cards read as one edge between them.
local function glue(index)
	local frame, before = cards[index].frame, cards[index - 1].frame
	size(cards[index])
	frame:ClearAllPoints()
	if side == "RIGHT" then
		frame:SetPoint("TOPLEFT", before, "TOPRIGHT", -1, 0)
	else
		frame:SetPoint("TOPRIGHT", before, "TOPLEFT", 1, 0)
	end
end

local waiter -- a frame of the addon's own, to wait for the next frame drawn
local beside = false -- whether the hover frame is to stand beside the game tooltip

-- Every card holding a look shown or kept unseen.
local function seen(alpha)
	for index = 1, math.max(shown, 1) do
		cards[index].frame:SetAlpha(alpha)
	end
end

-- Glue the hover frame to the side of the game tooltip with more room, where the client
-- or another addon has put it up for what the pointer rests on, the way the game glues
-- its comparison tooltips: glued, it moves as the tooltip follows the pointer. Then let
-- it be seen, still at the pointer where no tooltip is up.
local glueToTooltip = ns.Safely.Wrap(function()
	waiter:SetScript("OnUpdate", nil)
	local first, tooltip = cards[1].frame, _G.GameTooltip
	local left, right = tooltip:GetLeft(), tooltip:GetRight()
	if beside and first:IsShown() and tooltip:IsVisible() and left and right then
		local scale = tooltip:GetEffectiveScale() / _G.UIParent:GetEffectiveScale()
		local width = _G.UIParent:GetWidth()
		left, right = left * scale, right * scale
		side = Peek.Side((left + right) / 2, width)
		first:ClearAllPoints()
		if side == "RIGHT" then
			reach = width - right
			first:SetPoint("TOPLEFT", tooltip, "TOPRIGHT")
		else
			reach = left
			first:SetPoint("TOPRIGHT", tooltip, "TOPLEFT")
		end
		for index = 2, shown do
			glue(index)
		end
	end
	seen(1)
end)

-- Glue the hover frame to the game tooltip by the next frame drawn, when every addon
-- has put up what it shows for what the pointer rests on.
local function waitForTooltip()
	waiter = waiter or _G.CreateFrame("Frame")
	waiter:SetScript("OnUpdate", glueToTooltip)
end

-- Draw nothing on any card, take back a lent inside, and put away every card but
-- the first.
local function clear()
	for index, found in ipairs(cards) do
		found.stage:Clear()
		if found.lent then
			Providers.Hide(found.lent, found.inside)
			found.lent = nil
		end
		found.inside:Hide()
		if index > 1 then
			found.hint:SetText("")
			found.frame:Hide()
		end
	end
	shown = 0
end

-- The answer is in: no spinner.
local function settle()
	cards[1].spinner:Hide()
end

-- Lend the first card's inside to the addon that previews the read's kind, under
-- the name and kind every card wears. The card is shown first, since a model frame
-- inside it applies nothing while hidden.
local function lend(first, read)
	first.over:Show()
	first.name:SetText(read.name)
	first.inside:Show()
	first.frame:Show()
	first.lent = read.kind
	local filled, words =
		Providers.Show(read.kind, first.inside, read.id, Providers.Context("hover", read))
	if not filled then
		first.frame:Hide()
		return
	end
	first.caption:SetText(Presentations.Lent(read, words))
end

--- Show a read at the pointer, or beside the tooltips on the screen.
-- @param read the read to show
-- @param lent true where the addon that offers the read's kind previews it
-- @param asked true where another addon asked, which owns what a click on its own
--   button does, so the frame does not say a click opens it
-- @param byLink true where the pointer rests on the server's own link rather than a
--   button: the client or another addon may put up the game tooltip for it, so the frame
--   is glued to its side, unseen until it is, and says an Alt-click opens it
function Peek.Show(read, lent, asked, byLink)
	if not cards[1] then
		build()
	end
	local first = cards[1]
	settle()
	clear()
	place()
	beside = byLink == true
	if beside then
		seen(0)
		waitForTooltip()
	else
		seen(1)
	end
	if asked then
		first.hint:SetText("")
	elseif beside then
		first.hint:SetText(OPEN_LINK)
	else
		first.hint:SetText(OPEN)
	end
	first.frame:SetScript("OnUpdate", nil)
	if lent then
		Async.Cancel("peek")
		lend(first, read)
		return
	end
	first.over:Show()
	first.name:SetText(read.name)
	first.caption:SetText("")
	first.spinner:Show()
	first.frame:Show()
	Async.Ask("peek", read, function(subject)
		settle()
		if not (subject and subject.looks[1]) then
			first.caption:SetText(Presentations.NOTHING)
			return
		end
		local looks, look = subject.looks, subject.looks[1]
		shown = 1
		-- Several looks of a kind each get a card where the player has asked.
		if ns.Settings.Get("sideBySide") and #looks > 1 then
			shown = Peek.Fit(reach, extent(), #looks)
		end
		-- The looks turn where the player wants them turned and they are things to
		-- see from every side; something happening is watched from the front.
		local turning = ns.Settings.Get("hoverSpin") and not Presentations.Of(look).still
		local start = 0
		if turning then
			start = START
		end
		first.caption:SetText(Presentations.Caption(subject, 1))
		first.stage:Show(look, start)
		for index = 2, shown do
			cards[index] = cards[index] or card()
			local found = cards[index]
			glue(index)
			found.name:SetText("")
			found.caption:SetText(Presentations.Place(looks[index], index, #looks))
			found.frame:SetAlpha(first.frame:GetAlpha())
			found.frame:Show()
			found.stage:Show(looks[index], start)
		end
		if shown > 1 and shown < #looks then
			cards[shown].hint:SetText("+" .. (#looks - shown) .. " more")
		end
		if turning then
			first.frame:SetScript("OnUpdate", first.spin)
		end
	end)
end

--- Take the hover frame down and abandon whatever it was waiting for.
function Peek.Hide()
	if not cards[1] then
		return
	end
	settle()
	Async.Cancel("peek")
	beside = false
	if waiter then
		waiter:SetScript("OnUpdate", nil)
	end
	clear()
	cards[1].frame:Hide()
end
