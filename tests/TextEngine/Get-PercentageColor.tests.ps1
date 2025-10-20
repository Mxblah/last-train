Describe 'Get-PercentageColor tests' {
    BeforeAll {
		# Source all functions, even the ones we don't need, just in case we do need them
		Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }

        $validColorStrings = [System.Enum]::GetValues([System.ConsoleColor])
    }

    BeforeDiscovery {
        $testData = @(
            @{
                name = 'full'
                value = 10
                max = 10
            }
            @{
                name = 'good'
                value = 9
                max = 10
            }
            @{
                name = 'half'
                value = 5
                max = 10
            }
            @{
                name = 'bad'
                value = 1
                max = 10
            }
            @{
                name = 'dead'
                value = 0
                max = 10
            }
            @{
                name = 'overfull'
                value = 20
                max = 10
            }
            @{
                name = 'divide by zero'
                value = 10
                max = 0
            }
            @{
                name = 'double zero'
                value = 0
                max = 0
            }
            @{
                name = 'negative'
                value = -10
                max = 10
            }
            @{
                name = 'negative max'
                value = 10
                max = -10
            }
            @{
                name = 'double negative'
                value = -10
                max = -10
            }
        )
    }

    # We don't need to test the specific color it returns, in case I change it
    It 'Should return a non-empty string for any valid input (<name>)' -ForEach $testData {
        $result = Get-PercentageColor -Value $value -Max $max

        $result | Should -BeOfType [string]
        $result.Length | Should -BeGreaterThan 0
        [string]::IsNullOrWhiteSpace($result) | Should -Be $false
        $result | Should -BeIn $validColorStrings
    }
}
