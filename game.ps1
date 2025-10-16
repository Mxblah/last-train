# why did I write this in powershell?
# good question

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Clean,

    [Parameter()]
    [switch]$SkipOptionsMenu,

    [Parameter()]
    [int]$Slot,

    [Parameter()]
    [object[]]$Cheats
)

Write-Host '### LAST TRAIN ###'
Write-Host '### by Mxblah  ###'

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Warning "WARNING: Unsupported PowerShell version $($PSVersionTable.PSVersion.Major) - game is only tested on PS 7."
}

Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/functions" | ForEach-Object { . $_.FullName }

if (-not $Slot) {
    $Slot = Get-SaveSlot -Clean:$Clean
}
$state = Import-Save -Slot $Slot -CreateIfNotPresent

# New game handling
if (-not $state.options.meta.init) {
    $state | New-Options -Category 'options' -UseDefaults:$SkipOptionsMenu
}
if (-not $state.player.meta.init) {
    $state | New-Options -Category 'player' -UseDefaults:$SkipOptionsMenu
}
if (-not $state.game.meta.init) {
    $state | New-Options -Category 'game' -UseDefaults:$SkipOptionsMenu
    $State | Initialize-EnrichmentVariables
}
if (-not $state.time.meta.init) {
    $state | Set-GlobalTime
}

# Apply cheats
if ($Cheats.Count -gt 0) {
    $state | Apply-GameCheats -Cheats $Cheats
}

# Update now that all the init is done
$State | Update-CharacterValues -Character $State.player

# post-init debug dumper
if ($DebugPreference -eq 'Continue') {
    Write-Debug "DUMPING CURRENT STATE:"
    $state
}

Write-Host -ForegroundColor Cyan "🚂 Starting game in slot $($state.id). Good luck!"
:gameLoop while ($true) {
    $state | Start-Scene
}
