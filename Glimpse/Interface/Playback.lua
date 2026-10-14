local _, ns = ...

--- Playing a subject's sounds: one at a time on each channel, so music and an
-- ambience play together, as a zone plays them.
--
-- A sound's button in chat cannot change once the line is printed, so the
-- same button starts the sound and stops it: asking for the sound that is
-- already playing stops it, and asking for another on its channel stops the
-- one before. A right-click on any sound's button stops every sound started
-- here. Resting the pointer on the button says what a click will do.
local Playback = {}
ns.Playback = Playback

local playing = {} -- channel -> { key, handle }, from when a sound is started here until it stops or ends
local hinted -- { subject, index, owner } while the pointer rests on a sound's button

local function keyOf(subject, index)
	return ns.Subject.Key(subject) .. ":" .. index
end

-- Whether one of a subject's sounds is the one playing on its channel.
local function isPlaying(subject, index)
	local now = playing[subject.sounds[index].channel]
	return now ~= nil and now.key == keyOf(subject, index)
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
	if isPlaying(subject, index) then
		tooltip:AddLine("Click to stop")
	else
		tooltip:AddLine("Click to play")
	end
	if next(playing) then
		tooltip:AddLine("Right-click to stop every sound")
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

-- Stop the sound started here on a channel, if one is playing.
local function stop(channel)
	local now = playing[channel]
	if now then
		ns.Client.StopSound(now.handle)
		playing[channel] = nil
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
	local channel, same = sound.channel, isPlaying(subject, index)
	stop(channel)
	if not same then
		local started = { key = keyOf(subject, index) }
		started.handle = ns.Client.PlaySound(sound.kit, function()
			-- The sound ended by itself, so its button starts it again.
			if playing[channel] == started then
				playing[channel] = nil
				hint()
			end
		end)
		if started.handle then
			playing[channel] = started
		end
	end
	hint()
end

--- Stop every sound started here.
function Playback.StopAll()
	for channel in pairs(playing) do
		stop(channel)
	end
	hint()
end
