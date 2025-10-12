function Show-EquipMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )

    # Vars, info
    $slotData = Get-EquipmentSlotFlavorInfo -All

    while ($true) {
        # Display stats for informed equipping
        $State | Show-BattleCharacterInfo -Character $State.player -Inspect -NoDescription

        # Display currently-equipped items
        Write-Host 'Current equipment:'
        foreach ($slotRaw in $slotData.GetEnumerator()) {
            $slotId = $slotRaw.Key
            $slot = $slotRaw.Value
            $item = $State | Find-EquippedItem -Slot $slotId
            $itemData = $null -ne $item ? $State.data.items.$item : $null

            # Name and color it appropriately
            $itemName = $itemData.name ?? '(normal)'
            if (-not $itemData.name) {
                # no item
                $itemColor = 'DarkGray'
            } else {
                # item!
                if ($itemData.equipData.weaponData.type) {
                    # Flavor it from the weapon type
                    $damageFlavor = Get-DamageTypeFlavorInfo -Class $itemData.equipData.weaponData.class -Type $itemData.equipData.weaponData.type
                    $secondBadge = '⭐'
                } elseif ($itemData.effects.affinities.element) {
                    # Flavor it from the primary affinity
                    $damageFlavor = Get-DamageTypeFlavorInfo -Type ($itemData.effects.affinities.element.GetEnumerator() | Select-Object -First 1).Key
                    $secondBadge = '⚔️'
                } elseif ($itemData.effects.resistances.element) {
                    # Flavor it from the primary resistance
                    $damageFlavor = Get-DamageTypeFlavorInfo -Type ($itemData.effects.resistances.element.GetEnumerator() | Select-Object -First 1).Key
                    $secondBadge = '🛡️'
                } else {
                    # this item is not very cool >:(
                    $damageFlavor = @{ badge = '👕'; color = 'Gray' }
                    $secondBadge = $null
                }

                $itemColor = $damageFlavor.color
                $itemName = "$($damageFlavor.badge)$secondBadge $itemName"
            }

            # Print it
            Write-Host -ForegroundColor $slot.color "$($slot.badge) $($slot.name): " -NoNewline
            Write-Host -ForegroundColor $itemColor "$itemName" -NoNewline

            # For clarity, print how many available items with this slot exist
            $availableItems = $State | Find-EquippableItems -Slot $slotId
            $availableItemCount = $null -ne $availableItems -and $availableItems.GetType().BaseType -notlike '*Array' ? 1 : $availableItems.Count # (account for the stupid "single-item arrays don't exist" thing)
            $adjustedCount = $null -ne $item ? $availableItemCount - 1 : $availableItemCount # (subtract the item that's already equipped)
            if ($adjustedCount -gt 0) {
                Write-Host -ForegroundColor DarkGray " ($adjustedCount available)"
            } else {
                Write-Host ''
            }
        }

        # Prompt which slot to equip
        $choice = $State | Read-PlayerInput -Prompt 'Change equipment in which slot? (or <enter> to cancel)' -Choices ($slotData.GetEnumerator() | ForEach-Object { $_.Value.name }) -AllowNullChoice
        if ([string]::IsNullOrEmpty($choice)) {
            Write-Host 'You stopped changing your equipment.'
            return
        }

        # Get an item for that slot
        Write-Host "Available '$choice' items:"
        $id = $State | Show-Inventory -Equippable -EquipSlot (($slotData.GetEnumerator() | Where-Object { $_.Value.name -eq $choice }).Key)

        # Equip the item
        if ($id) {
            $State | Equip-GameItem -Id $id
        } else {
            Write-Host 'You changed your mind...'
        }

        # Cut the player off if we're in battle. Otherwise, add time and continue
        if ($State.game.scene.type -eq 'battle') {
            return
        } else {
            $State | Add-GlobalTime -Time '00:01:00'
        }
    }
}

function Find-GameItemData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true, ParameterSetName = 'guid')]
        [string]$Guid
    )

    foreach ($item in $State.items.GetEnumerator()) {
        if ($item.Value.guid -eq $Guid) {
            Write-Debug "found item '$($item.Key)' for guid '$($item.Value.guid)'"
            return $State.data.items."$($item.Key)"
        }
    }
}
