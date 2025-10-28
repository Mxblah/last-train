[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'Too many *-Damage functions to limit to just the main verbs.')]
param()
# Dummy param block for script analyzer rule suppression ^

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
    # If accuracy > speed, attacks will always hit. Conversely, the minimum hit chance is 10% to avoid impossible battles
    $hitChance = [System.Math]::Clamp(($SkillAccuracy * $Accuracy / $Speed), 0.1, 1)
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

    # Now get defense involved (if not healing/ignored)
    if ($AsHealing -or $IgnoreDefense -or $IgnoreAttack) {
        Write-Debug 'AsHealing or IgnoreDefense or IgnoreAttack is true, so skipping defense calculation (mult 1)'
        $damageMultiplier = 1
    } else {
        if ($Defense -eq 0 -or $DefMultiplier -eq 0) {
            Write-Debug "avoiding divide-by-zero error (def: $Defense, def mult: $DefMultiplier) - setting multiplier to max"
            $damageMultiplier = 2
        } else {
            $damageMultiplier = [System.Math]::Clamp(($Attack / ( $Defense * $DefMultiplier )), 0.01, 2)
        }
        Write-Debug "With defense of $Defense, damage multiplier is $damageMultiplier"
    }

    # Return the total number, rounded up and forced to be positive
    $totalDamage = [System.Math]::Max(([System.Math]::Ceiling($baseDamage * $damageMultiplier)), 0)
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
        [switch]$IgnoreResistance,

        # Number of targets being hit; used for certain special affinities/resistances
        [Parameter()]
        [ValidateSet('single', 'multi', 'all')]
        [string]$TargetClass = 'single'
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
                        TargetClass = $TargetClass
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
    if ($null -eq $Class -or $Class -eq 'weapon') {
        Write-Debug 'could not find a weapon damage class - either attacker is not the player or player has no equipped weapon'
        $Class = 'physical' # give up and assume it's physical. it's a weapon, after all, right?
    }
    if ($null -eq $Type -or $Type -eq 'weapon') {
        Write-Debug 'could not find a weapon damage type - either attacker is not the player or player has no equipped weapon'
        $Type = 'standard' # give up and assume it's normal
    }

    if (-not $IgnoreAffinity) {
        $classBonus = $Attacker.affinities.element.$Class.value
        $typeBonus = $Attacker.affinities.element.$Type.value
        $targetBonus = $Attacker.affinities.target.$TargetClass.value
        if ($classBonus) {
            Write-Debug "increasing $Damage $Class damage by $classBonus (class)"
            $Damage = [System.Math]::Max($Damage * (1 + $classBonus), 0)
        }
        if ($typeBonus) {
            Write-Debug "increasing $Damage $Type damage by $typeBonus (type)"
            $Damage = [System.Math]::Max($Damage * (1 + $typeBonus), 0)
        }
        if ($targetBonus) {
            Write-Debug "increasing $Damage damage by $targetBonus (target)"
            $Damage = [System.Math]::Max($Damage * (1 + $targetBonus), 0)
        }
        Write-Debug "-> (now $Damage)"
    }

    if (-not $IgnoreResistance) {
        $classResist = $Target.resistances.element.$Class.value
        $typeResist = $Target.resistances.element.$Type.value
        $targetResist = $Target.resistances.target.$TargetClass.value
        if ($classResist) {
            Write-Debug "reducing $Damage $Class damage by $classResist (class)"
            $Damage = [System.Math]::Max($Damage * (1 - $classResist), 0)
        }
        if ($typeResist) {
            Write-Debug "reducing $Damage $Type damage by $typeResist (type)"
            $Damage = [System.Math]::Max($Damage * (1 - $typeResist), 0)
        }
        if ($targetResist) {
            Write-Debug "reducing $Damage damage by $targetResist (target)"
            $Damage = [System.Math]::Max($Damage * (1 - $targetResist), 0)
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

    $totalCritChance = 0.05 + $EquipBonus + $SkillBonus + $StatusBonus
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
