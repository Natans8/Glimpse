local _, ns = ...

--- A view: this addon's drawing of a thing inside a frame of another addon's, with
-- nothing of this addon's own around it, no panel, name, caption or hint, which the
-- other addon draws where it wants them. It draws on a stage, as the hover frame and
-- the window do, so it draws what they draw and hands the client's model loader only
-- what they hand it. A thing whose kind another addon previews is lent to that addon
-- the way the hover frame lends it. A view takes no input and stands still, and does
-- nothing while its frame is hidden.
local Async, Stage, Providers, Kinds = ns.Async, ns.Stage, ns.Providers, ns.Kinds

local View = {}
View.__index = View
ns.View = View

-- How many views have been made. Each asks in a slot of its own, so one never abandons
-- another's question.
local made = 0

--- A view filling a frame.
-- @param frame the frame to fill
-- @return the view
function View.New(frame)
	made = made + 1
	local self = setmetatable({ slot = "view " .. made, looks = {} }, View)
	-- The inside a kind another addon previews is lent, above the stage.
	self.inside = _G.CreateFrame("Frame", nil, frame)
	self.inside:SetAllPoints()
	self.inside:Hide()
	self.stage = Stage.New(frame)
	return self
end

--- Draw nothing, take back what was lent, and abandon a question still out.
function View:Clear()
	Async.Cancel(self.slot)
	self.stage:Clear()
	if self.lent then
		Providers.Hide(self.lent, self.inside)
		self.lent = nil
	end
	self.inside:Hide()
	self.looks = {}
end

-- Tell the other addon how many looks the thing has; a fault in its function is its own.
local function tell(done, count)
	if done then
		pcall(done, count)
	end
end

--- Draw a thing as the hover frame would draw it, still.
-- @param read the read to draw
-- @param index which of its looks: a creature's displays, a set's models; the first
--   where it has fewer
-- @param done optional; called once with how many looks the thing has, 0 where there is
--   nothing to show, once that is known: at once where it already is
-- @return true where the thing is of a kind that is drawn and the player shows
function View:Show(read, index, done)
	self:Clear()
	local drawer = ns.Chat.Drawer(read)
	if drawer == "provider" then
		self.inside:Show()
		self.lent = read.kind
		local filled =
			Providers.Show(read.kind, self.inside, read.id, Providers.Context("hover", read))
		if filled then
			self.looks = { read }
		else
			self.inside:Hide()
		end
		tell(done, #self.looks)
		return true
	end
	if not (drawer == "own" and Kinds.Draws(read)) then
		tell(done, 0)
		return false
	end
	Async.Ask(self.slot, read, function(subject)
		if subject then
			self.looks = subject.looks
		end
		local look = self.looks[index] or self.looks[1]
		if look then
			self.stage:Show(look, 0)
		end
		tell(done, #self.looks)
	end)
	return true
end

--- How many looks the thing shown has: 0 where there is none, or none yet.
-- @return the count
function View:Looks()
	return #self.looks
end
