local _, ns = ...

--- The window: what a click on a preview button opens.
--
-- The hover frame shows a thing; the window is where it is turned over. It
-- wears the addon's own dress. Each control lives where its meaning puts it:
--
--   the header     what the thing is: its kind and id, and its name in full
--   the chooser    what is shown of it: several displays as a pager, a
--                  button that draws a creature again
--   the picture    the look itself, turned by dragging sideways, tilted by
--                  dragging up and down where it is a model rather than the
--                  player's body, and brought nearer by the wheel
--   over the picture, at its corners: putting the view back, weapons away or
--   in hand. These show only while the pointer is over the
--   picture, as the dressing room's do, so the look is otherwise uncovered.
--
-- A control is shown only where it applies. Clicking the button of a subject
-- a window already shows closes that window, and Escape closes them all.
--
-- A kind another addon previews gets the window's inside, empty, below the close
-- button: the window keeps its border, closing, moving and sizing, and the rest
-- is the other addon's. The window stays open only where that addon fills it.
--
-- One window serves every click unless the player has asked for a window of
-- each: then a click opens another, a little below and right of the last.
local Async, Stage, Subject, Settings = ns.Async, ns.Stage, ns.Subject, ns.Settings
local Presentations, Kinds, Tools, Providers = ns.Presentations, ns.Kinds, ns.Tools, ns.Providers

local Window = {}
ns.Window = Window

--- The windows' global names, which are what let Escape close them: the first is
-- this, and those after it carry their number.
local NAME = "GlimpseWindow"

local WIDTH, HEIGHT = 380, 480
local NARROWEST, SHORTEST, LARGEST = 300, 320, 1000
local MARGIN = 8

--- How far down a lent inside starts, clear of the close button.
local TOP = 30

--- How far above the window's own level its close button and grip stand, so
-- whatever fills the window stays under them.
local CHROME = 20

--- How far below and right of the last window another one opens.
local CASCADE = 24

--- How far a drag of one pixel turns the look, in radians.
local TURN_PER_PIXEL = 0.012

local windows = {} -- every window made so far; only the first keeps its place between sessions

-- The player has finished moving or sizing a window. The first keeps where it now is.
local function settle(self)
	local frame = self.frame
	frame:StopMovingOrSizing()
	if self ~= windows[1] then
		return
	end
	Settings.Set("windowPlace", {
		left = frame:GetLeft(),
		top = frame:GetTop(),
		width = frame:GetWidth(),
		height = frame:GetHeight(),
	})
end

-- Stand the first window where the player last left it, or in the middle the first
-- time. A place saved by hand that is not four numbers is not believed.
local function restore(frame)
	local place = Settings.Get("windowPlace")
	for _, key in ipairs({ "left", "top", "width", "height" }) do
		if type(place[key]) ~= "number" then
			frame:SetSize(WIDTH, HEIGHT)
			frame:SetPoint("CENTER")
			return
		end
	end
	frame:SetSize(
		math.max(NARROWEST, math.min(LARGEST, place.width)),
		math.max(SHORTEST, math.min(LARGEST, place.height))
	)
	frame:SetPoint("TOPLEFT", _G.UIParent, "BOTTOMLEFT", place.left, place.top)
end

-- The picture's controls are seen only while the pointer is over the picture.
local function reveal(self)
	local alpha = 0
	if self.picture:IsMouseOver() then
		alpha = 1
	end
	for _, control in ipairs(self.overlay) do
		control:SetAlpha(alpha)
	end
end

local function draw(self)
	local subject, index = self.shown.subject, self.shown.index
	local look = subject.looks[index]
	local presentation = Presentations.Of(look)
	local several = #subject.looks > 1

	-- The chooser: a pager where the looks are several of a kind, and a
	-- creature's "another".
	self.pager:SetShown(several)
	self.previous:SetShown(several)
	self.following:SetShown(several)
	self.pager:SetText(Presentations.Place(look, index, #subject.looks))
	self.another:SetShown(presentation.varies == true)
	if several or presentation.varies then
		self.chooser:SetHeight(24)
	else
		self.chooser:SetHeight(1)
	end

	self.reset:Show()
	self.sheathe:SetShown(presentation.body == true)
	self.stage:Show(look)
end

local function choose(self, index)
	self.shown.index = index
	draw(self)
end

local function step(self, by)
	choose(self, (self.shown.index - 1 + by) % #self.shown.subject.looks + 1)
end

-- A frame over the picture that takes the pointer: a drag sideways turns the
-- look, a drag up brings its bottom into view, and the wheel brings it nearer
-- or sends it back. It follows the pointer only while a button is held.
local function hands(self, holder)
	local catcher = _G.CreateFrame("Frame", nil, holder)
	catcher:SetAllPoints()
	catcher:SetFrameLevel(holder:GetFrameLevel() + 10)
	catcher:EnableMouse(true)
	catcher:EnableMouseWheel(true)
	local fromX, fromY
	local follow = ns.Safely.Wrap(function()
		local x, y = _G.GetCursorPosition()
		if x ~= fromX or y ~= fromY then
			self.stage:Turn((x - fromX) * TURN_PER_PIXEL)
			self.stage:Tilt((y - fromY) * TURN_PER_PIXEL)
			fromX, fromY = x, y
		end
	end)
	local release = ns.Safely.Wrap(function()
		catcher:SetScript("OnUpdate", nil)
	end)
	catcher:SetScript(
		"OnMouseDown",
		ns.Safely.Wrap(function()
			fromX, fromY = _G.GetCursorPosition()
			catcher:SetScript("OnUpdate", follow)
		end)
	)
	catcher:SetScript("OnMouseUp", release)
	catcher:SetScript("OnHide", release)
	catcher:SetScript(
		"OnMouseWheel",
		ns.Safely.Wrap(function(_, direction)
			self.stage:Zoom(direction)
		end)
	)
	return catcher
end

-- The corner the window is sized by.
local function grip(self, parent)
	local frame = self.frame
	local corner = _G.CreateFrame("Button", nil, parent)
	corner:SetSize(14, 14)
	corner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
	local lines = corner:CreateTexture(nil, "ARTWORK")
	lines:SetAllPoints()
	lines:SetAlpha(0.5)
	Tools.Draw(lines, "grip")
	corner:SetScript(
		"OnMouseDown",
		ns.Safely.Wrap(function()
			frame:StartSizing("BOTTOMRIGHT")
		end)
	)
	corner:SetScript(
		"OnMouseUp",
		ns.Safely.Wrap(function()
			settle(self)
		end)
	)
end

local function header(self)
	local frame = self.frame
	self.title = self.own:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	self.title:SetPoint("TOPLEFT", MARGIN + 2, -MARGIN)

	local close = Tools.Icon(self.chrome, "close", "Close", nil, function()
		frame:Hide()
	end)
	close:SetPoint("TOPRIGHT", -4, -4)

	self.name = self.own:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	self.name:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -4)
	self.name:SetPoint("RIGHT", frame, "RIGHT", -MARGIN - 24, 0)
	self.name:SetJustifyH("LEFT")
	self.name:SetMaxLines(2)
end

local function choosers(self)
	local chooser = _G.CreateFrame("Frame", nil, self.own)
	chooser:SetPoint("TOPLEFT", self.name, "BOTTOMLEFT", 0, -6)
	chooser:SetPoint("RIGHT", self.name, "RIGHT")
	chooser:SetHeight(24)
	self.chooser = chooser

	self.previous = Tools.Icon(chooser, "previous", "Previous", nil, function()
		step(self, -1)
	end)
	self.previous:SetPoint("LEFT")
	self.pager = chooser:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.pager:SetPoint("LEFT", self.previous, "RIGHT", 6, 0)
	self.following = Tools.Icon(chooser, "following", "Next", nil, function()
		step(self, 1)
	end)
	self.following:SetPoint("LEFT", self.pager, "RIGHT", 6, 0)

	self.another = Tools.Button(chooser, "Another display", function()
		draw(self)
	end)
	self.another:SetPoint("LEFT")
	Tools.Hint(
		self.another,
		"Another display",
		"A creature may have several displays. This draws it again, as the game does each time one spawns."
	)
end

-- The controls over the picture, each at a corner of it.
local function corners(self, over)
	self.reset = Tools.Icon(over, "reset", "Reset the view", nil, function()
		self.stage:Reset()
	end)
	self.reset:SetPoint("TOPLEFT", 6, -6)

	self.sheathe = Tools.Icon(
		over,
		"weapon",
		"Weapons",
		"Put them away, or take them in hand.",
		function()
			self.stage:Sheathe()
		end
	)
	self.sheathe:SetPoint("BOTTOMLEFT", 6, 6)

	self.overlay = { self.reset, self.sheathe }

	-- The pointer is still over the picture while it is over one of its controls.
	local seen = ns.Safely.Wrap(function()
		reveal(self)
	end)
	over:HookScript("OnEnter", seen)
	over:HookScript("OnLeave", seen)
	for _, control in ipairs(self.overlay) do
		control:HookScript("OnEnter", seen)
		control:HookScript("OnLeave", seen)
	end
	reveal(self)
end

-- Take down whatever the window shows, its own look or a lent inside.
local function empty(self)
	self.stage:Clear()
	if self.shown and self.shown.lent then
		Providers.Hide(self.shown.lent, self.inside)
		self.shown.lent = nil
	end
	self.inside:Hide()
end

-- Lend the window's inside to the addon that previews the read's kind; the
-- window closes again where that addon does not fill it.
local function lend(self, read)
	self.own:Hide()
	self.inside:Show()
	self.shown.lent = read.kind
	if not Providers.Show(read.kind, self.inside, read.id, { place = "window" }) then
		self.frame:Hide()
	end
end

-- The window's three layers: what it shows of its own, the inside it lends in
-- place of that, and its close button and grip over both.
local function layers(self)
	local frame = self.frame
	self.own = _G.CreateFrame("Frame", nil, frame)
	self.own:SetAllPoints()
	self.inside = _G.CreateFrame("Frame", nil, frame)
	self.inside:SetPoint("TOPLEFT", MARGIN, -TOP)
	self.inside:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
	self.inside:Hide()
	self.chrome = _G.CreateFrame("Frame", nil, frame)
	self.chrome:SetAllPoints()
	self.chrome:SetFrameLevel(frame:GetFrameLevel() + CHROME)
end

-- A window, unseen. The first stands where the player last left it; another stands
-- below and right of the window made before it, the size of the first.
local function new()
	local self = {}
	local index = #windows + 1
	local name = NAME
	if index > 1 then
		name = NAME .. index
	end
	self.slot = "window" .. index

	local frame = _G.CreateFrame("Frame", name, _G.UIParent)
	self.frame = frame
	Tools.Panel(frame)
	if index == 1 then
		restore(frame)
	else
		local last, first = windows[index - 1].frame, windows[1].frame
		frame:SetSize(first:GetWidth(), first:GetHeight())
		frame:SetPoint("TOPLEFT", last, "TOPLEFT", CASCADE, -CASCADE)
	end
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetMinResize(NARROWEST, SHORTEST)
	frame:SetMaxResize(LARGEST, LARGEST)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript(
		"OnDragStop",
		ns.Safely.Wrap(function()
			settle(self)
		end)
	)
	-- Hidden before its hide handler is set: the handler clears a stage not built yet.
	frame:Hide()
	frame:SetScript(
		"OnHide",
		ns.Safely.Wrap(function()
			frame:StopMovingOrSizing()
			Async.Cancel(self.slot)
			empty(self)
			self.shown = nil
		end)
	)
	table.insert(_G.UISpecialFrames, name)

	layers(self)
	header(self)
	choosers(self)

	local holder = _G.CreateFrame("Frame", nil, self.own)
	holder:SetPoint("TOPLEFT", self.chooser, "BOTTOMLEFT", -2, -6)
	holder:SetPoint("BOTTOMRIGHT", -MARGIN, MARGIN)
	Tools.Fill(holder, Tools.WELL)
	self.stage = Stage.New(holder)

	-- The controls stand on the frame that takes the pointer, so they are over it.
	self.picture = hands(self, holder)
	self.status = self.picture:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	self.status:SetPoint("CENTER")
	corners(self, self.picture)
	grip(self, self.chrome)

	windows[index] = self
	return self
end

-- Nothing is chosen or switched while there is no look to act on.
local function bare(self)
	for _, control in ipairs({ self.pager, self.previous, self.following, self.another }) do
		control:Hide()
	end
	for _, control in ipairs(self.overlay) do
		control:Hide()
	end
	self.chooser:SetHeight(1)
end

-- Show a read in a window, replacing whatever it showed; a lent read is shown by
-- the addon that offers its kind.
local function open(self, read, lent)
	Async.Cancel(self.slot)
	empty(self)
	self.shown = { key = Subject.Key(read) }
	self.frame:Show()
	self.frame:Raise()
	if lent then
		lend(self, read)
		return
	end
	self.own:Show()
	self.title:SetText(Kinds.Word(read) .. " " .. read.id)
	self.name:SetText(read.name)
	self.status:SetText("")
	bare(self)
	Async.Ask(self.slot, read, function(subject)
		if not (subject and subject.looks[1]) then
			self.status:SetText(Presentations.NOTHING)
			return
		end
		self.shown.subject, self.shown.index = subject, 1
		draw(self)
	end)
end

-- The window a click opens: the first, unless the player wants a window of each;
-- then one that shows nothing, made where every one is in use.
local function free()
	if not Settings.Get("manyWindows") then
		return windows[1] or new()
	end
	for _, window in ipairs(windows) do
		if not window.frame:IsShown() then
			return window
		end
	end
	return new()
end

--- Show a read in a window, or close the window that already shows that read.
-- @param read the read to show
-- @param lent true where the addon that offers the read's kind previews it
function Window.Toggle(read, lent)
	local key = Subject.Key(read)
	for _, window in ipairs(windows) do
		if window.shown and window.shown.key == key and window.frame:IsShown() then
			window.frame:Hide()
			return
		end
	end
	open(free(), read, lent)
end
