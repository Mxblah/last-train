Describe 'Get-DamageTypeFlavorInfo tests' {
    BeforeAll {
        # Source all functions
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }

        $validColorStrings = [System.Enum]::GetValues([System.ConsoleColor])
    }

    BeforeDiscovery {
        $testCases = @(
            @{ Type = 'standard'; Class = $null }
            @{ Type = 'weapon'; Class = 'weapon' }
            @{ Type = 'physical'; Class = 'physical' }
            @{ Type = 'magical'; Class = 'magical' }
            @{ Type = 'fire'; Class = 'magical' }
            @{ Type = 'acid'; Class = 'magical' }
            @{ Type = 'unknown-type'; Class = $null }
        )
    }

    It 'Returns a hashtable with badge/color/name for (<Type>,<Class>)' -ForEach $testCases {
        if ($Class) {
            $result = Get-DamageTypeFlavorInfo -Class $Class -Type $Type
        } else {
            $result = Get-DamageTypeFlavorInfo -Type $Type
        }

        $result | Should -BeOfType 'hashtable'
        $result.Keys | Should -Contain 'badge'
        $result.Keys | Should -Contain 'color'
        $result.Keys | Should -Contain 'name'
        $result.badge | Should -BeOfType [string]
        $result.color | Should -BeOfType [string]
        $result.name | Should -BeOfType [string]
        $result.badge.Length | Should -BeGreaterThan 0
        $result.color.Length | Should -BeGreaterThan 0
        $result.name.Length | Should -BeGreaterThan 0
        $result.color | Should -BeIn $validColorStrings
    }
}
