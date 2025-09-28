function Test-EncounterFlagConditions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$When,

        [Parameter()]
        [string]$WhenMode
    )

    # No conditions: return true
    if ($When.Count -eq 0) {
        Write-Debug 'no conditions passed in when block; returning true'
        return $true
    }

    # Param handling
    if ([string]::IsNullOrWhiteSpace($WhenMode)) {
        $WhenMode = 'and'
    }
    if ($WhenMode -notin @('and', 'or')) {
        throw [System.Management.Automation.ParameterBindingException]"'$WhenMode' is not in the set 'and,or'"
    }

    # Check each condition in turn
    foreach ($condition in $When.GetEnumerator()) {
        if ($condition.Key -eq "item") {
            # Check player items by turning it into a boolean
            Write-Debug "checking item-type condition for item $($condition.Value.id)"
            $requiredValue = $true
            $numberOfItems = [int]($State.items."$($condition.Value.id)".number)
            Write-Debug "found: $numberOfItems / want: number: $($condition.Value.number), min: $($condition.Value.min), max: $($condition.Value.max)"
            $actualValue = if ($condition.Value.number) {
                $numberOfItems -eq $condition.Value.number ? $true : $false
            } elseif ($condition.Value.min -and $condition.Value.max) {
                $numberOfItems -le $condition.Value.max -and $numberOfItems -ge $condition.Value.min ? $true : $false
            } elseif ($condition.Value.min) {
                $numberOfItems -ge $condition.Value.min ? $true : $false
            } elseif ($condition.Value.max) {
                $numberOfItems -le $condition.Value.max ? $true : $false
            } else {
                Write-Warning "Unknown item condition found for item: $($condition.Value.id)"
                $false
            }
        } else {
            # Normal flag-type condition
            $requiredValue = $condition.Value
            $actualValue = Get-HashtableValueFromPath -Hashtable $State.game.flags -Path $condition.Key
        }

        Write-Debug "checking condition '$($condition.Key)' - required: $requiredValue / actual: $actualValue"
        # Hard-convert to allow $null to count as $false
        if ([System.Convert]::ToBoolean($actualValue) -eq $requiredValue) {
            # if it's true and we only need one to be true, we're done
            if ($WhenMode -eq 'or') {
                Write-Debug "mode '$WhenMode' and result true: returning true"
                return $true
            }
            # otherwise, keep checking
        } else {
            # if it's false and we need them all to be true, we're done
            if ($WhenMode -eq 'and') {
                Write-Debug "mode '$WhenMode' and result false: returning false"
                return $false
            }
            # otherwise, keep checking
        }
    }

    # If we made it through the loop, that means all the conditions were true and we were in "and" mode, or all the conditions were false and we were in "or" mode
    # (if we were in "and" mode and anything was false, we would have exited above, and the same for "or" mode if anything was true)
    if ($WhenMode -eq 'and') {
        Write-Debug "mode '$WhenMode' and no conditions were false: returning true"
        return $true
    } else {
        Write-Debug "mode '$WhenMode' and no conditions were true: returning false"
        return $false
    }
}
