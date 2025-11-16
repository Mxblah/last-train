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
        $saveSlot = [int]$saveInput # throws if we have a letter
        if ($saveSlot -lt 1) {
            # was zero or the user entered a negative number to be cheeky
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
        [switch]$CreateIfNotPresent,

        [Parameter()]
        [string]$SavesRoot = "$PSScriptRoot/../saves"
    )

    # vars
    if ($Slot -eq -1) {
        $savePath = Join-Path -Path $SavesRoot -ChildPath 'auto.save'
    } else {
        $savePath = Join-Path -Path $SavesRoot -ChildPath "$Slot.save"
    }

    # Sanity check to make sure the dir exists
    if (-not (Test-Path $SavesRoot)) {
        Write-Host 'Save directory does not exist; creating it'
        New-Item -Path $SavesRoot -ItemType Directory | Out-Null
    }

    if ((Test-Path $savePath) -and ($Slot -ne 0)) {
        # exists, load it
        Write-Host -ForegroundColor Cyan "📚 Loading save data for slot $Slot"
        $state = Get-Content -Raw -Path $savePath | ConvertFrom-Json -AsHashtable
        # fix collection types for the state if needed (imports from json as arrays, but we need arraylists for add/remove operations)
        Convert-AllChildArraysToArrayLists -Data $state

        # Import game data now that the save is set up
        $state | Import-GameData -TimeStats

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
Writes a save game to its file. Also handles autosaving and the logic for that.
#>
function Save-Game {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter()]
        [int]$Slot,

        [Parameter()]
        [string]$SavesRoot = "$PSScriptRoot/../saves",

        [Parameter()]
        [switch]$Auto
    )

    if ($Slot) {
        if ($Slot -ne $State.id) {
            Write-Host -ForegroundColor Yellow "🔀 Changing save slot to $($Slot)"
        }
        $State.id = $Slot
    }

    # Temporarily offload the game data portion; we don't need to save that
    $dataExport = $State.data
    $State.Remove('data')

    # Save the game
    $State.lastSaved = Get-Date
    if (-not $Auto) {
        # Manual save
        $manualPath = Join-Path -Path $SavesRoot -ChildPath "$($State.id).save"
        $State | ConvertTo-Json -Compress -Depth 99 | Out-File -FilePath $manualPath
        Write-Host -ForegroundColor Cyan "✅📝 Saved to slot $($State.id)!"
    }

    # Keep the autosave synced up with the manual one, or just do autosave if $Auto
    if ($State.options.autosave) {
        $autoPath = Join-Path -Path $SavesRoot -ChildPath 'auto.save'
        $State | ConvertTo-Json -Compress -Depth 99 | Out-File -FilePath $autoPath
        if ($Auto) { Write-Host -ForegroundColor Cyan '✅📝 Autosaved!' }
    } else {
        Write-Verbose 'Autosave is disabled; not auto-saving game'
    }

    # Restore the offloaded game data
    $State.data = $dataExport
}

<#
.SYNOPSIS
Interactive interface for the save system
#>
function Invoke-ManualSave {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter()]
        [string]$SavesRoot = "$PSScriptRoot/../saves"
    )

    $response = Read-Host -Prompt 'Save to which slot? (number, or <enter> for current slot, or anything else to cancel)'
    try { $slot = [int]$response } catch {
        # not an int
        Write-Host 'Save cancelled.'
        break
    }
    if ([string]::IsNullOrWhiteSpace($slot) -or $slot -le 0) {
        # auto (current) slot
        $State | Save-Game -SavesRoot $SavesRoot
    } else {
        # new slot
        $State | Save-Game -Slot $slot -SavesRoot $SavesRoot
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
        [switch]$Force,

        [Parameter()]
        [string]$SavesRoot = "$PSScriptRoot/../saves"
    )

    $savePath = Join-Path -Path $SavesRoot -ChildPath "$Slot.save"

    if ($Slot -eq 0) {
        # Pick the next available instead of using the number directly
        $allSaves = Get-ChildItem -Path $SavesRoot -Filter '*.save'
        if ($allSaves.Count -gt 999) {
            # shortcut if there are a truly absurd number of saves
            $Slot = $allSaves.Count + 1
        } else {
            $Slot = 1
        }
        do {
            Write-Debug "Testing slot $Slot for new save..."
            if (-not (Test-Path (Join-Path -Path $SavesRoot -ChildPath "$Slot.save"))) {
                # Available slot; set the path
                $savePath = Join-Path -Path $SavesRoot -ChildPath "$Slot.save"
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
    } | ConvertTo-Json -Compress -Depth 99 | Out-File $savePath -Encoding ascii -Force:$Force

    return Import-Save -Slot $Slot -SavesRoot $SavesRoot
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
        [switch]$All,

        [Parameter()]
        [string]$SavesRoot = "$PSScriptRoot/../saves"
    )

    if ($All) {
        Write-Host -ForegroundColor Red "DELETING ALL SAVES"
        $pattern = Join-Path -Path $SavesRoot -ChildPath '*.save'
        Remove-Item -Recurse -Path $pattern
        return
    }

    $savePath = Join-Path -Path $SavesRoot -ChildPath "$Slot.save"

    Write-Host "Removing save $Slot"
    if (Test-Path $savePath -PathType Leaf) {
        Remove-Item -Path $savePath
    } else {
        Write-Warning "No save exists at slot $Slot"
    }
}
