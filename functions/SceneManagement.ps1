### Various functions for scene management

<#
.SYNOPSIS
Determines current scene ID and type, loads it, and hands off to that scene's specialized handler.
#>
function Start-Scene {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )

    # Vars
    $sceneTypesThatUsePath = @('battle', 'cutscene') # only some of them use path; others are all top-level
    $type = $State.game.scene.type
    $path = $State.game.scene.path
    $id = $State.game.scene.id

    # Try to get the scene data and offer a recovery option if unsuccessful
    try {
        if ($type -in $sceneTypesThatUsePath) {
            Write-Verbose "Loading scene ${type}:$path/$id..."
            $scene = $State.data.scenes.$type.$path.$id
        } else {
            Write-Verbose "Loading scene ${type}:$id..."
            $scene = $State.data.scenes.$type.$id
        }
        Convert-AllChildArraysToArrayLists -Data $scene # some scenes don't need this treatment, but some do
    } catch {
        # cut off an attempt to re-open a closed game
        if ($type -eq 'end') {
            Write-Debug 'caught attempt to load ended game; re-exiting'
            $State | Exit-Scene -Type $type -Id $id
        }

        # otherwise, this is a real error
        Write-Warning "Invalid scene data (${type}:$path/$id) failed to load with inner error '$_'"
        $response = Read-Host -Prompt 'Would you like to forcibly reset this save to the train? (Y/N)'
        if ($response -eq 'Y') {
            # Make sure the train exists first
            if (-not (Test-Path "$PSScriptRoot/../data/scenes/train/train.json")) {
                Write-Host -ForegroundColor Red "❌ Unable to locate the train! (Looked in $PSScriptRoot/../data/scenes/train/train.json) Cannot continue. Exiting."
                throw "Invalid scene data (${type}:$path/$id) failed to load with inner error '$_'"
            }

            # Put the player back in the train, which is proven to exist in the check above
            $State.game.scene.type = 'train'
            $State.game.scene.path = 'global'
            $State.game.scene.id = 'train'
            $State.game.train.playerOnBoard = $true
            $State | Save-Game
            Write-Host -ForegroundColor Green '✅ Reset save to the train.'
            return
        } else {
            # give up ¯\(°_o)/¯
            Write-Host -ForegroundColor Red '❌ Scene data invalid; cannot continue. Exiting.'
            throw "Invalid scene data (${type}:$path/$id) failed to load with inner error '$_'"
        }
    }

    if ($DebugPreference -eq 'Continue') {
        Write-Debug "DUMPING CURRENT SCENE:"
        $scene
    }

    # Start the actual scene
    switch ($type) {
        'battle' { $State | Start-BattleScene -Scene $scene }
        'cutscene' { $State | Start-CutsceneScene -Scene $scene }
        'tutorial' { $State | Start-CutsceneScene -Scene $scene }
        'explore' { $State | Start-ExploreScene -Scene $scene }
        'train' { $State | Start-TrainScene -Scene $scene }
    }
}

<#
.SYNOPSIS
Helper function to set the next scene and return to the main game loop once the current scene concludes. Also includes the autosave functionality.
#>
function Exit-Scene {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter()]
        [string]$Type,

        # Path to load the scene from, with a 2x fallback if not defined (in actual logic, not here).
        [Parameter()]
        [string]$Path,

        [Parameter()]
        [string]$Id
    )

    # First, the current station. Then, check in 'global' if we don't have a station. (Need to do this here instead of in params so $State exists)
    $Path = [string]::IsNullOrEmpty($Path) ? ($State.game.train.lastStation ?? 'global') : $Path

    if ([string]::IsNullOrEmpty($Type) -and [string]::IsNullOrEmpty($Id)) {
        Write-Debug 'no type or ID passed; returning to previous scene'
        $Type = $State.game.scene.previousType
        $Path = $State.game.scene.previousPath
        $Id = $State.game.scene.previousId
    }
    # If we didn't have a previous scene (due to "problems"), Start-Scene will allow the player to reset to the train later, so it's still okay.

    # Clear battle data if it exists (don't need it anymore if we just left the scene)
    if ($State.options.clearBattleDataOnExit -and $State.game.battle.phase) {
        Write-Debug 'clearing battle data'
        $State.game.battle = @{}
    }

    Write-Verbose "Exiting to new scene ${Type}:$Path/$Id"
    $State.game.scene.previousType = $State.game.scene.type
    $State.game.scene.previousPath = $State.game.scene.path
    $State.game.scene.previousId = $State.game.scene.id
    Write-Debug "(previous scene data set to $($State.game.scene.previousType):$($State.game.scene.previousPath)/$($State.game.scene.previousId))"
    $State.game.scene.type = $Type
    $State.game.scene.path = $Path
    $State.game.scene.id = $Id

    $State | Save-Game -Auto

    # Escape hatch to actually end the game
    if ($Type -eq 'end') {
        if ($Id -eq 'bad') {
            Write-Host -ForegroundColor DarkRed '💀 BAD END 💀'
        } elseif ($Id -eq 'good') {
            Write-Host -ForegroundColor DarkGreen '🌌 GOOD END 🌌'
        } else {
            # neutral end?
            Write-Host 'Game Over...'
        }
        break gameLoop
    }

    # Immediately end current scene to allow game to start the next one
    continue gameLoop
}
