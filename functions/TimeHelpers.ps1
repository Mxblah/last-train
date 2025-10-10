function Set-GlobalTime {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter()]
        [datetime]$GameStartTime = [datetime]'2028-10-01 06:00:00',

        [Parameter()]
        [datetime]$CurrentTime = [datetime]'2028-10-01 06:00:00',

        [Parameter()]
        [switch]$OverwriteStartTime
    )

    # Create if not present
    if ($null -eq $State.time) {
        Write-Debug 'creating time map in state'
        $State.time = @{
            meta = @{
                init = $false
            }
        }
    }

    # Set time
    if ($null -eq $State.time.startTime -or $OverwriteStartTime) {
        Write-Debug "Initializing start time to $GameStartTime"
        $State.time.meta.init = $true
        $State.time.startTime = $GameStartTime
        # don't need to set the phase here as it'll get set just below
    }
    $State.time.currentTime = $CurrentTime
    $State.time.phase = ConvertTo-DayPhase -DateTime $CurrentTime
    Write-Debug "Set current time to $CurrentTime (phase: $($State.time.phase))"
    $State | Update-TrainState
}

function Add-GlobalTime {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [timespan]$Time,

        [Parameter()]
        [switch]$NoSunDamage
    )

    # Add time
    Write-Debug "modifying global clock by $Time (currently $($State.time.currentTime))"
    $State.time.currentTime += $Time

    # Update day phase
    $State.time.phase = ConvertTo-DayPhase -DateTime $State.time.currentTime
    Write-Debug "now $($State.time.currentTime) - $($State.time.phase)"

    # If we're not in battle, apply and clear status effects
    if ($State.game.scene.type -ne 'battle' -and ($State.player.status.Count -gt 0 -or $State.party.status.Count -gt 0)) {
        $turns = [System.Math]::Min(($Time.TotalSeconds / 10), 10) # don't go on forever
        Write-Debug "applying party statuses for $turns turns due to time advancing"
        foreach ($turn in 1..$turns) {
            # In theory, all statuses reduce their stacks on either turnStart or turnEnd, and almost all are < 10 turn durations, so we should clear them with this loop
            $State | Apply-StatusEffects -Character $State.player -Phase 'turnStart'
            $State | Apply-StatusEffects -Character $State.player -Phase 'turnEnd'
            foreach ($ally in $State.party) {
                $State | Apply-StatusEffects -Character $ally -Phase 'turnStart'
                $State | Apply-StatusEffects -Character $ally -Phase 'turnEnd'
            }
            if ($State.player.status.Count -le 0 -and $State.party.status.Count -le 0) {
                Write-Debug "Out of statuses on turn $turn - stopping!"
                Write-Host -ForegroundColor DarkCyan '🧼 Your statuses have cleared.'
                break
            }
        }

        # If we didn't, clear them anyway (player only)
        if ($State.player.status.Count -gt 0 -and $turns -ge 10) {
            Write-Debug "clearing all player statuses due to having spent at least $turns turns out of battle on them"
            $State | Clear-AllStatusEffects -Character $State.player
            Write-Host -ForegroundColor DarkCyan '🧼 Your statuses have cleared.'
        }
        Write-Host ''
    }

    # Handle train and solar damage
    $State | Update-TrainState
    if ($NoSunDamage) {
        Write-Debug 'skipping sun damage'
    } else {
        $State | Apply-SunDamage -Time $Time
    }
}

function Write-GlobalTime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter()]
        [switch]$NoNewline
    )
    # helper var
    $time = $State.time.currentTime

    # Determine what badge and color to display based on time of day
    switch ($time) {
        { $_.TimeOfDay -ge [timespan]'18:30:00' } { $badge = '🌙'; $color = 'Blue'; break }
        { $_.TimeOfDay -ge [timespan]'18:00:00' } { $badge = '🌅'; $color = 'Yellow'; break }
        { $_.TimeOfDay -ge [timespan]'06:30:00' } { $badge = '☀️'; $color = 'Red'; break }
        { $_.TimeOfDay -ge [timespan]'06:00:00' } { $badge = '🌄'; $color = 'Yellow'; break }
        default { $badge = '🌙'; $color = 'Blue' } # earlier than 6am: dark
    }
    $phase = ConvertTo-DayPhase -DateTime $time

    Write-Host -ForegroundColor $color "$badge Day $($time.Day), $($time.TimeOfDay) | $($phase)" -NoNewline:$NoNewline
}

function ConvertTo-DayPhase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'DateTime', ValueFromPipeline)]
        [datetime]$DateTime,

        [Parameter(Mandatory = $true, ParameterSetName = 'TimeSpan', ValueFromPipeline)]
        [timespan]$Time
    )

    # Convert datetime to timespan
    if ($DateTime) {
        $Time = $DateTime.TimeOfDay
    }

    switch ($Time) {
        { $_ -ge [timespan]'18:30:00' } { return 'night' }
        { $_ -ge [timespan]'18:00:00' } { return 'sunset' }
        { $_ -ge [timespan]'06:30:00' } { return 'day' }
        { $_ -ge [timespan]'06:00:00' } { return 'sunrise' }
        default { return 'night' }
    }
}
