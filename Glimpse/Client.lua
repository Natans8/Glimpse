local addonName, ns = ...

--- The client functions the resolvers use, in one place.
--
-- Resolvers reach the game only through this table, which is what lets them be
-- tested with the table replaced. Each function here is a thin reading of one
-- client call, returning plain values.
local Client = {}
ns.Client = Client

local MISCELLANEOUS, COMPANION_PET, MOUNT = 15, 2, 5

--- The data addon and the global it defines.
local DATA = addonName .. "_Data"

--- A map's name, as the client gives it.
-- @param map a map id
-- @return the name, or nil where the client has no such map
function Client.MapName(map)
	local info = _G.C_Map.GetMapInfo(map)
	if info then
		return info.name
	end
	return nil
end

--- Open the client's world map at a map, as the player would by browsing to it.
-- @param map a map id
function Client.OpenWorldMap(map)
	_G.OpenWorldMap(map)
end

--- Search the client's object table by model name.
-- @param name a model file name
-- @return an array of `{ display, file, name }`; the name is as the client holds it, which may
--   carry a folder in front and a carriage return behind
function Client.SearchObjects(name)
	local epsilon = _G.C_Epsilon
	if not (epsilon and epsilon.GODI_Search and epsilon.GODI_RetrieveSearch) then
		return {}
	end
	local found = {}
	for i = 0, (epsilon.GODI_Search(name) or 0) - 1 do
		local row = epsilon.GODI_RetrieveSearch(i)
		if row then
			found[#found + 1] = { display = row.displayid, file = row.fileid, name = row.name }
		end
	end
	return found
end

--- What kind of thing an item is to a preview. Answers at once, with no server round trip.
-- @param id the item id
-- @return "mount", "pet" or "equipment", or nil where the item has nothing to show, and for
--   equipment the slot it goes in, as the client names it ("INVTYPE_CLOAK")
function Client.ItemKind(id)
	local _, _, _, slot, _, class, subclass = _G.GetItemInfoInstant(id)
	if class == MISCELLANEOUS and subclass == MOUNT then
		return "mount"
	end
	if class == MISCELLANEOUS and subclass == COMPANION_PET then
		return "pet"
	end
	if not _G.C_Item.IsDressableItemByID(id) then
		return nil
	end
	return "equipment", slot
end

--- Call `fn` once the item's record has arrived from the server.
-- @param id the item id
-- @param fn called with no arguments
-- @return a function that cancels the wait
function Client.WhenItemLoads(id, fn)
	return _G.Item:CreateFromItemID(id):ContinueWithCancelOnItemLoad(fn)
end

--- The displays of the mount an item teaches. Valid once the item has loaded.
-- @param id the item id
-- @return an array of creature display ids, empty where the item teaches no mount
function Client.MountDisplaysOfItem(id)
	local mount = _G.C_MountJournal.GetMountFromItem(id)
	local displays = {}
	if not mount then
		return displays
	end
	for _, row in ipairs(_G.C_MountJournal.GetMountAllCreatureDisplayInfoByID(mount) or {}) do
		displays[#displays + 1] = row.creatureDisplayID
	end
	if #displays == 0 then
		displays[1] = _G.C_MountJournal.GetMountInfoExtraByID(mount)
	end
	return displays
end

--- The displays of the pet an item teaches. Valid once the item has loaded.
-- @param id the item id
-- @return an array of creature display ids, empty where the item teaches no pet
function Client.PetDisplaysOfItem(id)
	return { (select(12, _G.C_PetJournal.GetPetInfoByItemID(id))) }
end

-- Every sound started here that has not ended, by its handle, with what to
-- call when it ends by itself where anything was asked. The client has no
-- call that says whether a sound is still playing; it says when one finishes,
-- to whoever asked for that when starting it.
local playing = {}

local function nothing() end

-- A sound outlives the interface that started it: a looping one would play on
-- through a reload with nothing left that could stop it. So when the
-- interface is about to go, every sound started here is stopped.
local sounds = _G.CreateFrame("Frame")
sounds:RegisterEvent("SOUNDKIT_FINISHED")
sounds:RegisterEvent("PLAYER_LOGOUT")
sounds:SetScript(
	"OnEvent",
	ns.Safely.Wrap(function(_, event, handle)
		if event == "PLAYER_LOGOUT" then
			for started in pairs(playing) do
				_G.StopSound(started)
			end
			playing = {}
			return
		end
		local finished = playing[handle]
		playing[handle] = nil
		if finished then
			finished()
		end
	end)
)

--- Start a sound kit.
-- @param kit the sound kit id
-- @param finished called with no arguments if the sound ends by itself; not called if it is
--   stopped
-- @return a handle for stopping it, or nil where the client would not play it
function Client.PlaySound(kit, finished)
	local willPlay, handle = _G.PlaySound(kit, "Master", false, true)
	if not willPlay then
		return nil
	end
	playing[handle] = finished or nothing
	return handle
end

--- Stop a sound started by `PlaySound`.
-- @param handle the handle it returned
function Client.StopSound(handle)
	playing[handle] = nil
	_G.StopSound(handle)
end

--- Called once, where the data addon cannot be used, with why: the reason the
-- client gives for not loading it ("MISSING", "DISABLED" and the like), or
-- "FORMAT" where it was made for another version of this addon. Whoever speaks
-- to the player replaces this.
-- @param reason why
function Client.Unavailable(_) end

local tried, data = false, nil

--- The large tables, loading their addon on first use and trying once.
-- @return the tables, or nil where the data addon cannot be used
function Client.Data()
	if tried then
		return data
	end
	tried = true
	local loaded, reason = _G.LoadAddOn(DATA)
	local found = _G[DATA]
	if not loaded then
		Client.Unavailable(reason)
	elseif not (found and found.format == ns.Data.Format) then
		Client.Unavailable("FORMAT")
	else
		data = found
	end
	return data
end
