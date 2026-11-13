local addonName, ns = ...

--- The settings panel, under Interface, AddOns: one page that scrolls, since it holds
-- more than the client's settings leave room for.
--
-- Each control changes its setting as it is used, so there is nothing to
-- confirm; the panel's Defaults button clears every choice. A control that
-- only matters while another is on is dimmed while that one is off.
--
-- Under them, a switch for each kind of thing turns its previews on or off.
-- Kinds that share a word, as the sounds do, share a switch; a kind another
-- addon previews says which addon does. A kind nothing previews has no switch,
-- but for spells, whose switch is greyed until an addon offers them.
local Settings, Kinds, Providers = ns.Settings, ns.Kinds, ns.Providers

local Options = {}
ns.Options = Options

--- What GLink adds after a line that links a creature, and one that links an object.
local GLINK_CREATURE = "|cffADFFFF -|r |cff00CCFF|Hcreature_entry:%d|h[Spawn]|h|r"
local GLINK_OBJECT = "|cffADFFFF -|r |cff00CCFF|Hgameobject_entry:%d|h[Spawn]|h|r"
	.. "|cffADFFFF -|r |cff00CCFF|Hgameobject_entry:%d|h[Copy Entry]|h|r"

--- Lines as the server prints them and a player with GLink sees them, for the examples
-- under the choice of where the buttons go: a creature and an object `.lookup` finds, an
-- `.npc info` with no id before its link, a zone's music, which plays rather than shows
-- and has no link, and a spawn reply whose link the server leaves open. Each with the
-- buttons it gains.
local SAMPLES = {
	{
		line = "184093 - |cffffffff|Hcreature_entry:184093|h[Spirit Wolf]|h|r"
			.. GLINK_CREATURE:format(184093),
		buttons = { "Preview" },
	},
	{
		line = "716709 - |cffffffff|Hgameobject_entry:716709|h[6dr_draenei_chair02.m2]|h|r"
			.. GLINK_OBJECT:format(716709, 716709),
		buttons = { "Preview" },
	},
	{
		line = "NPC Info: |cff00CCFF|Hcreature_entry:16998|h[Mr. Bigglesworth - 16998]|h|r"
			.. " (GUID: |cff00CCFF|HNPC_GUID:19647814|h19647814|h|r)"
			.. GLINK_CREATURE:format(16998),
		buttons = { "Preview" },
	},
	{
		line = "|cff00CCFF156|r - Zone-TavernAlliance",
		buttons = { "Play" },
	},
	{
		line = "Spawned gameobject |cff00CCFF|Hgameobject_entry:801862|h[6ar_fern_b02.m2 - 801862]|r"
			.. " (GUID: |cff00CCFF|Hgameobject_GUID:96102|h96102|h|r)"
			.. GLINK_OBJECT:format(801862, 801862),
		buttons = { "Preview" },
	},
}

-- The sample lines with this addon's buttons where a placement puts them, by the same
-- rule the chat filter follows.
local function examples(placement)
	local shown = {}
	for index, sample in ipairs(SAMPLES) do
		shown[index] = sample.line
		if placement ~= "none" then
			local _, place = ns.Lines.Locate(sample.line)
			shown[index] = ns.Chat.Place(sample.line, placement, place, function(lead)
				local buttons = {}
				for at, word in ipairs(sample.buttons) do
					buttons[at] = ns.Chat.COLOUR .. "[" .. word .. "]|r"
				end
				return ns.Chat.Join(buttons, lead)
			end)
		end
	end
	return shown
end

--- The controls, top to bottom. A `needs` names the switch a control depends on.
--   switch  { key, label }
--   choice  { key, label, options = { { value, label }, ... }, examples }, the options as
--           equals one under another; `examples`, optional, answers system chat lines
--           showing a value
--   range   { key, label, low, high, step }
local CONTROLS = {
	{
		kind = "choice",
		key = "buttons",
		label = "Put " .. ns.Chat.COLOUR .. "[Preview]|r and " .. ns.Chat.COLOUR .. "[Play]|r",
		options = {
			{ value = "beforeId", label = "before the ID" },
			{ value = "beforeLink", label = "before the link" },
			{ value = "afterLink", label = "after the link" },
			{ value = "end", label = "at the end of the line" },
			{ value = "none", label = "nowhere" },
		},
		examples = examples,
	},
	{ kind = "switch", key = "hover", label = "Preview on hover" },
	{
		kind = "range",
		key = "hoverSize",
		label = "Hover preview size",
		low = 150,
		high = 500,
		step = 10,
		needs = "hover",
	},
	{ kind = "switch", key = "hoverSpin", label = "Spin the hover preview", needs = "hover" },
	{
		kind = "switch",
		key = "sideBySide",
		label = "Show a creature's displays side by side on hover",
		needs = "hover",
	},
	{ kind = "switch", key = "manyWindows", label = "Open each preview in a window of its own" },
	{ kind = "switch", key = "linkHover", label = "Also preview on hovering the link" },
}

local GAP = { switch = 8, choice = 8, range = 32 }

--- The colour of what a kind's switch says beside its word.
local NOTE = "|cff808080"

--- How the kinds' switches lay out: two columns, this far apart, rows this far apart.
local COLUMNS, COLUMN_WIDTH, ROW_HEIGHT = 2, 300, 28

--- How a choice lays out: its label and each option a row this tall, then its examples
-- a row this tall each, under a gap.
local CHOICE_ROW, EXAMPLE_ROW, EXAMPLE_GAP = 18, 16, 10

-- The kinds, one group to a word, in the order the addon added them.
local function groups()
	local found, byWord = {}, {}
	for _, each in ipairs(Kinds.List()) do
		local group = byWord[each.word]
		if not group then
			group = { word = each.word, listed = each.listed, kinds = {} }
			byWord[each.word] = group
			found[#found + 1] = group
		end
		group.kinds[#group.kinds + 1] = each.kind
	end
	return found
end

-- A kind's switch, and what it says beside its word: the addon that previews the
-- kind where another one does. Settled each time the panel is shown, since an
-- addon may offer a kind or fault after the panel is built; `show` answers whether
-- the switch is shown. A kind nothing previews is greyed where it is shown at all.
local function kindSwitch(parent, group, changed)
	local first = group.kinds[1]
	local button = _G.CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
	button:SetScript(
		"OnClick",
		ns.Safely.Wrap(function()
			for _, kind in ipairs(group.kinds) do
				Settings.Turn(kind, button:GetChecked() == true)
			end
			changed()
		end)
	)
	local function show()
		local drawer = Kinds.DrawerOf(first)
		button:SetChecked(Settings.On(first))
		-- The addon is named in the label's own line, quieter: the label is wider
		-- than its words, so anything set after its edge stands far from them.
		local label = group.word
		if drawer == "provider" then
			label = label
				.. "  "
				.. NOTE
				.. "by "
				.. (Providers.Name(first) or "another addon")
				.. "|r"
		end
		button.Text:SetText(label)
		button:SetEnabled(drawer ~= nil)
		if drawer then
			button:SetAlpha(1)
		else
			button:SetAlpha(0.5)
		end
		local shown = drawer ~= nil or group.listed
		button:SetShown(shown)
		return shown
	end
	return button, show
end

local BUILD = {
	switch = function(parent, control, changed)
		local button =
			_G.CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
		button.Text:SetText(control.label)
		button:SetScript(
			"OnClick",
			ns.Safely.Wrap(function()
				Settings.Set(control.key, button:GetChecked() == true)
				changed()
			end)
		)
		return button, button.SetChecked
	end,
	-- A choice is its label, then a radio button for each option under it, the option
	-- chosen marked; a value that is none of them marks the default's. Where the
	-- control gives examples, lines under the options show what the choice does, in
	-- chat's font and the player's colour for system lines, as chat would show them,
	-- each cut short rather than wrapped where it is wider than the page.
	choice = function(parent, control, changed)
		local box = _G.CreateFrame("Frame", nil, parent)
		local label = box:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		label:SetPoint("TOPLEFT", 4, 0)
		label:SetText(control.label)
		local radios = {}
		for index, option in ipairs(control.options) do
			local radio = _G.CreateFrame("CheckButton", nil, box, "UIRadioButtonTemplate")
			radio:SetPoint("TOPLEFT", 16, -CHOICE_ROW * index)
			radio.text:SetFontObject("GameFontHighlight")
			radio.text:SetTextColor(_G.HIGHLIGHT_FONT_COLOR:GetRGB())
			radio.text:SetText(option.label)
			radio:SetHitRectInsets(0, -(radio.text:GetStringWidth() + 5), 0, 0)
			radio:SetScript(
				"OnClick",
				ns.Safely.Wrap(function()
					Settings.Set(control.key, option.value)
					changed()
				end)
			)
			radios[index] = radio
		end
		local lines, height = {}, CHOICE_ROW * (#radios + 1)
		if control.examples then
			local width = COLUMNS * COLUMN_WIDTH - 16
			for index = 1, #control.examples(Settings.DEFAULTS[control.key]) do
				local line = box:CreateFontString(nil, "ARTWORK", "ChatFontNormal")
				line:SetPoint("TOPLEFT", 16, -(height + EXAMPLE_GAP + EXAMPLE_ROW * (index - 1)))
				line:SetWidth(width)
				line:SetJustifyH("LEFT")
				line:SetWordWrap(false)
				lines[index] = line
			end
			height = height + EXAMPLE_GAP + EXAMPLE_ROW * #lines
		end
		box:SetSize(COLUMNS * COLUMN_WIDTH, height)
		return box,
			function(_, value)
				local known = false
				for _, option in ipairs(control.options) do
					known = known or option.value == value
				end
				if not known then
					value = Settings.DEFAULTS[control.key]
				end
				for index, option in ipairs(control.options) do
					radios[index]:SetChecked(option.value == value)
				end
				if #lines > 0 then
					local system = _G.ChatTypeInfo.SYSTEM
					for index, text in ipairs(control.examples(value)) do
						lines[index]:SetTextColor(system.r, system.g, system.b)
						lines[index]:SetText(text)
					end
				end
			end
	end,
	-- A slider says its value above it, and when that is the default, so the
	-- default can be found again; its ends say how far it goes.
	range = function(parent, control)
		local slider = _G.CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
		slider:SetWidth(220)
		slider:SetMinMaxValues(control.low, control.high)
		slider:SetValueStep(control.step)
		slider:SetObeyStepOnDrag(true)
		slider.Low:SetText(control.low)
		slider.High:SetText(control.high)
		slider:SetScript(
			"OnValueChanged",
			ns.Safely.Wrap(function(_, value, byPlayer)
				value = math.floor(value + 0.5)
				local text = control.label .. ": " .. value
				if value == Settings.DEFAULTS[control.key] then
					text = text .. " (default)"
				end
				slider.Text:SetText(text)
				if byPlayer then
					Settings.Set(control.key, value)
				end
			end)
		)
		return slider, slider.SetValue
	end,
}

local function build()
	local panel = _G.CreateFrame("Frame")
	panel.name = addonName

	-- What the panel shows is a page in a scroll frame. The template finds its parts by
	-- their keys, so the frame needs no global name.
	local scroll = _G.CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -26, 4)
	scroll.scrollBarHideable = true
	local page = _G.CreateFrame("Frame", nil, scroll)
	page:SetSize(COLUMNS * COLUMN_WIDTH + 32, 1)
	scroll:SetScrollChild(page)

	local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(addonName)

	-- Each control and switch is put as the settings stand, whenever one is used.
	local show

	local rows = {}
	local above = title
	for index, control in ipairs(CONTROLS) do
		local widget, put = BUILD[control.kind](page, control, function()
			show()
		end)
		widget:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -GAP[control.kind])
		rows[index] = { control = control, widget = widget, put = put }
		above = widget
	end

	local heading = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	heading:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -24)
	heading:SetText("Preview these")
	local switches = {}
	for index, group in ipairs(groups()) do
		local button, put = kindSwitch(page, group, function()
			show()
		end)
		switches[index] = { button = button, put = put }
	end

	local credit = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	credit:SetText("Put together by Nataari, mostly with AI — mistakes are possible")

	show = function()
		for _, row in ipairs(rows) do
			row.put(row.widget, Settings.Get(row.control.key))
			if row.control.needs then
				local on = Settings.Get(row.control.needs)
				row.widget:SetEnabled(on)
				if on then
					row.widget:SetAlpha(1)
				else
					row.widget:SetAlpha(0.5)
				end
			end
		end
		-- The switches shown fill the columns in order, with no gap where one is not.
		local shown = 0
		for _, switch in ipairs(switches) do
			if switch.put() then
				local column, line = shown % COLUMNS, math.floor(shown / COLUMNS)
				switch.button:ClearAllPoints()
				switch.button:SetPoint(
					"TOPLEFT",
					heading,
					"BOTTOMLEFT",
					column * COLUMN_WIDTH,
					-4 - line * ROW_HEIGHT
				)
				shown = shown + 1
			end
		end
		-- The credit follows the last row of switches, and the page is as tall as what
		-- it holds, which the client can measure once the panel stands on the screen.
		credit:ClearAllPoints()
		credit:SetPoint(
			"TOPLEFT",
			heading,
			"BOTTOMLEFT",
			0,
			-16 - math.ceil(shown / COLUMNS) * ROW_HEIGHT
		)
		local top, bottom = page:GetTop(), credit:GetBottom()
		if top and bottom then
			page:SetHeight(top - bottom + 16)
		end
	end

	panel.refresh = ns.Safely.Wrap(show)
	panel.default = ns.Safely.Wrap(function()
		Settings.Reset()
		show()
	end)
	return panel
end

local panel

--- Add the panel to the client's list. Called once, at login.
function Options.Install()
	panel = build()
	_G.InterfaceOptions_AddCategory(panel)
end

--- Open the client's settings at this addon's panel. The client picks a page from
-- the list it has drawn, and draws that list only once the settings are shown,
-- so the first call shows them and the second picks the page.
function Options.Open()
	_G.InterfaceOptionsFrame_OpenToCategory(panel)
	_G.InterfaceOptionsFrame_OpenToCategory(panel)
end
