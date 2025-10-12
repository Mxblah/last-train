function Invoke-DamageEffect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Expression,

        [Parameter(Mandatory = $true, ParameterSetName = 'Status')]
        [hashtable]$Status,

        [Parameter(Mandatory = $true, ParameterSetName = 'Item')]
        [hashtable]$Item,

        [Parameter(Mandatory = $true)]
        [hashtable]$Target,

        [Parameter()]
        [switch]$AsHealing,

        # If set, will ignore attack multipliers (but will not ignore skew or defense)
        [Parameter()]
        [switch]$IgnoreAttack,

        # If set, will ignore attack / defense multipliers in Get-Damage (but will not ignore skew or resistances in Adjust-Damage)
        [Parameter()]
        [switch]$IgnoreDefense,

        # If set, will ignore skew multiplier in Get-Damage (but will not ignore attack / defense or resistances in Adjust-Damage)
        [Parameter()]
        [switch]$IgnoreSkew,

        # If set, will ignore affinities in Adjust-Damage (but will not ignore attack and defense multipliers or skew in Get-Damage)
        [Parameter()]
        [switch]$IgnoreAffinity,

        # If set, will ignore resistances in Adjust-Damage (but will not ignore attack and defense multipliers or skew in Get-Damage)
        [Parameter()]
        [switch]$IgnoreResistance,

        # If set, will apply damage directly to HP, even if the target has BP remaining
        [Parameter()]
        [switch]$IgnoreBarrier,

        # If set, will skip removing statuses if the target is killed by Apply-Damage.
        # Should generally only be set when called from Apply-StatusEffects itself, to ensure statuses are cleared properly.
        [Parameter()]
        [switch]$DoNotRemoveStatuses
    )
    # Var handling
    if ($Status) {
        $id = $Status.id
        $guid = $Status.guid
        $class = $Status.class
        $type = $Status.type
        $pow = $Status.pow
        $atk = $Status.atk
    }
    if ($Item) {
        if ($AsHealing) { $effectPath = 'heal' } else { $effectPath = 'damage' }
        $itemData = $State | Find-GameItemData -Guid $Item.guid
        $id = $itemData.id
        $guid = $Item.guid
        $class = $itemData.useData.class
        $type = $itemData.useData.type
        $pow = $itemData.effects.$effectPath.pow
        $atk = $itemData.effects.$effectPath.atk
    }

    Write-Debug "applying damage/heal '$Expression' from $id ($guid)"
    # Nice and "simple" - just apply damage (after some parsing). $Status might be null here, but that's okay.
    $base = Parse-BattleExpression -Expression $Expression -Status $Status -TargetValue $Target.attrib.hp.max

    # Physical/magical determination
    $typeLetter = switch ($class) {
        'physical' { 'p' }
        'magical' { 'm' }
        default { Write-Warning "Invalid skill type '$_' - assuming physical"; 'p' }
    }

    # Switch handlers
    $splat = @{}
    if ($AsHealing) { $splat.AsHealing = $true }
    if ($IgnoreAttack) { $splat.IgnoreAttack = $true }
    if ($IgnoreDefense) { $splat.IgnoreDefense = $true }
    if ($IgnoreSkew) { $splat.IgnoreSkew = $true }

    # Calculate and apply damage/healing
    Write-Debug "adjusted pow from base damage: $pow * $base = $($pow * $base)"
    $damage = Get-Damage -Power ($pow * $base) -Attack $atk -Defense $Target.stats."${typeLetter}Def".value @splat |
        Adjust-Damage -Class $class -Type $type -Target $Target -IgnoreAffinity:$IgnoreAffinity -IgnoreResistance:$IgnoreResistance
    # statuses and items don't deal critical hits
    Write-Debug "adjusted damage/heal based on intensity of $base is $damage"
    $State | Apply-Damage -Target $Target -Damage $damage -Class "$class" -Type "$type" -AsHealing:$AsHealing -IgnoreBarrier:$IgnoreBarrier -DoNotRemoveStatuses:$DoNotRemoveStatuses
}

function Apply-SunDamage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [timespan]$Time
    )

    # Short-circuit conditions: if we're on the train or a cutscene, or the sun isn't out, exit immediately
    if ( $State.time.phase -eq 'night' -or $State.game.train.playerOnBoard ) {
        Write-Debug "solar damage is not applicable at current day phase '$($State.time.phase)', or current scene type '$($State.game.scene.type)' due to playerOnBoard"
        return
    }

    # Do this first as it's more complicated. Basically, reduce the damage during sunrise/sunset by an exponential expression
    if ($State.time.phase -eq 'day') { $timeOfDayFactor =  1 } else {
        $timeFromDaylight = if ($State.time.phase -eq 'sunrise') {
            (([timespan]'06:30:00') - $State.time.currentTime.TimeOfDay).TotalMinutes
        } else {
            ($State.time.currentTime.TimeOfDay - ([timespan]'18:00:00')).TotalMinutes
        }
        $timeOfDayFactor = [System.Math]::Pow(10, -$timeFromDaylight / 30) # ~90% at 1m, 67% at 5m, <50% at 10m, <33% at 15m, and 10% at 30m
        Write-Debug "time from full daylight: $($timeFromDaylight): time-of-day multiplier: 10^-$timeFromDaylight/30 = $timeOfDayFactor"
    }

    # Calculate the damage based on difficulty, time of day, time spent, sun strength multiplier, and the time we just added
    # Constant expression * T -> 4% of base HP per minute, on normal difficulty of 2. Pre-multiplied to reduce the parsing workload later (lots of terms).
    $strengthMult = $State.game.explore.currentSunStrengthMultiplier ?? 1
    Write-Debug "solar damage constant multiplier: $($Time.TotalMinutes) * 2 * $($State.options.difficulty) / 100 * $strengthMult * $timeOfDayFactor"
    $constant = $Time.TotalMinutes * 2 * $State.options.difficulty / 100 * $strengthMult * $timeOfDayFactor
    $expression = "$constant * t"
    Write-Debug "solar damage expression for this instance: $expression"

    # Just for fun, write a message based on current HP %
    $message = switch ($State.player.attrib.hp.value / $State.player.attrib.hp.max) {
        { $_ -gt 0.8 } { 'The sunlight burns your skin...'; break }
        { $_ -gt 0.6 } { 'You feel a feverish heat as the sun beats down...'; break }
        { $_ -gt 0.4 } { "Your body withers under the sun's relentless rays..."; break }
        { $_ -gt 0.2 } { "You feel the sun's fatal, mutative light welling up inside you..."; break }
        default { "The sunlight's glow blazes within your mind. You are going to die." }
    }
    Write-Host -ForegroundColor Red "☀️ $message"

    # Construct the fake status and apply the damage
    $fakeDamageStatus = @{
        id = 'sun-time-damage'
        guid = $null # just for tracking; not needed here as this isn't a status
        class = 'magical'
        type = 'solar'
        pow = 10
        atk = 1
    }
    $State | Invoke-DamageEffect -Expression $expression -Status $fakeDamageStatus -Target $State.player -IgnoreDefense -IgnoreBarrier
}

function Clear-AllStatusEffects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character
    )

    # Clean up statuses and refresh values for the character
    Write-Verbose "clearing all status effects for $($Character.name)"
    $Character.status = @{} # just get rid of 'em all

    # Now deal with the AEs granted by those statuses
    $effectsToRemove = New-Object -TypeName System.Collections.ArrayList
    foreach ($effect in $Character.activeEffects) {
        if ($effect.source -like 'status/*') {
            # Came from a temporary status, so get rid of it
            Write-Debug "will clear active effect from $($effect.source) ($($effect.guid))"
            $effectsToRemove.Add($effect) | Out-Null # can't remove it here; we're iterating over this collection
        }
    }
    foreach ($effect in $effectsToRemove) {
        # now we can remove it
        Write-Debug "clearing active effect from $($effect.source) ($($effect.guid))"
        $Character.activeEffects.Remove($effect)
    }
    $State | Update-CharacterValues -Character $Character
}
