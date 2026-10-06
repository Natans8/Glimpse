local _, ns = ...

--- Playing a subject's sounds, one at a time.
--
-- A sound's button in chat cannot change once the line is printed, so the
-- same button starts the sound and stops it: asking for the sound that is
-- already playing stops it, and asking for another stops the one before.
-- Resting the pointer on the button says which of the two a click will do.
local Playback = {}
ns.Playback = Playback

local playing -- { key, handle } from when a sound is started here until it stops or ends
local hinted -- { subject, index, owner } while the pointer rests on a sound's button

local function keyOf(subject, index)
	return ns.Subject.Key(subject) .. ":" .. index
end

-- Draw the tooltip of the button the pointer rests on, as things now stand.
local function hint()
	if not hinted then
		return
	end
	local subject, index = hinted.subject, hinted.index
	local tooltip = _G.GameTooltip
	tooltip:SetOwner(hinted.owner, "ANCHOR_CURSOR_RIGHT")
	tooltip:SetText(subject.name, 1, 1, 1)
	if #subject.sounds > 1 then
		tooltip:AddLine(subject.sounds[index].label, 1, 1, 1)
	end
	if playing and playing.key == keyOf(subject, index) then
		tooltip:AddLine("Click to stop")
	else
		tooltip:AddLine("Click to play")
	end
	tooltip:Show()
end

--- Say, in a tooltip, what a click on a sound's button will do.
-- @param subject a subject with `sounds`
-- @param index which of its sounds, counted from one
-- @param owner the frame the button is in
function Playback.Hint(subject, index, owner)
	if subject.sounds and subject.sounds[index] then
		hinted = { subject = subject, index = index, owner = owner }
		hint()
	end
end

--- Take the tooltip down, where it is up.
function Playback.Unhint()
	if hinted then
		hinted = nil
		_G.GameTooltip:Hide()
	end
end

-- Stop the sound started here, if one is playing.
local function stop()
	if playing then
		ns.Client.StopSound(playing.handle)
		playing = nil
	end
end

--- Play one of a subject's sounds, or stop it where it is the one playing.
-- @param subject a subject with `sounds`
-- @param index which of its sounds, counted from one
function Playback.Toggle(subject, index)
	local sound = subject.sounds and subject.sounds[index]
	if not sound then
		return
	end
	local key = keyOf(subject, index)
	local same = playing ~= nil and playing.key == key
	stop()
	if not same then
		local started = { key = key }
		started.handle = ns.Client.PlaySound(sound.kit, function()
			-- The sound ended by itself, so its button starts it again.
			if playing == started then
				playing = nil
				hint()
			end
		end)
		if started.handle then
			playing = started
		end
	end
	hint()
end
