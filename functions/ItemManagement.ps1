function Show-Inventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter()]
        [switch]$JustBrowsing,

        [Parameter()]
        [switch]$Useable,

        [Parameter()]
        [switch]$Equippable,

        [Parameter()]
        [string]$EquipSlot,

        [Parameter()]
        [string]$SortPropertyCategory = 'data',

        [Parameter()]
        [string]$SortProperty = 'name'
    )

    # Filter items based on switches
    $itemsToDisplay = foreach ($item in $State.items.GetEnumerator()) {
        $itemData = $State.data.items."$($item.Key)"

        if ($Useable -and $null -eq $itemData.useData) {
            Write-Debug "$($item.Key) is not useable; skipping"
            continue
        }

        if ($Equippable -and $null -eq $itemData.equipData) {
            Write-Debug "$($item.Key) is not equippable; skipping"
            continue
        }

        if ($EquipSlot -and $itemData.equipData.slot -ne $EquipSlot) {
            Write-Debug "$($item.Key) has slot '$($itemData.equipData.slot)' which does not match '$EquipSlot'; skipping"
            continue
        }

        Write-Debug "will display $($item.Key)"
        @{ id = $item.Key; data = $State.data.items."$($item.Key)"; playerData = $item.Value }
    }

    if ($null -eq $itemsToDisplay) {
        $adjective = ''
        if ($Useable) { $adjective += 'useable ' }
        if ($Equippable) { $adjective += 'equippable ' }
        if ($Useable -and $Equippable) { $adjective = 'useable or equippable ' }
        if ($Equippable -and $EquipSlot) { $slotText = " for that slot" }
        Write-Host "You don't have any ${adjective}items${slotText}..."
        return $null
    }

    # todo: Choose the sorting method
    # if ($Useable) { $SortProperty =  }

    # Display the items
    $choices = foreach ($item in $itemsToDisplay | Sort-Object -Property { $_.$SortPropertyCategory.$SortProperty } ) {
        $itemData = $item.data
        Write-Debug "displaying item $($item.id)"
        # Each one gets its own line
        $badge = ''
        $color = 'Gray'
        if ($itemData.itemType -eq 'quest') { $color = 'Magenta'; $badge += '🏅 ' }
        if ($itemData.useData) { $color = 'DarkCyan'; $badge += '🎯 ' }
        if ($itemData.useData.teachesSkill) { $color = 'DarkYellow'; $badge += '📜 ' }
        if ($itemData.equipData -and -not ($itemData.equipData.weaponData -or $itemData.equipData.barrierData)) { $color = 'Blue'; $badge += '👕 ' }
        if ($itemData.equipData.weaponData) { $color = 'DarkMagenta'; $badge += '⚔️ ' }
        if ($itemData.equipData.barrierData) { $color = 'DarkMagenta'; $badge += '🛡️ ' }
        if ($item.playerData.equipped) { $color = 'DarkGreen'; $badge += '✅ ' }
        if ($badge -eq '') { $badge = '🛍️ ' } # default badge
        Write-Host -ForegroundColor $color "$($item.playerData.number)x $($itemData.name) | $badge| " -NoNewline
        Write-Host ($State | Enrich-Text $itemData.description)

        # Print out the name for choice use
        $itemData.name
    }

    # Select an item, if desired
    Write-Debug 'presenting inventory prompt'
    $prompt = '> '
    if ($Useable) { $prompt = 'Use which item?' }
    if ($Equippable) { $prompt = 'Equip which item?' }
    $choice = $State | Read-PlayerInput -Prompt $prompt -Choices $choices -AllowNullChoice
    if ($null -eq $choice) {
        return $null
    } else {
        if ($JustBrowsing) {
            # todo: if not under the useable or equippable filters, maybe print all the info about the object? (or extra inspect description maybe?)
            return
        } else {
            return ($itemsToDisplay | Where-Object { $_.data.name -eq $choice } ).id
        }
    }
}

function Add-GameItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [int]$Number,

        [Parameter()]
        [ValidateSet('items', 'trainItems')]
        [string]$Location = 'items'
    )

    # todo: consider adding a storage / encumbrance system so that items have to be stored in the train. (but why?)
    # ^ if I do that, need to add Move-GameItem or something to transfer between storages

    Write-Verbose "Adding $Number instances of $Id"
    $details = $State.data.items.$Id
    if ($State.$Location.$Id) {
        # add to existing stock
        $State.$Location.$Id.number += $Number
    } else {
        # doesn't exist, so create it
        $State.$Location.$Id = @{
            number = $Number
            equipped = $false
            guid = (New-Guid).Guid
        }
    }
    Write-Host -ForegroundColor Green "🎒 Got ${Number}x $($details.name)"
}

function Remove-GameItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter(Mandatory = $true)]
        [int]$Number,

        [Parameter()]
        [ValidateSet('items', 'trainItems')]
        [string]$Location = 'items',

        [Parameter()]
        [string]$StolenBy
    )

    Write-Verbose "Removing $Number instances of $Id"
    if ($State.$Location.$Id) {
        $name = $State.data.items.$Id.name

        # Delete if removing all (or more than) we have; otherwise subtract normally
        if ($Number -ge $State.$Location.$Id.number) {
            # If it's an equipped item, and we're removing the last one, unequip it first
            if ($State.$Location.$Id.equipped) {
                $State | Unequip-GameItem -Id $Id -StolenBy $StolenBy
            }

            $Number = $State.$Location.$Id.number # can't remove more than we have, so set it here for the print
            $State.$Location.Remove($Id)
        } else {
            $State.$Location.$Id.number -= $Number
        }
        Write-Host -ForegroundColor DarkYellow "🗑️ Lost ${Number}x $name"
    } else {
        Write-Verbose 'No item to remove!'
    }
}

function Equip-GameItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )
    # Vars
    $data = $State.data.items.$Id
    $guid = $State.items.$Id.guid

    # Sanity check
    if ($null -eq $data.equipData) {
        Write-Warning "$Id is not in the inventory or is not equippable!"
        return
    }

    # Remove whatever was previously equipped, if any
    $alreadyEquippedItem = $State | Find-EquippedItem -Slot $data.equipData.slot
    if ($null -ne $alreadyEquippedItem) {
        Write-Verbose "Unequipping already equipped item $alreadyEquippedItem in this slot ($($data.equipData.slot))"
        $State | Unequip-GameItem -Id $alreadyEquippedItem
        if ($alreadyEquippedItem -eq $Id) {
            # we just unequipped the item we're trying to put on, so assume we wanted to take it off and just return
            return
        }
    }

    Write-Host "You equip the $($data.name)."
    $State.items.$Id.equipped = $true
    $State.equipment."$($data.equipData.slot)" = $Id

    # Slightly different from the status version of this, so nearly-duplicate code (darn)
    # todo: see if we can unify this stuff
    foreach ($effectClass in $data.effects.GetEnumerator()) {
        switch ($effectClass.Key) {
            'attrib' {
                Write-Debug "modifying attributes due to $Id ($guid))..."
                foreach ($attribRaw in $effectClass.Value.GetEnumerator()) {
                    # hp, bp, or mp, usually
                    $attrib = $attribRaw.Key
                    foreach ($subAttribRaw in $attribRaw.Value.GetEnumerator()) {
                        # regen, max, whatever
                        $subAttrib = $subAttribRaw.Key
                        foreach ($actionRaw in $subAttribRaw.Value.GetEnumerator()) {
                            # mult, buff, etc.
                            $action = $actionRaw.Key
                            $number = $actionRaw.Value

                            # Finally, we can do the thing
                            Write-Debug "modifying $attrib/$subAttrib by ${action}:$number"
                            $State.player.activeEffects.Add(@{
                                path = "attrib.$attrib.$subAttrib"
                                action = $action
                                number = $number
                                guid = $guid
                                source = "equipment/$Id"
                            }) | Out-Null
                        }
                    }
                }
            }
            'stats' {
                Write-Debug "modifying stats due to $Id ($guid)"
                # similar to attribs, but with a slightly different flow
                foreach ($statRaw in $effectClass.Value.GetEnumerator()) {
                    # atk, acc, spd, etc.
                    $stat = $statRaw.Key
                    foreach ($activity in $statRaw.Value.GetEnumerator()) {
                        # mult, buff, etc.
                        $action = $activity.Key
                        $number = $activity.Value

                        # Do the thing
                        Write-Debug "modifying $stat by ${action}:$number"
                        $State.player.activeEffects.Add(@{
                            path = "stats.$stat.value"
                            action = $action
                            number = $number
                            guid = $guid
                            source = "equipment/$Id"
                        }) | Out-Null
                    }
                }
            }
            { $_ -match 'resistances|affinities' } {
                # thankfully, these guys have identical structures and can be handled at the same time
                Write-Debug "modifying $($effectClass.Key) due to $Id ($guid)"
                foreach ($raw in $effectClass.Value.GetEnumerator()) {
                    # element or status
                    $class = $raw.Key
                    foreach ($bonusRaw in $raw.Value.GetEnumerator()) {
                        # modify individual resistances/affinities within the class
                        $bonusName = $bonusRaw.Key
                        $number = $bonusRaw.Value
                        Write-Debug "modifying $class/$bonusName by $number"
                        $State.player.activeEffects.Add(@{
                            path = "$($effectClass.Key).$class.$bonusName.value"
                            action = 'buff' # no 'mult' possible
                            number = $number
                            guid = $guid
                            source = "equipment/$Id"
                        }) | Out-Null
                    }
                }
            }
            default { Write-Warning "Unexpected item action $($effectClass.Key) found in item $Id ($guid)" }
        }
    }

    # Equipping complete; update those values
    $State | Update-CharacterValues -Character $State.player
}

function Unequip-GameItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Id,

        [Parameter()]
        [string]$StolenBy
    )
    # Vars
    $data = $State.data.items.$Id
    $guid = $State.items.$Id.guid

    # Sanity checks
    if ($null -eq $data.equipData) {
        Write-Warning "$Id is not equippable!"
        return
    }
    if (-not $State.items.$Id.equipped) {
        Write-Warning "$Id is not equipped!"
        return
    }
    Write-Verbose "Unequipping item $Id"

    # Remove active effects
    Write-Debug "removing equipment effects with guid $guid from $($State.player.name) (from $Id)"
    foreach ($effect in ($State.player.activeEffects | Where-Object -Property guid -EQ $guid)) {
        # remove all AEs derived from this item
        $State.player.activeEffects.Remove($effect)
    }

    # Officially unequip it
    if ($StolenBy) {
        Write-Host "$StolenBy takes off your $($data.name)."
    } else {
        Write-Host "You take off the $($data.name)."
    }
    $State.items.$Id.equipped = $false
    $State.equipment."$($data.equipData.slot)" = $null

    # Update values
    $State | Update-CharacterValues -Character $State.player
}

function Find-EquippedItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Slot
    )

    # Get ID from equipment list
    $id = $State.equipment.$Slot
    Write-Verbose "'$($id ?? '(nothing)')' found for equipped slot $Slot"

    # Return item data from main item list
    return $id
}

function Find-EquippableItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Slot
    )

    $availableItems = foreach ($item in $State.items.GetEnumerator()) {
        if ($State.data.items."$($item.Key)".equipData.slot -eq $Slot) {
            Write-Debug "found matching item $($item.Key) for slot $Slot"
            $item.Key
        }
    }

    if ($availableItems.Count -eq 0) {
        Write-Debug "could not find any equippable items for slot $Slot"
        return $null
    } else {
        return $availableItems
    }
}

function Use-GameItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )
    # Sanity checks
    $data = $State.data.items.$Id
    $guid = $State.items.$Id.guid
    $number = $State.items.$Id.number
    if ($null -eq $data.useData) {
        Write-Warning "$Id is not usable"
        return
    }
    if ($number -lt 1) {
        Write-Warning "Attempted to use item $($data.name), but number available was $number! Clearing invalid item entry."
        $State | Remove-GameItem -Id $Id -Number 1
        return
    }

    # It exists and is usable, so get target if applicable
    if ($data.useData.target -gt 0) {
        if ($data.useData.selfTargetOnly) {
            Write-Debug "$Id is self-target only, so targeting player"
            $target = $State.player
        } elseif ($State.game.battle.phase -eq 'active') {
            Write-Debug "$Id can be targeted and in battle; showing battle menu"
            $target = $State | Show-BattleTargetMenu -Character $State.player -Action $State.data.skills.special.'use-item'
        } else {
            # Not in battle but is not self-target only, so prompt for confirmation
            $response = $State | Read-PlayerInput -Prompt "Use $($data.name) on yourself? (Y/N)" -Choices @('Y', 'N')
            if ($response -eq 'Y') {
                $target = $State.player
            } else {
                Write-Host 'You changed your mind...'
                return
            }
        }
    }

    # If it has a use time, prompt for confirmation
    if ($data.useData.useTime) {
        $useTime = [timespan]$data.useData.useTime

        # Sanity check; you can't spend two hours reading a book in the middle of a battle
        if ($State.game.scene.type -eq 'battle' -and $useTime -gt (New-TimeSpan -Seconds 10)) {
            Write-Host "You don't have time to use $($data.name) in the middle of battle!"
            Write-Host 'You changed your mind...'
            return
        }

        $response = $State | Read-PlayerInput -Prompt "🕑 It will take you $useTime to use $($data.name). Use the item? (Y/N)" -Choices @('Y', 'N') -AllowNullChoice
        if ($response -ne 'Y') {
            Write-Host 'You changed your mind...'
            return
        }
    }

    # Perform the effects
    foreach ($effect in $data.effects.GetEnumerator()) {
        Write-Debug "applying $($effect.Key) from $Id ($guid)"
        switch ($effect.Key) {
            { $_ -match 'damage|heal' } {
                if ($_ -match 'heal') { $splat = @{ AsHealing = $true }; Write-Debug 'effect is healing' } else { $splat = @{}; Write-Debug 'effect is damage' }
                $State | Invoke-DamageEffect -Expression $effect.Value.expression -Item $State.items.$Id -Target $target @splat
            }
            'status' {
                foreach ($actionCategory in $data.effects.status.GetEnumerator()) {
                    $action = $actionCategory.Key
                    foreach ($status in $actionCategory.Value) {
                        Write-Debug "performing action $action on status $status"
                        switch ($action) {
                            'add' {
                                Write-Debug "adding status $($status.id)"
                                # Construct a fake skill to send to Add-Status
                                $fakeStatusSkill = @{
                                    id = $data.id
                                    name = $data.name
                                    data = @{
                                        class = $data.useData.class
                                        type = $data.useData.type
                                        pow = $data.useData.pow
                                        status = @(
                                            $status
                                        )
                                    }
                                }

                                # Add the status
                                $State | Add-Status -Attacker $State.player -Target $target -Skill $fakeStatusSkill
                            }
                            'remove' {
                                foreach ($ae in ($State.player.activeEffects | Where-Object -Property source -EQ "status/$status")) {
                                    Write-Debug "removing AE with guid $($ae.guid) from source $($ae.source)"
                                    $State.player.activeEffects.Remove($ae)
                                }
                                Write-Debug "removing status class $status"
                                $State.player.status.Remove($status)
                                Write-Host -ForegroundColor DarkCyan "🧼 Cleared status '$($State.data.status.$status.name)'"
                            }
                            default { Write-Warning "unknown action '$action' on status '$status' in item $Id ($guid)" }
                        }
                    }
                }
            }
            'learnSkill' {
                $atLeastOneSkillLearned = $false
                foreach ($skill in $data.effects.learnSkill) {
                    Write-Debug "Learning skill $($skill.category)/$($skill.id)"
                    $skillInfo = $State.data.skills."$($skill.category)"."$($skill.id)"

                    # Make sure the player doesn't already know this skill
                    if ($target.skills."$($skill.category)" | Where-Object -Property id -EQ $skill.id) {
                        Write-Host "You already know how to use $($skillInfo.name)!"
                        continue
                    } else {
                        # Add the ID to the target's skill list (if room)
                        $atLeastOneSkillLearned = $true
                        $State | Add-SkillIfRoom -Character $target -Category $skill.category -Id $skill.id
                    }
                }

                # If all the skills in this book are invalid, don't penalize them for the time spent
                if (-not $atLeastOneSkillLearned) {
                    Write-Host 'You changed your mind...'
                    return
                }
            }
            default { Write-Warning "Unexpected item action $_ found in item $Id ($guid)" }
        }
    }

    # Write use desc
    Write-Host ($State | Enrich-Text $data.useDescription)

    # Handle consumables
    if ($data.itemType -eq 'consumable') {
        $State | Remove-GameItem -Id $Id -Number 1
    }

    # Add time if applicable
    if ($useTime) {
        $State | Add-GlobalTime -Time $useTime
    }
}
