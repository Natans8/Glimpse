# Design

Glimpse adds a `[Preview]` or `[Play]` button to the lines Epsilon's server prints for `.lookup` and similar
commands, so a result can be seen or heard before it is spawned, learned or equipped.

## Where it applies

A system line does not say which command produced it. Glimpse recognises the typed link the server put on the
line, so any server reply carrying one of these links gains the button, whichever command printed it.

| Line | Recognised by | Button | Route |
|---|---|---|---|
| object, tile, plane | `gameobject_entry:` link | `[Preview]` | a model's name → the models the client's displays name, then the client's object search → file; a stock entry → shipped table → file. One whose model is a WMO, by its file name or a stock entry's display, is drawn by an addon such as `Glimpse_WMO`, as for a spell, while it has a picture to show |
| detail doodad | its four `.m2` names | `[Preview]` | same, four looks |
| creature | `creature_entry:` link | `[Preview]` | a stock creature's several displays, from a shipped table; otherwise the client draws it from its entry |
| creature display | `creatureDisplayID:` link | `[Preview]` | the display itself |
| equipment | `item:` link the client calls dressable | `[Preview]` | worn on an undressed body, turned to the hand or back that carries it |
| mount or pet item | `item:` link of that class | `[Preview]` | the item's mount or pet, once the item has loaded |
| enchant | `enchantID:` link | `[Preview]` | a weapon tried on with the enchant |
| emote | `emoteID:` link | `[Preview]` | the animation on the player's body |
| area | `area:` link, of an area that has a map | `[Map]` | the client's world map, opened at the area's map: its own, its zone's, or in an instance the dungeon floor named as the area is, else the first; resting on it names the area and the map in text |
| spell | `spell:` link, and an addon such as Epsilook offering it | `[Preview]` | whatever that addon draws inside Glimpse's hover frame and window |
| map, teleport, skill, title, blueprint, faction, WMO area, tile texture | their links (`MapID:`, `tele:`, `skill:`, `title:`, `blueprint_name:`), or the line's shape for the last three | `[Preview]`, only while an addon offers the kind | as for a spell |
| music, ambience, intro music | the line's shape, and its id and name both matching the shipped table | `[Play]` | the sound kit, played and stopped |

No button is added where there is nothing to show: a non-equipment item that is neither mount nor pet, a stock
enchant with no visual, an area with no world map, an object whose WMO the addon drawing it has no picture of, a
watertile among them, a kind the player has turned off, and a kind only another addon previews while none
offers it. Every kind of line `.lookup` prints is read, so an addon can offer any of them.

Glimpse does not touch what players post in chat, and it does not attach to item tooltips.

## The command

`/glimpse` opens the settings. `/glimpse <kind> <id>` previews one thing as its button on a `.lookup` line would,
for ids a player has from elsewhere: a tooltip, an object viewer, a macro, another player. The kind is a kind's own
name, or `gob` and `npc` as the server says them: `/glimpse emote 10`, `/glimpse npc 184093`. A link pasted after
`/glimpse` works too, a spell's from the spellbook included. It searches for nothing. An object is known by its
entry alone only where it is a stock one; any other is named by its model, which its `.lookup` line's link carries.

## What the client can and cannot draw

These were established in game and decide the routes above.

- A gameobject entry has no client lookup. The object search (`C_Epsilon.GODI_Search`) takes part of a name and
  returns every record holding it: the display, the file and the name, which may carry a folder or a patch's tag
  in front and a carriage return behind. It does not hold every model the client's own display table does: the
  Karabor door is display 14643 in the table and not in the search. So the addon ships every model the client's
  displays name, by name, and looks a named model up there first; the search is kept for the server's own models,
  which the client's tables do not name. A stock object named in words is found by its entry, through a table
  built from the stock server's objects and the client's displays.
- Entries that share one model name draw the same file, so they preview alike.
- A model frame cannot draw a WMO.
- `SetCreature` on a model picks one of the creature's displays at random on each call. The first call for a
  creature the client has not seen returns nothing; asking again answers within about half a second.
- A scene's actor leaves pieces out of some displays of a playable race's body (a draenei male's, as Epsilon's
  own object viewer does too); a model frame draws them whole.
- Mount and pet lookups by item return nothing until the item record has loaded.
- A model frame plays nothing for a flying animation; a body on the ground plays its ground twin instead.
- On a body that has loaded, an animation that takes the weapons in hand puts a staff in the wrong hand unless
  the animation is set first and the weapons moved after it.
- Zone music, ambience and intro ids are not sound kit ids; nothing on the client plays them directly.

## Layers

```
Data        generated tables                                     know nothing
Core        Safely, Packed, Lines, Subject, Providers, Kinds,    pure Lua
            Links, Async
Client      the client functions the resolvers use               the seam tests replace
Resolvers   Object, Item, Direct, Sound, Offered                 each adds its kinds
Interface   Settings, Tools, Presentations, Stage, Peek, Window, Playback, Chat, Options, Start, API
```

A layer knows only the layers above it in this list.

- **Lines** reads a system line into `{kind, id, name, …}` or nothing. A link is matched by its exact type;
  a line with no link is matched whole, and a sound line also by its id and name agreeing with the data.
- **Kinds** is the registry. A kind is one row, added by the resolver file that owns it: its word, the letter
  that stands for it in a link, the resolver, an optional instant check for whether a line has anything to
  show. Adding a kind is a reader in Lines and a row; a new way of drawing is also a row in Presentations.
  A kind only another addon previews has no resolver and says so; its line gains a button only while one
  offers it. Kinds decides who previews a line: an addon offering its kind, otherwise Glimpse.
- **Providers** keeps what other addons offer to preview, and calls it protected.
- **Links** writes the links on the buttons and reads them back. A link carries the whole read, so a click on a
  line that scrolled past long ago still knows what it was about.
- **Resolvers** answer through a callback, at once or later, with a subject or with nothing to show. Each
  request can be cancelled. A stock creature that spawns with one of several displays has them all as looks; any
  other creature's one look is its entry, which the client draws, choosing among its displays as it does when
  one spawns. Drawing it again may show another, which is what the window's "Another display" does.
- **Async** lets the latest question in a slot win, drops a late answer, and keeps resolved subjects.
- **Packed** reads the large tables: fixed-width decimal records in sorted strings, searched by halving.
- **Subject** is what a preview shows: `{kind, id, name, looks, sounds}`. A look is one thing to draw.
  A creature display is a "character" where it is one of a playable race's bodies, and a "display"
  otherwise; a piece of equipment's look carries the slot it is worn in.
- **Presentations** says how each kind of look is presented: which drawer draws it, from what angle, whether
  drawing it again may show another, whether it has sounds. A worn thing is turned by its slot to the hand,
  arm or back that carries it. The window decides its controls from these rows, never from a look's name.
- **Stage** draws one look. It has two drawers: a scene, with a camera fitted to the model's bounds, for an
  object's model file and a creature display (mounts and pets included); and a model frame for a creature from
  its entry, a character's display, and the player's body wearing something or performing an animation. It
  is the only file that loads a model. Asked for a creature it has not seen, the client redraws the frame's
  earlier display, so the stage keeps the frame unseen and asks again until the display changes. An emote is
  set once the body has loaded. Equipment is always worn, never drawn bare: a model frame keeps one
  camera distance whatever the item and reports no size.
- **Peek** is the hover frame: the first look, turning unless the player has turned that off, a name and one
  small line. A turning look starts 45 degrees clockwise of its angle and only once its model has appeared, so
  the turn carries its front past the viewer first. Where the player has asked, each of several looks of a kind gets a full-size card of its own,
  glued in a row the way the game glues its comparison tooltips, as many as the screen holds, the last counting
  the rest. It stands at the pointer as a tooltip does: a corner just above the button, or below it where there
  is no room above, the row running whichever way has more room. It takes no input.
- **Window** opens on click: movable, resizable, standing where it was left. A header says what the thing
  is; a chooser row offers several displays as a pager, or another display of a creature; the picture is turned by dragging sideways, tilted by dragging up and down where it is a model
  rather than the player's body, and brought nearer by the wheel. Over the picture, shown while the pointer
  is on it: putting the view back, weapons away or in hand. One window serves every click
  unless the player asks for a window of each, when another opens below and right of the last. A click on
  the button a window shows closes that window, and Escape closes them all. It has no buttons for turning or
  zooming, which the drag and the wheel do, and no animation list or pause, which belong to a model viewer
  rather than to choosing a lookup result.
- **Tools** is the addon's own dress: flat panels and controls drawn from one icon sheet, `tools/art.py`, so
  nothing depends on the client's artwork or on what another addon has done to it.
- **Playback** plays zone music, ambience and intro music from their own buttons, one at a time.
- **Settings** keeps the player's choices, saving only those that differ from the defaults.
- **Chat** is one filter on system messages plus hover and click hooks on the chat frames.
- **Start** installs the chat hooks and the settings panel at login, and says to the player what the addon has
  to say: a fault, a data folder that is missing or from another version.
- **API** is the one global the addon creates, `Glimpse`, the door other addons offer previews through.

## Beside GLink

GLink is the addon that appends `[Spawn]`, `[Learn]` and the rest. Glimpse works with it and without it, and
shares nothing with it. Glimpse's links use their own scheme and are spelled so that none of GLink's patterns
match them, because GLink stops a click it half-recognises from reaching anyone else.

Glimpse's button always comes after GLink's. Players click GLink's buttons by habit, so their place on the line
does not move. Two things hold the order: GLink is an optional dependency, so it loads and registers its filter
first, and Glimpse registers its own filter at login, after every other addon has. A line that reaches Glimpse
may therefore already carry GLink's buttons on its end; the server's own link is still the first on the line.

## Beside other addons

Another addon can preview any kind Glimpse reads and draws: the kinds Glimpse previews itself, and those it
leaves to others, such as spells, areas and WMOs. A spell is drawn whole only by the game in the world, and
showing one off the world takes data and playing that belong to another addon, Epsilook first among them. Such an
addon offers itself, kind by kind:

```lua
Glimpse.Provide("spell", {
    name = "Epsilook",
    Show = function(frame, id, context) ... return true end,
    Hide = function(frame) ... end,
})
```

An offer overrides Glimpse's own preview of that kind: offering is the other addon's call. Sounds cannot be
offered, since they are played rather than drawn. `name` is optional and is what the settings say previews the
kind.

The door belongs to Glimpse because Glimpse is the side that changes least and is reinstalled least, so the
side that changes often adapts to it and is never held to a shape. Glimpse lends the inside of its hover frame or
window, empty, and keeps only the frame around it: the border, closing, moving and sizing, and the thing's name
and kind, which every kind wears whoever draws it. Everything inside is the provider's, words and controls
included, so the provider changes anything in it without Glimpse changing. `context.place` says which it is,
"hover", which takes no input, or "window". `Show` answers true where it filled the inside; anything else, as when
it shows the thing in a frame of its own, means Glimpse shows nothing. After the true it may answer a few words
said of the thing, which Glimpse puts after the kind, as it puts a display's id after an item's: "Object,
invisible: its collision shape".

Where nothing offers a kind, its lines gain no button. A provider is called protected, and the first fault
withdraws it for the session, saying nothing, since the fault is its own. Offering nil withdraws an offer. An
addon offering at its own load lists Glimpse in `OptionalDeps`, so Glimpse has loaded first.

## Data

Generated from Epsilon's client tables and the stock server's world tables by `generator/`.

| Table | Ships in |
|---|---|
| zone music, ambience and intro id → day and night sound kits, with names | `Glimpse` |
| stock enchants that have no visual | `Glimpse` |
| area → map: its own, its zone's, or its instance's dungeon floor (floor names from `UiMapGroupMember`) | `Glimpse` |
| emote → animation; the animations that take weapons in hand; flying animation → its ground twin | `Glimpse` |
| model name → file; gameobject entry → model; creature → its displays; the displays of a playable race's body | `Glimpse_Data`, loaded on demand |

A file that would reach a model loader is emitted only when it is known to be an `.m2`. The data addon is a
separate folder so that a player who never previews an object or a creature never loads it; the main
addon says once, in chat, when it is missing, turned off or from another version.

## Settings

Preview on hover; the hover picture's size; whether it turns; whether a creature's several displays show
side by side on hover; whether each click opens a window of its own; and a switch per kind, on by default, that
turns its buttons off. There is a switch for every kind something previews, one to a word, naming the addon
that previews a kind where another one does; spells always have one, greyed while no addon offers them. A setting is added only once its default has been judged in game,
the switches excepted, since on is how the addon has always behaved.
