function Get-IfHit {
    [CmdletBinding()]
    param (
        # Attacker's accuracy
        [Parameter(Mandatory = $true)]
        [int]$Accuracy,

        # Target's speed
        [Parameter(Mandatory = $true)]
        [int]$Speed,

        # Skill accuracy multiplier
        [Parameter()]
        [double]$SkillAccuracy = 1.0
    )

    if ($Speed -le 0) {
        Write-Verbose 'Spd: 0 - returning true to avoid divide-by-zero error'
        return $true
    }
    # If accuracy > speed, attacks will always hit. Conversely, the minimum hit chance is 25% to avoid impossible battles
    $hitChance = [System.Math]::Pow(4, ($SkillAccuracy * $Accuracy / $Speed)) / 4
    Write-Debug "Acc: $Accuracy (x $SkillAccuracy) / Spd: $Speed`nChance to hit: $hitChance"
    return $hitChance -ge (Get-RandomPercent)
}

function Get-Damage {
    [CmdletBinding()]
    param (
        # Skill's attack power
        [Parameter(Mandatory = $true)]
        [int]$Power,

        # Attacker's relevant base attack
        [Parameter(Mandatory = $true)]
        [int]$Attack,

        # Target's relevant base defense
        [Parameter(Mandatory = $true)]
        [int]$Defense,

        # Attacker's current attack modifier
        [Parameter()]
        [double]$AtkMultiplier = 1.0,

        # Target's current defense modifier
        [Parameter()]
        [double]$DefMultiplier = 1.0,

        [Parameter()]
        [switch]$AsHealing,

        # If set, will ignore attack multipliers (but will not ignore skew or defense)
        [Parameter()]
        [switch]$IgnoreAttack,

        # If set, will ignore defense multipliers (but will not ignore attack or skew)
        [Parameter()]
        [switch]$IgnoreDefense,

        # If set, will ignore skew multiplier (but will not ignore attack or defense)
        [Parameter()]
        [switch]$IgnoreSkew
    )

    # Handle everything that doesn't involve defense
    if ($IgnoreSkew) {
        Write-Debug 'ignoring skew by setting it to 1'
        $overallSkew = 1
    } else {
        $overallSkew = Get-Random -Minimum 0.9 -Maximum 1.1
    }
    if ($IgnoreAttack) {
        Write-Debug 'ignoring attack for base damage calculation'
        $baseDamage = $overallSkew * $Power / 10
    } else {
        $baseDamage = $overallSkew * $Power / 10 * $Attack * $AtkMultiplier
    }
    Write-Debug "With pow $Power, atk $Attack, and skew of $overallSkew, base damage is $baseDamage"

    # Now get defense involved (if not healing)
    if ($AsHealing -or $IgnoreDefense) {
        Write-Debug 'AsHealing or IgnoreDefense is true, so skipping defense calculation'
        $damageMultiplier = 1
    } else {
        if ($Defense -eq 0 -or $DefMultiplier -eq 0) {
            Write-Debug "avoiding divide-by-zero error (def: $Defense, def mult: $DefMultiplier) - setting multiplier to max"
            $damageMultiplier = 2
        } else {
            $damageMultiplier = [System.Math]::Clamp(($Attack / ( $Defense * $DefMultiplier )), 0.01, 2)
        }
        # $damageMultiplier = 2 * [System.Math]::Pow(2, (-1 * $Defense * $DefMultiplier / $Attack))
        Write-Debug "With defense of $Defense, damage multiplier is $damageMultiplier"
    }

    # Return the total number, rounded up
    $totalDamage = [System.Math]::Ceiling($baseDamage * $damageMultiplier)
    Write-Debug "Total damage/healing is $totalDamage"
    return $totalDamage
}

function Adjust-Damage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [int]$Damage,

        [Parameter(Mandatory = $true)]
        [string]$Class,

        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter()]
        [hashtable]$Attacker,

        [Parameter(Mandatory = $true)]
        [hashtable]$Target,

        # If set, will ignore affinities
        [Parameter()]
        [switch]$IgnoreAffinity,

        # If set, will ignore resistances
        [Parameter()]
        [switch]$IgnoreResistance
    )
    # Escape hatches
    if ($IgnoreAffinity -and $IgnoreResistance) {
        Write-Debug 'Adjust-Damage called while ignoring affinities and resistances; nothing to do'
        return $Damage
    }
    if ($Damage -le 0) {
        Write-Debug "Adjust-Damage called with $Damage damage <= 0; nothing to do"
        return $Damage
    }

    Write-Verbose "Adjusting $Damage $Class/$Type damage for $($Target.name)"

    # Handle weapon typing
    if ($Type -eq 'weapon') {
        if ($Attacker.id -eq 'player') {
            # Only the player can equip weapons
            $equippedWeaponId = $State | Find-EquippedItem -Slot 'weapon'
            if ($equippedWeaponId) {
                $equippedWeapon = $State.data.items.$equippedWeaponId
                Write-Debug "replacing damage class '$Class' with equipped weapon's class $($equippedWeapon.equipData.weaponData.class)"
                $Class = $equippedWeapon.equipData.weaponData.class
                Write-Debug "replacing damage type '$Type' with equipped weapon's type $($equippedWeapon.equipData.weaponData.type)"
                $Type = $equippedWeapon.equipData.weaponData.type

                # Handle type percent by running through it twice with the two types
                $typePercent = $equippedWeapon.equipData.weaponData.typePercent
                if ($typePercent -ne 1) {
                    Write-Debug "type percent: $typePercent -> $($typePercent * 100)% of damage will be this type"
                    $commonSplat = @{
                        Class = $Class
                        Attacker = $Attacker
                        Target = $Target
                        IgnoreAffinity = $IgnoreAffinity
                        IgnoreResistance = $IgnoreResistance
                    }
                    $typedDamage = Adjust-Damage -Damage ($typePercent * $Damage) -Type $Type @commonSplat
                    $untypedDamage = Adjust-Damage -Damage ((1 - $typePercent) * $Damage) -Type 'standard' @commonSplat
                    return ($typedDamage + $untypedDamage) # both have been ceiling'd already, so no need to do it again
                } else {
                    Write-Debug "type percent: $typePercent -> all damage is this type"
                }
            }
        }
    }
    if ($null -eq $Type -or $Type -eq 'weapon') {
        Write-Debug 'could not find a weapon damage type - either attacker is not the player or player has no equipped weapon'
        $Type = 'standard' # give up and assume it's normal
    }

    if (-not $IgnoreAffinity) {
        $classBonus = $Attacker.affinities.element.$Class.value
        $typeBonus = $Attacker.affinities.element.$Type.value
        if ($classBonus) {
            Write-Debug "increasing $Damage $Class damage by $classBonus"
            $Damage = [System.Math]::Max($Damage * (1 + $classBonus), 0)
        }
        if ($typeBonus) {
            Write-Debug "increasing $Damage $Type damage by $typeBonus"
            $Damage = [System.Math]::Max($Damage * (1 + $typeBonus), 0)
        }
        Write-Debug "-> (now $Damage)"
    }

    if (-not $IgnoreResistance) {
        $classResist = $Target.resistances.element.$Class.value
        $typeResist = $Target.resistances.element.$Type.value
        if ($classResist) {
            Write-Debug "reducing $Damage $Class damage by $classResist"
            $Damage = [System.Math]::Max($Damage * (1 - $classResist), 0)
        }
        if ($typeResist) {
            Write-Debug "reducing $Damage $Type damage by $typeResist"
            $Damage = [System.Math]::Max($Damage * (1 - $typeResist), 0)
        }
        Write-Debug "-> (now $Damage)"
    }

    return [System.Math]::Ceiling($Damage)
}

function Get-CriticalMultiplier {
    param (
        # Equipment-based critical chance bonus
        [Parameter()]
        [double]$EquipBonus = 0.0,

        # Skill-based critical chance bonus
        [Parameter()]
        [double]$SkillBonus = 0.0,

        # Status-based critical chance bonus
        [Parameter()]
        [double]$StatusBonus = 0.0,

        # Amount a critical hit should increase damage by
        [Parameter()]
        [double]$CriticalMultiplier = 0.5
    )
    $finalMultiplier = 1

    $totalCritChance = 0.05 + $EquipBonus + $SkillBonus
    Write-Verbose "Total crit chance is $totalCritChance"

    # Handle doublecrits and more by adding to the multiplier and reducing the final chance back down below 100%
    while ($totalCritChance -gt 1) {
        $finalMultiplier += $CriticalMultiplier
        $totalCritChance--
        Write-Verbose "Crit chance > 100%; adding $CriticalMultiplier to final multiplier (now $finalMultiplier) and subtracting 100% (now $totalCritChance)"
    }

    # Determine if it's a crit now that it's definitely below 100%
    if ($totalCritChance -ge (Get-RandomPercent)) {
        $finalMultiplier += $CriticalMultiplier
        Write-Verbose "Critical hit! Adding $CriticalMultiplier to final multiplier (now $finalMultiplier)"
    }

    # Return multiplier to the caller, which should use it to multiply a damage total
    return $finalMultiplier
}

function Apply-Damage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Target,

        [Parameter(Mandatory = $true)]
        [int]$Damage,

        # Just used for icon / color; adjustments due to resistance, etc. are done in Adjust-Damage
        [Parameter()]
        [string]$Class,

        # Just used for icon / color; adjustments due to resistance, etc. are done in Adjust-Damage
        [Parameter()]
        [string]$Type,

        [Parameter()]
        [switch]$AsHealing,

        # If set, will apply damage directly to HP, even if the target has BP remaining
        [Parameter()]
        [switch]$IgnoreBarrier,

        # If set, will skip removing statuses if the target is killed.
        # Should generally only be set when damage is applied from Apply-StatusEffects itself, to ensure statuses are cleared properly.
        [Parameter()]
        [switch]$DoNotRemoveStatuses
    )
    # Break immediately if there is no damage
    if ($Damage -le 0) {
        Write-Debug 'no damage to apply; returning'
        return
    }

    # Apply to BP first, if applicable (not applicable for healing, as well)
    if ($AsHealing -or $IgnoreBarrier) {
        Write-Debug 'applying healing-type or barrier-ignoring damage, so skipping BP calculation'
    } else {
        switch ($Target.attrib.bp.value) {
            { $_ -gt $Damage } {
                # Barrier absorbs the hit
                $originalBp = $Target.attrib.bp.value
                $Target.attrib.bp.value -= $Damage
                Write-Host -ForegroundColor Blue "🛡️ $($Target.name)'s barrier takes $Damage damage."
                $Damage -= $originalBp
            }
            { $_ -le $Damage -and $_ -gt 0 } {
                # Barrier absorbs some damage, then breaks
                $Damage -= $Target.attrib.bp.value
                $Target.attrib.bp.value = 0
                Write-Host -ForegroundColor Blue "🛡️ $($Target.name)'s barrier breaks!"
            }
            default { <# no barrier; do nothing #> }
        }

        # Break out if we're out of damage
        if ($Damage -le 0) {
            return
        }
    }

    # Apply to HP next
    $flavorMap = Get-DamageTypeFlavorInfo -Class "$Class" -Type "$Type"
    if ($AsHealing) {
        Write-Host -ForegroundColor $flavorMap.color "$($flavorMap.badge) $($Target.name) regains $Damage HP."
        switch ($Target.attrib.hp.max - $Target.attrib.hp.value) {
            { $_ -ge $Damage } {
                # We won't overflow
                $Target.attrib.hp.value += $Damage
            }
            { $_ -lt $Damage } {
                # Overflow risk, so set to max
                $Target.attrib.hp.value = $Target.attrib.hp.max
            }
        }
    } else {
        Write-Host -ForegroundColor $flavorMap.color "$($flavorMap.badge) $($Target.name) takes $Damage damage."
        switch ($Target.attrib.hp.value) {
            { $_ -gt $Damage } {
                # Target survives
                $Target.attrib.hp.value -= $Damage
            }
            { $_ -le $Damage } {
                # Target dies
                $State | Kill-Character -Character $Target -DoNotRemoveStatuses:$DoNotRemoveStatuses
            }
        }
    }
}

function Parse-BattleExpression {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Expression,

        # Required for 's' and 'i'
        [Parameter()]
        [hashtable]$Status,

        # Required for 't'
        [Parameter()]
        [int]$TargetValue,

        [Parameter()]
        [switch]$SuperDebug
    )
    Write-Debug "parsing expression '$Expression' with data: stack '$($Status.stack)' / intensity '$($Status.intensity)' / target value '$($TargetValue)'"

    [double]$toReturn = 0
    $currentOperator = $null
    foreach ($term in $Expression.Split(' ')) {
        if ($term -match '^(\+|-|\*|/)$') {
            if ($SuperDebug) { Write-Debug "operator: $term" }
            $currentOperator = $term
        } else {
            # Replacements for letters
            switch ($term) {
                's' {
                    if ($SuperDebug) { Write-Debug "replacing stacks with $($Status.stack)" }
                    $term = $Status.stack
                }
                'i' {
                    if ($SuperDebug) { Write-Debug "replacing intensity with $($Status.intensity)" }
                    $term = $Status.intensity
                }
                't' {
                    if ($SuperDebug) { Write-Debug "replacing target value with $TargetValue" }
                    $term = $TargetValue
                }
                default {
                    if ($SuperDebug) { Write-Debug "number: $term" }
                }
            }

            if ($null -eq $currentOperator -and $toReturn -eq 0) {
                # initial add, so just set it
                $toReturn = $term
            } elseif ($null -eq $currentOperator) {
                # something weird is going on as we have a term but no operator to use on it
                Write-Warning "syntax error within expression '$Expression' (from status '$($Status.id)' ($($Status.guid)) if applicable) - no operator found for term '$term'"
            } else {
                # try to use the operator on it, then clear the operator
                $toReturn = Invoke-Expression -Command "$toReturn $currentOperator $term"
                $currentOperator = $null
            }
        }
        if ($SuperDebug) { Write-Debug "intermediate total: $toReturn" }
    }

    # actually return it
    Write-Debug "returning parsed value $toReturn"
    return $toReturn
}

function Update-CharacterValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character,

        [Parameter()]
        [switch]$SuperDebug
    )
    Write-Debug "updating character values for $($Character.name)"

    # Reset all stats/attribs/etc. to base, before processing AEs
    foreach ($statRaw in $Character.stats.GetEnumerator()) {
        if ($SuperDebug) { Write-Debug "resetting $($statRaw.Key) to $($statRaw.Value.base)" }
        $statRaw.Value.value = $statRaw.Value.base
    }
    foreach ($attribRaw in $Character.attrib.GetEnumerator()) {
        $attrib = $attribRaw.Key
        $data = $attribRaw.Value

        if ($SuperDebug) { Write-Debug "resetting $attrib max to $($data.max) / regen: '$($data.baseRegen)' if applicable" }
        if ($null -ne $data.regen) {
            $data.regen = $data.baseRegen
        }
        $data.max = $data.base
    }
    foreach ($bonusCategoryName in @('resistances', 'affinities')) {
        foreach ($bonusCategory in $Character.$bonusCategoryName.GetEnumerator()) {
            foreach ($bonusRaw in $bonusCategory.Value.GetEnumerator()) {
                $bonusName = $bonusRaw.Key
                $data = $bonusRaw.Value

                # resistances/affinities might be added after the default init, so create a "base" entry if needed
                if ($null -eq $data.base) {
                    Write-Debug "creating missing $bonusName base entry: 0"
                    $data.base = 0
                }

                if ($SuperDebug) { Write-Debug "resetting $bonusName to $($data.base)" }
                $data.value = $data.base
            }
        }
    }

    # Process all AEs at once
    foreach ($effect in $Character.activeEffects) {
        # todo: consider updating this to do additive multiplication (i.e. "buff" and "mult" fields for stats/attribs instead of direct operations)

        # Find the right thing to modify
        $existingValue = Get-HashtableValueFromPath -Hashtable $Character -Path $effect.path
        Write-Debug "modifying $($effect.path) ($existingValue) with $($effect.action):$($effect.number)"

        # modify it
        $newValue = switch ($effect.action) {
            'buff' { $existingValue + $effect.number }
            'debuff' { $existingValue - $effect.number }
            'mult' { $existingValue * $effect.number }
            default { Write-Warning "unknown action type $($effect.action) found in AE with guid $($effect.guid) (source: $($effect.source))" }
        }

        # round up if we're in a path that does that
        if ($effect.path -match 'attrib|base') {
            if ($SuperDebug) { Write-Debug "rounding up $newValue to ensure a whole number" }
            $newValue = [System.Math]::Ceiling($newValue)
        }
        # make positive if we need it to be
        if ($effect.path -notmatch 'affinities|resistances') {
            if ($SuperDebug) { Write-Debug "forcing $newValue to be positive" }
            $newValue = [System.Math]::Max($newValue, 0)
        }

        # set it
        if ($null -ne $newValue) {
            Set-HashtableValueFromPath -Hashtable $Character -Path $effect.path -Value $newValue
            Write-Debug " -> (now $newValue)"
        } else {
            Write-Debug "did not set new value '$newValue' because it was null"
        }
    }

    # Overflow protection for attributes now that all AEs are processed
    foreach ($attribRaw in $Character.attrib.GetEnumerator()) {
        $attrib = $attribRaw.Key
        $data = $attribRaw.Value

        Write-Debug "resetting $attrib overflow $($data.value) to max $($data.max) if applicable"
        if ($data.value -gt $data.max) {
            $data.value = $data.max
        }
    }

    Write-Verbose "finished applying all AEs on $($Character.name)"
}

function Kill-Character {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character,

        # If set, will skip removing statuses during the onDeath phase.
        # Should generally only be set when the fatal damage comes from Apply-StatusEffects itself, to ensure statuses are cleared properly.
        [Parameter()]
        [switch]$DoNotRemoveStatuses
    )
    # isActive handles death inside of battle
    if ($Character.isActive) {
        # avoid spamming this message if the character dies from the first hit of a zillion-hit combo, for instance
        Write-Host "💀 $($Character.name) is defeated..."
        $Character.isActive = $false
    }
    $Character.attrib.hp.value = 0

    # Handle on-death effects
    $State | Apply-StatusEffects -Character $Character -Phase 'onDeath' -DoNotRemoveStatuses:$DoNotRemoveStatuses

    # Check to see if the character is still dead (maybe a status effect revived them, for instance)
    if ($Character.attrib.hp.value -gt 0) {
        Write-Host -ForegroundColor White "🪽 $($Character.name) is revived!"
        if ($Character.isActive -eq $false) {
            $Character.isActive = $true
        }
        # short-circuit to avoid any further effects, since we're not dead anymore
        return
    }

    # Remove allies from the party after death
    if ($Character.faction -eq 'ally' -and $Character.id -ne 'player') {
        Write-Debug "Removing ally $($Character.name) from the party"
        $State | Remove-PartyMember -Id $Character.id
    }

    # Handle death outside of battle (during a cutscene, for instance)
    if ($State.game.scene.type -ne 'battle') {
        # Generic bad end for scenes that don't have their own death words
        Write-Debug "performing death for non-battle scene type $($State.game.scene.type)"
        $State | Exit-Scene -Type 'end' -Id 'bad'
    }
}

function Invoke-Skill {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Attacker,

        [Parameter(Mandatory = $true)]
        [System.Collections.ArrayList]$Targets,

        [Parameter(Mandatory = $true)]
        [hashtable]$Skill
    )

    # Update state
    $State.game.battle.attacker = $Attacker.name
    $State.game.battle.defender = $Targets[0].name

    # Print initial skill usage description
    if ($Skill.description) {
        Write-Host ($State | Enrich-Text $Skill.description)
    }

    # Expend MP, if relevant
    if ($null -ne $Skill.data.mp) {
        if ($Attacker.attrib.mp.value -ge $Skill.data.mp) {
            # We can pay; no problem
            Write-Debug "subtracting $($Skill.data.mp) MP from $($Attacker.name) to cast $($Skill.id)"
            $Attacker.attrib.mp.value -= $Skill.data.mp
        } else {
            # oh no, a shortage of MP!
            Write-Warning "$($Attacker.name) tried to use $($Skill.name), but didn't have enough focus!"
            return
        }
    }

    # Add queued actions to the queue, if applicable
    if ($null -ne $Skill.data.queue) {
        foreach ($actionToQueue in $Skill.data.queue) {
            if ($actionToQueue.target -eq 'attacker') {
                Write-Debug "queueing $($actionToQueue.class)/$($actionToQueue.id) for $($Attacker.name)"
                $Attacker.actionQueue.Add($actionToQueue) | Out-Null
            } else {
                foreach ($target in $Targets) {
                    Write-Debug "queueing $($actionToQueue.class)/$($actionToQueue.id) for $($target.name)"
                    $target.actionQueue.Add($actionToQueue) | Out-Null
                }
            }
        }
    }

    # Short-circuit for no-hit skills
    if ($Skill.data.hits -eq 0) {
        Write-Debug "0 hits for skill $($Skill.id) - nothing left to do!"
        return
    }

    # If this is a weapon-typed skill and the attacker is the player, merge the weapon and skill's status entries, if any
    if ($Skill.data.type -eq 'weapon' -and $Attacker.id -eq 'player') {
        $Skill = $Skill | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable # clone to avoid modifying the base skill data

        $equippedWeaponId = $State | Find-EquippedItem -Slot 'weapon'
        if ($equippedWeaponId) {
            $equippedWeapon = $State.data.items.$equippedWeaponId
            Write-Debug "Merging $($equippedWeapon.equipData.weaponData.status.Count) statuses from equipped weapon $equippedWeaponId into skill $($Skill.id)"
            if ($null -ne $equippedWeapon.equipData.weaponData.status) {
                # Don't destroy the arraylist here, and in fact create it if needed
                if ($null -eq $Skill.data.status) {
                    $Skill.data.status = New-Object -TypeName System.Collections.ArrayList
                }

                # Merge those statuses
                foreach ($weaponStatus in $equippedWeapon.equipData.weaponData.status) {
                    Write-Debug "merging weapon status $($weaponStatus.id)"
                    $Skill.data.status.Add($weaponStatus) | Out-Null
                }
            }
        }
    }

    # Loop over all the targets in order
    foreach ($Target in $Targets) {
        $State.game.battle.defender = $Target.name

        # Loop for multi-hit skills
        $timesHit = 0
        foreach ($hit in (1..$Skill.data.hits)) {
            # Check if the skill is targeting an ally (or self) and thus needs no hit calculation
            if ($Attacker.faction -eq $Target.faction) {
                $isHit = $true
            } else {
                $isHit = Get-IfHit -Accuracy $Attacker.stats.acc.value -Speed $Target.stats.spd.value -SkillAccuracy $Skill.data.acc
            }

            # Whiff if it missed
            if (-not $isHit) {
                Write-Host -ForegroundColor DarkGray '... but it missed.'
                continue
            }

            # Add to total for mult-hits
            $timesHit++

            # Physical/magical determination
            $typeLetter = switch ($Skill.data.class) {
                'physical' { 'p' }
                'magical' { 'm' }
                default { Write-Warning "Invalid skill type '$_' - assuming physical"; 'p' }
            }

            # Calculate damage and crit if it hit
            $damage = Get-Damage -Power $Skill.data.pow -Attack $Attacker.stats."${typeLetter}Atk".value -Defense $Target.stats."${typeLetter}Def".value |
                Adjust-Damage -Class $Skill.data.class -Type $Skill.data.type -Attacker $Attacker -Target $Target
            $critMult = Get-CriticalMultiplier -SkillBonus $Skill.data.crit
            switch ($critMult) {
                { $_ -le 1 } { break <# do nothing; normal hit #> }
                { $_ -le 2 } { Write-Host -ForegroundColor Magenta '💥 A critical hit!'; break }
                { $_ -le 3 } { Write-Host -ForegroundColor DarkMagenta '💫 A brutal hit!'; break }
                default { Write-Host -ForegroundColor DarkRed '💀 A mortal hit!' }
            }
            $damage *= $critMult

            # Apply and report damage
            $State | Apply-Damage -Target $Target -Damage $damage -Class $Skill.data.class -Type $Skill.data.type

            # Handle status additions, if present
            if ($Skill.data.status) {
                $State | Add-Status -Attacker $Attacker -Target $Target -Skill $Skill
            }

            # Handle status removals, if present
            if ($Skill.data.removeStatus) {
                $State | Remove-Status -Attacker $Attacker -Target $Target -Skill $Skill
            }

            # Handle special effects, if present
            if ($Skill.data.specialType) {
                $State | Invoke-SpecialSkill -Attacker $Attacker -Target $Target -Skill $Skill
            }
        }

        # Print for multi-hits
        if ($timesHit -gt 1) {
            Write-Host "It hit $timesHit times!"
        }
    }
}

function Invoke-NonTargetSkill {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Attacker,

        [Parameter(Mandatory = $true)]
        [hashtable]$Skill
    )
    # Update state
    $State.game.battle.attacker = $Attacker.name
    $State.game.battle.defender = $Attacker.name

    # Print initial skill usage description
    if ($Skill.description) {
        Write-Host ($State | Enrich-Text $Skill.description)
    }

    # Idle skills do literally nothing, so just stop here
    if ($Skill.skillType -eq 'idle') {
        return
    }

    # Special skills are more... special, so let's do something
    if ($Skill.skillType -eq 'special') {
        $State | Invoke-SpecialSkill -Attacker $Attacker -Skill $Skill
    } else {
        # dunno what this is but it's weird
        Write-Warning "unexpected non-target skill type $($Skill.skillType) encountered when invoking skill $($Skill.id)"
    }
}

function Invoke-SpecialSkill {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Attacker,

        # Optional as some special skills don't have a target
        [Parameter()]
        [hashtable]$Target,

        [Parameter(Mandatory = $true)]
        [hashtable]$Skill
    )
    # Called from the other invoke-*skill functions, so no need to update state

    switch ($Skill.data.specialType) {
        'flee' {
            $State | Invoke-SpecialFlee -Attacker $Attacker -Skill $Skill
        }
        'inspect' {
            $State | Invoke-SpecialInspect -Attacker $Attacker -Target $Target -Skill $Skill
        }
        'item' {
            $State | Invoke-SpecialItem -Attacker $Attacker -Skill $Skill
        }
        'equip' {
            $State | Invoke-SpecialEquip -Attacker $Attacker -Skill $Skill
        }
        'steal' {
            $State | Invoke-SpecialSteal -Attacker $Attacker -Target $Target -Skill $Skill
        }
        'summon' {
            $State | Invoke-SpecialSummon -Attack $Attacker -Skill $Skill
        }
        'queue' {
            Write-Debug "$($Skill.id) is a queueing skill only; no special behavior will be executed"
        }
        default { Write-Warning "unexpected special type $_ encountered when invoking special skill $($Skill.id)" }
    }
}

function Invoke-AttribRegen {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character,

        [Parameter(Mandatory = $true, ParameterSetName = 'Individual')]
        [string]$Attribute,

        [Parameter(Mandatory = $true, ParameterSetName = 'All')]
        [switch]$All
    )

    if ($All) {
        Write-Debug "regenerating all $($Character.attrib.Keys.count) attributes for $($Character.name)"
        foreach ($attribKey in $Character.attrib.Keys) {
            $State | Invoke-AttribRegen -Character $Character -Attribute $attribKey
        }
    } else {
        # Var init
        $regen = $Character.attrib.$Attribute.regen
        $max = $Character.attrib.$Attribute.max
        $current = $Character.attrib.$Attribute.value

        # Make sure this is a regenerating attribute at all
        if ($null -eq $regen -or $regen -le 0) {
            Write-Debug "not regenerating non-regenerating or zero-regen attrib $Attribute"
            return
        }

        # It is, so check to see if it needs to regen
        if ($current -lt $max) {
            # It does, so do it
            if (($max - $current) -ge $regen) {
                # add it directly; we won't overflow
                Write-Debug "$Attribute regen: adding $regen to $current"
                $Character.attrib.$Attribute.value += $regen
            } else {
                # set to max to avoid overflow
                Write-Debug "$Attribute regen: setting $current to $max (diff < $regen)"
                $Character.attrib.$Attribute.value = $max
            }
        } else {
            Write-Debug "$Attribute regen: not needed; $current >= $max"
        }
    }
}
