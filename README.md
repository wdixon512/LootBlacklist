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

The game's own Auto Loot takes everything before an addon can step in. So while Loot Blacklist is on, it turns the game's Auto Loot setting off and does the auto looting itself: the loot window stays out of sight, everything else is taken, and the window closes, leaving blacklisted items on the corpse. Holding Shift still flips auto loot for one corpse. If something can't be taken (full bags, a roll, a bind-on-pickup prompt), the loot window shows, just like the game's Auto Loot.

Your Auto Loot choice is given back to the game at every logout and by `/lbl off`, so removing the addon never leaves Auto Loot off. New characters start with the same choice.

When you loot by hand, you can still click a blacklisted item to take it.

## Install

Copy this folder to `World of Warcraft\<client>\Interface\AddOns\LootBlacklist`, or run:

```powershell
.\Install.ps1 -Game "C:\Program Files\World of Warcraft\_forever_"
```

Restart the game after installing for the first time.
