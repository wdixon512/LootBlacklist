# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A World of Warcraft addon (Lua, no build step, no dependencies, no test suite). All logic lives in `LootBlacklist.lua`; `LootBlacklist.toc` is the addon manifest and `Bindings.xml` declares key bindings and the modified click.

## Commands

Install into a WoW client (copies the `.toc`, `.lua`, and `Bindings.xml`):

```powershell
.\Install.ps1 -Game "C:\Program Files\World of Warcraft\_forever_"
```

`-Game` is the client folder that contains `Interface\AddOns`. After installing, `/reload` in game; the first install (or any change to the `.toc` or `Bindings.xml`) needs a full game restart. There is no automated way to run or test the addon — verification happens in game.

If you add a new source file, list it in `LootBlacklist.toc`, the file list in `Install.ps1`, and `SHIPPED` in `.github/workflows/release.yml`. PR checks fail if one is missing.

## Versions and releases

Same model as the AHPrice addon:
- **Never pick, type, or bump a version number.** `LootBlacklist.toc` stays `## Version: @project-version@`; PR checks fail otherwise. The version is the newest `vMAJOR.MINOR.PATCH` git tag, and only `.github/workflows/release.yml` creates tags.
- Every push to `main` diffs the shipped files (`SHIPPED` in `release.yml`) against the last tag. If any changed, it releases last tag + 1 patch: builds `LootBlacklist-vX.Y.Z.zip` with the version stamped into the TOC, creates the GitHub release (which creates the tag), then uploads to CurseForge when the `CURSEFORGE_API_TOKEN`, `CURSEFORGE_PROJECT_ID`, and `CURSEFORGE_GAME_VERSIONS` secrets are set. Docs or CI-only changes do not release.
- For a minor or major bump, **start** the commit subject or PR title with `[minor]` or `[major]` (or add a `Release: minor` line). Running **Release** manually with `bump` forces one.
- Release notes (GitHub and CurseForge) are the commit subjects and merged PR titles since the last tag, so write PR titles as player-facing notes.
- Ship through a pull request into `main`; don't push `main` directly. PR checks: Lua 5.1 syntax, `Bindings.xml` well-formed, version placeholder, shipped file lists in sync.
- Every PR links a GitHub issue in this repo: open one first (`gh issue create`, label `bug` or `enhancement`), put `Closes #N` in the PR body, and confirm the PR's Development box shows it (`gh pr view <n> --json closingIssuesReferences`). Write bodies to a UTF-8 file and pass `--body-file`; piping them through a Windows shell garbles `→` and emoji.
- Read the PR's checks (`gh pr checks <n>`) before calling it done.

## Architecture

**Core trick: the addon replaces the game's auto loot.** The game's native Auto Loot grabs everything before addon code runs, so while the addon is enabled it forces the `autoLootDefault` CVar to `0` and auto loots itself, and it must feel the same as the native one (the owner treats auto loot as critical):
- A loot `session` starts on the first of `LOOT_READY` / `LOOT_OPENED` (clients send one or both). `LootPass` calls `LootSlot` once per non-blacklisted slot, re-runs on `LOOT_SLOT_CLEARED` and a short `C_Timer` retry (the loot list can arrive late), and calls `CloseLoot()` when only blacklisted items (or nothing) remain.
- The loot frame is faded with `SetAlpha(0)` while auto looting, never `Hide()` (hiding it closes the loot). `HandToPlayer` shows it again when something can't be taken: retries exhausted (full bags, rolls) or `LOOT_BIND_CONFIRM`.
- The `AUTOLOOTTOGGLE` modified click (Shift) inverts auto loot for one corpse, mimicking native behavior.
- The player's real choice is `db.autoLoot` (per character) and `account.autoLoot` (account wide, the default for new characters, since the CVar is already off by then); set both through `SetAutoLootChoice`. It is written back to the CVar by `/lbl off` and on `PLAYER_LOGOUT`, so an uninstalled addon never leaves Auto Loot off.
- `OnCVarUpdate` catches the player re-enabling Auto Loot in game options, records it, and flips the CVar back off. The `settingCVar` flag stops the addon from reacting to its own CVar writes. `PLAYER_ENTERING_WORLD` re-applies the mode because the game restores the saved CVar on login.

**Saved data:** `LootBlacklistCharDB` (per character) holds `items` (itemID → cached name string, `""` if unknown), `enabled`, `autoLoot`, `announce`, `autoLootFixed` (one-time migration flag). `LootBlacklistDB` (account wide) holds `autoLoot`. Both are declared in the `.toc`; defaults are filled in on `ADDON_LOADED`. Item names are re-cached opportunistically in `Refresh` and on `GET_ITEM_INFO_RECEIVED`.

**Ctrl+Shift+right-click detection:** `Bindings.xml` registers a `LOOTBLACKLIST` `ModifiedClick` so bag/loot buttons treat the click as modified and don't use or loot the item. `HookClicks` uses `hooksecurefunc` on `HandleModifiedItemClick` plus `ContainerFrameItemButtonMixin.OnClick` as a backup; since both can fire for one click, `OnItemClick` debounces (0.3s). It shows a `MenuUtil` context menu when available, otherwise toggles directly. The same hooks on `ChatEdit_InsertLink` / `ChatFrameUtil.InsertLink` redirect Shift-clicked links into the manager's Add box when it has focus.

**Global entry points** (referenced from `Bindings.xml` / `.toc`, so they must stay global with these names): `LootBlacklist_OnAddonCompartmentClick`, `LootBlacklist_ToggleHovered`, and the `BINDING_HEADER_*` / `BINDING_NAME_*` strings. `LootBlacklistAPI` (`IsBlocked`, `Toggle`, `Open`, `SetMenuHost`) is read by ahprice: when ahprice registers a menu host, `OnItemClick` opens ahprice's shared item menu (with a Never loot box) instead of ours.

**Manager window** (`BuildFrame`) is built lazily on first open, with a fixed pool of `ROWS` row buttons scrolled via `f.offset`. Any code that changes `db` should call `frame:Refresh()` when `frame` exists and is shown — follow the existing pattern.

## Conventions for API calls

The code targets several client versions (`## Interface: 16001, 16000, 16010`) and is written defensively:
- Prefer `C_Item.*` / `C_CVar.*` and fall back to the legacy globals (`GetItemInfo`, `GetCVar`, …); check that a function exists before calling it.
- Wrap item/value lookups with `IsSecret()` (`issecretvalue`) checks — newer clients can return secret values that must not be used.
- Use `pcall` around Blizzard calls that might error, and keep startup steps (`ApplyAutoLootMode`, `HookClicks`, `HookTooltip`) independent so one failure doesn't block the others.
- Use `hooksecurefunc` / `HookScript` rather than replacing Blizzard functions, to avoid taint.

User-facing chat output goes through `Print()` (prefixed with the addon name). Keep README.md in sync when changing commands, clicks, or auto-loot behavior.
