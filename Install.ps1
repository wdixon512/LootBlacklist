# Copy Loot Blacklist into a WoW client's Interface\AddOns folder.
# -Game is the client folder that contains Interface\AddOns (for example ...\World of Warcraft\_forever_).
param([Parameter(Mandatory = $true)][string]$Game)

$ErrorActionPreference = "Stop"
$addons = Join-Path $Game "Interface\AddOns"
if (-not (Test-Path $addons)) {
    Write-Host "No Interface\AddOns folder in $Game" -ForegroundColor Red
    exit 1
}
$dest = Join-Path $addons "LootBlacklist"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
foreach ($file in @("LootBlacklist.toc", "LootBlacklist.lua", "Bindings.xml")) {
    Copy-Item (Join-Path $PSScriptRoot $file) $dest -Force
}
Write-Host "Installed to $dest. /reload in game (restart the game the first time)." -ForegroundColor Green
