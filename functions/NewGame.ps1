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

    $State.$Category = Get-Content -Raw -Path "$PSScriptRoot/../data/$Category/default.json" | ConvertFrom-Json -AsHashtable
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

    $schema = Get-Content -Raw -Path "$PSScriptRoot/../data/$Category/schema.json" | ConvertFrom-Json -AsHashtable

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
