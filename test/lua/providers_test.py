"""The door other addons preview a kind through, in frames this addon lends them."""

from __future__ import annotations

from support import LuaRuntime, evaluate

#: A provider for spells, recording what it is asked. `ANSWER` is what `Show` answers, and
#: `FAULT` makes it throw.
PROVIDER = b"""
    ASKED, ANSWER, FAULT = {}, true, false
    PROVIDER = {
        Show = function(frame, id, context)
            if FAULT then error("broken") end
            ASKED[#ASKED + 1] = "show " .. id .. " in " .. frame.name .. " at " .. context.place
            return ANSWER
        end,
        Hide = function(frame) ASKED[#ASKED + 1] = "hide in " .. frame.name end,
    }
    -- The inside this addon lends.
    INSIDE = { name = "the inside" }
"""

SPELL = '{ kind = "spell", id = 116, name = "Frostbolt" }'


def offer(addon: LuaRuntime) -> object:
    """Offer the recording provider through the global door, answering what the door answers."""
    return offer_kind(addon, "spell")


def offer_kind(addon: LuaRuntime, kind: str) -> object:
    """Offer the recording provider for a kind, answering what the door answers."""
    addon.execute(PROVIDER)
    return evaluate(addon, f'Glimpse.Provide("{kind}", PROVIDER)')


def test_an_offered_kind_fills_the_inside_it_is_lent(addon: LuaRuntime) -> None:
    assert offer(addon) is True
    assert evaluate(addon, f"NS.Kinds.Buttons({SPELL})") == ["Preview"]
    assert evaluate(addon, 'NS.Providers.Show("spell", INSIDE, 116, { place = "hover" })') is True
    addon.execute(b'NS.Providers.Hide("spell", INSIDE)')
    assert evaluate(addon, "ASKED") == ["show 116 in the inside at hover", "hide in the inside"]


def test_a_kind_nobody_offers_gains_no_button(addon: LuaRuntime) -> None:
    assert evaluate(addon, f"NS.Kinds.Buttons({SPELL})") is None
    assert evaluate(addon, 'NS.Providers.Show("spell", {}, 116, { place = "hover" })') is False


def test_any_kind_that_is_drawn_may_be_offered_and_nothing_else(addon: LuaRuntime) -> None:
    addon.execute(PROVIDER)
    for kind in ("spell", "object", "creature", "texture", "wmo"):
        assert evaluate(addon, f'Glimpse.Provide("{kind}", PROVIDER)') is True, kind
    assert evaluate(addon, 'Glimpse.Provide("music", PROVIDER)') is False, "a sound is played"
    assert evaluate(addon, 'Glimpse.Provide("area", PROVIDER)') is False, "an area opens a map"
    assert evaluate(addon, 'Glimpse.Provide("nothing like it", PROVIDER)') is False
    assert evaluate(addon, "Glimpse.Provide(nil, PROVIDER)") is False


def test_only_a_whole_provider_is_taken(addon: LuaRuntime) -> None:
    addon.execute(PROVIDER)
    assert evaluate(addon, 'Glimpse.Provide("spell", { Show = PROVIDER.Show })') is False
    assert evaluate(addon, 'Glimpse.Provide("spell", PROVIDER.Show)') is False
    assert evaluate(addon, f"NS.Kinds.Buttons({SPELL})") is None


def test_an_offered_kind_this_addon_draws_is_previewed_by_the_one_that_offers_it(
    addon: LuaRuntime,
) -> None:
    creature = '{ kind = "creature", id = 184093, name = "Spirit Wolf" }'
    assert evaluate(addon, f"NS.Kinds.Drawer({creature})") == "own"
    offer_kind(addon, "creature")
    assert evaluate(addon, f"NS.Kinds.Drawer({creature})") == "provider"
    nameless = '{ kind = "emote", id = 999999, name = "?" }'
    assert evaluate(addon, f"NS.Kinds.Buttons({nameless})") is None, "nothing of ours to show"
    offer_kind(addon, "emote")
    assert evaluate(addon, f"NS.Kinds.Buttons({nameless})") == ["Preview"], "the offer decides"


def test_every_kind_of_lookup_line_can_be_offered(addon: LuaRuntime) -> None:
    title = '{ kind = "title", id = 174, name = "Player, Bane of the Fallen King" }'
    assert evaluate(addon, f"NS.Kinds.Buttons({title})") is None
    offer_kind(addon, "title")
    assert evaluate(addon, f"NS.Kinds.Buttons({title})") == ["Preview"]


def test_the_offering_addon_gives_its_name(addon: LuaRuntime) -> None:
    offer(addon)
    assert evaluate(addon, 'NS.Providers.Name("spell")') is None, "it gave none"
    addon.execute(b"""
        Glimpse.Provide("spell", { name = "Epsilook", Show = PROVIDER.Show, Hide = PROVIDER.Hide })
    """)
    assert evaluate(addon, 'NS.Providers.Name("spell")') == "Epsilook"


def test_an_offer_is_withdrawn_by_offering_nothing(addon: LuaRuntime) -> None:
    offer(addon)
    assert evaluate(addon, 'Glimpse.Provide("spell", nil)') is True
    assert evaluate(addon, f"NS.Kinds.Buttons({SPELL})") is None


def test_an_inside_not_filled_is_not_shown(addon: LuaRuntime) -> None:
    offer(addon)
    for answer in (b"false", b"nil", b'"yes"'):
        addon.execute(b"ANSWER = " + answer)
        shown = evaluate(addon, 'NS.Providers.Show("spell", INSIDE, 116, { place = "window" })')
        assert shown is False, answer


def test_a_provider_that_faults_is_withdrawn_for_the_session(addon: LuaRuntime) -> None:
    offer(addon)
    addon.execute(b"FAULT = true")
    assert evaluate(addon, 'NS.Providers.Show("spell", INSIDE, 116, { place = "hover" })') is False
    assert evaluate(addon, f"NS.Kinds.Buttons({SPELL})") is None, "spell lines gain no button"
    addon.execute(b'FAULT = false NS.Providers.Show("spell", INSIDE, 116, { place = "hover" })')
    assert not evaluate(addon, "ASKED"), "and the provider is not asked again"
