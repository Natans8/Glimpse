local _, ns = ...

--- Asking for a subject, where the latest question wins.
--
-- A resolver may answer at once or later. Each place a preview is shown is a
-- slot; a new question in a slot abandons the one before it, so an answer
-- that arrives late for a line the player has left is dropped. A subject,
-- once found, is kept, so asking again about the same thing is immediate.
local Async = {}
ns.Async = Async

local current = {} -- slot -> the question it is waiting on: { cancel }
local answers = {} -- "kind:id" -> subject

--- Abandon whatever a slot is waiting for. Its answer, if one comes, is dropped.
-- @param slot the slot's name
function Async.Cancel(slot)
	local pending = current[slot]
	current[slot] = nil
	if pending and pending.cancel then
		pending.cancel()
	end
end

--- Ask about a read, on behalf of a slot.
-- @param slot the slot's name; any earlier question in it is abandoned
-- @param read the read to resolve
-- @param done called once with the subject, or with nil where there is nothing to show, unless
--   the question is abandoned first
function Async.Ask(slot, read, done)
	Async.Cancel(slot)
	local key = ns.Subject.Key(read)
	if answers[key] then
		done(answers[key])
		return
	end
	local pending = {}
	current[slot] = pending
	local cancel = ns.Kinds.Resolve(read, function(subject)
		-- Only a subject is kept: "nothing to show" may change once the client has
		-- loaded what was asked of it.
		if subject then
			answers[key] = subject
		end
		if current[slot] == pending then
			current[slot] = nil
			done(subject)
		end
	end)
	if current[slot] == pending then
		pending.cancel = cancel
	end
end
