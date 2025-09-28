function Invoke-SpecialFlee {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Attacker,

        [Parameter(Mandatory = $true)]
        [hashtable]$Skill
    )

    # Get character speed and the highest speed on the opposing faction to see if the flee is successful
    $ourSpeed = $Attacker.stats.spd.value
    $enemySpeed = ($State.game.battle.characters |
        Where-Object -Property faction -NE $Attacker.faction).stats.spd.value |
        Sort-Object -Descending |
        Select-Object -First 1
    # 10% base chance, affected by difficulty. Very high difficulty levels can even reduce the flee chance
    $difficultyBaseChance = 0.3 - (0.1 * $State.options.difficulty)
    $fleeBonus = $Attacker.id -eq 'player' ? $State.game.battle.cumulativeFleeBonus : 0 # only the player gets the bonus
    $fleeChance = $difficultyBaseChance + ($ourSpeed / ( $enemySpeed * (1.5 * $State.options.difficulty) )) + $fleeBonus

    Write-Debug "flee chance: $difficultyBaseChance + ($ourSpeed / ( $enemySpeed * (1.5 * $($State.options.difficulty)))) + $($State.game.battle.cumulativeFleeBonus) = $fleeChance"
    if ($fleeChance -ge (Get-RandomPercent)) {
        Write-Host -ForegroundColor Blue "$($Attacker.name) escapes!"

        if ($Attacker.id -ne 'player') {
            # Enemy or non-player ally: just inactivate them and call it a day
            $Attacker.isActive = $false
            $Attacker.fled = $true # also need this for loot calculations
        } else {
            # Player escape, so we have to handle the scene transition
            $State.game.battle.victor = 'escaped'
            break mainBattleLoop
        }
    } else {
        Write-Host -ForegroundColor DarkGray "$($Attacker.name) could not get away..."

        # Cumulatively increase chance of future flee attempts based on difficulty
        if ($Attacker.id -eq 'player') {
            # 10% base chance, affected by difficulty (minimum 0)
            $State.game.battle.cumulativeFleeBonus += [System.Math]::Max(0.3 - (0.1 * $State.options.difficulty), 0)
        }
    }
}

function Invoke-SpecialInspect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Attacker,

        [Parameter(Mandatory = $true)]
        [hashtable]$Target,

        [Parameter()]
        [hashtable]$Skill
    )

    # Display info about a character on the field (the target)
    if ($null -eq $Target) {
        Write-Warning "No target present for targeted skill '$($Skill.id)' - cannot continue"
        return
    }

    # kind of a hack to get extra data for the bestiary
    if ($Skill.id -eq 'bestiary') {
        Write-Debug 'being called from the bestiary; adding extra flag'
        $splat = @{ Bestiary = $true }
    } else {
        $splat = @{}
    }

    if ($false) {
        # todo: make inspect more precise if the character equips a special item or something
        $State | Show-BattleCharacterInfo -Character $Target -Inspect @splat
    } else {
        # Imprecise version: vagueness only
        $State | Show-BattleCharacterInfo -Character $Target -Inspect -Vague @splat
    }
}

function Invoke-SpecialItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Attacker,

        [Parameter()]
        [hashtable]$Skill
    )

    # Get the item to use
    $id = $State | Show-Inventory -Useable

    # Use the item
    if ($id) {
        $State | Use-GameItem -Id $id
    } else {
        Write-Host 'You changed your mind...'
    }
}

function Invoke-SpecialEquip {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Attacker,

        [Parameter()]
        [hashtable]$Skill
    )

    # Used to have more logic; now is sort of vestigial since everything's in the shared function
    $State | Show-EquipMenu
}

function Invoke-SpecialSteal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Attacker,

        [Parameter(Mandatory = $true)]
        [hashtable]$Target,

        # Mandatory here; some skills have different steal categories or allowed items
        [Parameter(Mandatory = $true)]
        [hashtable]$Skill
    )

    # Vars
    $targetIsPlayer = ($Target.id -eq 'player')
    $stealData = $Skill.data.specialData

    # Get what items the target has
    $availableItems = if ($targetIsPlayer) {
        $State.items.Keys
    } else {
        $Target.loot.id
    }
    Write-Debug "found the following items: [$($availableItems -join ', ')]"

    if ($availableItems.Count -le 0) {
        Write-Host "$($Target.name) does not have any items to steal!"
        return
    }

    # Filter items based on allowed categories (most of these only apply against the player, as enemies don't use or equip items)
    if ($targetIsPlayer) {
        $stealableItems = New-Object -TypeName System.Collections.ArrayList
        foreach ($item in $availableItems) {
            # Check each item for validity
            if ($stealData.stealCategories -and $State.items.$item.data.itemType -notin $stealData.stealCategories) {
                Write-Debug "$item is not in category list [$($stealData.stealCategories -join ', ')] so is not a valid steal target (is $($State.items.$item.data.itemType))"
                continue
            }

            if (-not $stealData.canStealEquippedItem -and $State.items.$item.equipped) {
                Write-Debug "$item is equipped and stealing equipped items is disabled, so is not a valid target"
                continue
            }

            if ($stealData.mustStealEquippedItem -and -not $State.items.$item.equipped) {
                Write-Debug "$item is not equipped and stealing equipped items is required, so is not a valid target"
                continue
            }

            Write-Debug "$item is a valid steal target"
            $stealableItems.Add($item) | Out-Null
        }
    } else {
        Write-Debug "target $($Target.name) is not the player, so most restrictions do not apply. Adding all available items."
        $stealableItems = New-Object -TypeName System.Collections.ArrayList(,$availableItems)
    }

    # check if the filtered list is empty
    if ($stealableItems.Count -le 0) {
        Write-Host "$($Target.name) does not have any items that $($Skill.name) can steal."
        return
    }

    # We now have our non-empty filtered list. Let's steal something.
    $id = $stealableItems | Get-Random
    $details = Get-Content "$PSScriptRoot/../data/items/$id.json" | ConvertFrom-Json -AsHashtable
    Write-Debug "selected '$id' to steal"

    # get how many there are
    $availableNumber = if ($targetIsPlayer) {
        $State.items.$id.number
    } else {
        $lootDetails = $Target.loot | Where-Object -Property id -EQ $id
        if ($lootDetails.number) {
            $lootDetails.number
        } else {
            Get-Random -Minimum $lootDetails.min -Maximum ($lootDetails.max + 1)
        }
    }
    Write-Debug "there are ${availableNumber}x $id available to steal"

    # get how many we're allowed to take
    if ($stealData.stealAmount -eq 'all' -or $stealData.stealAmount -gt $availableNumber) {
        $number = $availableNumber
    } else {
        $number = $stealData.stealAmount
    }
    Write-Host "$($Attacker.name) steals ${number}x $($details.name) from $($Target.name)!"

    # take 'em
    if ($targetIsPlayer) {
        # Steal item *from* the player: remove item from player inventory and add it to attacker's loot pool as chance 1
        $State | Remove-GameItem -Id $id -Number $number -StolenBy $Attacker.name
        $Attacker.loot.Add(@{
            id = $id
            number = $number
            chance = 1
        }) | Out-Null
    } else {
        if ($Attacker.id -eq 'player') {
            # Player is stealing the item: remove from target's loot pool and add to player inventory
            $Target.loot.Remove($lootDetails)
            $State | Add-GameItem -Id $id -Number $number
        } else {
            # NPC is stealing from NPC: transfer between loot pools
            $Target.loot.Remove($lootDetails)
            $Attacker.loot.Add(@{
                id = $id
                number = $number
                chance = 1
            }) | Out-Null
        }
    }
}
