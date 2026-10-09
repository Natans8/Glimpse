"""The resolvers over a client that answers as the game was seen to answer."""

from __future__ import annotations

from typing import cast

import pytest
from support import LuaRuntime, evaluate

#: A client whose answers are the ones the probe recorded. `HOLD` keeps a
#: callback back so a test decides when an answer arrives. The object search,
#: like the client's, returns every record whose name holds what is asked.
#: `STOCK` is the data addon's table of stock objects.
CLIENT = b"""
    HOLD, CANCELS = {}, 0
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
    -- Stormwind City Guard's four displays, the last of them a character's.
    CREATURES = {
        widths = { 6, 6 }, offsets = { 0, 0 },
        records = "000068003167" .. "000068005446" .. "000068099389" .. "000068099391",
    }
    CHARACTERS = { widths = { 7 }, offsets = { 0 }, records = "0099391" }
    -- Ship (The Bravery), whose display is a WMO.
    WMO_OBJECTS = { widths = { 6 }, offsets = { 0 }, records = "176310" }
    -- The data addon: the models the client's displays name and the stock objects.
    DATA = {
        models = ";0xp_scale_ruler01=2351343;6dr_draenei_karabor_bigdoor=926294;"
            .. "7nb_nightborn_floorpillow03=999901;zm_last_one=7;",
        objects = STOCK,
        creatures = CREATURES,
        characters = CHARACTERS,
        wmoObjects = WMO_OBJECTS,
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
        WhenItemLoads = function(id, fn)
            HOLD[id] = fn
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


def test_a_creature_with_several_displays_has_them_all(game: LuaRuntime) -> None:
    looks = evaluate(game, 'RESOLVE("creature", { id = 68, name = "Guard" }).looks')
    assert looks == [
        *({"draw": "display", "value": value} for value in (3167, 5446, 99389)),
        {"draw": "character", "value": 99391},
    ], "a character's display is told apart, for a model frame to draw"


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
    assert button('{ kind = "map", id = 1 }') == "Map"
    assert button('{ kind = "map", id = 24298 }') is None, "a map the client draws no world map of"


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
