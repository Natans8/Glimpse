local addonName, ns = ...

--- The addon's own dress: its panels and its controls, all drawn one way.
--
-- Nothing here borrows the client's artwork, so every part matches every
-- other whatever another addon has done to the client's buttons. A panel is
-- a flat dark fill inside a hairline. A control is a white drawing from the
-- addon's icon sheet, or words, grey at rest, white under the pointer, and
-- the accent colour while it is the one chosen or switched on. The fonts are
-- the game's own. An icon says what it does in a tooltip, in a title and at
-- most a line.
local Tools = {}
ns.Tools = Tools

--- The colours, each as red, green, blue and opacity.
local FILL, EDGE = { 0.055, 0.055, 0.075, 0.97 }, { 1, 1, 1, 0.14 }
local REST, LIT, ACCENT = { 0.72, 0.72, 0.76 }, { 1, 1, 1 }, { 0.78, 0.66, 1 }

--- The fill behind a picture: darker than a panel's.
Tools.WELL = { 0.03, 0.03, 0.045, 1 }
local UNDER_POINTER = { 1, 1, 1, 0.09 }

local SHEET = "Interface\\AddOns\\" .. addonName .. "\\Art\\Icons"

--- The icons, in the order they stand in the sheet, and how many it has room for.
local ICONS = {
	"reset",
	"weapon",
	"soundOn",
	"soundOff",
	"close",
	"grip",
	"previous",
	"following",
}
local SLOTS = 8

local SLOT = {}
for slot, icon in ipairs(ICONS) do
	SLOT[icon] = slot
end

local SIZE = 22

--- Draw an icon into a texture.
-- @param texture the texture
-- @param icon the icon's name
function Tools.Draw(texture, icon)
	local slot = SLOT[icon]
	texture:SetTexture(SHEET)
	texture:SetTexCoord((slot - 1) / SLOTS, slot / SLOTS, 0, 1)
end

--- Fill a frame with a flat colour, behind everything it holds.
-- @param frame the frame
-- @param colour the colour, as red, green, blue and opacity
function Tools.Fill(frame, colour)
	local fill = frame:CreateTexture(nil, "BACKGROUND")
	fill:SetAllPoints()
	fill:SetColorTexture(unpack(colour))
end

--- The sides of a frame a hairline runs along: two corners, and which way it is thin.
local SIDES = {
	{ from = "TOPLEFT", to = "TOPRIGHT", flat = true },
	{ from = "BOTTOMLEFT", to = "BOTTOMRIGHT", flat = true },
	{ from = "TOPLEFT", to = "BOTTOMLEFT", flat = false },
	{ from = "TOPRIGHT", to = "BOTTOMRIGHT", flat = false },
}

--- Dress a frame as a panel: the fill, inside a hairline.
-- @param frame the frame
function Tools.Panel(frame)
	Tools.Fill(frame, FILL)
	for _, side in ipairs(SIDES) do
		local edge = frame:CreateTexture(nil, "BORDER")
		edge:SetColorTexture(unpack(EDGE))
		edge:SetPoint(side.from)
		edge:SetPoint(side.to)
		if side.flat then
			edge:SetHeight(1)
		else
			edge:SetWidth(1)
		end
	end
end

--- Give a control a tooltip.
-- @param control the frame the pointer rests on
-- @param title what the control is, in a word or two
-- @param text optional; one line more
function Tools.Hint(control, title, text)
	control:HookScript(
		"OnEnter",
		ns.Safely.Wrap(function()
			local tooltip = _G.GameTooltip
			tooltip:SetOwner(control, "ANCHOR_RIGHT")
			tooltip:SetText(title, 1, 1, 1)
			if text then
				tooltip:AddLine(text, nil, nil, nil, true)
			end
			tooltip:Show()
		end)
	)
	control:HookScript(
		"OnLeave",
		ns.Safely.Wrap(function()
			_G.GameTooltip:Hide()
		end)
	)
end

-- A bare button that lights under the pointer. `paint(colour)` colours what it shows;
-- `button.chosen` keeps it in the accent colour.
local function control(parent, paint)
	local button = _G.CreateFrame("Button", nil, parent)
	local glow = button:CreateTexture(nil, "BACKGROUND")
	glow:SetAllPoints()
	glow:SetColorTexture(unpack(UNDER_POINTER))
	glow:Hide()
	local function repaint()
		if button.chosen then
			paint(ACCENT)
		elseif button:IsMouseOver() then
			paint(LIT)
		else
			paint(REST)
		end
	end
	button.Repaint = repaint
	button:SetScript(
		"OnEnter",
		ns.Safely.Wrap(function()
			glow:Show()
			repaint()
		end)
	)
	button:SetScript(
		"OnLeave",
		ns.Safely.Wrap(function()
			glow:Hide()
			repaint()
		end)
	)
	return button
end

--- A button with words on it.
-- @param parent the frame it stands on
-- @param text its words
-- @param clicked called when it is clicked
-- @return the button, as wide as its words; `button.chosen` keeps it in the accent colour
function Tools.Button(parent, text, clicked)
	local words
	local button = control(parent, function(colour)
		words:SetTextColor(unpack(colour))
	end)
	words = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	words:SetPoint("CENTER")
	words:SetText(text)
	button.words = words
	button:SetSize(words:GetStringWidth() + 16, SIZE)
	button:SetScript("OnClick", ns.Safely.Wrap(clicked))
	button:Repaint()
	return button
end

--- A button with an icon on it.
-- @param parent the frame it stands on
-- @param icon the icon's name
-- @param title its tooltip's title
-- @param text optional; its tooltip's line
-- @param clicked called when it is clicked
-- @return the button, with its `icon` texture
function Tools.Icon(parent, icon, title, text, clicked)
	local picture
	local button = control(parent, function(colour)
		picture:SetVertexColor(unpack(colour))
	end)
	button:SetSize(SIZE, SIZE)
	picture = button:CreateTexture(nil, "ARTWORK")
	picture:SetPoint("CENTER")
	picture:SetSize(SIZE - 6, SIZE - 6)
	Tools.Draw(picture, icon)
	button.icon = picture

	button:SetScript("OnClick", ns.Safely.Wrap(clicked))
	Tools.Hint(button, title, text)
	button:Repaint()
	return button
end
