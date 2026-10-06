local _, ns = ...

--- The kinds only another addon previews: this addon reads their lines and shows
-- nothing of its own for them, so a line of one gains a button only while an
-- addon offers it through `Glimpse.Provide`, and that addon fills the inside of
-- this addon's hover frame and window with whatever it shows.
--
-- A spell, for one, is drawn whole only by the game in the world; showing one
-- off the world takes data and playing that belong to an addon such as Epsilook.
local Kinds = ns.Kinds

--- Each kind: what it is called, and its letter in a link.
local OFFERED = {
	{ "spell", "Spell", "s" },
	{ "map", "Map", "p" },
	{ "teleport", "Teleport", "t" },
	{ "skill", "Skill", "k" },
	{ "title", "Title", "h" },
	{ "faction", "Faction", "f" },
	{ "blueprint", "Blueprint", "b" },
	{ "wmo", "WMO", "w" },
	{ "wmoarea", "WMO area", "g" },
	{ "texture", "Texture", "x" },
}

for _, kind in ipairs(OFFERED) do
	Kinds.Add(kind[1], { word = kind[2], code = kind[3], provided = true })
end
