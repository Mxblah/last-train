function Start-CutsceneScene {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Scene
    )

    # Main loop: iterate through the data until we hit something that makes us exit
    Write-Debug "Found $($scene.data.count) paragraphs in scene $($scene.id)"
    foreach ($para in $Scene.data) {
        # First, output the text
        Write-Host ($State | Enrich-Text $para.text)

        # Next, check to see if we have a choice to display
        if ($para.choice) {
            # We do, but don't know the choices yet, so delay till later.
        } else {
            $prompt = '> '
        }

        # Perform an action(s) (non-choice)
        if ($para.action) {
            $State | Invoke-CutsceneAction -Action $para.action
        }

        # Read player input and make choice or continue to next entry
        if ($para.choice) {
            # Handle "when" blocks if present
            $choicesToList = foreach ($choiceRaw in $para.choice.responses.GetEnumerator()) {
                $choiceName = $choiceRaw.Key
                $choiceInfo = $choiceRaw.Value
                if ($choiceInfo.when) {
                    $shouldList = $State | Test-WhenConditions -When $choiceInfo.when -WhenMode $choiceInfo.whenMode
                } else {
                    # Always list choices without whens
                    $shouldList = $true
                }

                if ($shouldList) {
                    $choiceName
                } else {
                    Write-Debug "'$choiceName' did not meet 'when' criteria"
                }
            }

            $prompt = $State | Enrich-Text "$($para.choice.text) ($($choicesToList -join ' / ')) > " # now we can set the prompt
            $State | Invoke-CutsceneAction -Action $para.choice.responses.$($State | Read-PlayerInput -Prompt $prompt -Choices $choicesToList)
        } else {
            # just keep going if we have no choice to make, regardless of what was entered
            Read-Host -Prompt $prompt
        }

        # Finally, exit if we have one
        if ($para.exit) {
            $State | Exit-Scene -Type $para.exit.type -Id $para.exit.id
        }
    }

    # Failsafe: if we get here, we hit the end of the scene without any exit block. So exit with the default args (ie: back to the previous scene).
    $State | Exit-Scene
}

function Invoke-CutsceneAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Action
    )

    # There can be multiple actions per action, so enumerate them
    foreach ($actRaw in $Action.GetEnumerator()) {
        $actionType = $actRaw.Key
        $act = $actRaw.Value

        Write-Verbose "Performing cutscene action: $actionType"
        if ($DebugPreference -eq 'Continue') {
            Write-Debug "DUMPING ACTION:"
            $act
        }

        switch ($ActionType) {
            'text' {
                # Just print some text
                foreach ($line in $act) {
                    Write-Host ($State | Enrich-Text $line)
                    Read-Host -Prompt '> '
                }
            }
            { $_ -match 'damage|heal' } {
                # Various splat construction effects
                $splat = @{}
                if ($_ -match 'heal') { $splat.AsHealing = $true ; Write-Debug 'effect is healing' } else { Write-Debug 'effect is damage' }
                if ($act.ignoreDefense) { $splat.IgnoreDefense = $true; Write-Debug 'effect will ignore defense' }
                if ($act.ignoreSkew) { $splat.IgnoreSkew = $true; Write-Debug 'effect will ignore skew' }
                if ($act.ignoreResistance) { $splat.IgnoreResistance = $true; Write-Debug 'effect will ignore resistances' }
                if ($act.ignoreBarrier) { $splat.IgnoreBarrier = $true; Write-Debug 'effect will ignore barrier' }

                $fakeDamageStatus = @{
                    id = 'cutscene-damage'
                    guid = $null # just for tracking; not needed here as this isn't a status
                    class = $act.class
                    type = $act.type
                    pow = $act.pow ?? 10
                    atk = $act.atk ?? 1
                }
                $State | Invoke-DamageEffect -Expression $act.expression -Status $fakeDamageStatus -Target $State.player @splat
            }
            'clearStatus' {
                # finally, a simple one
                $State | Clear-AllStatusEffects -Character $State.player
            }
            'party' {
                foreach ($partyMember in $act) {
                    switch ($partyMember.action) {
                        'remove' {
                            $State | Remove-PartyMember -Id $partyMember.id
                        }
                        default {
                            # "Add" is the default action
                            $State | Add-PartyMember -Id $partyMember.id
                        }
                    }
                }
            }
            'item' {
                # Add / remove the items
                foreach ($item in $act) {
                    # Check if chance succeeds, if provided
                    if ($null -ne $item.chance) {
                        Write-Debug "rolling for $($item.id) (chance: $($item.chance))"
                        if ($item.chance -ge (Get-RandomPercent)) {
                            Write-Debug 'succeeded!'
                        } else {
                            Write-Debug 'failed :('
                            continue
                        }
                    }

                    switch ($item.action) {
                        'remove' {
                            $State | Remove-GameItem -Id $item.id -Number $item.number
                        }

                        default {
                            $State | Add-GameItem -Id $item.id -Number $item.number
                        }
                    }
                }
            }
            'attrib' {
                # Permanent buffs, not from items, don't use AEs - they modify values directly
                Write-Debug "modifying attributes due to cutscene action..."
                foreach ($attribRaw in $act.GetEnumerator()) {
                    # hp, bp, or mp, usually
                    $attrib = $attribRaw.Key
                    foreach ($subAttribRaw in $attribRaw.Value.GetEnumerator()) {
                        # regen, max, base, whatever
                        $subAttrib = $subAttribRaw.Key
                        foreach ($actionRaw in $subAttribRaw.Value.GetEnumerator()) {
                            # mult, buff, etc.
                            $effect = $actionRaw.Key
                            $expression = $actionRaw.Value
                            $number = Parse-BattleExpression -Expression $expression -Target $State.player.attrib.$attrib.max

                            # Get some pretty badges and colors and such
                            switch ($attrib) {
                                'hp' { $badge = '❤️'; $color = 'Green' }
                                'mp' { $badge = '✨'; $color = 'Blue' }
                                'bp' { $badge = '🛡️'; $color = 'DarkCyan' }
                                default { $badge = '❓'; $color = 'Gray' }
                            }

                            # Finally, we can do the thing
                            Write-Debug "modifying $attrib/$subAttrib by ${effect}:$number"
                            switch ($effect) {
                                'buff' {
                                    $number = [System.Math]::Ceiling($number)
                                    Write-Host -ForegroundColor $color "$badge $($attrib.ToUpper()) $subAttrib increased by $number."
                                    $State.player.attrib.$attrib.$subAttrib += $number
                                }
                                'mult' {
                                    Write-Host -ForegroundColor $color "$badge $($attrib.ToUpper()) $subAttrib multiplied by $number."
                                    # Do the Ceiling() *after* multiplying, to avoid 1.01x -> 2x, for instance
                                    $State.player.attrib.$attrib.$subAttrib *= $number
                                    $State.player.attrib.$attrib.$subAttrib = [System.Math]::Ceiling($State.player.attrib.$attrib.$subAttrib)
                                }
                                'set' {
                                    [System.Math]::Ceiling($number)
                                    Write-Host -ForegroundColor $color "$badge $($attrib.ToUpper()) $subAttrib set to $number."
                                    $State.player.attrib.$attrib.$subAttrib = $number
                                }
                                default { Write-Warning "Invalid attrib action '$_' found in cutscene ID $($State.game.scene.id)" }
                            }
                            $State | Update-CharacterValues -Character $State.player
                        }
                    }
                }
            }
            'time' {
                # turn off the sun if desired
                if ($act.noSunDamage) {
                    Write-Debug 'disabling sun damage for time actions in cutscene'
                    $splat = @{ NoSunDamage = $true }
                } else {
                    $splat = @{}
                }

                foreach ($timeAction in $act.Keys) {
                    switch ($timeAction) {
                        'add' {
                            $State | Add-GlobalTime -Time $act.add @splat
                        }
                        'set' {
                            $State | Set-GlobalTime -CurrentTime $act.set @splat
                        }
                        default {
                            if ($_ -eq 'noSunDamage') {} else {
                                Write-Warning "Invalid time action '$_' found in cutscene ID $($State.game.scene.id)"
                            }
                        }
                    }
                }
            }
            'train' {
                foreach ($trainAction in $act.GetEnumerator()) {
                    switch ($trainAction.Key) {
                        'playerOnBoard' { $State.game.train.playerOnBoard = $trainAction.Value }
                        default {
                            Write-Warning "Invalid train action '$_' found in cutscene ID $($State.game.scene.id)"
                        }
                    }
                }
            }
            'flag' {
                foreach ($flag in $act.GetEnumerator()) {
                    Set-HashtableValueFromPath -Hashtable $State.game.flags -Path $flag.Key -Value $flag.Value
                }
            }
            'exit' {
                $State | Exit-Scene -Type $act.type -Id $act.id
            }
            { $_ -match 'when|whenMode' } {
                # Do nothing; these are used in conditionals, not as actions themselves
            }
            default {
                Write-Warning "Unknown cutscene action type '$_' encountered in cutscene with ID '$($State.game.scene.id)'!"
            }
        }
    }
}
