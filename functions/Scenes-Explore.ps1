function Start-ExploreScene {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Scene
    )

    # Vars
    $explore = $State.game.explore."$($Scene.id)"

    # player has definitely left the train
    $State.game.train.playerOnBoard = $false

    # We have to initialize if we're missing the scene data, likely because this is our first time here
    if (-not $explore) {
        $State | Initialize-ExploreScene -Scene $Scene
        $explore = $State.game.explore."$($Scene.id)" # re-set the var if it was just created
    }

    # If the player is just getting off the train, handle that
    if ($explore.location -eq $Scene.data.station.location -and $explore.depth -eq -1) {
        Write-Host ($State | Enrich-Text $Scene.data.station.leaveTrainDescription)

        # Shouldn't strictly be necessary, but just in case something weird happened, reset it.
        $State.game.explore.currentSunStrengthMultiplier = ($Scene.data.locations |
            Where-Object -Property id -EQ $Scene.data.station.location).sunStrengthMultiplier
        Write-Debug "sun strength is $($State.game.explore.currentSunStrengthMultiplier) in $($Scene.id):$($Scene.data.station.location)"

        $State | Invoke-ExploreMovement -Scene $Scene -SetDepth 0
    }

    # Main exploration loop
    while ($true) {
        $State | Show-ExploreMenu -Scene $Scene

        # Regenerate once after every exploration action, not just based on time (assume you regen slower outside of combat, I guess)
        if ($State.game.explore.blockAttribRegen -le 0) {
            $State | Invoke-AttribRegen -Character $State.player -All
        } else {
            Write-Debug "reducing attrib regen blocker (currently $($State.game.explore.blockAttribRegen)) by 1"
            $State.game.explore.blockAttribRegen -= 1
        }
    }
}

function Initialize-ExploreScene {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Scene
    )

    Write-Verbose "Initializing new explore scene $($Scene.id)"
    # Initial skeleton structure of the scene's state data
    $State.game.explore."$($Scene.id)" = @{
        location = $Scene.data.station.location
        depth = -1
        locationData = @{}
    }
    # Store this guy separately because it's needed in battle scenes too
    $State.game.explore.currentSunStrengthMultiplier = ($Scene.data.locations |
        Where-Object -Property id -EQ $Scene.data.station.location).sunStrengthMultiplier
    Write-Debug "sun strength is $($State.game.explore.currentSunStrengthMultiplier) in $($Scene.id):$($Scene.data.station.location)"

    # Add the locations
    foreach ($location in $Scene.data.locations) {
        Write-Debug "adding location $($location.id) to scene $($Scene.id)"
        $State.game.explore."$($Scene.id)".locationData."$($location.id)" = @{
            encountersCompleted = @{}
        }
    }
}

function Show-ExploreMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Scene
    )

    # Vars
    $explore = $State.game.explore."$($Scene.id)"
    $locationData = $Scene.data.locations | Where-Object -Property id -EQ $explore.location

    # Show headers
    $State | Write-GlobalTime # Always write the time header
    if ($explore.location -eq $Scene.data.station.location -and $explore.depth -eq 0) {
        # We're standing right in front of the train, so write its state
        $State | Write-TrainState -Explore
    }
    # Always write the normal exploration header
    $State | Write-ExplorationState -Scene $Scene

    # Get and write available actions
    $availableActions = New-Object -TypeName System.Collections.ArrayList(,@('Browse', 'Item', 'Equip', 'Save'))
    Write-Host "| $($availableActions[0..3] -join ' | ') |"

    if ($explore.location -eq $Scene.data.station.location -and $explore.depth -eq 0) {
        $availableActions.Add('Board Train [00:00:30]') | Out-Null
    }
    if ($explore.depth -gt 0) {
        $availableActions.Add("⏪ $($locationData.field.shallowerDescription) (`"shallower`") [$($locationData.field.travelBaseCost)]") | Out-Null
    }
    if ($explore.depth -lt $locationData.field.depth) {
        $availableActions.Add("⏩ $($locationData.field.deeperDescription) (`"deeper`") [$($locationData.field.travelBaseCost)]") | Out-Null
    }
    # This one is always available as long as the player is in the field, but it's just added later for ordering
    $availableActions.Add("⏸️ $($locationData.field.exploreHereDescription) (`"here`") [$($locationData.field.travelBaseCost)]") | Out-Null

    # Will always have at least one of these actions available, so no conditional needed
    $actionListLengthBeforeConnections = $availableActions.Count
    foreach ($actionString in $availableActions[4..($actionListLengthBeforeConnections - 1)]) {
        # These can get pretty long, so give them each their own line
        Write-Host "| $actionString |"
    }
    # Write-Host "| $($availableActions[3..($actionListLengthBeforeConnections - 1)] -join ' | ') |"

    foreach ($connection in $locationData.connections.GetEnumerator()) {
        if (
            $explore.depth -ge $connection.Value.minDepthAvailable -and
            $explore.depth -le $connection.Value.maxDepthAvailable
        ) {
            # Validate the when condition, if it has one
            if ($connection.Value.notWhen) { $splat = @{ Inverted = $true } } else { $splat = @{} }
            if (-not ($State | Test-WhenConditions -When $connection.Value.when -WhenMode $connection.Value.whenMode @splat)) {
                Write-Debug "connection $($connection.Key) does not meet its 'when' prerequisites; skipping"
                continue
            }

            # we're within this connection's depth range and its 'when' is valid (or does not exist), so add it
            Write-Debug "adding valid connection $($connection.Key) ($($connection.Key -replace '\.\d+', ''))"
            $availableActions.Add("🔀 Enter $(($Scene.data.locations | Where-Object -Property id -EQ ($connection.Key -replace '\.\d+', '')).name) (`"go:$($connection.Key)`") [$($connection.Value.travelCost)]") | Out-Null
        } else {
            Write-Debug "$($connection.Key) not valid from depth of $($explore.depth)"
        }
    }
    # We might not have any connections, so conditional-ify this
    if ($availableActions.Count -ne $actionListLengthBeforeConnections) {
        Write-Host "| $($availableActions[$actionListLengthBeforeConnections..($availableActions.Count - 1)]) |"
    } else {
        Write-Debug 'no connections available; not printing third line'
    }

    # Get choice
    $choice = $State | Read-PlayerInput -Choices $availableActions

    # Perform action
    switch ($choice) {
        'browse' {
            $State | Show-Inventory -JustBrowsing
            $State | Add-GlobalTime -Time '00:01:00'
        }
        'item' {
            $State | Show-BattleCharacterInfo -Character $State.player # to show HP, etc. for informed item use
            Write-Host ''
            $State | Invoke-SpecialItem -Attacker $State.player
            $State | Add-GlobalTime -Time '00:01:00'
        }
        'equip' {
            Write-Host ''
            $State | Invoke-SpecialEquip -Attacker $State.player
            $State | Add-GlobalTime -Time '00:01:00'
        }
        'save' {
            $State | Invoke-ManualSave
            # Block attribute regen immediately after a save. Otherwise you could cheese it by regenerating for 0 time penalty by saving repeatedly.
            $State.game.explore.blockAttribRegen += 1
        }

        { $_ -like 'board train `[*`]' } {
            Write-Host 'You climb aboard the train.'
            $explore.depth = -1
            $State.game.train.playerOnBoard = $true # Make sure they can get on board even if < 30s left
            $State | Add-GlobalTime -Time '00:00:30'
            $State | Exit-Scene -Type 'train' -Id $Scene.id
        }

        # These three handle the time cost in the helper function
        { $_ -like '*(`"deeper`") `[*`]' } {
            $State | Invoke-ExploreMovement -Scene $Scene -AddDepth 1
        }
        { $_ -like '*(`"shallower`") `[*`]' } {
            $State | Invoke-ExploreMovement -Scene $Scene -AddDepth -1
        }
        { $_ -like '*(`"here`") `[*`]' } {
            $State | Invoke-ExploreMovement -Scene $Scene -AddDepth 0
        }

        { $_ -like '*(`"go:*`") `[*`]' } {
            # Handle connections
            $newLocationId = (($choice | Select-String -Pattern '\("go:(?<id>.*)"\)').Matches.Groups | Where-Object -Property Name -EQ 'id').Value
            $State | Invoke-ExploreConnection -Scene $Scene -NewLocation $newLocationId
            # also handles the time cost in the helper function
        }

        default { Write-Warning "Invalid explore action '$choice' found in scene ID '$($Scene.id)'" }
    }
}

function Write-ExplorationState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Scene
    )

    # Vars
    $explore = $State.game.explore."$($Scene.id)"
    $locationData = $Scene.data.locations | Where-Object -Property id -EQ $explore.location

    # Write overall and time line
    Write-Host "$($Scene.badge) $($Scene.name) | " -NoNewline
    switch ($State.game.train.willDepartAt - $State.time.currentTime) {
        { $_ -gt ([timespan]'01:00:00') } { $color = 'Green'; break }
        { $_ -gt ([timespan]'00:30:00') } { $color = 'Yellow'; break }
        { $_ -gt ([timespan]'00:00:00') } { $color = 'Red'; break }
        default { $color = 'Magenta' }
    }
    if ($color -ne 'Magenta') {
        Write-Host -ForegroundColor $color "Departure: Day $($State.game.train.willDepartAt.Day), $($State.game.train.willDepartAt.TimeOfDay)"
    } else {
        $maximumGraceTime = $State.game.train.willDepartAt + (New-TimeSpan -Minutes $State.options.trainDepartureGracePeriod)
        Write-Host -ForegroundColor $color "⚠️ Last Call: Day $($maximumGraceTime.Day), $($maximumGraceTime.TimeOfDay) ⚠️"
    }

    # Write current sublocation and depth
    Write-Host "Exploring: $($locationData.name) | Depth: $($explore.depth)/$($locationData.field.depth)"

    # Write character short-status
    $State | Show-BattleCharacterInfo -Character $State.player -Short
}

function Invoke-ExploreConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Scene,

        [Parameter(Mandatory = $true)]
        [string]$NewLocation
    )

    # Vars
    $explore = $State.game.explore."$($Scene.id)"
    $locationData = $Scene.data.locations | Where-Object -Property id -EQ $explore.location
    $connectionData = $locationData.connections.$NewLocation
    $newLocationClean = ($NewLocation -replace '\.\d+', '')
    $newLocationData = $Scene.data.locations | Where-Object -Property id -EQ $newLocationClean

    # Handle cutscene, if present (usually used for first-time actions or to open one-way connections)
    if ($connectionData.cutscene) {
        if ($connectionData.cutscene.notWhen) { $splat = @{ Inverted = $true } } else { $splat = @{} }
        $shouldPlayCutscene = $State | Test-WhenConditions -When $connectionData.cutscene.when -WhenMode $connectionData.cutscene.whenMode @splat
        if ($shouldPlayCutscene) {
            Write-Debug "playing cutscene for connection to $NewLocation ($shouldPlayCutscene)"
            # Can set flags, add time, grant items, deal damage; anything a single cutscene paragraph can do, can be done here.
            # For more complicated cutscenes, use a real cutscene.
            $State | Invoke-CutsceneAction -Action $connectionData.cutscene
        } else {
            Write-Debug "cutscene for $NewLocation connection did not pass its when requirements ($shouldPlayCutscene)"
        }
    }

    # Handle time and print the travel line
    $State | Add-GlobalTime -Time $connectionData.travelCost
    Write-Host ($State | Enrich-Text $connectionData.description)

    # Move to the new location and reset depth
    Write-Debug "resetting explore location to $NewLocation ($newLocationClean) at depth $($connectionData.arrivalDepth)"
    $explore.location = $newLocationClean
    $explore.depth = $connectionData.arrivalDepth

    # update sun strength
    $State.game.explore.currentSunStrengthMultiplier = $newLocationData.sunStrengthMultiplier
    Write-Debug "sun strength is $($State.game.explore.currentSunStrengthMultiplier) in $($Scene.id):$newLocationClean"

    # Roll for an encounter
    $State | Get-ExploreEncounter -Scene $Scene
}

function Invoke-ExploreMovement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Scene,

        [Parameter(Mandatory = $true, ParameterSetName = 'Add')]
        [int]$AddDepth,

        [Parameter(Mandatory = $true, ParameterSetName = 'Set')]
        [int]$SetDepth
    )

    # Vars
    $explore = $State.game.explore."$($Scene.id)"
    $locationData = $Scene.data.locations | Where-Object -Property id -EQ $explore.location
    Write-Debug "adding: '$AddDepth' / setting: '$SetDepth' - will use $($PSCmdlet.ParameterSetName)"

    # Handle time first
    $State | Add-GlobalTime -Time $locationData.field.travelBaseCost

    # Move to the new location, if applicable
    if ($PSCmdlet.ParameterSetName -eq 'Set') {
        Write-Debug "setting depth in $($explore.location) to $SetDepth"
        $explore.depth = $SetDepth
    } elseif ($PSCmdlet.ParameterSetName -eq 'Add') {
        Write-Debug "adding $AddDepth to current depth $($explore.depth) in $($explore.location)"
        $explore.depth += $AddDepth
    } else {
        Write-Debug "depth of $($explore.depth) is unchanged in $($explore.location)"
    }

    # Roll for an encounter
    $State | Get-ExploreEncounter -Scene $Scene
}

function Get-ExploreEncounter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Scene
    )

    # Vars
    $explore = $State.game.explore."$($Scene.id)"
    $locationData = $Scene.data.locations | Where-Object -Property id -EQ $explore.location
    $encountersCompleted = $explore.locationData."$($explore.location)".encountersCompleted
    $dangerLevel = $State.game.explore.dangerLevel

    # Pre-roll if the danger level is > 0
    if ($dangerLevel -gt 0) {
        Write-Debug "rolling pre-check for danger level $dangerLevel"

        $random = Get-RandomPercent
        if ($dangerLevel -ge $random) {
            Write-Debug "triggered horror encounter with strength variant $random -> ($($random/$dangerLevel))"

            # Use the lesser one if we're < 50%, otherwise the worse one, otherwise the worst one
            if (($random/$dangerLevel) -lt 0.5) {
                $State | Exit-Scene -Type 'battle' -Path 'global' -Id 'hunting-horror-x1'
            } elseif (($random/$dangerLevel) -lt 0.75) {
                $State | Exit-Scene -Type 'battle' -Path 'global' -Id 'hunting-horror-x2'
            } else {
                $State | Exit-Scene -Type 'battle' -Path 'global' -Id 'hunting-horror-x2-nofirstturn'
            }
        } else {
            Write-Debug "no horror encounter (rolled $random)"
        }
    }

    # Clone an encounter list to roll on
    $availableEncounters = $locationData.field.encounters.Clone()

    # Skip the ones we don't meet prereqs for, then roll for each valid encounter in turn
    foreach ($encounter in $availableEncounters) {
        if ($encounter.notWhen) { $splat = @{ Inverted = $true } } else { $splat = @{} }
        if (
            ($null -ne $encounter.minDepthAvailable -and $explore.depth -lt $encounter.minDepthAvailable) -or
            ($null -ne $encounter.maxDepthAvailable -and $explore.depth -gt $encounter.maxDepthAvailable) -or
            ($null -ne $encounter.requiredPhase -and $State.time.phase -ne $encounter.requiredPhase) -or
            ($null -ne $encounter.maxTimes -and $encountersCompleted."$($encounter.id)" -ge $encounter.maxTimes) -or
            ($null -ne $encounter.when -and -not ($State | Test-WhenConditions -When $encounter.when -WhenMode $encounter.whenMode @splat))
        ) {
            Write-Debug "$($encounter.id) does not meet prereqs and will be skipped"

            # Remove it from the scene permanently(-ish; until re-imported) if a permanent prereq is not met
            # This way, future calls to this function won't have to deal with it until re-imported later
            if ($encountersCompleted."$($encounter.id)" -gt 0 -and
                $encounter.maxTimes -gt 0 -and
                $encountersCompleted."$($encounter.id)" -ge $encounter.maxTimes) {
                Write-Debug "$($encounter.id) does not meet permanent prereqs and will be removed from the scene"
                $locationData.field.encounters.Remove($encounter)
            }
        } else {
            # Valid encounter, so roll to see if it happens
            if ($encounter.chance -ge (Get-RandomPercent)) {
                Write-Debug "$($encounter.id) triggered (with chance $($encounter.chance))"
                $State | Invoke-ExploreEncounter -Scene $Scene -Encounter $encounter
                return
            } else {
                Write-Debug "$($encounter.id) was not triggered (had chance $($encounter.chance))"
            }
        }
    }

    # If we made it all the way down here, we didn't trigger any encounters. So just print a random flavor text we meet prereqs for
    $flavorTextOptions = foreach ($category in $locationData.field.flavor.GetEnumerator()) {
        if ($category.Key -in @('general', "$($explore.depth)", $State.time.phase)) {
            Write-Debug "$($category.Key) meets requirements"
            $category.Value
        }
    }

    # Print it
    Write-Host ($State | Enrich-Text ($flavorTextOptions | Get-Random))
}

function Invoke-ExploreEncounter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Scene,

        [Parameter(Mandatory = $true)]
        [hashtable]$Encounter
    )

    # Mark the encounter as complete for repeat purposes
    $encountersCompleted = $State.game.explore."$($Scene.id)".locationData."$($State.game.explore."$($Scene.id)".location)".encountersCompleted
    if ([string]::IsNullOrEmpty($encountersCompleted."$($Encounter.id)")) {
        Write-Debug "setting encounters completed to 1 for $($Encounter.id) in $($Scene.id)/$($State.game.explore."$($Scene.id)".location)"
        $encountersCompleted."$($Encounter.id)" = 1
    } else {
        Write-Debug "adding 1 to encounters completed (currently '$($encountersCompleted."$($Encounter.id)")') for $($Encounter.id) in $($Scene.id)/$($State.game.explore."$($Scene.id)".location)"
        $encountersCompleted."$($Encounter.id)" += 1
    }

    # Perform the scene transition
    switch ($Encounter.type) {
        { $_ -match 'battle|cutscene|train|explore' } {
            $State | Exit-Scene -Type $Encounter.type -Id $Encounter.id
        }
        'item' {
            # Found an item; print the text provided (if any) and add the item. Anything more complex than this should be a cutscene.
            if ($Encounter.text) { Write-Host ($State | Enrich-Text $Encounter.text) } else {
                Write-Host 'You find an item in your exploration.' # kind of a weak default, but all of these should have some sort of text
            }

            # Randomly get the number if provided with bounds, otherwise use the direct number. Otherwise, 1.
            $number = if ($Encounter.number) {
                Write-Debug "Adding exactly $($Encounter.number)x $($Encounter.id)"
                $Encounter.number
            } elseif ($Encounter.minAmount -and $Encounter.maxAmount) {
                Write-Debug "Randomly generating number of $($Encounter.id) to add between $($Encounter.minAmount) and $($Encounter.maxAmount)"
                Get-Random -Minimum $Encounter.minAmount -Maximum ($Encounter.maxAmount + 1)
            } else {
                1
            }

            # Remove if specified, otherwise add.
            if ($Encounter.mode -eq 'remove') {
                Write-Debug "Removing ${number}x $($Encounter.id)"
                $State | Remove-GameItem -Id $Encounter.id -Number $number -StolenBy $Encounter.removeActor
            } else {
                Write-Debug "Adding ${number}x $($Encounter.id)"
                $State | Add-GameItem -Id $Encounter.id -Number $number
            }

            # Require an <enter> to keep going, then save.
            Read-Host -Prompt '> '
            $State | Save-Game -Auto
        }
        default { Write-Warning "Invalid encounter type '$_' found in explore scene ID $($Scene.id)" }
    }
}
