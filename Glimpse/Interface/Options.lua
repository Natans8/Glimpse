local addonName, ns = ...

--- The settings panel, under Interface, AddOns.
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

--- A `.lookup` result as a player with GLink sees it, its id in the colour chat gives
-- system lines and its link in the server's white, for the example beside the choice
-- of where the buttons go.
local SAMPLE = "184093 - |cffffffff|Hcreature_entry:184093|h[Spirit Wolf]|h|r"
	.. "|cffADFFFF -|r |cff00CCFF|Hcreature_entry:184093|h[Spawn]|h|r"

-- The sample result with this addon's button where a placement puts it, by the
-- same rule the chat filter follows.
local function example(placement)
	if placement == "none" then
		return SAMPLE
	end
	local _, place = ns.Lines.Locate(SAMPLE)
	return ns.Chat.Place(SAMPLE, placement, place, function(lead)
		return ns.Chat.Join({ ns.Chat.COLOUR .. "[Preview]|r" }, lead)
	end)
end

--- The controls, top to bottom. A `needs` names the switch a control depends on.
--   switch  { key, label }
--   choice  { key, label, options = { { value, label }, ... }, example }, the options as
--           equals one under another; `example`, optional, answers a system chat line
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
		example = example,
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
}

local GAP = { switch = 8, choice = 8, range = 32 }

--- The colour of what a kind's switch says beside its word.
local NOTE = "|cff808080"

--- How the kinds' switches lay out: two columns, this far apart, rows this far apart.
local COLUMNS, COLUMN_WIDTH, ROW_HEIGHT = 2, 300, 28

--- How a choice lays out: its label and each option a row this tall, and its example
-- line this far right of the options.
local CHOICE_ROW, EXAMPLE_INDENT = 18, 200

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
local function kindSwitch(panel, group, changed)
	local first = group.kinds[1]
	local button = _G.CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
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
	switch = function(panel, control, changed)
		local button =
			_G.CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
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
	-- control gives an example, a line beside the options shows what the choice does,
	-- in chat's font and the player's colour for system lines, as chat would show it.
	choice = function(panel, control, changed)
		local box = _G.CreateFrame("Frame", nil, panel)
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
		local shown
		if control.example then
			shown = box:CreateFontString(nil, "ARTWORK", "ChatFontNormal")
			shown:SetPoint("LEFT", radios[math.ceil(#radios / 2)], "LEFT", EXAMPLE_INDENT, 0)
		end
		box:SetSize(COLUMNS * COLUMN_WIDTH, CHOICE_ROW * (#radios + 1))
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
				if shown then
					local system = _G.ChatTypeInfo.SYSTEM
					shown:SetTextColor(system.r, system.g, system.b)
					shown:SetText(control.example(value))
				end
			end
	end,
	-- A slider says its value above it, and when that is the default, so the
	-- default can be found again; its ends say how far it goes.
	range = function(panel, control)
		local slider = _G.CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
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

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(addonName)

	-- Each control and switch is put as the settings stand, whenever one is used.
	local show

	local rows = {}
	local above = title
	for index, control in ipairs(CONTROLS) do
		local widget, put = BUILD[control.kind](panel, control, function()
			show()
		end)
		widget:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -GAP[control.kind])
		rows[index] = { control = control, widget = widget, put = put }
		above = widget
	end

	local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	heading:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -24)
	heading:SetText("Preview these")
	local switches = {}
	for index, group in ipairs(groups()) do
		local button, put = kindSwitch(panel, group, function()
			show()
		end)
		switches[index] = { button = button, put = put }
	end

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
	end

	local credit = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	credit:SetPoint("BOTTOMLEFT", 16, 16)
	credit:SetText("Put together by Nataari, mostly with AI — mistakes are possible")

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
