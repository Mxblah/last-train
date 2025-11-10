Describe 'Get-IfHit tests' {
    BeforeAll {
        # Source all functions, even the ones we don't need, just in case we do need them
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }

        # Suppress noisy host output if any called indirectly
        Mock Write-Host
    }

    BeforeDiscovery {
        # Parameterized cases: accuracy, speed, skillAccuracy, mocked random, and expected result
        $testCases = @(
            @{ name = 'low chance - miss'; accuracy = 2; speed = 10; skillAccuracy = 1.0; random = 0.3; expected = $false }
            @{ name = 'low chance - hit'; accuracy = 2; speed = 10; skillAccuracy = 1.0; random = 0.2; expected = $true }
            @{ name = 'zero accuracy baseline - miss (0.1)'; accuracy = 0; speed = 10; skillAccuracy = 1.0; random = 0.11; expected = $false }
            @{ name = 'zero accuracy baseline - hit (0.1)'; accuracy = 0; speed = 10; skillAccuracy = 1.0; random = 0.09; expected = $true }
            @{ name = 'accuracy greater than speed -> always hit'; accuracy = 5; speed = 1; skillAccuracy = 1.0; random = 0.999; expected = $true }
            @{ name = 'skill reduces chance - miss'; accuracy = 2; speed = 2; skillAccuracy = 0.5; random = 0.6; expected = $false }
            @{ name = 'skill reduces chance - hit'; accuracy = 2; speed = 2; skillAccuracy = 0.5; random = 0.4; expected = $true }
            @{ name = 'speed zero - always hit'; accuracy = 5; speed = 0; skillAccuracy = 1.0; random = 0.999; expected = $true }
            @{ name = 'speed negative - always hit'; accuracy = 5; speed = -1; skillAccuracy = 1.0; random = 0.999; expected = $true }
            @{ name = 'speed zero and accuracy zero - still hits'; accuracy = 0; speed = 0; skillAccuracy = 1.0; random = 0.999; expected = $true }
        )
    }

    It '<name>' -ForEach $testCases {
        Mock Get-RandomPercent -MockWith { return $random }

        $result = Get-IfHit -Accuracy $accuracy -Speed $speed -SkillAccuracy $skillAccuracy

        $result | Should -Be $expected
    }
}
