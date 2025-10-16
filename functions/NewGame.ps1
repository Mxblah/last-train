### Functions relating to new game initialization ###

function New-Options {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter()]
        [switch]$UseDefaults
    )

    Write-Host "Initializing default $Category"

    $State.$Category = $State.data.$Category.default
    Convert-AllChildArraysToArrayLists -Data $State.$Category # Fix whatever we imported if it has arrays in it
    $State | Set-Options -Category $Category -UseDefaults:$UseDefaults
}

function Set-Options {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter()]
        [switch]$UseDefaults
    )

    $schema = $State.data.$Category.schema

    Write-Host -ForegroundColor Cyan $schema.meta.title
    Write-Host -ForegroundColor DarkGray '("Enter" to keep current value or "!" to skip remaining config)'

    if ($DebugPreference -eq 'Continue') {
        Write-Debug 'DUMPING OPTIONS SCHEMA:'
        $schema
    }

    $State.$Category.meta.init = $true
    # need to clone to avoid modifying the collection as we're iterating
    :optionLoop foreach ($option in $State.$Category.Clone().GetEnumerator() | Where-Object {$_.Key -notin @('id', 'faction', 'meta', 'attrib', 'stats', 'skills', 'status', 'activeEffects', 'resistances', 'items', 'scene', 'train')} ) {
        # repeatable vars
        $schemaKey = $schema.$($option.Key)
        if (-not $schemaKey) {
            # probably not a real option, so skip!
            continue
        }
        $validatorsStringArray = if ($null -ne $schemaKey.validators) {
            Write-Debug "found $($schemaKey.validators.Count) validators for $($option.Key)"
            foreach ($validator in $schemaKey.validators.GetEnumerator()) {
                Write-Debug "$($validator.Key) / $($validator.Value)"
                "$($validator.Key): [$($validator.Value -join ', ')]"
            }
        }

        while ($true) {
            if ($UseDefaults) {
                # skip!
                $optionInput = '!'
            } else {
                # Read input normally
                Write-Host -ForegroundColor DarkGray -NoNewline "[$($schemaKey.type)] "
                $optionInput = Read-Host -Prompt "$($option.Key) (Current: $($option.Value) / Available: [$($validatorsStringArray -join ', ')])$(if ($schemaKey.hint) {"`n (hint) -> $($schemaKey.hint)"})"
            }

            # skip out if specified
            if ([string]::IsNullOrEmpty($optionInput)) {
                continue optionLoop
            }
            if ($optionInput -eq '!') {
                break optionLoop
            }

            try {
                # cast based on the specified type in the schema
                $newValue = switch ($schemaKey.type) {
                    'bool' { [System.Convert]::ToBoolean($optionInput) }
                    'int' { [System.Convert]::ToInt32($optionInput) }
                    'string' { $optionInput }
                    default { throw "Unknown type '$_' - update schema file" }
                }

                # make sure the value passes all the validators
                if ($schemaKey.validators.enum -and ($newValue -notin $schemaKey.validators.enum)) {
                    throw "'$newValue' not in allowed list for '$($option.Key)'"
                }
                if ($schemaKey.validators.pattern -and ($newValue -notmatch $schemaKey.validators.pattern)) {
                    throw "'$newValue' does not match required pattern '$($schemaKey.validators.pattern)'"
                }
                if ($schemaKey.validators.lessThan -and ($newValue -ge $schemaKey.validators.lessThan)) {
                    throw "'$newValue' is not less than $($schemaKey.validators.lessThan)"
                }
                if ($schemaKey.validators.greaterThan -and ($newValue -le $schemaKey.validators.greaterThan)) {
                    throw "'$newValue' is not greater than $($schemaKey.validators.greaterThan)"
                }

                # write the value to the map
                $State.$Category.$($option.Key) = $newValue
                break
            } catch {
                Write-Host -ForegroundColor Yellow "❌ Invalid value - try again (validation error: $_)"
            }
        }
    }

    # save options to disk
    $State | Save-Game
    Write-Host -ForegroundColor Green "✅ $Category saved"
}

function Initialize-EnrichmentVariables {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )
    # Just set a few vars ahead of time that could be needed before you might think

    # Create the parent hashtables first using the function, then directly set the rest
    Set-HashtableValueFromPath -Hashtable $State -Path 'game.battle.currentTurn.characterName' -Value $State.player.name
    $State.game.battle.attacker = $State.player.name
    $State.game.battle.defender = $State.player.name
}

function Apply-GameCheats {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [object[]]$Cheats
    )

    if ($Cheats.Count -gt 0) {
        $state.cheater = $true
        foreach ($cheat in $Cheats) {
            switch ($cheat) {
                'bullseye' {
                    Write-Host -ForegroundColor Cyan "CHEAT: 🎯 Set player accuracy to 999999"
                    $state.player.stats.acc.base = 999999
                }
                'def' {
                    Write-Host -ForegroundColor Cyan "CHEAT: 🛡️ Set player defenses to 999999"
                    $state.player.stats.pDef.base = 999999; $state.player.stats.mDef.base = 999999
                }
                'healthy' {
                    Write-Host -ForegroundColor Cyan "CHEAT: ❤️ Set player HP to 999999"
                    $state.player.attrib.hp.base = 999999; $state.player.attrib.hp.value = 999999
                }
                'speedy' {
                    Write-Host -ForegroundColor Cyan "CHEAT: 👟 Set player speed to 999999"
                    $state.player.stats.spd.base = 999999
                }
                'onboard' {
                    Write-Host -ForegroundColor Cyan "CHEAT: 🚂 Forcing player to board the train"
                    $state.game.train.playerOnBoard = $true
                }
                { $null -ne $_.items } {
                    Write-Host -ForegroundColor Cyan "CHEAT: 🛒 Adding extra items"
                    foreach ($item in $_.items) {
                        $state | Add-GameItem -Id $item.id -Number ($item.number ?? 1)
                    }
                }
                { $null -ne $_.skills } {
                    Write-Host -ForegroundColor Cyan "CHEAT: 🤹 Adding extra skills"
                    foreach ($skill in $_.skills) {
                        $state | Add-SkillIfRoom -Character $State.player -Category $skill.category -Id $skill.id
                    }
                }
                { $null -ne $_.sceneOverride } {
                    Write-Host -ForegroundColor Cyan "CHEAT: 🔐 Setting current scene to $($_.sceneOverride.id)"
                    $state.game.scene.type = $_.sceneOverride.type
                    $state.game.scene.path = $_.sceneOverride.path
                    $state.game.scene.id = $_.sceneOverride.id
                }
                default { Write-Warning "unknown cheat $cheat - ignoring" }
            }
        }
    } else {
        Write-Verbose 'No cheats passed in'
    }
}
