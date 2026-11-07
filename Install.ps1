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
# Stamp the newest release tag into the installed TOC (the repo keeps @project-version@).
$tag = $null
if (Get-Command git -ErrorAction SilentlyContinue) {
    $tag = git -C $PSScriptRoot describe --tags --abbrev=0 --match "v*" 2>$null
}
if ($tag) {
    $toc = Join-Path $dest "LootBlacklist.toc"
    (Get-Content $toc) -replace '^## Version: @project-version@$', "## Version: $($tag.TrimStart('v'))-dev" | Set-Content -Encoding utf8 $toc
}
Write-Host "Installed to $dest. /reload in game (restart the game the first time)." -ForegroundColor Green
