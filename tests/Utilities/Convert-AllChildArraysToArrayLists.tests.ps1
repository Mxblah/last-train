Describe 'Convert-AllChildArraysToArrayLists tests' {
    BeforeAll {
        # Source all functions
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }

        function Test-NoArraysLeft {
            param(
                [Parameter()]
                [AllowNull()]
                [object]
                $ObjectToInspect
            )

            if ($null -eq $ObjectToInspect) { return $true }

            # Detect arrays (System.Array) explicitly and fail
            try {
                $objectType = $ObjectToInspect.GetType()
            } catch {
                return $true
            }

            if ($objectType.BaseType -and $objectType.BaseType.Name -like '*Array') { return $false }

            switch ($objectType.Name) {
                'Hashtable' {
                    foreach ($value in $ObjectToInspect.Values) {
                        if (-not (Test-NoArraysLeft $value)) { return $false }
                    }
                    return $true
                }
                'ArrayList' {
                    foreach ($value in $ObjectToInspect) {
                        if (-not (Test-NoArraysLeft $value)) { return $false }
                    }
                    return $true
                }
                default {
                    # scalars or other container types we don't inspect further
                    return $true
                }
            }
        }
    }

    BeforeDiscovery {
        $testCases = @(
            @{ name = 'hashtable with array child'; payload = @{ items = @(1,2,3) } },
            @{ name = 'nested array in hashtable'; payload = @{ outer = @{ inner = @('a','b') } } },
            @{ name = 'null child in array'; payload = @{ list = @(1, $null, 3) } },
            @{ name = 'null child in hashtable'; payload = @{ key1 = $null; key2 = @(4,5) } },
            @{ name = 'arraylist of arrays'; payload = (New-Object System.Collections.ArrayList(,@(@(1,2), @(3,4)))) },
            @{ name = 'mixed deep structures'; payload = @{ list = (New-Object System.Collections.ArrayList(,@(@(1,2), @{ nested = @(9,8) } ))); other = @('x','y') } },
            @{ name = 'already arraylist child'; payload = @{ arr = (New-Object System.Collections.ArrayList(,@(1,2,3))) } },
            @{ name = 'deeply nested arrays'; payload = @{ a = @(@(@(1,2), @(3,4)), @{ inner = @(@('x','y')) }) } },
            @{ name = 'array inside arraylist inside hashtable'; payload = @{ top = (New-Object System.Collections.ArrayList(,@(@(7,8), @{ deep = @(9,10) } ))) } }
        )
    }

    Context 'conversion succeeds for <name>' -ForEach $testCases {
        It 'converts all child arrays into ArrayList instances' {
            # Run conversion in-place
            Convert-AllChildArraysToArrayLists -Data $payload

            # Assert there are no System.Array types anywhere inside the structure
            Test-NoArraysLeft $payload | Should -BeTrue
        }
    }

    It 'throws when passed a non-collection scalar' {
        { Convert-AllChildArraysToArrayLists -Data 5 } | Should -Throw
    }

    It 'handles null children without throwing' {
        $tbl = @{ a = $null; b = @(1,2) }
        { Convert-AllChildArraysToArrayLists -Data $tbl } | Should -Not -Throw
        Test-NoArraysLeft $tbl | Should -BeTrue
    }

    It 'Test-NoArraysLeft returns false for raw arrays and true after conversion' {
        $raw = @{ x = @(1,2) }
        Test-NoArraysLeft $raw | Should -BeFalse
        Convert-AllChildArraysToArrayLists -Data $raw
        Test-NoArraysLeft $raw | Should -BeTrue
    }

    # Various structures that hit all the SuperDebug calls
    It 'honors SuperDebug by calling verbose/debug writers' -ForEach @(@{ items = @(1,2,3) }, @{ items = @(1, $null, 3) }, @(1, @(2,3)), @(1, (New-Object -TypeName System.Collections.ArrayList(,@(2,3)))), @(@{ key = 'value' })) {
        Mock Write-Debug
        Mock Write-Verbose

        Convert-AllChildArraysToArrayLists -Data $_ -SuperDebug

        Should -Invoke Write-Debug
        Should -Invoke Write-Verbose
    }
}
