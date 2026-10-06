"""Each guard shown a violation and a clean file.

A guard fails open: when its pattern stops matching, it passes for ever. These
tests are where every guard is watched failing.
"""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path

import check
import pytest

Guard = Callable[[check.Sources], list[str]]

HEAD = "local _, ns = ...\n"

CLEAN = {
    "Core/Lines.lua": HEAD + "ns.Lines = {}\n",
    "Resolvers/Object.lua": HEAD + "local search = ns.Client.SearchObjects\n",
    "Interface/Chat.lua": HEAD + 'frame:HookScript("OnHyperlinkEnter", ns.Peek.Enter)\n',
    "Interface/Stage.lua": HEAD
    + "actor:SetModelByFileID(file)\n_G.GlimpseFaults = {}\n"
    + 'frame:SetScript("OnUpdate", ns.Safely.Wrap(function() end))\n',
    "Client.lua": HEAD
    + 'local frame = _G.CreateFrame("Frame")\nframe:RegisterEvent("SOUNDKIT_FINISHED")\n'
    + "local timer = _G.C_Timer.NewTimer(1, f)\nlocal epsilon = _G.C_Epsilon\n"
    + '_G.hooksecurefunc("SetItemRef", f)\nlocal wide = _G.UIParent:GetWidth()\n',
}


@pytest.mark.parametrize("name, guard", check.GUARDS)
def test_clean_sources_pass(name: str, guard: Guard) -> None:
    assert guard(CLEAN) == [], name


@pytest.mark.parametrize(
    "guard, path, line",
    [
        (check.send_violations, "Interface/Chat.lua", 'SendChatMessage(".lookup next", "GUILD")'),
        (check.send_violations, "Core/Async.lua", "C_ChatInfo.SendAddonMessage(prefix, text)"),
        (check.global_violations, "Interface/Chat.lua", "_G.ChatFrame_OnHyperlinkShow = mine"),
        (check.global_violations, "Core/Kinds.lua", 'rawset(_G, "Kinds", {})'),
        (
            check.foreign_script_violations,
            "Interface/Chat.lua",
            'chat:SetScript("OnHyperlinkEnter", f)',
        ),
        (check.loader_violations, "Interface/Peek.lua", "model:SetCreature(entry)"),
        (check.loader_violations, "Resolvers/Item.lua", "model:TryOn(link)"),
        (check.layer_violations, "Core/Lines.lua", "local find = _G.string.find"),
        (check.layer_violations, "Core/Async.lua", "ns.Client.After(1, f)"),
        (check.layer_violations, "Resolvers/Spell.lua", "ns.Stage:Show(look)"),
        (check.layer_violations, "Resolvers/Item.lua", "local info = _G.GetItemInfoInstant(id)"),
        (check.client_violations, "Client.lua", "return _G.C_Sound.IsPlaying(handle)"),
        (check.client_violations, "Client.lua", "return _G.GetItemInfoInstantly(id)"),
        (check.client_violations, "Interface/Chat.lua", 'hooksecurefunc("SetItemReference", f)'),
        (check.client_violations, "Client.lua", 'frame:RegisterEvent("SOUND_FINISHED")'),
        (check.callback_violations, "Interface/Peek.lua", 'frame:SetScript("OnUpdate", function()'),
        (
            check.callback_violations,
            "Interface/Tools.lua",
            'button:HookScript("OnEnter", function()',
        ),
        (check.callback_violations, "Interface/Peek.lua", "_G.C_Timer.NewTimer(4, function()"),
        (
            check.callback_violations,
            "Interface/Chat.lua",
            'hooksecurefunc("SetItemRef", function()',
        ),
    ],
)
def test_guard_fires(guard: Guard, path: str, line: str) -> None:
    violations = guard({path: f"{HEAD}{line}\n"})
    assert len(violations) == 1
    assert violations[0].startswith(f"{path}:2:")


def test_comments_do_not_fire() -> None:
    sources = {
        "Core/Lines.lua": "-- never SendChatMessage here\n--[[ _G.Thing = 1\nSetCreature( ]]\n"
    }
    for _, guard in check.GUARDS:
        assert guard(sources) == []


def test_toc_names_what_exists(tmp_path: Path) -> None:
    addon = tmp_path / "Glimpse"
    (addon / "Core").mkdir(parents=True)
    (addon / "Core" / "Lines.lua").write_text("", encoding="utf-8")
    (addon / "Core" / "Stray.lua").write_text("", encoding="utf-8")
    (addon / "Core" / "Map.xml").write_text("", encoding="utf-8")
    (addon / "Core" / "Stray.xml").write_text("", encoding="utf-8")
    (addon / "Glimpse.toc").write_text(
        "## Interface: 90207\n# a comment\nCore\\Lines.lua\nCore\\Gone.lua\nCore\\Map.xml\n"
        "Core\\Gone.xml\n",
        encoding="utf-8",
    )
    assert check.toc_violations(addon) == [
        "Glimpse.toc: lists Core/Gone.lua, which does not exist",
        "Glimpse.toc: lists Core/Gone.xml, which does not exist",
        "Core/Stray.lua: not listed in Glimpse.toc",
        "Core/Stray.xml: not listed in Glimpse.toc",
    ]


def test_missing_toc_is_a_violation(tmp_path: Path) -> None:
    (tmp_path / "Glimpse").mkdir()
    assert check.toc_violations(tmp_path / "Glimpse") == ["Glimpse.toc: missing"]
