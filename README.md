# Loot Blacklist

A World of Warcraft addon that never picks up the items you blacklist.

## Use

- **Ctrl+Shift+right-click** an item in your bags, the loot window, or a chat link, then choose **Add to blacklist** or **Remove from blacklist**.
- **`/lbl`** (or `/lootblacklist`) opens the list. Add items by ID, name, or Shift-clicked link, or drag an item onto the window. Remove with the X or by right-clicking a row.
- Blacklisted items show "Loot Blacklist: never looted" on their tooltip.
- Key Bindings → **Loot Blacklist** has optional keys to add/remove the item under the mouse and to open the list.
- `/lbl add <item>`, `/lbl remove <item>`, `/lbl on`, `/lbl off`.

Each character has its own list and settings.

## How it skips items

The game's own Auto Loot takes everything before an addon can step in. So while Loot Blacklist is on, it turns the game's Auto Loot setting off and auto loots everything else itself, leaving blacklisted items on the corpse. Holding Shift still flips auto loot for one corpse. `/lbl off` gives the game its Auto Loot setting back. If you uninstall the addon, turn Auto Loot back on in the game options.

When you loot by hand, you can still click a blacklisted item to take it.

## Install

Copy this folder to `World of Warcraft\<client>\Interface\AddOns\LootBlacklist`, or run:

```powershell
.\Install.ps1 -Game "C:\Program Files\World of Warcraft\_forever_"
```

Restart the game after installing for the first time.
