local _, ns = ...

--- Zone music, intro music and ambience: sound kits to play.
--
-- Each entry has a day kit and a night kit. One button is offered where they
-- are the same or only one exists, two where they differ. The line gains a
-- button for each, so a sound is chosen and played from the line itself.
local Subject, Kinds = ns.Subject, ns.Kinds

local function sounds(day, night)
	if day == 0 then
		day, night = night, 0
	end
	if night == 0 or night == day then
		return { { label = Kinds.PLAY, kit = day } }
	end
	return { { label = "Day", kit = day }, { label = "Night", kit = night } }
end

--- Each kind of sound: the shipped table that lists it, and its letter in a link.
local KINDS = {
	music = { data = "Music", code = "u" },
	intro = { data = "Intro", code = "n" },
	ambience = { data = "Ambience", code = "a" },
}

-- Lines reads a sound line only where its id is in the kind's table, so the
-- row is always there.
for kind, of in pairs(KINDS) do
	local function soundsOf(read)
		local row = ns.Data[of.data][read.id]
		return sounds(row.day, row.night)
	end
	Kinds.Add(kind, {
		word = "Sound",
		code = of.code,
		draws = false,
		buttons = function(read)
			local labels = {}
			for i, sound in ipairs(soundsOf(read)) do
				labels[i] = sound.label
			end
			return labels
		end,
		resolve = function(read, done)
			local subject = Subject.New(read)
			subject.sounds = soundsOf(read)
			done(subject)
		end,
	})
end
