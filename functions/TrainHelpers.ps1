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
            Write-Debug "$now >= departure time of $departureTime - train is departing"
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
        [object]$State
    )

    # Vars
    $train = $State.game.train

    # If player is not on board, game over and short-circuit the rest of this stuff
    if (-not $train.playerOnBoard) {
        $State | Exit-Scene -Type 'cutscene' -Id 'gameover-leftbehind'
    }

    # Load scene data from the station we just left to get available stations and such
    $scene = Get-Content "$PSScriptRoot/../data/scenes/train/$($train.lastStation).json" | ConvertFrom-Json -AsHashtable
    $train.availableStations = $scene.data.availableStations
    $train.lastStationName = $scene.name

    # Update state
    $train.stopped = $false
    $train.lastDepartedAt = $train.willDepartAt
    $train.willDepartAt = $null
    $train.stationDecisionPoint = $train.lastDepartedAt.Add([timespan]$scene.data.decisionTime)

    Write-Host -ForegroundColor Cyan "🚂 The train has departed $($scene.name)."
    $State | Invoke-AutoSave
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
    $State | Invoke-AutoSave
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
