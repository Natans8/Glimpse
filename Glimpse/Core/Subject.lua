local _, ns = ...

--- What a preview shows.
--
-- A subject is a plain record: `{ kind, id, name, looks }`, and for some kinds
-- `sounds`. The interface chooses its controls from each look's presentation
-- (see Presentations).
--
--   looks   { { draw, value, ... }, ... }         one thing to draw each; `draw` is "file",
--                                                 "creature", "display", "character", "tryon",
--                                                 "enchant" or "animation". A look may carry a
--                                                 `name` of its own.
--   sounds  { { label, kit }, ... }               sound kits to play
local Subject = {}
ns.Subject = Subject

--- A subject for a read, with nothing to show yet.
-- @param read the read it answers
-- @return the subject
function Subject.New(read)
	return { kind = read.kind, id = read.id, name = read.name, looks = {} }
end

--- What tells one subject from another: its kind and id. A read has the same key
-- as the subject resolved from it.
-- @param of a read or a subject
-- @return the key
function Subject.Key(of)
	return of.kind .. ":" .. of.id
end

--- Add a look to a subject.
-- @param subject the subject
-- @param draw how the look is drawn
-- @param value what is drawn
-- @return the look, for the caller to add fields to
function Subject.Look(subject, draw, value)
	local look = { draw = draw, value = value }
	subject.looks[#subject.looks + 1] = look
	return look
end

--- Add a creature display to a subject. A display of one of the character bodies
-- the data names is a "character", which only a model frame draws whole; any
-- other is a "display".
-- @param subject the subject
-- @param display the display id
-- @param data the data addon, or nil where it is not loaded
-- @return the look
function Subject.Display(subject, display, data)
	local draw = "display"
	if data and ns.Packed.First(data.characters, display) then
		draw = "character"
	end
	return Subject.Look(subject, draw, display)
end

local function filled(list)
	return list ~= nil and #list > 0
end

--- Answer with a subject, or with nothing where it has nothing to show.
-- @param subject the subject a resolver built
-- @param done the resolver's answer function
function Subject.Answer(subject, done)
	if filled(subject.looks) or filled(subject.sounds) then
		done(subject)
	else
		done(nil)
	end
end

--- A resolver for a kind whose one look is its own id, drawn a given way.
-- @param draw how the look is drawn
-- @return a resolver
function Subject.Direct(draw)
	return function(read, done)
		local subject = Subject.New(read)
		Subject.Look(subject, draw, read.id)
		done(subject)
	end
end
