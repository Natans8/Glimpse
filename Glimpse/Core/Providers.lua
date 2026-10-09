local _, ns = ...

--- Kinds another addon previews, in frames this addon lends it.
--
-- An addon offers itself through `Glimpse.Provide(kind, provider)`, for any kind
-- that is drawn, this addon's own or one it leaves to others: "spell", "object",
-- "creature" and the rest, never a sound or an area, which draw nothing. It then
-- previews that kind in place of this addon, while the player has not turned the
-- kind off. A provider is a table, its functions called as plain functions:
--
--   name   optional; the addon's name, which the settings show the player
--   Shows  optional; `Shows(id, context)`: answer false where there is nothing to
--          show for the thing, and its line gains no button. It is asked as the
--          line is read, so it answers at once; `context` is as `Show` has it,
--          with `context.place` "line". Anything else, or no `Shows`, means there is.
--   Show   `Show(frame, id, context)`: fill `frame`, an empty frame filling the
--          inside of the hover frame or the window, with whatever shows the thing.
--          `context.place` is "hover", which takes no input, or "window", and the
--          rest of `context` is everything the line said about the thing: its
--          `kind`, its `id` again, and its `name` where the line printed one,
--          since an id alone may name nothing the client can look up. Answer
--          true where the frame was filled; anything else means it was not,
--          whether the thing was shown elsewhere or there was nothing to show, and
--          this addon then shows nothing of its own. A provider may answer a few
--          words after the true, said of the thing after its kind on the line
--          under its name: "seen only from inside".
--   Hide   `Hide(frame)`: empty a frame it filled.
--
-- This addon keeps the frame around the inside: the border, closing, moving and
-- sizing, and the thing's name and kind over it, as every kind has. What is inside
-- is the provider's alone, so the provider may change anything in it without this
-- addon changing. A provider changes far more often
-- than this addon is reinstalled, so nothing else of it is read, its functions
-- are called protected, and the first fault withdraws it for the session without
-- a word: the fault is its own.
local Providers = {}
ns.Providers = Providers

local offered = {} -- kind -> provider

--- Offer previews of a kind, replacing an earlier offer; nil withdraws it.
-- @param kind a kind that is drawn: "spell", "object"
-- @param provider a table with `Show` and `Hide` functions, or nil
-- @return true where the offer was taken
function Providers.Provide(kind, provider)
	if not ns.Kinds.Providable(kind) then
		return false
	end
	if provider ~= nil then
		if type(provider) ~= "table" then
			return false
		end
		if type(provider.Show) ~= "function" or type(provider.Hide) ~= "function" then
			return false
		end
	end
	offered[kind] = provider
	return true
end

--- What a provider is told with a thing: where it is shown, and everything the
-- line said about it. A provider may keep the table; it is its own.
-- @param place "line", "hover" or "window"
-- @param read the read the thing came from
-- @return the context
function Providers.Context(place, read)
	local context = { place = place }
	for key, value in pairs(read) do
		context[key] = value
	end
	return context
end

--- Whether another addon previews a kind.
-- @param kind a kind
-- @return true while a provider for it is offered and has not faulted
function Providers.Has(kind)
	return offered[kind] ~= nil
end

--- The name of the addon that previews a kind, as it gave it.
-- @param kind a kind
-- @return the name, or nil where none is offered or it gave none that is text
function Providers.Name(kind)
	local provider = offered[kind]
	if provider and type(provider.name) == "string" and provider.name ~= "" then
		return provider.name
	end
	return nil
end

-- Call one of a kind's provider's functions, protected, for its first two answers. A
-- fault withdraws the provider.
local function call(kind, name, ...)
	local provider = offered[kind]
	if not provider then
		return nil
	end
	local ok, answer, more = pcall(provider[name], ...)
	if not ok then
		offered[kind] = nil
		return nil
	end
	return answer, more
end

--- Whether the provider of a read's kind has anything to show for it. A provider
-- that does not say is taken to have.
-- @param read a read of a kind another addon previews
-- @return false where none is offered, it faults, or it answers false
function Providers.Shows(read)
	local provider = offered[read.kind]
	if not provider then
		return false
	end
	if type(provider.Shows) ~= "function" then
		return true
	end
	local answer = call(read.kind, "Shows", read.id, Providers.Context("line", read))
	return offered[read.kind] ~= nil and answer ~= false
end

--- Have the provider of a kind fill a frame with a thing.
-- @param kind the thing's kind
-- @param frame the frame to fill, shown and empty
-- @param id the thing's id
-- @param context `{ place = "hover" }` or `{ place = "window" }`
-- @return true where the provider filled the frame, then the words it said of the
--   thing where it said any that are text
function Providers.Show(kind, frame, id, context)
	local filled, words = call(kind, "Show", frame, id, context)
	if filled ~= true then
		return false
	end
	if type(words) ~= "string" or words == "" then
		return true
	end
	return true, words
end

--- Have the provider of a kind empty a frame it filled.
-- @param kind the kind it was filled for
-- @param frame the frame
function Providers.Hide(kind, frame)
	call(kind, "Hide", frame)
end
