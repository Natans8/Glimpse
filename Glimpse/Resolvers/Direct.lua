local _, ns = ...

--- The kinds a line's own id is enough to draw: a creature, a creature
-- display, a weapon enchant, and an emote through its animation.
local Subject, Kinds, Packed = ns.Subject, ns.Kinds, ns.Packed

-- A stock creature that spawns with one of several displays has them all as its
-- looks. Any other is drawn from its entry, the client choosing its display as
-- it does when one spawns; drawing it again may show another.
Kinds.Add("creature", {
	word = "Creature",
	code = "c",
	resolve = function(read, done)
		local subject = Subject.New(read)
		local data = ns.Client.Data()
		local displays = data and Packed.Find(data.creatures, read.id) or {}
		if #displays > 1 then
			for _, row in ipairs(displays) do
				Subject.Display(subject, row[1], data)
			end
		else
			Subject.Look(subject, "creature", read.id)
		end
		done(subject)
	end,
})

Kinds.Add("display", {
	word = "Display",
	code = "v",
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
	resolve = Subject.Direct("enchant"),
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
