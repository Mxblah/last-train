# why did I write this in powershell?
# good question

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Clean,

    [Parameter()]
    [ValidatePattern('^[^:\s]+:[^:\s]+$')]
    [string]$SceneOverride,

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
    $state.cheater = $true
    foreach ($cheat in $Cheats) {
        switch ($cheat) {
            'bullseye' {
                Write-Host -ForegroundColor Cyan "CHEAT: 🎯 Set player accuracy to 999999"
                $state.player.stats.acc.base = 999999
            }
            'def' {
                Write-Host -ForegroundColor Cyan "CHEAT: 🛡️ Set player defenses to 999999"
                $state.player.stats.pDef.base = 999999; $state.player.stats.mDef.base = 999999
            }
            'healthy' {
                Write-Host -ForegroundColor Cyan "CHEAT: ❤️ Set player HP to 999999"
                $state.player.attrib.hp.base = 999999; $state.player.attrib.hp.value = 999999
            }
            'speedy' {
                Write-Host -ForegroundColor Cyan "CHEAT: 👟 Set player speed to 999999"
                $state.player.stats.spd.base = 999999
            }
            'onboard' {
                Write-Host -ForegroundColor Cyan "CHEAT: 🚂 Forcing player to board the train"
                $state.game.train.playerOnBoard = $true
            }
            { $null -ne $_.items } {
                Write-Host -ForegroundColor Cyan "CHEAT: 🛒 Adding extra items"
                foreach ($item in $_.items) {
                    $state | Add-GameItem -Id $item.id -Number ($item.number ?? 1)
                }
            }
            default { Write-Warning "unknown cheat $cheat - ignoring" }
        }
    }
}

# Update now that all the init is done
$State | Update-CharacterValues -Character $State.player

if ($SceneOverride) {
    Write-Host -ForegroundColor Cyan "🔐 Setting current scene to $SceneOverride"
    $state.game.scene.type = $SceneOverride.Split(':')[0]
    $state.game.scene.id = $SceneOverride.Split(':')[1]
}

# post-init debug dumper
if ($DebugPreference -eq 'Continue') {
    Write-Debug "DUMPING CURRENT STATE:"
    $state
}

Write-Host -ForegroundColor Cyan "🚂 Starting game in slot $($state.id). Good luck!"
:gameLoop while ($true) {
    $state | Start-Scene
}
