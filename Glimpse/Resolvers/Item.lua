local _, ns = ...

--- Items: equipment, and the mount or pet an item teaches.
--
-- What an item is comes from the client at once. Which mount or pet it
-- teaches is known only after the item's record has arrived, so those wait
-- for it. An item that is none of these has nothing to show.
local Subject, Kinds = ns.Subject, ns.Kinds

--- Which client function lists the displays an item of each kind teaches.
local TAUGHT = { mount = "MountDisplaysOfItem", pet = "PetDisplaysOfItem" }

Kinds.Add("item", {
	word = "Item",
	code = "i",
	shows = function(read)
		return ns.Client.ItemKind(read.id) ~= nil
	end,
	resolve = function(read, done)
		local client = ns.Client
		local kind, slot = client.ItemKind(read.id)
		local subject = Subject.New(read)
		if kind == "equipment" then
			-- Worn on the player's body, which is the one thing here whose size is known.
			Subject.Look(subject, "tryon", read.id).slot = slot
			done(subject)
			return nil
		end
		return client.WhenItemLoads(read.id, function()
			local data = client.Data()
			for _, display in ipairs(client[TAUGHT[kind]](read.id)) do
				Subject.Display(subject, display, data)
			end
			Subject.Answer(subject, done)
		end)
	end,
})
