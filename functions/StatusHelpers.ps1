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
        $statusApplyChance = $status.chance * ( 1 - $Target.resistances.status."$($status.id)".value )
        Write-Debug "checking if status applies: chance is $($status.chance) * 1 - $($Target.resistances.status."$($status.id)".value ?? '(none)') = $statusApplyChance"
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
        $statusInfo = $State.data.status."$($status.id)"
        $statusData = @{
            guid = (New-Guid).Guid
            stack = $status.stack
            intensity = $status.intensity
            pow = $status.powOverride ?? $Skill.data.pow
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

function Remove-Status {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Attacker,

        [Parameter(Mandatory = $true)]
        [hashtable]$Target,

        [Parameter(Mandatory = $true)]
        [hashtable]$Skill
    )

    # Update state
    $State.game.battle.attacker = $Attacker.name
    $State.game.battle.defender = $Target.name

    # Collect GUIDs to remove after iteration (avoid modifying collection while iterating)
    $guidsToRemove = New-Object -TypeName System.Collections.ArrayList

    foreach ($removal in $Skill.data.removeStatus) {
        Write-Debug "Attempting removals for status $($removal.id) against $($Target.name)"

        # If the target has no instances of this status, skip
        if ($null -eq $Target.status."$($removal.id)") {
            Write-Debug "No stacks of $($removal.id) on $($Target.name); skipping"
            continue
        }

        # For every instance of the status, check chance and reduce stacks accordingly
        foreach ($instance in $Target.status."$($removal.id)" ) {
            $chance = $removal.chance
            Write-Debug "checking removal chance $chance"
            if ($chance -lt (Get-RandomPercent)) {
                Write-Debug "did not remove instance $($instance.guid) of $($removal.id)"
                continue
            }

            # Subtract stacks, but do not fully remove now
            $oldStack = $instance.stack
            $instance.stack = $instance.stack - $removal.stack # todo: double check that this gets the real reference
            Write-Debug "reduced $($removal.id) $($instance.guid) from $oldStack to $($instance.stack)"

            if ($instance.stack -le 0) {
                $guidsToRemove.Add($instance.guid) | Out-Null
            }
        }
    }

    # Now perform final removals
    if ($guidsToRemove.Count -gt 0) {
        Write-Debug "will remove the following status guids: [$($guidsToRemove -join ', ')]"
        $State | Remove-StatusByGuid -Character $Target -Guids $guidsToRemove
    }
}

# todo: there's seemingly some sort of bug where if a status expires at the start of your turn, then you re-apply it with an item, the new status doesn't apply. no idea why that's happening.
# (??? - cannot reproduce??? ^)
function Apply-StatusEffects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character,

        [Parameter(Mandatory = $true)]
        [ValidateSet('passive', 'turnStart', 'turnEnd', 'onHit', 'onDeath')]
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
                Write-Debug "getting status info for $statusId ($($status.guid))"
                $statusInfo.$statusId = $State.data.status.$statusId
            }

            # Print description if this is a turn start status and we haven't already written its description this turn
            if ($Phase -eq 'turnStart') {
                if (-not ($statusId -in $alreadyWritten)) {
                    # Almost all statuses use this property for their description, so set it if it's not right (usually happens out of battle when data is cleared)
                    if ($State.game.battle.currentTurn.characterName -ne $Character.name) {
                        Write-Debug "override: setting currentTurn name to $($Character.name)"
                        Set-HashtableValueFromPath -Hashtable $State -Path 'game.battle.currentTurn.characterName' -Value $Character.name
                    }

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

                        # Check for faction damage
                        if ($_ -match 'faction') {
                            Write-Debug 'effect is faction-based; verifying extra targets'
                            $targets = switch ($data.faction) {
                                # The isActive check is particularly important - avoids applying to dead characters, which can cause infinite loops if this is an onDeath effect
                                # (even if not, it looks weird to have dead characters taking damage)
                                'own' { $State.game.battle.characters | Where-Object { $_.faction -eq $Character.faction -and $_.isActive } }
                                'opposite' { $State.game.battle.characters | Where-Object { $_.faction -ne $Character.faction -and $_.isActive } }
                                # Ignore self and allies to avoid triggering onHit effects when a character/ally provides buffs, for instance (technically a "hit")
                                'attacker' { $State.game.battle.characters | Where-Object { $_.name -eq $State.game.battle.attacker -and $_ -ne $Character -and $_.faction -ne $Character.faction -and $_.isActive } }
                                default { Write-Warning "unknown faction '$($data.faction)' in status $statusId ($($status.guid)); will not apply" }
                            }

                            Write-Debug "will apply to the following targets: [$($targets.name -join ', ')]"
                            foreach ($target in $targets) {
                                Write-Debug "applying to $($target.name)..."
                                if ($data.faction -ne 'own' -and $Phase -eq 'onHit') {
                                    # Print a message to inform the attacker why they're taking damage
                                    Write-Host -ForegroundColor Blue "↩️ $($target.name) takes retaliatory damage!"
                                }
                                $State | Invoke-DamageEffect -Expression $expression -Status $status -Target $target @splat -DoNotRemoveStatuses
                            }
                        } else {
                            # Verify we aren't doing self-targeted damage onDeath (causes infinite loop as the damage kills us again)
                            if ($Phase -eq 'onDeath' -and (-not $splat.AsHealing)) {
                                Write-Debug "skipping self-targeted damage onDeath effect for $($Character.name) ($statusId ($($status.guid)))"
                                continue
                            }

                            # Ship it normally
                            $State | Invoke-DamageEffect -Expression $expression -Status $status -Target $Character @splat -DoNotRemoveStatuses
                        }

                    }
                    'skipTurn' {
                        Write-Debug "setting skipTurn flag to $data for $($Character.name) due to $statusId ($($status.guid))"
                        $Character.skipTurn = $data
                    }
                    # todo: attrib, stats, affinities, resistances all have very similar code - can we combine them?
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
                                    $number = Parse-BattleExpression -Expression $actionRaw.Value -Status $status -TargetValue $Character.attrib.$attrib.max
                                    # Using 'max' instead of $subAttrib here because "t" is generally used in effects relative to max, not current

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
                        Write-Debug "modifying stats due to $statusId ($($status.guid))"
                        # similar to attribs, but with a slightly different flow
                        foreach ($statRaw in $data.GetEnumerator()) {
                            # atk, acc, spd, etc.
                            $stat = $statRaw.Key
                            foreach ($activity in $statRaw.Value.GetEnumerator()) {
                                # mult, buff, etc.
                                $action = $activity.Key
                                $number = Parse-BattleExpression -Expression $activity.Value -Status $status -TargetValue $Character.stats.$stat.value

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
                    { $_ -match 'affinities|resistances' } {
                        Write-Debug "modifying $case due to $statusId ($($status.guid))"
                        foreach ($affResCategory in $data.GetEnumerator()) {
                            # e.g. 'element', 'status', etc.
                            $affResCategoryName = $affResCategory.Key
                            foreach ($affResRaw in $affResCategory.Value.GetEnumerator()) {
                                # e.g. 'fire', 'physical', etc.
                                $affRes = $affResRaw.Key
                                foreach ($activity in $affResRaw.Value.GetEnumerator()) {
                                    # mult, buff, etc.
                                    $action = $activity.Key
                                    $number = Parse-BattleExpression -Expression $activity.Value -Status $status -TargetValue $Character."$case"."$affRes".value

                                    # Do the thing
                                    Write-Debug "modifying $case/$affResCategoryName/$affRes by ${action}:$number"
                                    $Character.activeEffects.Add(@{
                                        path = "$case.$affResCategoryName.$affRes.value"
                                        action = $action
                                        number = $number
                                        guid = $status.guid
                                        source = "status/$statusId"
                                    }) | Out-Null
                                }
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
        if ($statusGuidsToRemove.Count -gt 0) {
            # Remove statuses and their AEs by GUID
            $State | Remove-StatusByGuid -Character $Character -Guids $statusGuidsToRemove
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

function Remove-StatusByGuid {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline=$true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character,

        [Parameter(Mandatory = $true)]
        [System.Collections.IEnumerable]$Guids
    )

    Write-Debug "removing statuses from $($Character.name) with guids: [$($Guids -join ', ')]"
    $statusClassesToRemove = New-Object -TypeName System.Collections.ArrayList

    foreach ($guid in $Guids) {
        Write-Debug "removing status guid $guid from $($Character.name)"

        # Remove active effects tied to this guid
        foreach ($effect in ($Character.activeEffects | Where-Object -Property guid -EQ $guid)) {
            Write-Debug "removing activeEffect with guid $guid (source: $($effect.source))"
            $Character.activeEffects.Remove($effect)
        }

        # Remove status instances matching guid from any status class
        foreach ($statusClass in $Character.status.GetEnumerator()) {
            foreach ($status in ($statusClass.Value | Where-Object -Property guid -EQ $guid)) {
                Write-Debug "removing status $($statusClass.Key) instance $guid"

                $Character.status."$($statusClass.Key)".Remove($status)
                if ($Character.status."$($statusClass.Key)".Count -le 0) {
                    Write-Debug "all out of $($statusClass.Key) - will remove class"
                    $statusClassesToRemove.Add("$($statusClass.Key)") | Out-Null
                }
            }
        }
    }

    # Remove empty classes
    foreach ($statusClass in $statusClassesToRemove) {
        Write-Debug "removing empty status class $statusClass from $($Character.name)"
        $Character.status.Remove($statusClass)

        # Optionally show a remove description if present in data
        $statusInfo = $State.data.status."$($statusClass)"
        if ($statusInfo -and $statusInfo.removeDesc) {
            Write-Host -ForegroundColor Blue "🧼 $($State | Enrich-Text $statusInfo.removeDesc)"
        }
    }
}
