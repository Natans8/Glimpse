local _, ns = ...

--- Running the addon's code where a fault cannot reach the client.
--
-- Every function the client calls into is wrapped once. A fault inside it is
-- recorded by the place it happened and announced the first time only, so a
-- defect on a hover reports once and not on every mouse movement.
local Safely = {}
ns.Safely = Safely

--- Faults seen this session, by place: `{ message = string, count = number }`.
Safely.faults = {}

--- Called with `(place, message)` the first time a place faults. Set by the
-- interface, which knows how to tell the player and where faults are saved.
Safely.Announce = nil

-- Where a fault happened, `file:line` where the message names one and the whole
-- first line otherwise, and the first line of the message.
local function placed(fault)
	local line = tostring(fault):match("^[^\n]*")
	return line:match("^(.-:%d+):") or line, line
end

--- Record a fault. Never raises.
-- @param fault whatever was raised
function Safely.Report(fault)
	local place, line = placed(fault)
	local record = Safely.faults[place]
	if not record then
		record = { count = 0 }
		Safely.faults[place] = record
	end
	record.count = record.count + 1
	record.message = line
	if record.count == 1 and Safely.Announce then
		pcall(Safely.Announce, place, line)
	end
end

--- A function that runs `fn` and never raises.
-- @param fn the function to guard
-- @return a function passing its arguments to `fn` and returning what `fn` returns, or nothing
--   where `fn` faulted
function Safely.Wrap(fn)
	local function finish(ok, ...)
		if ok then
			return ...
		end
	end
	return function(...)
		local given, args = select("#", ...), { ... }
		return finish(xpcall(function()
			return fn(unpack(args, 1, given))
		end, Safely.Report))
	end
end
