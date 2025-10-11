# Function that should be called when adding or setting time, in order to keep the train state in sync with time
function Update-TrainState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )

    # Vars
    $now = $State.time.currentTime
    $stopped = $State.game.train.stopped
    $departureTime = $State.game.train.willDepartAt
    $arrivalTime = $State.game.train.willArriveAt
    $decideTime = $State.game.train.stationDecisionPoint

    # Handle train departure
    if ($null -ne $departureTime -and $now -ge $departureTime) {
        if ($stopped) {
            # We're stopped at a station and due to depart, so do that
            Write-Debug "$now >= departure time of $departureTime - train is attempting to depart"
            $State | Invoke-TrainDeparture
        } else {
            # Departure time is stuck or something; clear it
            Write-Warning "train is scheduled to depart but not at a station; clearing departure time of $departureTime"
            $State.game.train.willDepartAt = $null
        }
    }

    # Handle train arrival
    if ($null -ne $arrivalTime -and $now -ge $arrivalTime) {
        if (-not $stopped) {
            # We're traveling and due to arrive, so do that
            Write-Debug "$now >= arrival time of $arrivalTime - train is stopping"
            $State | Invoke-TrainArrival
        } else {
            # Arrival time is stuck or something; clear it
            Write-Warning "train is scheduled to arrive but not traveling; clearing arrival time of $arrivalTime"
            $State.game.train.willArriveAt = $null
        }
    }

    # Handle train decision point
    if ($null -ne $decideTime -and $now -ge $decideTime) {
        Write-Debug "$now >= decide time of $decideTime - making decision"
        $State | Invoke-TrainDecisionPoint
    }
}

function Write-TrainState {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        # Only show information relevant for explore scenes
        [Parameter()]
        [switch]$Explore
    )

    # Vars
    $train = $State.game.train

    if ($train.stopped) {
        if ($null -ne $train.willDepartAt -and ($train.willDepartAt - $State.time.currentTime) -le [timespan]'00:30:00' ) {
            # close to departure
            $color = 'Red'
            Write-Host -ForegroundColor $color 'The train rumbles as it prepares for departure.'
        } elseif ($null -ne $train.lastArrivedAt -and ($State.time.currentTime - $train.lastArrivedAt) -le [timespan]'00:15:00') {
            # just arrived
            $color = 'Green'
            Write-Host -ForegroundColor $color 'The train hisses and cools as the locomotive powers down.'
        } else {
            # far from departure
            $color = 'Yellow'
            Write-Host -ForegroundColor $color 'The train rests idle at the platform.'
        }
        if (-not $Explore) {
            Write-Host "🚉 Stopped at: $($train.lastStationName) | " -NoNewline
            Write-Host -ForegroundColor $color "Departure: Day $($train.willDepartAt.Day), $($train.willDepartAt.TimeOfDay)."
        }
    } else {
        if ($null -ne $train.willArriveAt -and ($train.willArriveAt - $State.time.currentTime) -le [timespan]'00:10:00') {
            # close to arrival
            Write-Host -ForegroundColor DarkYellow ' The train slows as it approaches the station.'
        } elseif (($State.time.currentTime - $train.lastDepartedAt) -le [timespan]'00:10:00') {
            # close to last departure
            Write-Host -ForegroundColor DarkYellow 'The train accelerates as it leaves the station.'
        } else {
            # in transit somewhere
            Write-Host -ForegroundColor Yellow 'The train speeds along its tracks at a rapid pace.'
        }
        if ($train.nextStationName) {
            Write-Host "🚂 Traveling to: $($train.nextStationName) | " -NoNewline
            Write-Host -ForegroundColor Green "Arrival: Day $($train.willArriveAt.Day), $($train.willArriveAt.TimeOfDay)."
        } else {
            Write-Host "🚂 Traveling from: $($train.lastStationName) | " -NoNewline
            Write-Host -ForegroundColor Red "Decide by: Day $($train.stationDecisionPoint.Day), $($train.stationDecisionPoint.TimeOfDay)."
        }
    }
}

function Invoke-TrainDeparture {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter()]
        [switch]$EarlyDeparture
    )

    # Vars
    $train = $State.game.train
    $now = $State.time.currentTime
    $departureTime = $State.game.train.willDepartAt
    $maximumGraceTime = $departureTime + (New-TimeSpan -Minutes $State.options.trainDepartureGracePeriod)

    # If player is not on board, check the time and game over if it's too late
    if (-not $train.playerOnBoard) {
        if ($now -gt $maximumGraceTime) {
            # We're beyond the grace period, so the train departs without the player. Game over.
            $State | Exit-Scene -Type 'cutscene' -Id 'gameover-leftbehind'
        } else {
            # We're within the grace period, so update the danger level
            $State | Update-TrainDangerLevel
            return
        }
    }
    # Otherwise, the player is on board, so we're ready to depart. Handle that.

    # Load scene data from the station we just left to get available stations and such
    $scene = Get-Content "$PSScriptRoot/../data/scenes/train/$($train.lastStation).json" | ConvertFrom-Json -AsHashtable
    $train.availableStations = $scene.data.availableStations
    $train.lastStationName = $scene.name

    # Update state
    $train.stopped = $false
    # If we boarded before last call and didn't depart early, use the scheduled departure time. Otherwise, use now, which is whenever the player boarded or chose to depart.
    $train.lastDepartedAt = $State.game.explore.dangerLevel -gt 0 -or $EarlyDeparture ? $now : $train.willDepartAt
    $train.willDepartAt = $null
    $train.stationDecisionPoint = $train.lastDepartedAt.Add([timespan]$scene.data.decisionTime)
    $State | Update-TrainDangerLevel -Clear

    Write-Host -ForegroundColor Cyan "🚂 The train has departed $($scene.name)."
    $State | Save-Game -Auto
}

function Invoke-TrainArrival {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )

    # Vars
    $train = $State.game.train

    # load scene data from nextStation
    $scene = Get-Content "$PSScriptRoot/../data/scenes/train/$($train.nextStation).json" | ConvertFrom-Json -AsHashtable
    $train.availableStations = $scene.data.availableStations
    $train.nextStationName = $scene.name

    # Update state
    $train.stopped = $true
    $train.lastArrivedAt = $train.willArriveAt
    $train.willArriveAt = $null

    # We've arrived somewhere new, so set the next station to the last station and clear the decision point
    $train.lastStation = $train.nextStation
    $train.lastStationName = $train.nextStationName
    $train.nextStation = $null
    $train.nextStationName = $null
    $train.stationDecisionPoint = $null

    # Need to set departure time and the new decision point
    $desiredDepartureTime = $train.lastArrivedAt.Add([timespan]$scene.data.dwellTime)
    if ($desiredDepartureTime -lt $State.time.currentTime) {
        # Desired departure time is in the past - whoops! It'll depart ASAP whenever time next advances, so just warn of that
        Write-Debug "departure is in the past: will depart at $desiredDepartureTime or ASAP once time updates!"
        Write-Warning "The train is overdue (supposed to depart at Day $($desiredDepartureTime.Day, $desiredDepartureTime.TimeOfDay)) and will depart imminently!"
    } else {
        # it's in the future; we're good
        Write-Debug "setting train departure time to $desiredDepartureTime"
        $train.willDepartAt = $desiredDepartureTime
    }
    Write-Debug "setting decision point based on departure time of $($train.willDepartAt) and decision time of $($scene.data.decisionTime)"
    $train.stationDecisionPoint = $train.willDepartAt.Add([timespan]$scene.data.decisionTime)

    Write-Host -ForegroundColor Cyan "🚉 The train has arrived at $($scene.name)."
    $State | Save-Game -Auto
}

function Show-TrainDecisionMenu {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )

    # Vars
    $train = $State.game.train
    $availableStations = $train.availableStations

    # Write the options
    Write-Host 'Where will you direct the train to go?'
    Write-Host '|' -NoNewline
    $nameIdMap = @{}
    $choices = foreach ($station in $availableStations.GetEnumerator()) {
        $data = Get-Content -Path "$PSScriptRoot/../data/scenes/train/$($station.Key).json" | ConvertFrom-Json -AsHashtable
        Write-Host " $($data.name) |" -NoNewline
        $data.name
        $nameIdMap."$($data.name)" = $data.id
    }
    Write-Host ''

    # Get the choice and set the result
    $choice = $State | Read-PlayerInput -Choices $choices -AllowNullChoice
    if ($null -eq $choice) {
        Write-Host 'You changed your mind...'
    } else {
        Write-Host "You set the train's next destination to $($choice)."
        $train.nextStation = $nameIdMap.$choice
        $train.nextStationName = $choice
        Write-Debug "set next station to $($train.nextStation)"
        Write-Debug "calculating arrival time based on departure of $($train.lastDepartedAt) and travel time of $($availableStations."$($train.nextStation)".travelTime)"
        $train.willArriveAt = $train.lastDepartedAt.Add([timespan]$availableStations."$($train.nextStation)".travelTime)
    }
    $State | Add-GlobalTime -Time '00:00:30'
}

function Invoke-TrainDecisionPoint {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )

    # Vars
    $train = $State.game.train

    # If we don't already have a decision made, make one
    if ($null -eq $train.nextStation) {
        $train.nextStation = $train.availableStations.Keys | Get-Random
        Write-Debug "station not selected, so chose $($train.nextStation) randomly. Gathering scene data..."
        $nextStationData = Get-Content -Path "$PSScriptRoot/../data/scenes/train/$($train.nextStation).json" | ConvertFrom-Json -AsHashtable
        $train.nextStationName = $nextStationData.name
        Write-Host 'The train selected its next station without your input.'

        # Update arrival time based on departure + travel time
        Write-Debug "calculating arrival time based on departure of $($train.lastDepartedAt) and travel time of $($train.availableStations."$($train.nextStation)".travelTime)"
        $train.willArriveAt = $train.lastDepartedAt.Add([timespan]$train.availableStations."$($train.nextStation)".travelTime)
    }

    # Clear the decision point so we can't change the decision any more (and so we stop calling this function)
    $train.stationDecisionPoint = $null

    if ($State.time.currentTime -ge $train.willArriveAt) {
        # whoops, it's in the past! Not sure how this happened, so warp us there immediately.
        Write-Warning "Train arrival time of $($train.willArriveAt) is in the past! Immediately warping to the next station of $($train.nextStation)!"
        $State | Invoke-TrainArrival
    } else {
        Write-Debug "train's arrival time is $($train.willArriveAt) at $($train.nextStation)"
        Write-Host -ForegroundColor Cyan "🛤️ The train's next destination is now locked in..."
    }
}

function Update-TrainDangerLevel {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        # Zero out the current danger level (used when properly departing to the next station)
        [Parameter()]
        [switch]$Clear
    )

    # Vars
    $now = $State.time.currentTime
    $departureTime = $State.game.train.willDepartAt
    $currentDangerLevel = $State.game.explore.dangerLevel

    # Zero it
    if ($Clear) {
        Write-Verbose "clearing current danger level of $($State.game.explore.dangerLevel)"
        $State.game.explore.dangerLevel = $null
        return
    }

    # Not past departure time, so nothing to do
    if ($now -le $departureTime) {
        Write-Debug "current time ($now) <= departure time of $departureTime - not updating danger level"
        return
    }

    # It's past the departure time, so update the danger level
    try {
        $percentageOfGraceTime = ( $now - $departureTime ).TotalMinutes / $State.options.trainDepartureGracePeriod
    } catch {
        # probably a divide-by-zero error, although that should be caught earlier, in Invoke-TrainDeparture
        $percentageOfGraceTime = 1
    }
    Write-Debug "have spent $($percentageOfGraceTime * 100)% of grace time so far"
    switch ($percentageOfGraceTime) {
        { $_ -le 0.15 } { $newDangerLevel = 0.01; $message = "⚠️ A short blast from the train's horn signals it's time to depart. You will be hunted if you stay any longer."; break }
        { $_ -le 0.30 } { $newDangerLevel = 0.05; $message = '⚠️ Ominous clicking echoes from an indistinct point in the distance. The horrors are here and searching for you.'; break }
        { $_ -le 0.45 } { $newDangerLevel = 0.1; $message = "💀 The train sounds its horn again, melancholy and low. It's a small miracle you've survived so long, but you need to leave, immediately."; break }
        { $_ -le 0.60 } { $newDangerLevel = 0.2; $message = '💀 Clicking sounds carry through the air almost nonstop now. The horrors are very close.'; break }
        { $_ -le 0.85 } { $newDangerLevel = 0.3; $message = "💀 Nearby shadows ripple with ominous red light. You're almost out of time."; break }
        { $_ -le 1 } { $newDangerLevel = 0.4; $message = '‼️ The train blasts its horn in an urgent peal. Get back to the station now, before it leaves you behind!'; break }
        default { $newDangerLevel = 0.5; $message = '🚂 With a hiss of brakes, the train departs. Hunting horrors crawl and writhe nearby. You have failed.' }
    }

    # Modify by difficulty
    Write-Debug "selected new danger level $newDangerLevel"
    $newDangerLevel *= ($State.options.difficulty / 2)
    Write-Debug "modified by difficulty, is $newDangerLevel"

    # If this isn't a change, we're done
    if ($newDangerLevel -eq $currentDangerLevel) {
        Write-Debug 'no change of danger level; exiting'
        return
    }

    # There is a change, so set the new level and print a warning
    $State.game.explore.dangerLevel = $newDangerLevel
    Write-Host ''
    Write-Host -ForegroundColor Magenta $message
    Write-Host ''
}
