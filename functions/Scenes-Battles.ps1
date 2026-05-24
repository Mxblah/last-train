function Start-BattleScene {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Scene
    )

    # Initial battle setup (skipped if we're loading into a battle already in progress)
    if ($State.game.battle.phase -ne 'active') {
        # Read scene, prepare state
        Write-Verbose "Assembling battle $($Scene.id) with $($Scene.data.characters.enemy.Count) opponents"
        # todo: figure out a better way to force allies to be allies instead of adding faction overrides in the scene json
        $battleParticipants = @( @(@{id = 'player'}) + ( $State.party ?? $null ) + @($Scene.data.characters.ally) + @($Scene.data.characters.enemy) )
        Write-Debug "All battle IDs: $($battleParticipants.id -join ', ') ($($battleParticipants.GetType()))"
        $battleCharacters = New-Object -TypeName System.Collections.ArrayList
        foreach ($npc in $battleParticipants) {
            # Import actual data from the passed-in stub
            $battleCharacters.Add(($State | Import-BattleCharacter -Character $npc)) | Out-Null
        }

        $State.game.battle = @{
            phase = 'preparing'
            round = 0
            cumulativeFleeBonus = 0.0
            victor = $null
            currentTurn = @{}
            # Get a list of all the active characters, then sort by speed
            characters = New-Object -TypeName System.Collections.ArrayList(,($battleCharacters | Sort-Object { $_.stats.spd.value } -Descending))
            pendingCharacters = New-Object -TypeName System.Collections.ArrayList
        }

        # Handle multiple characters named the same thing
        Rename-ForUniquePropertyValues -List $State.game.battle.characters -Property 'name' -SuffixType 'Number'

        if ($DebugPreference -eq 'Continue') {
            Write-Debug "DUMPING BATTLE STATE"
            $State.game.battle
            Write-Debug "DUMPING BATTLE CHARACTERS"
            $State.game.battle.characters
        }

        Write-Verbose 'Handling special battle properties'
        if ($Scene.data.special.forceFirstTurn) {
            Write-Debug "forcing $($Scene.data.special.forceFirstTurn) to take first turn"
            # Ensure the designated id (usually "player") goes first by rearranging the list
            $State.game.battle.characters = New-Object -TypeName System.Collections.ArrayList(
                ,(@($State.game.battle.characters |
                    Where-Object -Property id -EQ $Scene.data.special.forceFirstTurn) +
                @($State.game.battle.characters |
                    Where-Object -Property id -NE $Scene.data.special.forceFirstTurn))
            )
        }
        if ($Scene.data.special.weather) {
            Write-Verbose "applying weather effect $($Scene.data.special.weather.id) to all participants - if applicable, atkOverride is $($Scene.data.special.weather.atkOverride)"
            if ($Scene.data.special.weather.globalChance -gt (Get-RandomPercent)) {
                $atkOverrideSplat = $null -ne $Scene.data.special.weather.atkOverride ? @{ AttackOverride = $Scene.data.special.weather.atkOverride } : @{}
                foreach ($character in $State.game.battle.characters) {
                    $State | Add-Status -Attacker @{name = $Scene.data.special.weather.id} -Target $character -Skill @{
                        data = @{
                            status = $Scene.data.special.weather
                            pow = $Scene.data.special.weather.pow
                            class = $Scene.data.special.weather.class
                        }
                    } @atkOverrideSplat
                }
            } else {
                Write-Verbose "... but it failed (had chance $($Scene.data.special.weather.globalChance))"
            }
        }
        if ($Scene.data.special.noSunDamage) {
            Write-Debug 'disabling sun damage for this battle'
            $State.game.battle.noSunDamage = $true
        }
        if ($Scene.data.special.guaranteedFlee) {
            Write-Debug 'adding 100% flee chance'
            $State.game.battle.cumulativeFleeBonus = 1
        }
        if ($Scene.data.special.cannotFlee) {
            Write-Debug 'disabling flee option'
            $State.game.battle.cannotFlee = $true
        }
        if ($Scene.data.special.noRegen) {
            Write-Debug "disabling regen for [$($Scene.data.special.noRegen -join ', ')]"
            $State.game.battle.noRegen = $Scene.data.special.noRegen
        }

        Write-Verbose 'Starting battle'
        $State.game.battle.phase = 'active'
        foreach ($entryDesc in ($State.game.battle.characters | Where-Object -Property id -NE 'player').entryDescription) {
            Write-Host -ForegroundColor Yellow ($State | Enrich-Text $entryDesc )
        }
        $State | Save-Game -Auto
    } else {
        # Assume a battle is already active and we've loaded in, so we need to quickly fix the arraylist collection types before starting
        Convert-AllChildArraysToArrayLists -Data $State.game.battle.characters

        # After that, we need to re-import the player and allies, since loading here breaks the reference between main state and battle state
        Write-Debug 'resuming battle: re-importing player'
        # This convoluted method with IndexOf and some other stuff is to ensure we get the reference, not just a copy of the object
        $State.game.battle.characters[
            $State.game.battle.characters.IndexOf(($State.game.battle.characters | Where-Object -Property id -EQ 'player'))
        ] = ($State | Import-BattleCharacter -Character $State.player)
        # For allies, same deal
        foreach ($ally in $State.game.battle.characters | Where-Object { $_.faction -eq 'ally' -and $_.id -ne 'player' }) {
            Write-Debug "resuming battle: re-importing $($ally.name)"
            $State.game.battle.characters[$State.game.battle.characters.IndexOf($ally)] = $State |
                Import-BattleCharacter -Character ($State.party |
                Where-Object -Property name -EQ $ally.name)
        }
    }

    # Perform the battle
    Write-Debug 'entering main battle loop'
    :mainBattleLoop while ($State.game.battle.phase -eq 'active') {
        $State.game.battle.round++
        $State | Show-TurnOrder
        $State | Add-GlobalTime -Time '00:00:10' -NoSunDamage:($State.game.battle.noSunDamage)

        # Do all the turns
        :battleTurnLoop foreach ($character in $State.game.battle.characters | Where-Object -Property isActive -EQ $true) {
            if ($character.isActive) {
                $State | Start-BattleTurn -Character $character
                if ($Character.id -eq 'player' -or ($Character.faction -eq 'ally' -and $Character.isPlayerControlled)) {
                    # Just print a newline to separate turns visually
                    Write-Host ''
                } else {
                    # Not a player-controlled character, so make sure the player is ready before continuing
                    Read-Host -Prompt '> '
                }
            } else {
                Write-Debug "$($character.name) became inactive before turn start; skipping them!"
            }

            # Check to see if only one faction is left and end the battle if so
            $remainingFactions = @( ($State.game.battle.characters |
                Where-Object -Property isActive -EQ $true).faction |
                Select-Object -Unique )
            if ($remainingFactions.Count -le 1) {
                # If yes, exit the loop
                if ($remainingFactions -eq 'ally') {
                    Write-Host -ForegroundColor Green "🏆 $($State.player.name)'s party is victorious!"
                } else {
                    Write-Host -ForegroundColor DarkRed "💀 $($State.player.name)'s party was defeated..."
                }
                $State.game.battle.victor = $remainingFactions
                break mainBattleLoop
            }
        }

        # Add any new guys that have been summoned in the last round
        if ($State.game.battle.pendingCharacters.Count -gt 0) {
            Write-Verbose "Adding $($State.game.battle.pendingCharacters.Count) new characters to in-progress battle"

            # Add to the actual battle list, then clear the pending list
            foreach ($character in $State.game.battle.pendingCharacters) {
                $State.game.battle.characters.Add(($State | Import-BattleCharacter -Character $character)) | Out-Null
            }
            $State.game.battle.pendingCharacters.Clear()

            # Fix name collisions (again)
            Rename-ForUniquePropertyValues -List $State.game.battle.characters -Property 'name' -SuffixType 'Number'
        }

        # Always re-sort in case speed changed over the course of the round (or a new guy has been added)
        $State.game.battle.characters = New-Object -TypeName System.Collections.ArrayList(,($State.game.battle.characters | Sort-Object { $_.stats.spd.value } -Descending))

        # End of round. Save if set, then continue
        $State | Save-Game -Auto
    }

    # Battle is complete, so wrap it up and return to whatever we were doing before the battle happened
    $State.game.battle.phase = 'ending'
    $State | Exit-Battle -Scene $Scene
}

function Import-BattleCharacter {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character
    )
    Write-Debug "importing $($Character.id)"

    # Load the main structure
    if ($Character.id -eq 'player') {
        $data = $State.player
    } elseif ($Character.attrib) {
        # we were passed a full character block (probably; at least attribs are there), so just import directly
        $data = $Character
    } else {
        # Json intermediary to break the reference and fully clone the data. Only allies and the player should keep the reference
        $data = $State.data.character."$($Character.id)" | ConvertTo-Json -Depth 99 -Compress | ConvertFrom-Json -AsHashtable
    }

    # Add to bestiary if not already there
    if ((-not $State.player.encyclopedia.bestiary."$($data.id)") -and $data.id -ne 'player') {
        Write-Verbose "Adding $($data.id) ($($data.name)) to player bestiary"
        $State.player.encyclopedia.bestiary."$($data.id)" = $data.name
    }

    # Mark as active
    $data.isActive = $true

    # Add an action queue if we don't already have one
    if ($null -eq $data.actionQueue) {
        $data.actionQueue = New-Object -TypeName System.Collections.ArrayList
    }

    # Apply any modifiers found, if applicable
    if ($Character.name) {
        $data.name = $Character.name
    }
    if ($Character.faction) {
        Write-Debug "overriding faction for $($data.name) to $($Character.faction)"
        $data.faction = $Character.faction
    }
    if ($Character.loot) {
        Write-Debug "adding loot items $($Character.loot.id -join ', ')"
        $data.loot += $Character.loot
    }
    if ($Character.isSummon) {
        $data.actionQueue.Add(@{ class = "idle"; id = "summon-arrive" }) | Out-Null
    }

    # Fix collection types for participants if needed
    Convert-AllChildArraysToArrayLists -Data $data

    # Ensure all the values are synced up before beginning
    $State | Update-CharacterValues -Character $data

    # Reset BP to max
    if ($data.attrib.bp.max -gt 0) {
        Write-Debug "restoring $($data.name)'s bp to $($data.attrib.bp.max)"
        $data.attrib.bp.value = $data.attrib.bp.max
    } else {
        Write-Debug "$($data.name) max bp <= 0"
    }

    return $data
}

function Start-BattleTurn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character
    )
    # Handle start of turn stuff
    $State.game.battle.currentTurn.characterName = $Character.name
    $State.game.battle.attacker = $Character.name
    $State.game.battle.defender = $Character.name

    # Attrib regen
    if (-not $State.game.battle.noRegen) {
        $State | Invoke-AttribRegen -Character $Character -All
    } else {
        # Only regen attribs that aren't disabled
        foreach ($attrib in (@('hp', 'mp', 'bp') | Where-Object { $_ -notin $State.game.battle.noRegen })) {
            $State | Invoke-AttribRegen -Character $Character -Attribute $attrib
        }
    }

    # Status stuff
    $State | Apply-StatusEffects -Character $Character -Phase 'turnStart'

    # Start of turn check to see if the character just died (due to a status or something)
    if ($Character.isActive -ne $true -or $Character.attrib.hp.value -le 0) {
        $State | Kill-Character -Character $Character
        return
    }

    if ($Character.skipTurn) {
        # can't act, so just say that
        Write-Host -ForegroundColor Blue "$($Character.name) is unable to act..."

        # (also clear queued action if any, due to interrupt)
        if ($Character.actionQueue.Count -ge 1) {
            Write-Host -ForegroundColor Blue "$($Character.name) lost their queued actions..."
            $Character.actionQueue.Clear()
        }

        # Continue
        if ($Character.id -eq 'player' -or ($Character.faction -eq 'ally' -and $Character.isPlayerControlled)) {
            Read-Host -Prompt '> '
        } else {
            Start-Sleep -Milliseconds $State.options.turnDelayMs
        }
    } else {
        Write-Host -ForegroundColor Blue "$($Character.name) prepares to act..."

        # Check if we have a queued action. If so, use it immediately, bypassing the normal turn
        if ($Character.actionQueue.Count -ge 1) {
            Write-Host -ForegroundColor Blue "$($Character.name) executes a queued action!"

            # Take the first action from the list and use it
            $action = $State | Select-BattleAction -Character $Character -QueuedAction $Character.actionQueue[0]
            $Character.actionQueue.RemoveAt(0) # remove it from the list now that it's been used
        } else {
            # If player or ally we control, display the menu. Otherwise, use their AI to determine what action to take.
            if ($Character.id -eq 'player' -or ($Character.faction -eq 'ally' -and $Character.isPlayerControlled)) {
                $action = $State | Show-BattleMenu -Character $Character
            } else {
                Start-Sleep -Milliseconds $State.options.turnDelayMs
                $action = $State | Select-BattleAction -Character $Character
                Start-Sleep -Milliseconds $State.options.turnDelayMs
            }
        }

        # Perform the chosen action
        if ($action) {
            $State | Invoke-BattleAction -Character $Character -Action $action
        } else {
            Write-Host -ForegroundColor Blue "$($Character.name) didn't select an action."
        }
    }

    # Status stuff
    $State | Apply-StatusEffects -Character $Character -Phase 'turnEnd'
}

function Show-TurnOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )
    # Round number
    Write-Host -ForegroundColor Blue "Round $($State.game.battle.round)" -NoNewline

    # write out each character's name in order
    foreach ($character in $State.game.battle.characters | Where-Object -Property isActive -EQ $true) {
        if ($character.id -eq 'player') { $color = 'Cyan' } elseif ($character.faction -eq 'ally') { $color = 'DarkGreen' } else { $color = 'DarkRed' }
        $badge = Get-PercentageHeartBadge -Value $character.attrib.hp.value -Max $character.attrib.hp.max
        Write-Host -ForegroundColor $color " ➡️ $badge $($character.name)" -NoNewline
    }

    # finish the line
    Write-Host -ForegroundColor Blue ' 🔁'
}

function Show-BattleCharacterInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character,

        # Hide precise numbers
        [Parameter()]
        [switch]$Vague,

        # Show stats and description
        [Parameter()]
        [switch]$Inspect,

        # Show an extra lore line (only works in Inspect mode)
        [Parameter()]
        [switch]$Bestiary,

        # Skip the inspect description (only works in Inspect mode)
        [Parameter()]
        [switch]$NoDescription,

        # Only display the first line (basic attribs)
        [Parameter()]
        [switch]$Short
    )
    # Display a concise list of character data, ideally on a single line
    if ($Character.id -eq 'player') { $color = 'Cyan' } elseif ($Character.faction -eq 'ally') { $color = 'DarkGreen' } else { $color = 'DarkRed'; }
    if ($Inspect) { $icon = '🔎' } else { $icon = '⭐' }
    Write-Host -ForegroundColor $color "$icon $($Character.name): " -NoNewline

    # Print HP, BP, and MP
    foreach ($attrib in $Character.attrib.GetEnumerator()) {
        $attribValue = if ($Bestiary -and $Character.id -ne 'player') { $attrib.Value.base } else { $attrib.Value.value }
        $badge = Get-AttribStatBadge -AttribOrStat $attrib.Key
        $color = Get-PercentageColor -Value $attribValue -Max $attrib.Value.max

        # Print it
        if ($Vague -and ($Character.id -ne 'player')) {
            # mult by 5, round, (divide by 5, times 100) (ie times 20) should give us roughly 20% increments
            # (catch divide-by-zero errors)
            $vaguePercent = try { [System.Math]::Round(($attribValue / $attrib.Value.max) * 5) * 20 } catch { 0 }
            Write-Host -ForegroundColor $color "$badge ~$vaguePercent% " -NoNewline
        } else {
            # Either precise, or we're looking at ourselves. And we deserve to know our own stats precisely.
            Write-Host -ForegroundColor $color "$badge $($attribValue)/$($attrib.Value.max) " -NoNewline
        }
    }

    # Add the missing newline
    Write-Host ''

    if ($Short) {
        Write-Debug 'short mode active; terminating inspection'
        return
    }

    # Add a status display to the next row
    Write-Host -ForegroundColor Cyan "$icon Status: " -NoNewline
    if ($Character.status.Count -le 0) {
        Write-Host 'Normal' -NoNewline
    } else {
        foreach ($statusClass in $Character.status.GetEnumerator()) {
            # Each status gets a color and the number of instances + highest stacks
            $statusInfo = $State.data.status."$($statusClass.Key)"
            $name = $statusInfo.name
            $color = $statusInfo.color
            $badge = $statusInfo.badge
            $instances = $statusClass.Value.Count
            $highestStack = $statusClass.Value.stack | Sort-Object -Descending | Select-Object -First 1
            $highestIntensity = try {
                # Round to two decimal places if needed
                [System.Math]::Ceiling(($statusClass.Value.intensity | Sort-Object -Descending | Select-Object -First 1), 2)
            } catch {
                # If that fails, just print the whole thing I guess
                ($statusClass.Value.intensity | Sort-Object -Descending | Select-Object -First 1)
            }

            # This is a "ghost status" that doesn't really exist and will be removed the next time statuses are updated, so don't print it
            if ($highestStack -le 0) {
                Write-Debug "skipping $highestStack-stack status $name"
                continue
            }

            # Print it
            if ($Vague -and ($Character.id -ne 'player')) {
                Write-Host -ForegroundColor $color "$badge $name<?> (?) " -NoNewline
            } else {
                # precise or it's us!
                Write-Host -ForegroundColor $color "$badge ${name}<${highestIntensity}/${highestStack}> ($instances) " -NoNewline
            }
        }
    }

    # Add the missing newline
    Write-Host ''

    # In inspect mode, also check the stats
    if ($Inspect) {
        Write-Host -ForegroundColor Cyan "$icon Stats: " -NoNewline

        foreach($stat in $Character.stats.GetEnumerator()) {
            # Give a general idea of how good the stats are compared to each other
            $partner = switch ($stat.Key) {
                'pAtk' { 'mAtk' }
                'mAtk' { 'pAtk' }
                'pDef' { 'mDef' }
                'mDef' { 'pDef' }
                'acc' { 'spd' }
                'spd' { 'acc' }
                default { $null }
            }
            # catch /0 errors; if we throw, partner's value is probably 0, so assume we're dark green
            $comparePercent = try { $stat.Value.value / $Character.stats.$partner.value } catch { 99 }
            $color = switch ($comparePercent) {
                { $_ -ge 1.5 } { 'DarkGreen'; break }
                { $_ -ge 1.2 } { 'Green'; break }
                { $_ -ge 0.9 } { 'Yellow'; break }
                { $_ -ge 0.7 } { 'DarkYellow'; break }
                { $_ -gt 0.5 } { 'Red'; break }
                default { 'DarkRed' }
            }

            # get the badge
            $badge = Get-AttribStatBadge -AttribOrStat $stat.Key

            # Print it
            if ($Vague -and ($Character.id -ne 'player')) {
                Write-Host -ForegroundColor $color "$badge ??? " -NoNewline
            } else {
                # precise or it's us!
                Write-Host -ForegroundColor $color "$badge $([System.Math]::Ceiling($stat.Value.value)) " -NoNewline
            }
        }

        # Add the missing newline
        Write-Host ''

        # Resistances and affinities
        foreach ($category in @('resistances', 'affinities')) {
            foreach ($subcategory in @('element', 'status')) {
                if ($Character.$category.$subcategory.count -gt 0) {
                    # Start the line
                    Write-Host -ForegroundColor Cyan ("$icon $subcategory ${category}: " | ConvertTo-TitleCase) -NoNewline

                    foreach ($bonusRaw in $Character.$category.$subcategory.GetEnumerator()) {
                        $name = $bonusRaw.Key
                        if ($Bestiary -and $Character.id -ne 'player') {
                            # Bestiary entries often have "value" set to 0 due to technical reasons, so scan the base instead
                            # (but the player always uses the 'value' value)
                            $value = $bonusRaw.Value.base
                        } else {
                            $value = $bonusRaw.Value.value
                        }

                        # Short-circuit: skip if the value is 0, as there's no adjustment there
                        if ($value -eq 0) {
                            continue
                        }

                        if ($subcategory -eq 'Status') {
                            # Get status info from the definition
                            $info = $State.data.status.$name
                            $printName = $info.name
                            $nameColor = $info.color
                            $badge = $info.badge
                        } else {
                            # Get element info from the helper function
                            $flavorMap = Get-DamageTypeFlavorInfo -Type $name
                            $printName = $flavorMap.name
                            $nameColor = $flavorMap.color
                            $badge = $flavorMap.badge
                        }

                        # Print the name and icon
                        Write-Host -ForegroundColor $nameColor "$badge $printName " -NoNewline

                        # Get the color for the value, then print it
                        $color = Get-PercentageColor -Value $value -Max 1
                        if ($Vague -and ($Character.id -ne 'player')) {
                            # vague
                            $vaguePercent = try { [System.Math]::Round($value * 5) * 20 } catch { 0 }
                            Write-Host -ForegroundColor $color "~$vaguePercent% " -NoNewline
                        } else {
                            # precise
                            Write-Host -ForegroundColor $color "$($value * 100)% " -NoNewline
                        }
                    }

                    # Finish the line
                    Write-Host ''
                }
                # Otherwise, no need to write anything
            }
        }

        # In inspect mode, also print the description
        if (-not $NoDescription) {
            Write-Host ($State | Enrich-Text "📕 $($Character.inspectDescription)")
        }

        # In inspect bestiary mode, also-also print the bestiary description
        if ($Bestiary) {
            Write-Host ($State | Enrich-Text "📖 $($Character.bestiaryDescription)")
        }
    }
}

function Get-ActionList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character
    )

    # Get available actions
    $actionList = [ordered]@{}
    $weightedActionList = New-Object -TypeName System.Collections.ArrayList
    foreach ($skillClass in $Character.skills.GetEnumerator()) {
        if ($skillClass.Value.Count -ge 1) {
            # At least one skill here; add them to the available pool
            $actionList.$($skillClass.Key) = New-Object -TypeName System.Collections.ArrayList(,@( foreach ($skill in $skillClass.Value) {
                Write-Debug "Adding $($skillClass.Key)/$($skill.id) to action map"
                try {
                    $State.data.skills."$($skillClass.Key)"."$($skill.id)"
                } catch {
                    Write-Warning "Unable to load data for skill $($skillClass.Key)/$($skill.id) with inner error: $_"
                }
            } ))

            # Output raw action to array for input reading later
            foreach ($action in $actionList.$($skillClass.Key)) {
                $weightedActionList.Add(@{
                    skillClass = $skillClass.Key
                    id = $action.id
                    name = $action.name
                    fullName = "$($skillClass.Key)/$($action.name)"
                    weight = ($Character.skills."$($skillClass.Key)" | Where-Object -Property id -EQ $action.id).weight
                }) | Out-Null
            }
        }
    }

    return @{
        list = $actionList
        weightedList = $weightedActionList
    }
}

function Get-TargetList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character,

        [Parameter(Mandatory = $true)]
        [hashtable]$Action,

        [Parameter()]
        [System.Collections.ArrayList]$AlreadySelected
    )

    # Get available battle participants that can be targeted by an action of this type
    # todo: there has to be a better way to do this
    $validFactions = switch ($Action.data.targetOverride) {
        # Use defined target if applicable
        'own-faction' { if ($Character.faction -eq 'ally') { @( 'ally' ) } else { @( 'enemy' ) } }
        'opposite-faction' { if ($Character.faction -eq 'ally') { @( 'enemy' ) } else { @( 'ally' ) } }
        'all' { @( 'ally', 'enemy' ) }
        default {
            # Use skill type
            switch ($Action.skillType) {
                'attack-single' { if ($Character.faction -eq 'ally') { @( 'enemy' ) } else { @( 'ally' ) } }
                'attack-multi' { if ($Character.faction -eq 'ally') { @( 'enemy' ) } else { @( 'ally' ) } }
                'buff-single' { if ($Character.faction -eq 'ally') { @( 'ally' ) } else { @( 'enemy' ) } }
                'buff-multi' { if ($Character.faction -eq 'ally') { @( 'ally' ) } else { @( 'enemy' ) } }
                'debuff-single' { if ($Character.faction -eq 'ally') { @( 'enemy' ) } else { @( 'ally' ) } }
                'debuff-multi' { if ($Character.faction -eq 'ally') { @( 'enemy' ) } else { @( 'ally' ) } }
                'heal-single' { if ($Character.faction -eq 'ally') { @( 'ally' ) } else { @( 'enemy' ) } }
                'heal-multi' { if ($Character.faction -eq 'ally') { @( 'ally' ) } else { @( 'enemy' ) } }
                'idle' { $null }
                'special' { @( 'ally', 'enemy' ) }
                default { Write-Warning "no target factions defined for skill type $_"; $null }
            }
        }
    }
    Write-Debug "valid faction(s): $validFactions"

    if ($Action.data.cannotSelfTarget) {
        # Remove self from the list, if applicable
        $targetList = $State.game.battle.characters |
            Where-Object -Property faction -in $validFactions |
            Where-Object -Property name -NE $Character.name |
            Where-Object -Property isActive -EQ $true |
            Where-Object -Property name -NotIn $AlreadySelected.name
    } else {
        # Faction-only target
        $targetList = $State.game.battle.characters |
            Where-Object -Property faction -in $validFactions |
            Where-Object -Property isActive -EQ $true |
            Where-Object -Property name -NotIn $AlreadySelected.name
    }
    $targetNames = $targetList.name
    Write-Debug "found targets: $($targetNames -join ', ')"

    return @{
        list = $targetList
        rawArray = $targetNames
    }
}

function Show-BattleMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character
    )
    # Initial info
    $State | Show-BattleCharacterInfo -Character $Character
    Write-Host -ForegroundColor Blue "What will $($Character.name) do?"

    # Get available actions
    $actionMap = $State | Get-ActionList -Character $Character

    # Display available actions now that we've parsed them all
    foreach ($skillClass in $actionMap.list.GetEnumerator()) {
        Write-Host '| ' -NoNewline
        foreach ($skill in $skillClass.Value) {
            # Only print MP cost for skills that cost MP
            if ($skill.data.mp -ge 1) {
                $mpCost = "($($skill.data.mp)) "
            } else { $mpCost = $null }
            Write-Host "$($skill.name) $mpCost| " -NoNewline
        }
        Write-Host ''
    }

    # Escape hatch if we have no actions somehow
    if ($actionMap.weightedList.Count -le 0) {
        Write-Host "😵‍💫 $($Character.name) can't do anything!"
        return $null
    }

    # Read prompt, select action
    $actionName = $State | Read-PlayerInput -Choices $actionMap.weightedList.name
    Write-Debug "selecting $actionName"

    # Find the action in the list and return it
    # todo: possible issue with duplicate action names; investigate solutions if that becomes a problem
    foreach ($category in $actionMap.list.GetEnumerator()) {
        $matchedAction = $category.Value | Where-Object -Property name -EQ $actionName
        if ($null -ne $matchedAction) {
            Write-Debug "returning $($matchedAction.id)"
            return $matchedAction
        }
    }
}

function Select-BattleAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character,

        [Parameter()]
        [hashtable]$QueuedAction
    )

    # todo: something based on the AI type. For now, weights is sufficient
    $actionMap = $State | Get-ActionList -Character $Character

    while ($true) {
        # If a queued action was passed, attempt to select it
        if ($QueuedAction) {
            Write-Debug "queued action was passed: overriding action selection to $($QueuedAction.class)/$($QueuedAction.id)"
            # No guarantee the character has the queued action on their list (could have been added by another character, for one, so get it directly)
            $skill = $State.data.skills."$($QueuedAction.class)"."$($QueuedAction.id)"
            # only try this once
            $QueuedAction = $null
        } else {
            # Get a weighted random choice from the array
            $skillMap = Get-WeightedRandom -List $actionMap.weightedList
            $skillClass = $actionMap.list."$($skillMap.skillClass)"
            $skill = $skillClass | Where-Object -Property id -EQ $skillMap.id
            Write-Debug "selected skill $($skill.id)"
        }

        if ($null -ne $skill.data.mp -and $Character.attrib.mp.value -lt $skill.data.mp) {
            # too expensive, so remove it from the list and try again
            Write-Debug "... but it costs $($skill.data.mp) MP and $($Character.name) only has $($Character.attrib.mp.value), so removing and retrying"
            $actionMap.weightedList.Remove($skillMap) # this doesn't hurt even if the skill doesn't exist on the list (ie a queued action)
        } else {
            # doesn't cost MP or we have enough to cast it
            return $skill
        }
    }
}

function Invoke-BattleAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character,

        [Parameter(Mandatory = $true)]
        [hashtable]$Action
    )

    # Check if this action needs a target. If so, get one
    if ($Action.data.target -gt 0) {
        $targets = New-Object -TypeName System.Collections.ArrayList
        if ($Action.data.selfTargetOnly) {
            # No need to choose a target if it can only self-target
            $targets.Add($Character) | Out-Null
        } elseif ($Action.data.targetsAll) {
            # no need to show the menus if we target everything; just return everything
            Write-Debug "'all' specified, so targeting all for $($Action.id)"
            $targetList = $State | Get-TargetList -Character $Character -Action $Action
            foreach ($availableTarget in $targetList.list) {
                Write-Debug "adding target $($availableTarget.name)"
                $targets.Add($availableTarget) | Out-Null
            }

        # Otherwise, show the menu if it's a player-controlled character, or just choose if not
        } elseif ($Character.id -eq 'player' -or ($Character.faction -eq 'ally' -and $Character.isPlayerControlled)) {
            foreach ($possibleTarget in 1..$Action.data.target) {
                $targetToAdd = $State | Show-BattleTargetMenu -Character $Character -Action $Action -AlreadySelected $targets
                $null -ne $targetToAdd ? ($targets.Add($targetToAdd) | Out-Null) : $null
            }
        } else {
            foreach ($possibleTarget in 1..$Action.data.target) {
                $targetToAdd = $State | Select-BattleTarget -Character $Character -Action $Action -AlreadySelected $targets
                $null -ne $targetToAdd ? ($targets.Add($targetToAdd) | Out-Null) : $null
            }
        }
    }

    # If we have a target, perform the skill on it
    if ($targets) {
        $State | Invoke-Skill -Attacker $Character -Targets $targets -Skill $Action
    } else {
        # Whoops. This might happen if a solo enemy tries to use a skill on an ally when there aren't any left, for instance.
        if ($Action.data.target -gt 0) {
            Write-Host -ForegroundColor DarkGray "$($Character.name) tried to use $($Action.name), but there weren't any valid targets..."
            return
        }
        $State | Invoke-NonTargetSkill -Attacker $Character -Skill $Action
    }
}

function Show-BattleTargetMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character,

        [Parameter(Mandatory = $true)]
        [hashtable]$Action,

        [Parameter()]
        [System.Collections.ArrayList]$AlreadySelected
    )
    # Get and display available targets
    $targetMap = $State | Get-TargetList -Character $Character -Action $Action -AlreadySelected $AlreadySelected

    # short-circuit if we have no more targets to select
    if ($targetMap.list.Count -eq 0) {
        Write-Host "No more targets available for $($Action.name)"
        return $null
    }

    Write-Host -ForegroundColor Blue "Use $($Action.name) on which character?"
    Write-Host "[ $($targetMap.rawArray -join ' | ') ]"

    # Read prompt, select action
    $targetName = $State | Read-PlayerInput -Choices $targetMap.rawArray
    Write-Debug "targeting $targetName"
    $target = $targetMap.list | Where-Object -Property name -EQ $targetName
    return $target
}

function Select-BattleTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character,

        [Parameter(Mandatory = $true)]
        [hashtable]$Action,

        [Parameter()]
        [System.Collections.ArrayList]$AlreadySelected
    )

    # todo: something based on AI type. For now, random.

    $targetMap = $State | Get-TargetList -Character $Character -Action $Action -AlreadySelected $AlreadySelected
    $target = $targetMap.list | Get-Random
    Write-Debug "selected target $($target.name)"
    return $target
}

function Exit-Battle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Scene
    )

    # Reset vars for out-of-combat enrichment
    $State.game.battle.attacker = $State.player.name
    $State.game.battle.defender = $State.player.name
    $State.game.battle.currentTurn.characterName = $State.player.name

    # Reset all character BPs and clear action queues
    foreach ($character in $State.game.battle.characters) {
        if ($character.attrib.bp) {
            Write-Debug "restoring $($character.id)'s bp to $($character.attrib.bp.max)"
            $character.attrib.bp.value = $character.attrib.bp.max

            if ($character.id -eq 'player' -and $character.isActive -and $State.game.battle.victor -ne 'enemy') {
                # Only write this out for the player, if they didn't die
                Write-Host -ForegroundColor Blue "🛡️ $($character.name)'s barrier reforms."
            }
        }

        Write-Debug "clearing $($character.name)'s action queue"
        $character.actionQueue.Clear()
    }

    $State.game.battle.phase = 'inactive'

    if ($State.game.battle.victor -eq 'enemy') {
        if ($Scene.data.special.nonFatal) {
            # re-alive the player if needed
            if ($State.player.attrib.hp.value -le 0) {
                $State.player.attrib.hp.value = 1

                # use the defeat scene if defined; otherwise go back to wherever we were
                $type = $Scene.data.loseExit.type ?? $State.game.scene.previousType
                $id = $Scene.data.loseExit.id ?? $State.game.scene.previousId
                $State | Exit-Scene -Type $type -Id $id
            }
        } else {
            # end the game if the player died
            $State | Exit-Scene -Type 'cutscene' -Path 'gameover' -Id 'gameover-battle'
        }
    } elseif ($State.game.battle.victor -eq 'escaped') {
        # If the player died but an ally fled, end the game
        if (-not $State.player.isActive) {
            Write-Host 'Your party leaves you to die...'
            $State.game.battle.victor = 'enemy'
            $State | Exit-Battle -Scene $Scene
        }

        # Set flee flags if defined
        if ($Scene.data.fleeFlags) {
            foreach ($flag in $Scene.data.fleeFlags.GetEnumerator()) {
                Set-HashtableValueFromPath -Hashtable $State.game.flags -Path $flag.Key -Value $flag.Value
            }
        }

        # escape if they fled (use the flee scene if defined; otherwise go back to wherever we were)
        $type = $Scene.data.fleeExit.type ?? $State.game.scene.previousType
        $id = $Scene.data.fleeExit.id ?? $State.game.scene.previousId
        $State | Exit-Scene -Type $type -Id $id
    } else {
        # Revive the player if an ally managed to win after their death
        if ($State.player.attrib.hp.value -le 0) {
            if ($State.player.attrib.hp.max -lt 1) {
                # If the player somehow managed to get a max HP less than 1, they're dead regardless
                Write-Host 'Your party is unable to revive you...'
                $State.game.battle.victor = 'enemy'
                $State | Exit-Battle -Scene $Scene
            } else {
                # All set; revive them
                $State | Apply-Damage -Target $State.player -Damage 1 -Class 'physical' -Type 'healing' -AsHealing
                if ($State.player.attrib.hp.value -gt 0) {
                    Write-Host -ForegroundColor White '🪽 Your party manages to revive you.'
                    $State.player.isActive = $true
                } else {
                    # Whoops, player is still dead. Maybe they're immune to healing somehow? This shouldn't be possible without calling Adjust-Damage, but just to be safe.
                    Write-Host 'Your party is unable to revive you...'
                    $State.game.battle.victor = 'enemy'
                    $State | Exit-Battle -Scene $Scene
                }
            }
        }

        # If the player won, collect any loot
        foreach ($character in $State.game.battle.characters) {
            if ($character.loot -and -not $character.fled) {
                $gotAtLeastOneItem = $false
                foreach ($lootItem in $character.loot) {
                    # Check to see if it drops
                    if ($lootItem.chance -ge (Get-RandomPercent)) {
                        if ($lootItem.min -and $lootItem.max) {
                            # Roll for how many, if applicable
                            Write-Debug "adding $($lootItem.min)-$($lootItem.max)x $($lootItem.id)"
                            $number = Get-Random -Minimum $lootItem.min -Maximum ($lootItem.max + 1)
                        } else {
                            # Otherwise, it's an exact number
                            Write-Debug "adding $($lootItem.number)x $($lootItem.id)"
                            $number = $lootItem.number
                        }
                        if (-not $gotAtLeastOneItem) {
                            # Only write this once, no matter how many items we got
                            if ($character.faction -eq 'ally' -and $character.isActive) {
                                Write-Host -ForegroundColor DarkGreen "🎁 $($character.name) gives you some items they found."
                            } else {
                                Write-Host -ForegroundColor DarkGreen "🛒 You find some items on $($character.name)."
                            }
                            $gotAtLeastOneItem = $true
                        }
                        # Add the item
                        $State | Add-GameItem -Id $lootItem.id -Number $number
                    }
                }
                # If we're taking from an ally (steal-backs, maybe?), clear their loot table after we're done looting to avoid infinite items
                if ($character.faction -eq 'ally') { $character.loot = @() }
            }
        }

        # Set flags if defined
        if ($Scene.data.flags) {
            foreach ($flag in $Scene.data.flags.GetEnumerator()) {
                Set-HashtableValueFromPath -Hashtable $State.game.flags -Path $flag.Key -Value $flag.Value
            }
        }

        # Exit to the next scene if defined, but otherwise just go back to wherever we were
        $type = $Scene.data.exit.type ?? $State.game.scene.previousType
        $id = $Scene.data.exit.id ?? $State.game.scene.previousId
        $State | Exit-Scene -Type $type -Id $id
    }
}
