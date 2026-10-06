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
--   Show   `Show(frame, id, context)`: fill `frame`, an empty frame filling the
--          inside of the hover frame or the window, with whatever shows the thing.
--          `context.place` is "hover", which takes no input, or "window". Answer
--          true where the frame was filled; anything else means it was not,
--          whether the thing was shown elsewhere or there was nothing to show, and
--          this addon then shows nothing of its own.
--   Hide   `Hide(frame)`: empty a frame it filled.
--
-- This addon keeps the frame around the inside: the border, closing, moving and
-- sizing. What is inside is the provider's alone, so the provider may change
-- anything in it without this addon changing. A provider changes far more often
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

-- Call one of a kind's provider's functions, protected. A fault withdraws the provider.
local function call(kind, name, ...)
	local provider = offered[kind]
	if not provider then
		return nil
	end
	local ok, answer = pcall(provider[name], ...)
	if not ok then
		offered[kind] = nil
		return nil
	end
	return answer
end

--- Have the provider of a kind fill a frame with a thing.
-- @param kind the thing's kind
-- @param frame the frame to fill, shown and empty
-- @param id the thing's id
-- @param context `{ place = "hover" }` or `{ place = "window" }`
-- @return true where the provider filled the frame
function Providers.Show(kind, frame, id, context)
	return call(kind, "Show", frame, id, context) == true
end

--- Have the provider of a kind empty a frame it filled.
-- @param kind the kind it was filled for
-- @param frame the frame
function Providers.Hide(kind, frame)
	call(kind, "Hide", frame)
end
