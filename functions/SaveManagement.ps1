### Various functions for save game management

<#
.SYNOPSIS
Prompts user for a save slot, performs basic validation, and returns that value
#>
function Get-SaveSlot {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Clean,

        [Parameter()]
        [int]$Slot
    )

    # Early save initialization
    if ($Clean) {
        $saveInput = 'D'
    } elseif ($Slot) {
        $saveInput = $Slot
    } else {
        $saveInput = Read-Host -Prompt 'Select desired save slot (integer only; use 0 for next available, leave blank or use A for autosave, or use D to delete all saves)'
    }
    try {
        if ([string]::IsNullOrWhiteSpace($saveInput)) { $saveInput = 'A' } # blank, so autosave
        $saveSlot = [int]$saveInput
        if ($saveSlot -lt 1) {
            # was empty or the user entered a negative number to be cheeky
            $saveSlot = 0
            Write-Host 'Will create new save in next valid slot'
        } else {
            Write-Host "Using slot $saveSlot"
        }
    } catch {
        if ($saveInput -eq 'D') {
            if ($Clean) {
                $confirmation = 'Y'
            } else {
                $confirmation = Read-Host 'Really delete all saves? (Y to confirm)'
            }
            if ($confirmation -eq 'Y') {
                Remove-Save -All
                return 0
            }
        }
        if ($saveInput -eq 'A') {
            return -1
        }
        throw "Invalid slot $saveInput - exiting"
    }

    return $saveSlot
}

<#
.SYNOPSIS
Loads a saved game, optionally creating it if it doesn't exist. Returns game state object.
#>
function Import-Save {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Slot,

        [Parameter()]
        [switch]$CreateIfNotPresent
    )

    # vars
    if ($Slot -eq -1) {
        $savePath = "$PSScriptRoot/../saves/auto.save"
    } else {
        $savePath = "$PSScriptRoot/../saves/$Slot.save"
    }

    # Sanity check to make sure the dir exists
    if (-not (Test-Path "$PSScriptRoot/../saves")) {
        Write-Host 'Save directory does not exist; creating it'
        New-Item -Path "$PSScriptRoot/../saves" -ItemType Directory
    }

    if ((Test-Path $savePath) -and ($Slot -ne 0)) {
        # exists, load it
        $state = Get-Content -Raw -Path $savePath | ConvertFrom-Json -AsHashtable
        # fix collection types for the state if needed (imports from json as arrays, but we need arraylists for add/remove operations)
        Convert-AllChildArraysToArrayLists -Data $state

        return $state
    } elseif ($CreateIfNotPresent -and $savePath -notlike '*auto*') {
        # does not; create it
        return New-Save -Slot $Slot
    } else {
        throw "No save exists in slot $Slot"
    }
}

<#
.SYNOPSIS
Writes a save game to its file
#>
function Save-Game {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter()]
        [int]$Slot
    )

    if ($Slot) {
        if ($Slot -ne $State.id) {
            Write-Host -ForegroundColor Yellow "🔀 Changing save slot to $($Slot)"
        }
        $State.id = $Slot
    }

    $State.lastSaved = Get-Date
    $State | ConvertTo-Json -Compress -Depth 99 | Out-File -FilePath "$PSScriptRoot/../saves/$($State.id).save"
    Write-Host -ForegroundColor Cyan "✅📝 Saved to slot $($State.id)!"
    $State | Invoke-AutoSave -Quiet # keep the autosave synced up with the manual one
}

<#
.SYNOPSIS
Autosaves the game if autosave is enabled
#>
function Invoke-AutoSave {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter()]
        [switch]$Quiet
    )

    if (-not $State.options.autosave) {
        Write-Verbose 'Autosave is disabled; not saving game'
    }

    # Write to the autosave slot
    $State.lastSaved = Get-Date
    $State | ConvertTo-Json -Compress -Depth 99 | Out-File -FilePath "$PSScriptRoot/../saves/auto.save"
    if (-not $Quiet) {
        Write-Host -ForegroundColor Cyan '✅📝 Autosaved!'
    }
}

<#
.SYNOPSIS
Interactive interface for the save system
#>
function Invoke-ManualSave {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )

    $response = Read-Host -Prompt 'Save to which slot? (number, or <enter> for auto, or anything else to cancel)'
    try { $slot = [int]$response } catch {
        # not an int
        Write-Host 'Save cancelled.'
        break
    }
    if ([string]::IsNullOrWhiteSpace($slot) -or $slot -le 0) {
        # auto (current) slot
        $State | Save-Game
    } else {
        # new slot
        $State | Save-Game -Slot $slot
    }
}

<#
.SYNOPSIS
Creates a new save game at the indicated slot, optionally overwriting existing file. Returns game state object.
#>
function New-Save {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Slot,

        [Parameter()]
        [switch]$Force
    )

    $savePath = "$PSScriptRoot/../saves/$Slot.save"

    if ($Slot -eq 0) {
        # Pick the next available instead of using the number directly
        $allSaves = Get-ChildItem "$PSScriptRoot/../saves" -Filter '*.save'
        if ($allSaves.Count -gt 999) {
            # shortcut if there are a truly absurd number of saves
            $Slot = $allSaves.Count + 1
        } else {
            $Slot = 1
        }
        do {
            Write-Debug "Testing slot $Slot for new save..."
            if (-not (Test-Path "$PSScriptRoot/../saves/$Slot.save")) {
                # Available slot; set the path
                $savePath = "$PSScriptRoot/../saves/$Slot.save"
                break
            } else {
                $Slot++
            }
        } while ($true)
    }

    # Empty skeleton structure
    Write-Host "Creating new save in slot $Slot"
    @{
        id = $Slot
        lastSaved = Get-Date
        options = @{ meta = @{ init = $false } }
        player = @{ meta = @{ init = $false } }
        party = New-Object -TypeName System.Collections.ArrayList
        game = @{ meta = @{ init = $false } }
        items = @{}
        equipment = @{}
    } | ConvertTo-Json -Compress -Depth 99 | Out-File $savePath -Force:$Force

    return Import-Save -Slot $Slot
}

<#
.SYNOPSIS
Deletes a saved game
#>
function Remove-Save {
    [CmdletBinding()]
    param (
        [Parameter(ParameterSetName = 'Single', Mandatory = $true)]
        [int]$Slot,

        [Parameter(ParameterSetName = 'All', Mandatory = $true)]
        [switch]$All
    )

    if ($All) {
        Write-Host -ForegroundColor Red "DELETING ALL SAVES"
        Remove-Item -Recurse -Path "$PSScriptRoot/../saves/*.save"
        return
    }

    $savePath = "$PSScriptRoot/../saves/$Slot.save"

    Write-Host "Removing save $Slot"
    if (Test-Path $savePath -PathType Leaf) {
        Remove-Item -Path $savePath
    } else {
        Write-Warning "No save exists at slot $Slot"
    }
}
