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

            # Handle multi-target parsing for resistance purposes
            $targetClass = if ($Skill.data.targetsAll) { 'all' } elseif ($Skill.data.target -gt 1) { 'multi' } else { 'single' }

            # Calculate damage and crit if it hit
            $damage = Get-Damage -Power $Skill.data.pow -Attack $Attacker.stats."${typeLetter}Atk".value -Defense $Target.stats."${typeLetter}Def".value |
                Adjust-Damage -Class $Skill.data.class -Type $Skill.data.type -Attacker $Attacker -Target $Target -TargetClass $targetClass
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

            # Handle onHit status effects first, to avoid triggering them for statuses being added by this attack (if applicable)
            if ($Skill.data.skipOnHitEffects) {
                Write-Debug "skipping onHit status effects for $($Skill.name) against $($Target.name)"
            } else {
                $State | Apply-StatusEffects -Character $Target -Phase 'onHit'
            }

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
        [switch]$All,

        # Directly specify the amount to regenerate, instead of using the character's regen attribute
        [Parameter(ParameterSetName = 'Individual')]
        [int]$RegenOverride,

        # If true, will write output to the player
        [Parameter()]
        [switch]$Loud
    )

    if ($All) {
        Write-Debug "regenerating all $($Character.attrib.Keys.count) attributes for $($Character.name)"
        foreach ($attribKey in $Character.attrib.Keys) {
            $State | Invoke-AttribRegen -Character $Character -Attribute $attribKey
        }
    } else {
        # Var init
        $regen = $null -eq $RegenOverride -or 0 -eq $RegenOverride ? $Character.attrib.$Attribute.regen : $RegenOverride
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
                $regen = $max - $current # for printing later, if needed
            }

            # Output to player if called as such
            if ($Loud) {
                Write-Host -ForegroundColor Green "$(Get-AttribStatBadge -AttribOrStat $Attribute) $Attribute recovered by $regen"
            }
        } else {
            Write-Debug "$Attribute regen: not needed; $current >= $max"
        }
    }
}
