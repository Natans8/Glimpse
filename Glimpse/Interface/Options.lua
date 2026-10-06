local addonName, ns = ...

--- The settings panel, under Interface, AddOns.
--
-- Each control changes its setting as it is used, so there is nothing to
-- confirm; the panel's Defaults button clears every choice. A control that
-- only matters while another is on is dimmed while that one is off.
--
-- Under them, a switch for each kind of thing turns its previews on or off.
-- Kinds that share a word, as the sounds do, share a switch; a kind another
-- addon previews says which addon does, and a kind nothing previews has none.
local Settings, Kinds, Providers = ns.Settings, ns.Kinds, ns.Providers

local Options = {}
ns.Options = Options

--- The controls, top to bottom. A `needs` names the switch a control depends on.
--   switch  { key, label }
--   range   { key, label, low, high, step }
local CONTROLS = {
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

local GAP = { switch = 8, range = 32 }

--- How the kinds' switches lay out: two columns, this far apart, rows this far apart.
local COLUMNS, COLUMN_WIDTH, ROW_HEIGHT = 2, 300, 28

-- The kinds, one group to a word, in the order the addon added them.
local function groups()
	local found, byWord = {}, {}
	for _, each in ipairs(Kinds.List()) do
		local group = byWord[each.word]
		if not group then
			group = { word = each.word, kinds = {} }
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
-- anything previews the kind, and so whether the switch is shown at all.
local function kindSwitch(panel, group, changed)
	local first = group.kinds[1]
	local button = _G.CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
	button.Text:SetText(group.word)
	local note = button:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	note:SetPoint("LEFT", button.Text, "RIGHT", 6, 0)
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
		note:SetText("")
		if drawer == "provider" then
			note:SetText("by " .. (Providers.Name(first) or "another addon"))
		end
		button:SetShown(drawer ~= nil)
		return drawer ~= nil
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

	local rows = {}
	local show

	local above = title
	for index, control in ipairs(CONTROLS) do
		local widget, put = BUILD[control.kind](panel, control, function()
			show()
		end)
		widget:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -GAP[control.kind])
		rows[index] = { control = control, widget = widget, put = put }
		above = widget
	end

	show = function()
		for _, row in ipairs(rows) do
			row.put(row.widget, Settings.Get(row.control.key))
			local on = not row.control.needs or Settings.Get(row.control.needs)
			row.widget:SetEnabled(on)
			if on then
				row.widget:SetAlpha(1)
			else
				row.widget:SetAlpha(0.5)
			end
		end
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
	-- The switches shown fill the columns in order, with no gap where one is not.
	local showSettings = show
	show = function()
		showSettings()
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
	credit:SetText("Made with the help of AI.")

	panel.refresh = ns.Safely.Wrap(show)
	panel.default = ns.Safely.Wrap(function()
		Settings.Reset()
		show()
	end)
	return panel
end

--- Add the panel to the client's list. Called once, at login.
function Options.Install()
	_G.InterfaceOptions_AddCategory(build())
end
