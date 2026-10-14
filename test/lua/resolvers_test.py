"""The resolvers over a client that answers as the game was seen to answer."""

import json
from typing import cast

import pytest
from support import LuaRuntime, evaluate

#: A client whose answers are the ones the probe recorded. `HOLD` keeps a
#: callback back so a test decides when an answer arrives. The object search,
#: like the client's, returns every record whose name holds what is asked.
#: `STOCK` is the data addon's table of stock objects.
CLIENT = b"""
    HOLD, REFUSE, CANCELS = {}, {}, 0
    RECORDS = {
        { display = -14856, file = 875053, name = "6dr_draenei_chair02.m2\\r" },
        {
            display = -239801, file = 30087564,
            name = "dungeons/textures/pandaren/buildingtile_stone_529117.m2\\r",
        },
        { display = -243896, file = 3734220, name = "[9270100] 9ori_sky02.m2\\r" },
        { display = -1, file = 111, name = "chair02destroyed.m2\\r" },
    }
    -- Pillow, the Karabor door, and the chair under another entry with another model.
    STOCK = {
        widths = { 6, 7 }, offsets = { 0, 0 },
        records = "2360830926294" .. "2530440999901" .. "7167090000001",
    }
    -- Stormwind City Guard's four displays, the last of them a character's; then Coilfang
    -- Underbog Hydra Trigger's two, an Infernal's and the invisible stalker's.
    CREATURES = {
        widths = { 6, 6 }, offsets = { 0, 0 },
        records = "000068003167" .. "000068005446" .. "000068099389" .. "000068099391"
            .. "020167001126" .. "020167011686",
    }
    -- The invisible stalker's display, and Event Generator 001, which only ever spawns as it.
    STALKERS = { widths = { 6 }, offsets = { 0 }, records = "011686" }
    UNSEEN = { widths = { 6 }, offsets = { 0 }, records = "002334" }
    CHARACTERS = { widths = { 7 }, offsets = { 0 }, records = "0099391" }
    -- Ship (The Bravery), whose display is a WMO.
    WMO_OBJECTS = { widths = { 6 }, offsets = { 0 }, records = "176310" }
    -- The data addon: the models the client's displays name and the stock objects.
    DATA = {
        models = ";0xp_scale_ruler01=2351343;6dr_draenei_karabor_bigdoor=926294;"
            .. "6td_treestump_b01=920823;7nb_nightborn_floorpillow03=999901;zm_last_one=7;",
        objects = STOCK,
        creatures = CREATURES,
        characters = CHARACTERS,
        wmoObjects = WMO_OBJECTS,
        stalkers = STALKERS,
        unseenCreatures = UNSEEN,
    }
    NS.Client = {
        SearchObjects = function(query)
            local found = {}
            for _, record in ipairs(RECORDS) do
                if record.name:lower():find(query:lower(), 1, true) then
                    found[#found + 1] = record
                end
            end
            return found
        end,
        ItemKind = function(id)
            local slot = ({ [25] = "INVTYPE_WEAPONMAINHAND", [2435] = "INVTYPE_ROBE" })[id]
            if slot then return "equipment", slot end
            return ({ [25470] = "mount", [8485] = "pet" })[id]
        end,
        WhenItemLoads = function(id, fn, refused)
            HOLD[id], REFUSE[id] = fn, refused
            return function() CANCELS = CANCELS + 1 end
        end,
        MountDisplaysOfItem = function(id) return id == 25470 and { 17697 } or {} end,
        PetDisplaysOfItem = function(id) return id == 8485 and { 5448 } or {} end,
        Data = function() return DATA end,
    }
    function RESOLVE(kind, read)
        read.kind = kind
        RESULT, ANSWERED = nil, false
        CANCEL = NS.Kinds.Resolve(read, function(subject) RESULT, ANSWERED = subject, true end)
        return RESULT
    end
"""


@pytest.fixture
def game(addon: LuaRuntime) -> LuaRuntime:
    """The addon with the recorded client in place."""
    addon.execute(CLIENT)
    return addon


def test_an_object_the_client_holds_under_a_patch_tag_is_found(game: LuaRuntime) -> None:
    looks = evaluate(game, 'RESOLVE("object", { id = 953448, name = "9ori_sky02.m2" }).looks')
    assert looks == [{"draw": "file", "value": 3734220}]


def test_an_object_is_found_by_its_own_name(game: LuaRuntime) -> None:
    subject = evaluate(game, 'RESOLVE("object", { id = 716709, name = "6dr_draenei_chair02.m2" })')
    assert subject == {
        "kind": "object",
        "id": 716709,
        "name": "6dr_draenei_chair02.m2",
        "looks": [{"draw": "file", "value": 875053}],
    }


def test_a_stock_object_is_found_by_its_entry(game: LuaRuntime) -> None:
    looks = evaluate(game, 'RESOLVE("object", { id = 253044, name = "Pillow" }).looks')
    assert looks == [{"draw": "file", "value": 999901}]
    assert evaluate(game, 'NS.Kinds.Of({ kind = "object", id = 1, name = "Pillow" })') is None, (
        "a name that is no file, of an entry not known, gains no button"
    )


def test_a_model_the_search_does_not_hold_is_found_among_the_clients(game: LuaRuntime) -> None:
    door = '{ id = 1, name = "6dr_draenei_karabor_bigdoor.m2" }'
    assert evaluate(game, f'RESOLVE("object", {door}).looks') == [{"draw": "file", "value": 926294}]


def test_a_servers_own_object_named_by_its_model_is_searched_for(game: LuaRuntime) -> None:
    chair = '{ kind = "object", id = 700001, name = "6dr_draenei_chair02" }'
    assert evaluate(game, f"NS.Kinds.Buttons({chair})") == ["Preview"]
    assert evaluate(game, f'RESOLVE("object", {chair}).looks[1].value') == 875053
    door = '{ kind = "object", id = 700296, name = "6dr_draenei_karabor_bigdoor" }'
    assert evaluate(game, f"NS.Kinds.Buttons({door})") == ["Preview"], "a model the client names"
    assert evaluate(game, f'RESOLVE("object", {door}).looks[1].value') == 926294
    gone = '{ kind = "object", id = 700297, name = "nothing_by_this_name" }'
    assert evaluate(game, f"NS.Kinds.Buttons({gone})") is None


def test_a_named_model_is_believed_over_its_entry(game: LuaRuntime) -> None:
    chair = '{ id = 716709, name = "6dr_draenei_chair02.m2" }'
    assert evaluate(game, f'RESOLVE("object", {chair}).looks[1].value') == 875053


def test_an_object_record_may_carry_a_folder(game: LuaRuntime) -> None:
    looks = evaluate(
        game, 'RESOLVE("object", { id = 1, name = "buildingtile_stone_529117.m2" }).looks'
    )
    assert looks == [{"draw": "file", "value": 30087564}]


def test_a_record_with_another_name_is_not_taken(game: LuaRuntime) -> None:
    assert evaluate(game, 'RESOLVE("object", { id = 1, name = "chair02.m2" })') is None
    assert evaluate(game, 'RESOLVE("object", { id = 1, name = "unknown.m2" })') is None
    assert evaluate(game, 'RESOLVE("object", { id = 1, name = "6dr_draenei" })') is None, (
        "a name that holds a model's is not that model"
    )
    assert evaluate(game, "ANSWERED") is True


def test_a_doodad_shows_the_models_that_are_found(game: LuaRuntime) -> None:
    looks = evaluate(
        game,
        'RESOLVE("doodad", { id = 5, names = { "unknown.m2", "6dr_draenei_chair02.m2" } }).looks',
    )
    assert looks == [{"draw": "file", "value": 875053, "name": "6dr_draenei_chair02.m2"}]
    assert evaluate(game, 'RESOLVE("doodad", { id = 5, names = { "unknown.m2" } })') is None


def test_a_spawned_object_is_drawn_as_the_server_says_it_stands(game: LuaRuntime) -> None:
    game.execute(b"""
        STANDING = {
            -- `.gob tint 100 0 0` as the server recorded it: no transparency typed, 0.
            [1] = { file = 999901, scale = 1, spell = 0,
                tint = { red = 100, green = 0, blue = 0, transparency = 0, saturation = 100 } },
            -- `.gob tint 20 40 60 80 60`: saturation 80, transparency 60.
            [2] = { file = 999901, scale = 1, spell = 0,
                tint = { red = 20, green = 40, blue = 60, transparency = 60, saturation = 80 } },
            [3] = { file = 999901, scale = 1, spell = 0,
                tint = { red = 20, green = 40, blue = 60, transparency = 100, saturation = 80 } },
            [4] = { file = 999901, scale = 1, spell = 116 },
        }
        NS.Client.ObjectRecord = function(guid) return STANDING[guid] end
        NS.Client.SpellName = function(id) return id == 116 and "Frostbolt" or nil end
    """)

    def look(guid: int) -> object:
        pillow = f'{{ id = 1, name = "7nb_nightborn_floorpillow03.m2", ids = {{ {guid} }} }}'
        return evaluate(game, f'RESOLVE("object", {pillow}).looks[1]')

    assert look(1) == {"draw": "tinted", "value": 999901, "kit": 167021}, (
        "the red proven in game, wholly opaque"
    )
    assert look(2) == {"draw": "tinted", "value": 999901, "kit": 320641}, (
        "20 40 60 on the grid, two fifths opaque, a fifth desaturated"
    )
    assert look(3) == {"draw": "tinted", "value": 999901, "kit": 167000}, "wholly transparent"
    assert look(4) == {"draw": "file", "value": 999901, "name": "with Frostbolt"}
    assert look(5) == {"draw": "file", "value": 999901}, "no record has come for it"


def test_a_placed_doodad_shows_its_model_and_what_replaced_it(game: LuaRuntime) -> None:
    # 821144 is what `.doodad near` printed after this stump's name: a terrain file,
    # GunDrak_29_30_tex0.adt, which crashed the client when it reached a model loader.
    stump = '{ id = 821144, name = "6td_treestump_b01.m2" }'
    assert evaluate(game, f'RESOLVE("mapdoodad", {stump}).looks') == [
        {"draw": "file", "value": 920823}
    ], "drawn from its name, never from the number its line prints"
    replaced = '{ id = 821144, name = "6td_treestump_b01.m2", ids = { 999901 } }'
    assert evaluate(game, f'RESOLVE("mapdoodad", {replaced}).looks') == [
        {"draw": "file", "value": 920823, "name": "before"},
        {"draw": "file", "value": 999901, "name": "after"},
    ]
    unknown = '{ id = 821144, name = "6td_treestump_b01.m2", ids = { 123 } }'
    assert evaluate(game, f'RESOLVE("mapdoodad", {unknown}).looks') == [
        {"draw": "file", "value": 920823, "name": "replaced by file 123"}
    ], "a file no display names never reaches a model loader"


def test_a_placed_doodad_whose_model_is_found_nowhere_gains_no_button(game: LuaRuntime) -> None:
    lost = '{ kind = "mapdoodad", id = 821144, name = "6sm_freriedragon_incubator04.m2" }'
    assert evaluate(game, f"NS.Kinds.Of({lost})") is None
    assert evaluate(game, f"RESOLVE('mapdoodad', {lost})") is None


#: A provider for WMOs as the released pictures offer it, with a picture for each name in
#: `PICTURED`, recording the ids it is asked about.
WMO_PICTURES = b"""
    PICTURED, ASKED_IDS = {}, {}
    Glimpse.Provide("wmo", {
        Shows = function(id, context)
            ASKED_IDS[#ASKED_IDS + 1] = id
            return PICTURED[context.name] == true
        end,
        Show = function() return true end,
        Hide = function() end,
    })
"""


def test_an_object_named_without_an_extension_is_a_wmo_where_the_pictures_have_it(
    game: LuaRuntime,
) -> None:
    game.execute(WMO_PICTURES)
    game.execute(b'PICTURED["eps_gilneas_garrison_ip_foundation_v3"] = true')

    def settled(name: str) -> object:
        read = f'{{ kind = "object", id = 879615, name = "{name}" }}'
        return evaluate(game, f"NS.Kinds.Settle({read})")

    assert settled("eps_gilneas_garrison_ip_foundation_v3") == {
        "kind": "wmo",
        "id": 879615,
        "name": "eps_gilneas_garrison_ip_foundation_v3",
    }, "Epsilon's own WMO, named without its extension"
    assert cast(dict[str, str], settled("eps_unpictured_thing"))["kind"] == "object"
    game.execute(b'PICTURED["eps_bl_godstatue_01.m2"] = true')
    assert cast(dict[str, str], settled("eps_bl_godstatue_01.m2"))["kind"] == "object", (
        "a name with a model's extension is never asked"
    )
    assert set(cast(list[int], evaluate(game, "ASKED_IDS"))) == {0}, "only the name is asked of"


def test_a_placed_wmo_is_shown_by_whoever_previews_wmos(game: LuaRuntime) -> None:
    tower = '{ kind = "mapdoodad", id = 833676, name = "6td_shattrathtower.wmo" }'
    assert evaluate(game, f"NS.Kinds.Buttons({tower})") is None, "nothing previews WMOs yet"
    game.execute(WMO_PICTURES)
    game.execute(b'PICTURED["6td_shattrathtower.wmo"] = true')
    assert evaluate(game, f"NS.Kinds.Settle({tower})") == {
        "kind": "wmo",
        "id": 0,
        "name": "6td_shattrathtower.wmo",
        "ids": [833676],
    }, "its id is its file's, carried aside"
    assert evaluate(game, f"NS.Kinds.Buttons(NS.Kinds.Settle({tower}))") == ["Preview"]
    bush = '{ kind = "mapdoodad", id = 820157, name = "6td_bush_b01.m2" }'
    assert evaluate(game, f"NS.Kinds.Settle({bush}).kind") == "mapdoodad", "a model is drawn here"


def test_a_name_is_found_anywhere_among_the_models(game: LuaRuntime) -> None:
    def file(name: str) -> object:
        subject = evaluate(game, f'RESOLVE("object", {{ id = 1, name = "{name}" }})')
        if not isinstance(subject, dict):
            return None
        return cast(list[dict[str, object]], subject["looks"])[0]["value"]

    assert file("0xp_scale_ruler01") == 2351343, "the first"
    assert file("7nb_nightborn_floorpillow03") == 999901, "one in the middle"
    assert file("zm_last_one.m2") == 7, "the last"
    assert file("zz_after_every_name") is None
    assert file("0a_before_every_name") is None


def test_a_search_record_that_is_no_model_file_is_never_taken(game: LuaRuntime) -> None:
    game.execute(b'RECORDS[#RECORDS + 1] = { display = -2, file = 222, name = "keep.wmo\\r" }')
    assert evaluate(game, 'RESOLVE("object", { id = 1, name = "keep" })') is None


def test_a_creature_with_one_display_is_drawn_from_its_entry(game: LuaRuntime) -> None:
    looks = evaluate(game, 'RESOLVE("creature", { id = 36, name = "Harvest Golem" }).looks')
    assert looks == [{"draw": "creature", "value": 36}]
    assert evaluate(game, "ANSWERED") is True


def test_a_spawned_creature_is_drawn_in_the_display_it_stands_in(game: LuaRuntime) -> None:
    looks = evaluate(game, 'RESOLVE("creature", { id = 68, name = "Guard", ids = { 5446 } }).looks')
    assert looks == [{"draw": "display", "value": 5446}], "not the entry's several, the one it has"


def test_a_creature_with_several_displays_has_them_all(game: LuaRuntime) -> None:
    looks = evaluate(game, 'RESOLVE("creature", { id = 68, name = "Guard" }).looks')
    assert looks == [
        *({"draw": "display", "value": value} for value in (3167, 5446, 99389)),
        {"draw": "character", "value": 99391},
    ], "a character's display is told apart, for a model frame to draw"


def test_a_creature_standing_in_the_invisible_stalker_gains_no_button(game: LuaRuntime) -> None:
    outfit = (
        '{ kind = "creature", id = 2372187, name = "Shattrath City Peacekeeper", ids = { 11686 } }'
    )
    assert evaluate(game, f"NS.Kinds.Buttons({outfit})") is None, "a spawn in an outfit"
    shown = '{ kind = "creature", id = 68, name = "Guard", ids = { 5446 } }'
    assert evaluate(game, f"NS.Kinds.Buttons({shown})") == ["Preview"]
    trigger = '{ kind = "creature", id = 2334, name = "Event Generator 001" }'
    assert evaluate(game, f"NS.Kinds.Buttons({trigger})") is None, "only ever the stalker"
    assert (
        evaluate(game, 'NS.Kinds.Buttons({ kind = "display", id = 11686, name = "11686" })') is None
    )


def test_a_forged_npc_named_by_its_entry_alone_gains_no_button(game: LuaRuntime) -> None:
    listed = '{ kind = "creature", id = 2637828, name = "NPC 268" }'
    assert evaluate(game, f"NS.Kinds.Buttons({listed})") is None, "it may wear an outfit"
    spawned = '{ kind = "creature", id = 2634994, name = "NPC 268", ids = { 1000 } }'
    assert evaluate(game, f"NS.Kinds.Buttons({spawned})") == ["Preview"], "a spawn in a display"
    stock = '{ kind = "creature", id = 184093, name = "Spirit Wolf" }'
    assert evaluate(game, f"NS.Kinds.Buttons({stock})") == ["Preview"]


def test_a_creature_spawning_as_the_stalker_or_as_something_shows_only_the_something(
    game: LuaRuntime,
) -> None:
    hydra = '{ id = 20167, name = "Coilfang Underbog Hydra Trigger" }'
    assert evaluate(game, f'RESOLVE("creature", {hydra}).looks') == [
        {"draw": "display", "value": 1126}
    ], "the Infernal alone, not the entry, which may spawn as the stalker"


def test_equipment_resolves_at_once(game: LuaRuntime) -> None:
    assert evaluate(game, 'RESOLVE("item", { id = 25, name = "Sword" }).looks') == [
        {"draw": "tryon", "value": 25, "slot": "INVTYPE_WEAPONMAINHAND"}
    ]
    assert evaluate(game, 'RESOLVE("item", { id = 2435, name = "Robe" }).looks') == [
        {"draw": "tryon", "value": 2435, "slot": "INVTYPE_ROBE"}
    ]


def test_a_mount_item_waits_for_the_item_to_load(game: LuaRuntime) -> None:
    game.execute(b'RESOLVE("item", { id = 25470, name = "Golden Gryphon" })')
    assert evaluate(game, "ANSWERED") is False
    game.execute(b"HOLD[25470]()")
    assert evaluate(game, "RESULT.looks") == [{"draw": "display", "value": 17697}]


def test_an_item_the_server_has_no_record_of_has_nothing_to_show(game: LuaRuntime) -> None:
    game.execute(b'RESOLVE("item", { id = 25470, name = "Golden Gryphon" }) REFUSE[25470]()')
    assert evaluate(game, "ANSWERED") is True
    assert evaluate(game, "RESULT") is None


def test_a_pet_item_shows_its_pet_and_can_be_cancelled(game: LuaRuntime) -> None:
    game.execute(b'RESOLVE("item", { id = 8485, name = "Cat Carrier" }) HOLD[8485]()')
    assert evaluate(game, "RESULT.looks") == [{"draw": "display", "value": 5448}]
    game.execute(b'RESOLVE("item", { id = 8485, name = "Cat Carrier" }) CANCEL()')
    assert evaluate(game, "CANCELS") == 1


def test_an_item_that_is_nothing_previewable_has_nothing_to_show(game: LuaRuntime) -> None:
    assert evaluate(game, 'RESOLVE("item", { id = 117, name = "Jerky" })') is None
    assert evaluate(game, "ANSWERED") is True


def test_zone_sounds_offer_one_button_or_two(game: LuaRuntime) -> None:
    assert evaluate(
        game, 'RESOLVE("music", { id = 156, name = "Zone-TavernAlliance" }).sounds'
    ) == [{"label": "Play", "kit": 4516}]
    assert evaluate(game, 'RESOLVE("ambience", { id = 28, name = "forest" }).sounds') == [
        {"label": "Day", "kit": 4170},
        {"label": "Night", "kit": 4171},
    ]
    assert evaluate(game, 'RESOLVE("intro", { id = 122, name = "Stormwind" }).sounds') == [
        {"label": "Play", "kit": 6837}
    ]


def test_an_emote_the_table_lacks_follows_the_servers_rule(game: LuaRuntime) -> None:
    def animation(emote: int) -> object:
        return evaluate(game, f'RESOLVE("emote", {{ id = {emote}, name = "x" }}).looks[1].value')

    assert evaluate(game, "NS.Data.EmoteAnimations[4069]") is None, "not shipped: the rule gives it"
    assert animation(4069) == 69, "a looping emote is 4000 and its animation"
    assert animation(2069) == 69, "a one-shot emote is 2000 and its animation"
    listed = evaluate(game, "NS.Data.EmoteAnimations[5909]")
    assert isinstance(listed, int) and listed != 1909, "an exception is shipped"
    assert animation(5909) == listed, "and the table is believed over the rule"
    assert evaluate(game, 'NS.Kinds.Of({ kind = "emote", id = 5999 })') is None, "no such animation"


def test_an_emote_says_whether_its_animation_takes_weapons_in_hand(game: LuaRuntime) -> None:
    def wields(emote: int) -> object:
        return evaluate(game, f'RESOLVE("emote", {{ id = {emote}, name = "x" }}).looks[1].wields')

    assert wields(2017) is True, "an attack with a weapon"
    assert wields(2026) is True, "a ready stance"
    assert wields(10) is False, "a dance"
    assert wields(2016) is False, "an unarmed attack"


def test_a_flying_emote_plays_what_a_body_on_the_ground_plays(game: LuaRuntime) -> None:
    look = evaluate(game, 'RESOLVE("emote", { id = 2246, name = "x" }).looks[1]')
    assert look == {"draw": "animation", "value": 17, "wields": True}, "FlyAttack1H as Attack1H"


def test_an_emote_plays_its_animation(game: LuaRuntime) -> None:
    looks = evaluate(game, 'RESOLVE("emote", { id = 10, name = "STATE_DANCE" }).looks')
    assert looks == [{"draw": "animation", "value": 69, "wields": False}]


def test_a_line_gains_a_button_only_where_there_is_something_to_show(game: LuaRuntime) -> None:
    def button(read: str) -> object:
        words = evaluate(game, f"NS.Kinds.Buttons({read})")
        return " ".join(cast(list[str], words)) if words else None

    assert button('{ kind = "object", id = 1, name = "anything.m2" }') == "Preview"
    assert button('{ kind = "object", id = 253044, name = "Pillow" }') == "Preview"
    assert button('{ kind = "object", id = 1, name = "Pillow" }') is None
    assert button('{ kind = "music", id = 156 }') == "Play"
    assert button('{ kind = "ambience", id = 28 }') == "Day Night"
    assert button('{ kind = "item", id = 25 }') == "Preview"
    assert button('{ kind = "item", id = 117 }') is None
    assert button('{ kind = "enchant", id = 803 }') == "Preview"
    assert button('{ kind = "enchant", id = 9001 }') == "Preview"
    assert button('{ kind = "enchant", id = (next(NS.Data.EnchantsWithoutVisual)) }') is None
    assert button('{ kind = "emote", id = 10 }') == "Preview"
    assert button('{ kind = "emote", id = 999999 }') is None
    assert button('{ kind = "spell", id = 116 }') is None, "no addon offers to preview it"
    assert button('{ kind = "area", id = 12 }') == "Map"
    assert button('{ kind = "area", id = 999999 }') is None, "an area with no map"


def test_a_stock_object_whose_display_is_a_wmo_is_a_wmo_line_under_another_name(
    game: LuaRuntime,
) -> None:
    ship = '{ kind = "object", id = 176310, name = "Ship (The Bravery)" }'
    assert evaluate(game, f"NS.Kinds.Settle({ship})") == {
        "kind": "wmo",
        "id": 176310,
        "name": "Ship (The Bravery)",
    }
    pillow = '{ kind = "object", id = 253044, name = "Pillow" }'
    assert evaluate(game, f"NS.Kinds.Settle({pillow}).kind") == "object"
    assert evaluate(game, f"NS.Kinds.Of({ship})") is None, "nothing of the addon's own draws it"


#: The data addon missing, turned off or from another version: `Client.Data` answers nothing.
NO_DATA = b"NS.Client.Data = function() return nil end"


def test_without_the_data_a_creature_is_drawn_from_its_entry(game: LuaRuntime) -> None:
    game.execute(NO_DATA)
    looks = evaluate(game, 'RESOLVE("creature", { id = 68, name = "Guard" }).looks')
    assert looks == [{"draw": "creature", "value": 68}], "the client chooses among its displays"


def test_without_the_data_an_object_is_still_found_by_the_clients_search(game: LuaRuntime) -> None:
    game.execute(NO_DATA)
    looks = evaluate(
        game, 'RESOLVE("object", { id = 716709, name = "6dr_draenei_chair02.m2" }).looks'
    )
    assert looks == [{"draw": "file", "value": 875053}]


def test_without_the_data_what_only_the_data_names_gains_no_button(game: LuaRuntime) -> None:
    game.execute(NO_DATA)
    door = '{ kind = "object", id = 1, name = "6dr_draenei_karabor_bigdoor.m2" }'
    pillow = '{ kind = "object", id = 253044, name = "Pillow" }'
    assert evaluate(game, f"RESOLVE('object', {door})") is None, "the search does not hold it"
    assert evaluate(game, f"NS.Kinds.Of({pillow})") is None, "a stock entry named in words"


def test_each_row_of_a_detail_shows_its_own_model_when_asked_in_turn(game: LuaRuntime) -> None:
    """Resting on one row and then the next, as the pointer moves down the line."""
    line = (
        "Detail ID: |cff00CCFF31042|r:\r"
        "Doodad 1: |cff00CCFF6dr_draenei_chair02.m2|r\r"
        "Doodad 2: |cff00CCFF0xp_scale_ruler01.m2|r\r"
        "Doodad 3: |cff00CCFF6dr_draenei_chair02.m2|r"
    )
    game.execute(
        f"""
        local line = {json.dumps(line)}
        local rows = NS.Lines.Rows(line, NS.Lines.Read(line))
        DRAWN = {{}}
        for index = 2, 4 do
            NS.Async.Ask("peek", rows[index], function(subject)
                DRAWN[#DRAWN + 1] = subject.looks[1].value
            end)
        end
        """.encode()
    )
    assert evaluate(game, "DRAWN") == [875053, 2351343, 875053]
