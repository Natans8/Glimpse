local addonName, ns = ...

--- Starting the addon: what happens once, when the player logs in.
--
-- Also where the addon speaks to the player: a fault, said once for each place
-- it happens and kept in the saved faults so a report can carry it; data
-- that cannot be used.
local Safely = ns.Safely

local function say(text)
	_G.print(ns.Chat.COLOUR .. addonName .. ":|r " .. text)
end

Safely.Announce = function(place, line)
	if type(_G.GlimpseFaults) ~= "table" then
		_G.GlimpseFaults = {}
	end
	_G.GlimpseFaults[place] = line
	say("something went wrong and was noted. " .. line)
end

--- What is wrong with the data addon, by the reason the client or the format gives.
local UNAVAILABLE = {
	MISSING = "is missing",
	DISABLED = "is turned off in the addon list",
	FORMAT = "is from another version of " .. addonName,
}

-- Said once, the first time the data is wanted and cannot be used, with what is
-- missing because of it and how to put it right.
ns.Client.Unavailable = function(reason)
	local folder = addonName .. "_Data"
	local mend = "Install the " .. addonName .. " and " .. folder .. " folders from one download."
	if reason == "DISABLED" then
		mend = "Turn it on and reload."
	end
	say(
		folder
			.. " "
			.. (UNAVAILABLE[reason] or ("could not be loaded (" .. tostring(reason) .. ")"))
			.. ", so objects and creatures with several displays have no preview. "
			.. mend
	)
end

local frame = _G.CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript(
	"OnEvent",
	Safely.Wrap(function()
		ns.Chat.Install()
		ns.Options.Install()
	end)
)
