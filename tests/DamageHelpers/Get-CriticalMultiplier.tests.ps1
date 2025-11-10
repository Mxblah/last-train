Describe 'Get-CriticalMultiplier tests' {
    BeforeAll {
        # Source all functions so the function under test is available
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }

        # Suppress noisy host output
        Mock Write-Host
    }

    BeforeDiscovery {
        $testCases = @(
            @{ name = 'no bonuses - no crit (random high)'; Equip = 0.0; Skill = 0.0; Status = 0.0; Random = 0.1; expected = 1.0 }
            @{ name = 'no bonuses - crit (random low)'; Equip = 0.0; Skill = 0.0; Status = 0.0; Random = 0.0; expected = 1.5 }
            @{ name = 'exact 100% -> crit'; Equip = 0.95; Skill = 0.0; Status = 0.0; Random = 0.999; expected = 1.5 }
            @{ name = 'status bonus crit'; Equip = 0.0; Skill = 0.0; Status = 0.8; Random = 0.7; expected = 1.5 }
            @{ name = 'overflow >100% (one overflow) then extra crit'; Equip = 1.2; Skill = 0.3; Status = 0.0; Random = 0.0; expected = 2.0 }
            @{ name = 'overflow >100% (one overflow) without extra crit'; Equip = 1.2; Skill = 0.3; Status = 0.0; Random = 0.6; expected = 1.5 }
            @{ name = 'large overflow (multiple loops) adds multiples correctly'; Equip = 2.2; Skill = 0.0; Status = 0.0; Random = 0.0; expected = 2.5 }
            @{ name = 'custom CriticalMultiplier used'; Equip = 0.9; Skill = 0.0; Status = 0.0; CriticalMultiplier = 1.0; Random = 0.0; expected = 2.0 }
        )
    }

    It '<name>' -ForEach $testCases {
        # Mock randomness deterministically
        Mock Get-RandomPercent -MockWith { return $Random }

        $result = Get-CriticalMultiplier -EquipBonus $Equip -SkillBonus $Skill -StatusBonus $Status -CriticalMultiplier ($CriticalMultiplier ?? 0.5)

        # Use a numeric comparison. Pester's -Be is fine for doubles here.
        $result | Should -Be $expected
        Should -Invoke Get-RandomPercent
    }
}
