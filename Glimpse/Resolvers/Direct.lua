local _, ns = ...

--- The kinds a line's own id is enough to draw: a creature, a creature
-- display, a weapon enchant, and an emote through its animation.
local Subject, Kinds, Packed = ns.Subject, ns.Kinds, ns.Packed

-- Whether a display draws the invisible stalker, which shows nothing. An NPC
-- dressed in an outfit stands in one as far as any client can see.
local function unseen(data, display)
	return data ~= nil and Packed.First(data.stalkers, display) ~= nil
end

-- The displays a stock creature spawns with that show something, and how many it
-- spawns with in all.
local function shownDisplays(data, entry)
	local all = data and Packed.Find(data.creatures, entry) or {}
	local shown = {}
	for _, row in ipairs(all) do
		if not unseen(data, row[1]) then
			shown[#shown + 1] = row[1]
		end
	end
	return shown, #all
end

-- A spawned creature whose line says which display it stands in is drawn in
-- that one, and has nothing to show where that is the stalker: it stands in an
-- outfit, whatever else its template holds. A stock creature that spawns with
-- several displays has the ones that show something as its looks, and one that
-- only ever spawns as the stalker has none. Any other is drawn from its entry,
-- the client choosing its display as it does when one spawns; drawing it again
-- may show another.
Kinds.Add("creature", {
	word = "Creature",
	code = "c",
	shows = function(read)
		local data = ns.Client.Data()
		if read.ids then
			return not unseen(data, read.ids[1])
		end
		return not (data and Packed.First(data.unseenCreatures, read.id))
	end,
	resolve = function(read, done)
		local subject = Subject.New(read)
		local data = ns.Client.Data()
		local shown, all = shownDisplays(data, read.id)
		if read.ids then
			if not unseen(data, read.ids[1]) then
				Subject.Display(subject, read.ids[1], data)
			end
		elseif #shown > 1 or #shown < all then
			for _, display in ipairs(shown) do
				Subject.Display(subject, display, data)
			end
		else
			Subject.Look(subject, "creature", read.id)
		end
		Subject.Answer(subject, done)
	end,
})

Kinds.Add("display", {
	word = "Display",
	code = "v",
	shows = function(read)
		return not unseen(ns.Client.Data(), read.id)
	end,
	resolve = function(read, done)
		local subject = Subject.New(read)
		Subject.Display(subject, read.id, ns.Client.Data())
		done(subject)
	end,
})

Kinds.Add("enchant", {
	word = "Enchant",
	code = "e",
	-- Only a stock enchant known to draw nothing is denied; an id the client's
	-- table lacks is one of the server's own, which may well draw.
	shows = function(read)
		return not ns.Data.EnchantsWithoutVisual[read.id]
	end,
	resolve = function(read, done)
		local subject = Subject.New(read)
		Subject.Look(subject, "enchant", read.id)
		done(subject)
	end,
})

-- The animation an emote plays. The client's own emotes and the exceptions are
-- in the table. The rest follow the server's rule, an emote being a base plus
-- its animation, so an emote added since the data was made still has one.
local function animationOf(emote)
	local listed = ns.Data.EmoteAnimations[emote]
	if listed then
		return listed
	end
	for _, base in ipairs(ns.Data.EmoteBases) do
		if emote >= base then
			local animation = emote - base
			-- The client's animations are numbered from nought with no gaps.
			if animation < ns.Data.AnimationCount then
				return animation
			end
			return nil
		end
	end
	return nil
end

Kinds.Add("emote", {
	word = "Emote",
	code = "m",
	shows = function(read)
		return animationOf(read.id) ~= nil
	end,
	resolve = function(read, done)
		local subject = Subject.New(read)
		-- A flying animation is played as a body on the ground plays it.
		local animation = animationOf(read.id)
		animation = ns.Data.GroundedAnimations[animation] or animation
		local look = Subject.Look(subject, "animation", animation)
		look.wields = ns.Data.WieldingAnimations[animation] == true
		done(subject)
	end,
})
