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

-- The word on each sound's button.
local function labels(list)
	local found = {}
	for i, sound in ipairs(list) do
		found[i] = sound.label
	end
	return found
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
			return labels(soundsOf(read))
		end,
		resolve = function(read, done)
			local subject = Subject.New(read)
			subject.sounds = soundsOf(read)
			done(subject)
		end,
	})
end

--- The sounds a phase sets on an area or a WMO, in the order its lists print them,
-- each with the word on its button and the table it is listed in.
local OVERRIDDEN = {
	{ label = "Ambience", data = "Ambience" },
	{ label = "Music", data = "Music" },
	{ label = "Intro", data = "Intro" },
}

-- A sound for each the line names and the tables list: its day kit, or its night
-- kit where it has no day kit.
local function overridden(read)
	local found = {}
	for i, of in ipairs(OVERRIDDEN) do
		local row = ns.Data[of.data][read.ids[i]]
		if row then
			local kit = row.day
			if kit == 0 then
				kit = row.night
			end
			found[#found + 1] = { label = of.label, kit = kit }
		end
	end
	return found
end

-- An area or a WMO a phase has overridden: a button to play each sound it now has.
Kinds.Add("areasounds", {
	word = "Sound",
	code = "r",
	draws = false,
	shows = function(read)
		return #overridden(read) > 0
	end,
	buttons = function(read)
		return labels(overridden(read))
	end,
	resolve = function(read, done)
		local subject = Subject.New(read)
		subject.sounds = overridden(read)
		done(subject)
	end,
})
