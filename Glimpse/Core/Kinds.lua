local _, ns = ...

--- The kinds of thing a line can be about.
--
-- A kind is one row, added by the file that knows how to resolve it:
--
--   word      what the kind is called to the player: "Creature"
--   code      the one letter that stands for the kind in the links this addon writes
--   button    optional; the word on the button the line gains, "Preview" where absent
--   buttons   optional, in place of `button`; `buttons(read)` gives the words of several
--   resolve  `resolve(read, done)`: answer with a subject or with nil, at once or later,
--             and return a function that cancels the waiting, or nothing
--   draws     optional; false for a kind with nothing to look at, which is never hovered
--   shows     optional; `shows(read)` answers at once whether this line has anything to
--             show, so a line that has nothing gains no button
--   provided  optional; true for a kind only another addon previews (Providers), which
--             has no `resolve`
--   listed    optional; true for such a kind whose switch the settings show, greyed, even
--             while no addon offers it
--   opens     optional; `opens(read)` does what a click on this addon's own preview does,
--             in place of opening the window
--   hint      optional; `hint(read)` gives the lines of a text tooltip shown on hover, for a
--             kind with nothing to draw
--   recast    optional; `recast(read)` answers a read of another kind where the data says
--             the line is really about that, or nil to keep the read as it is
--
-- Any kind that is drawn may also be offered by another addon, which then
-- previews it in place of this one.
--
-- Adding a kind is a reader in Lines and a file that adds its row.
local Kinds = {}
ns.Kinds = Kinds

--- The words a button can carry.
Kinds.PREVIEW, Kinds.PLAY = "Preview", "Play"

local rows = {}
local named = {} -- code -> kind
local order = {} -- every kind, in the order it was added

--- Add a kind.
-- @param name the kind, as a read names it
-- @param row its row
function Kinds.Add(name, row)
	rows[name] = row
	named[row.code] = name
	order[#order + 1] = name
end

--- The read a line is really about: the read itself, or the one its kind
-- recasts it as once the data has been asked.
-- @param read a read from `Lines.Read`
-- @return a read
function Kinds.Settle(read)
	local row = rows[read.kind]
	if row and row.recast then
		return row.recast(read) or read
	end
	return read
end

--- Whether a kind has been added.
-- @param kind a kind, or anything
-- @return true for a kind of this addon's
function Kinds.Known(kind)
	return rows[kind] ~= nil
end

--- The letter that stands for a kind in a link.
-- @param kind a kind that has been added
-- @return the letter
function Kinds.Code(kind)
	return rows[kind].code
end

--- The kind a link's letter stands for.
-- @param code a letter from a link
-- @return the kind, or nil where no kind has that letter
function Kinds.Named(code)
	return named[code]
end

--- Every kind, in the order the addon added them.
-- @return an array of `{ kind, word, listed }`
function Kinds.List()
	local list = {}
	for index, kind in ipairs(order) do
		local row = rows[kind]
		list[index] = { kind = kind, word = row.word, listed = row.listed == true }
	end
	return list
end

--- Whether another addon may offer previews of a kind.
-- @param kind a kind, or anything
-- @return true for a kind that has been added and is drawn
function Kinds.Providable(kind)
	local row = rows[kind]
	return row ~= nil and row.draws ~= false
end

--- The kind of a read, where this addon has something of its own to show for it.
-- @param read a read from `Lines.Read`
-- @return the kind's row, or nil where this addon shows nothing of its own for the line
function Kinds.Of(read)
	local row = rows[read.kind]
	if not row or row.provided then
		return nil
	end
	if row.shows and not row.shows(read) then
		return nil
	end
	return row
end

--- Who previews a kind: the addon that offers it, and otherwise this one.
-- @param kind a kind
-- @return "provider", "own", or nil where nothing previews it
function Kinds.DrawerOf(kind)
	local row = rows[kind]
	if not row then
		return nil
	end
	if ns.Providers.Has(kind) then
		return "provider"
	end
	if not row.provided then
		return "own"
	end
	return nil
end

--- Who previews a read: as its kind is previewed, where this addon has something
-- of its own to show for the line when it is the one.
-- @param read a read from `Lines.Read`
-- @return "provider", "own", or nil where the line gains no button
function Kinds.Drawer(read)
	local drawer = Kinds.DrawerOf(read.kind)
	if drawer == "own" and not Kinds.Of(read) then
		return nil
	end
	return drawer
end

--- Do what a click on a read's own preview does where its kind says, in place of
-- opening the window.
-- @param read a read this addon previews itself
-- @return true where the kind did something of its own
function Kinds.Open(read)
	local row = rows[read.kind]
	if not row.opens then
		return false
	end
	row.opens(read)
	return true
end

--- The lines of the text tooltip a read's own button shows on hover, where its kind
-- has one.
-- @param read a read this addon previews itself
-- @return an array of lines, the first the title, or nil
function Kinds.Hint(read)
	local row = rows[read.kind]
	if row.hint then
		return row.hint(read)
	end
	return nil
end

--- What a kind of thing is called, to the player.
-- @param of a read or a subject that has a kind
-- @return the word, capitalised: "Creature"
function Kinds.Word(of)
	return rows[of.kind].word
end

--- Whether a read's kind is drawn, as opposed to played.
-- @param read a read that has a kind
-- @return true where a preview of it is a picture
function Kinds.Draws(read)
	return rows[read.kind].draws ~= false
end

--- The words of the buttons a read's line gains, in order.
-- @param read a read from `Lines.Read`
-- @return an array of words, or nil where the line gains no button
function Kinds.Buttons(read)
	local drawer = Kinds.Drawer(read)
	if not drawer then
		return nil
	end
	local row = rows[read.kind]
	if drawer == "own" and row.buttons then
		return row.buttons(read)
	end
	return { row.button or Kinds.PREVIEW }
end

--- Resolve a read through its kind. A read this addon has nothing of its own to
-- show for answers nil without its resolver being asked.
-- @param read a read from `Lines.Read`
-- @param done called with the subject, or with nil
-- @return a function that cancels the resolver's waiting, or nil
function Kinds.Resolve(read, done)
	local row = Kinds.Of(read)
	if not (row and row.resolve) then
		done(nil)
		return nil
	end
	return row.resolve(read, done)
end
