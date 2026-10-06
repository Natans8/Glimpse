"""Settings: a choice, its default, and what a damaged saved file reads as."""

from __future__ import annotations

from support import LuaRuntime, evaluate


def test_a_setting_reads_as_its_default_until_chosen(addon: LuaRuntime) -> None:
    assert evaluate(addon, 'NS.Settings.Get("hoverSpin")') is True
    assert evaluate(addon, 'NS.Settings.Get("hoverSize")') == 300


def test_a_choice_is_kept_and_read_back(addon: LuaRuntime) -> None:
    addon.execute(b'NS.Settings.Set("hoverSpin", false) NS.Settings.Set("hoverSize", 400)')
    assert evaluate(addon, 'NS.Settings.Get("hoverSpin")') is False
    assert evaluate(addon, 'NS.Settings.Get("hoverSize")') == 400
    assert evaluate(addon, "GlimpseSettings") == {"hoverSpin": False, "hoverSize": 400}


def test_choosing_the_default_saves_nothing(addon: LuaRuntime) -> None:
    addon.execute(b'NS.Settings.Set("hoverSize", 400) NS.Settings.Set("hoverSize", 300)')
    assert evaluate(addon, "next(GlimpseSettings)") is None


def test_a_saved_value_of_the_wrong_type_reads_as_the_default(addon: LuaRuntime) -> None:
    addon.execute(b'GlimpseSettings = { hoverSize = "large", hover = 1 }')
    assert evaluate(addon, 'NS.Settings.Get("hoverSize")') == 300
    assert evaluate(addon, 'NS.Settings.Get("hover")') is True
    addon.execute(b'GlimpseSettings = "damaged"')
    assert evaluate(addon, 'NS.Settings.Get("hoverSize")') == 300
    addon.execute(b'NS.Settings.Set("hover", false)')
    assert evaluate(addon, "GlimpseSettings") == {"hover": False}


def test_reset_clears_every_choice(addon: LuaRuntime) -> None:
    addon.execute(b'NS.Settings.Set("hover", false) NS.Settings.Reset()')
    assert evaluate(addon, 'NS.Settings.Get("hover")') is True


def test_a_kind_is_on_until_turned_off(addon: LuaRuntime) -> None:
    assert evaluate(addon, 'NS.Settings.On("creature")') is True
    addon.execute(b'NS.Settings.Turn("creature", false) NS.Settings.Turn("spell", false)')
    assert evaluate(addon, 'NS.Settings.On("creature")') is False
    assert evaluate(addon, 'NS.Settings.On("object")') is True, "only the kinds turned off"
    addon.execute(b'NS.Settings.Turn("creature", true) NS.Settings.Turn("spell", true)')
    assert evaluate(addon, 'NS.Settings.On("creature")') is True
    assert evaluate(addon, "GlimpseSettings.off") is None, "turning every kind on saves nothing"


def test_a_kind_turned_off_by_hand_with_anything_but_true_stays_on(addon: LuaRuntime) -> None:
    addon.execute(b'GlimpseSettings = { off = { creature = "yes", spell = true } }')
    assert evaluate(addon, 'NS.Settings.On("creature")') is True
    assert evaluate(addon, 'NS.Settings.On("spell")') is False
