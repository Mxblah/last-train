# Returns a random decimal between 0 and 1
function Get-RandomPercent {
    [CmdletBinding()]
    param(
        # Set the random seed, for debugging
        [Parameter(Mandatory = $false)]
        [int]$Seed = 0
    )

    $splat = @{
        Minimum = 0
        Maximum = 1.0
    }
    if ($Seed -ne 0 ) {
        Write-Debug "Using set seed $Seed"
        $splat.SetSeed = $Seed
    }
    return Get-Random @splat
}

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
            $equippedWeapon = $State | Find-EquippedItem -Slot 'weapon'
            if ($equippedWeapon) {
                Write-Debug "replacing damage class '$Class' with equipped weapon's class $($equippedWeapon.data.equipData.weaponData.class)"
                $Class = $equippedWeapon.data.equipData.weaponData.class
                Write-Debug "replacing damage type '$Type' with equipped weapon's type $($equippedWeapon.data.equipData.weaponData.type)"
                $Type = $equippedWeapon.data.equipData.weaponData.type

                # Handle type percent by running through it twice with the two types
                $typePercent = $equippedWeapon.data.equipData.weaponData.typePercent
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

function Add-Status {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Attacker,

        [Parameter(Mandatory = $true)]
        [hashtable]$Target,

        [Parameter(Mandatory = $true)]
        [hashtable]$Skill,

        # Explicitly set the atk value, instead of calculating from the attacker
        [Parameter()]
        [double]$AttackOverride
    )
    # Update state
    $State.game.battle.attacker = $Attacker.name
    $State.game.battle.defender = $Target.name

    # Loop through all the statuses we have
    foreach ($status in $Skill.data.status) {
        Write-Debug "Applying status $($status.id) against $($Target.name)"

        # Check if it applies at all
        $statusApplyChance = $status.chance - $Target.resistances.status."$($status.id)".value
        Write-Debug "checking if status applies: chance is $($status.chance) - $($Target.resistances.status."$($status.id)".value ?? '(none)') = $statusApplyChance"
        if ($statusApplyChance -lt (Get-RandomPercent)) {
            Write-Debug 'did not apply'
            continue
        }

        # It did, so get the pow and stuff to apply to the intensity
        if (-not $AttackOverride) {
            # Physical/magical determination
            $typeLetter = switch ($Skill.data.class) {
                'physical' { 'p' }
                'magical' { 'm' }
                default { Write-Warning "Invalid skill type '$_' - assuming physical"; 'p' }
            }
        } else {
            Write-Debug "will use attack override of '$AttackOverride' instead of $($Attacker.name)'s atk"
        }

        # Write the status data to the target
        if ($null -eq $Target.status."$($status.id)") { $Target.status."$($status.id)" = New-Object -TypeName System.Collections.ArrayList }
        $statusInfo = Get-Content "$PSScriptRoot/../data/status/$($status.id).json" | ConvertFrom-Json -AsHashtable
        $statusData = @{
            guid = (New-Guid).Guid
            stack = $status.stack
            intensity = $status.intensity
            pow = $Skill.data.pow
            atk = $AttackOverride -gt 0 ? $AttackOverride : $Attacker.stats."${typeLetter}Atk".value
            class = $statusInfo.data.class
            type = $statusInfo.data.type
        }
        $Target.status."$($status.id)".Add($statusData) | Out-Null
        Write-Host ($State | Enrich-Text $statusInfo.applyDesc)

        # Immediately apply passive status effects
        $State | Apply-StatusEffects -Character $Target -Phase 'passive'
    }
}

# todo: there's seemingly some sort of bug where if a status expires at the start of your turn, then you re-apply it with an item, the new status doesn't apply. no idea why that's happening. (??? - cannot reproduce???)
function Apply-StatusEffects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character,

        [Parameter(Mandatory = $true)]
        [ValidateSet('passive', 'turnStart', 'turnEnd', 'onDeath')]
        [string]$Phase,

        # If set, will skip removing statuses that are out of stacks.
        # Should generally only be set when this is a recursive call from Apply-StatusEffects itself, to ensure statuses are cleared properly.
        [Parameter()]
        [switch]$DoNotRemoveStatuses
    )
    Write-Debug "applying $Phase status effects to $($Character.name)"
    $statusInfo = @{}
    $alreadyWritten = New-Object -TypeName System.Collections.ArrayList
    $statusGuidsToRemove = New-Object -TypeName System.Collections.ArrayList
    $statusMapsToAdd = New-Object -TypeName System.Collections.ArrayList

    # Loop through all statuses, applying as we go (thus automatically applying in order from oldest to newest)
    foreach ($statusBlock in $Character.status.GetEnumerator()) {
        $statusId = $statusBlock.Key
        $statusList = $statusBlock.Value

        foreach ($status in $statusList) {
            # Pre-check to make sure we aren't applying statuses with 0 stacks left.
            # This can happen due to onDeath effects and some technical reasons involving modifying collections while iterating over them, so just fix it here before it can matter
            if ($status.stack -le 0) {
                Write-Debug "pre-check: out of stacks: will remove $statusId $($status.guid)"
                $statusGuidsToRemove.Add($status.guid) | Out-Null # we can't modify the collection as we're iterating over it, so do it at the end
                continue
            }

            if ($Phase -eq 'passive' -and $status.passiveApplied) {
                # We already did the passive effects for this status, so skip!
                Write-Debug "already applied passive effects for $statusId ($($status.guid))"
                continue
            }

            # we need to do something, so load the status data from the data zone if we don't already have it
            if (-not $statusInfo.$statusId) {
                Write-Debug "loading status info for $statusId ($($status.guid))..."
                $statusInfo.$statusId = Get-Content "$PSScriptRoot/../data/status/$statusId.json" | ConvertFrom-Json -AsHashtable
            }

            # Print description if this is a turn start status and we haven't already written its description this turn
            if ($Phase -eq 'turnStart') {
                if (-not ($statusId -in $alreadyWritten)) {
                    Write-Host ($State | Enrich-Text $statusInfo.$statusId.turnDesc)
                    $alreadyWritten.Add($statusId) | Out-Null
                } else {
                    Write-Debug "already wrote $statusId for turnStart; not writing it again"
                }
            }

            # Check to make sure we actually have something to do
            if (-not $statusInfo.$statusId.data.$Phase) {
                Write-Debug "no data for $Phase in $statusId; skipping"
                continue
            }

            # Okay, we do. Let's do it
            foreach ($thingToApply in $statusInfo.$statusId.data.$Phase.GetEnumerator()) {
                $case = $thingToApply.Key
                $data = $thingToApply.Value

                switch ($case) {
                    'stacks' {
                        Write-Debug "modifying $statusId ($($status.guid)) stacks by $data (currently $($status.stack))"
                        $status.stack += $data
                    }
                    { $_ -match 'damage|heal' } {
                        $splat = @{}
                        if ($_ -match 'heal') { $splat.AsHealing = $true ; Write-Debug 'effect is healing' } else { Write-Debug 'effect is damage' }

                        # Check to see if this is a hashtable or not, and apply extra conditions if so
                        if ($null -ne $data.expression) {
                            Write-Debug "found extra hashtable properties for expression $($data.expression)"
                            $expression = $data.expression
                            if ($data.ignoreAttack) { $splat.IgnoreAttack = $true }
                            if ($data.ignoreDefense) { $splat.IgnoreDefense = $true }
                            if ($data.ignoreSkew) { $splat.IgnoreSkew = $true }
                            if ($data.ignoreAffinity) { $splat.ignoreAffinity = $true }
                            if ($data.ignoreResistance) { $splat.IgnoreResistance = $true }
                            if ($data.ignoreBarrier) { $splat.IgnoreBarrier = $true }
                        } else {
                            $expression = $data
                        }

                        # Ship it
                        $State | Invoke-DamageEffect -Expression $expression -Status $status -Target $Character @splat -DoNotRemoveStatuses
                    }
                    'skipTurn' {
                        Write-Debug "setting skipTurn flag to $data for $($Character.name) due to $statusId ($($status.guid))"
                        $Character.skipTurn = $data
                    }
                    'attrib' {
                        Write-Debug "modifying attributes due to $statusId ($($status.guid))..."
                        foreach ($attribRaw in $data.GetEnumerator()) {
                            # hp, bp, or mp, usually
                            $attrib = $attribRaw.Key
                            foreach ($subAttribRaw in $attribRaw.Value.GetEnumerator()) {
                                # regen, max, whatever
                                $subAttrib = $subAttribRaw.Key
                                foreach ($actionRaw in $subAttribRaw.Value.GetEnumerator()) {
                                    # mult, buff, etc.
                                    $action = $actionRaw.Key
                                    $number = Parse-BattleExpression -Expression $actionRaw.Value -Status $status

                                    # Finally, we can do the thing
                                    Write-Debug "modifying $attrib/$subAttrib by ${action}:$number"
                                    $Character.activeEffects.Add(@{
                                        path = "attrib.$attrib.$subAttrib"
                                        action = $action
                                        number = $number
                                        guid = $status.guid
                                        source = "status/$statusId"
                                    }) | Out-Null
                                }
                            }
                        }
                    }
                    'stats' {
                        Write-Debug "modifying status due to $statusId ($($status.guid))"
                        # similar to attribs, but with a slightly different flow
                        foreach ($statRaw in $data.GetEnumerator()) {
                            # atk, acc, spd, etc.
                            $stat = $statRaw.Key
                            foreach ($activity in $statRaw.Value.GetEnumerator()) {
                                # mult, buff, etc.
                                $action = $activity.Key
                                $number = Parse-BattleExpression -Expression $activity.Value -Status $status

                                # Do the thing
                                Write-Debug "modifying $stat by ${action}:$number"
                                $Character.activeEffects.Add(@{
                                    path = "stats.$stat.value"
                                    action = $action
                                    number = $number
                                    guid = $status.guid
                                    source = "status/$statusId"
                                }) | Out-Null
                            }
                        }
                    }
                    'status' {
                        Write-Debug "applying subordinate statuses for $statusId ($($status.guid))"
                        # Check to see if chance, stack, or intensity needs to be parsed, and do so if needed
                        foreach ($subStatus in $data) {
                            Write-Debug "parsing expressions for $($subStatus.id)"
                            foreach ($subProperty in @('chance', 'stack', 'intensity')) {
                                if ($subStatus.$subProperty -is [int] -or $subStatus.$subProperty -is [double]) {
                                    Write-Debug "$subProperty is not an expression"
                                } else {
                                    $subStatus.$subProperty = Parse-BattleExpression -Expression $subStatus.$subProperty -Status $status
                                    Write-Debug "parsed $subProperty into $($subStatus.$subProperty)"
                                }
                            }
                        }

                        # We definitely can't add it now, as that would modify during iteration, so do it later
                        $statusMapsToAdd.Add(@{
                            id = $statusId
                            name = $statusInfo.$statusId.name
                            atkOverride = $status.atk
                            data = @{
                                class = $status.class
                                type = $status.type
                                pow = $status.pow
                                status = $data
                            }
                        }) | Out-Null
                        Write-Debug "will apply [$($data.id -join ', ')] post-loop"
                    }
                    default { Write-Warning "Unexpected status action $case found in status $statusId ($($status.guid))" }
                }

                # If we're out of stacks after all the actions, remove the status
                # You'd think we could do this just in the "stack" switch case, but damage can cause onDeath effects...
                # ...which might reduce stacks of other statuses without explicitly calling the "stack" case *here*, so to be safe we have to check every time
                if ($status.stack -le 0) {
                    Write-Debug "out of stacks: will remove $statusId $($status.guid)"
                    $statusGuidsToRemove.Add($status.guid) | Out-Null # we can't modify the collection as we're iterating over it, so do it at the end
                }
            }

            if ($Phase -eq 'passive' -and -not $status.passiveApplied) {
                Write-Debug "setting passive applied flag for $statusId ($($status.guid))"
                $status.passiveApplied = $true
            }
        }
    }

    if (-not $DoNotRemoveStatuses) {
        # If we have statuses to remove, do it now
        Write-Debug "will remove the following statuses: [$($statusGuidsToRemove -join ', ')]"
        $statusClassesToRemove = New-Object -TypeName System.Collections.ArrayList
        if ($statusGuidsToRemove.Count -gt 0) {
            foreach ($guid in $statusGuidsToRemove) {
                Write-Debug "removing status guid $guid from $($Character.name)"
                foreach ($effect in ($Character.activeEffects | Where-Object -Property guid -EQ $guid)) {
                    # remove all AEs derived from this status
                    $Character.activeEffects.Remove($effect)
                }
                foreach ($statusClass in $Character.status.GetEnumerator()) {
                    foreach ($status in ($statusClass.Value | Where-Object -Property guid -EQ $guid)) {
                        # Remove the status itself
                        $Character.status."$($statusClass.Key)".Remove($status)
                        if ($Character.status."$($statusClass.Key)".count -le 0) {
                            # and mark the status class for removal if we're all out of statuses within it (can't remove it here as we're iterating over it)
                            Write-Debug "all out of $($statusClass.Key) - will remove class"
                            $statusClassesToRemove.Add("$($statusClass.Key)") | Out-Null
                        }
                    }
                }
            }

            # Remove empty classes
            foreach ($statusClass in $statusClassesToRemove) {
                Write-Debug "removing $statusClass"
                $Character.status.Remove($statusClass)
            }
        }
    } else {
        # Usually this only happens during 'onDeath', to avoid modifying the collection when a character dies to ongoing damage
        Write-Verbose "explicitly instructed to not remove statuses during phase '$Phase', so skipping that part"
    }

    # Add statuses if we have any to add
    if ($statusMapsToAdd.Count -gt 0) {
        Write-Debug "will add subordinate statuses from the following statuses: [$($statusMapsToAdd.id -join ', ')]"
        foreach ($statusMapToAdd in $statusMapsToAdd) {
            $State | Add-Status -Attacker @{ name = $statusMapToAdd.name } -Target $Character -Skill $statusMapToAdd -AttackOverride $statusMapToAdd.atkOverride
        }
    }

    # Update values now that we're done with everything
    $State | Update-CharacterValues -Character $Character
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
        [int]$TargetValue
    )
    Write-Debug "parsing expression '$Expression' with data: stack '$($Status.stack)' / intensity '$($Status.intensity)' / target value '$($TargetValue)'"

    [double]$toReturn = 0
    $currentOperator = $null
    foreach ($term in $Expression.Split(' ')) {
        if ($term -match '^(\+|-|\*|/)$') {
            Write-Debug "operator: $term"
            $currentOperator = $term
        } else {
            # Replacements for letters
            switch ($term) {
                's' {
                    Write-Debug "replacing stacks with $($Status.stack)"
                    $term = $Status.stack
                }
                'i' {
                    Write-Debug "replacing intensity with $($Status.intensity)"
                    $term = $Status.intensity
                }
                't' {
                    Write-Debug "replacing target value with $TargetValue"
                    $term = $TargetValue
                }
                default {
                    Write-Debug "number: $term"
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
        Write-Debug "intermediate total: $toReturn"
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
        [hashtable]$Character
    )
    # Reset all stats/attribs/etc. to base, before processing AEs
    foreach ($statRaw in $Character.stats.GetEnumerator()) {
        Write-Debug "resetting $($statRaw.Key) to $($statRaw.Value.base)"
        $statRaw.Value.value = $statRaw.Value.base
    }
    foreach ($attribRaw in $Character.attrib.GetEnumerator()) {
        $attrib = $attribRaw.Key
        $data = $attribRaw.Value

        Write-Debug "resetting $attrib max to $($data.max) / regen: '$($data.baseRegen)' if applicable"
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

                Write-Debug "resetting $bonusName to $($data.base)"
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
            'debuff' { [System.Math]::Max(($existingValue - $effect.number), 0) } # ensure positive number
            'mult' { $existingValue * $effect.number }
            default { Write-Warning "unknown action type $($effect.action) found in AE with guid $($effect.guid) (source: $($effect.source))" }
        }

        # round up if we're in a path that does that
        if ($effect.path -notmatch 'resistances|affinities') {
            Write-Debug "rounding up $newValue to ensure a whole number"
            $newValue = [System.Math]::Ceiling($newValue)
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
            foreach ($target in $Targets) {
                Write-Debug "queueing $($actionToQueue.class)/$($actionToQueue.id) for $($target.name)"
                $target.actionQueue.Add($actionToQueue) | Out-Null
            }
        }
    }

    # Short-circuit for no-hit skills
    if ($Skill.data.hits -eq 0) {
        Write-Debug "0 hits for skill $($Skill.id) - nothing left to do!"
        return
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

            # Handle status calculations, if present
            if ($Skill.data.status) {
                $State | Add-Status -Attacker $Attacker -Target $Target -Skill $Skill
            }

            # Handle special effects, if present
            if ($Skill.skillType -eq 'special') {
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
