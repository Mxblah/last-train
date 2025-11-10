Describe 'Get-Damage tests' {
    BeforeAll {
        # Source all functions so the function under test is available
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }

        # Suppress noisy host output
        Mock Write-Host
    }

    BeforeDiscovery {
        $testCases = @(
            @{ name = 'normal calculation with reasonable values (lower def)'; Power = 30; Attack = 15; Defense = 12; splat = @{}; expected = 57 }
            @{ name = 'normal calculation with reasonable values (higher def)'; Power = 30; Attack = 15; Defense = 18; splat = @{}; expected = 38 }
            @{ name = 'attack multiplier multiplies damage'; Power = 30; Attack = 15; Defense = 15; AtkMultiplier = 2.0; splat = @{}; expected = 90 }
            @{ name = 'defense multiplier divides damage'; Power = 30; Attack = 15; Defense = 15; DefMultiplier = 2.0; splat = @{}; expected = 23 } # 22.5, ceiling'd
            @{ name = 'basic calculation with no skew and clamp to max'; Power = 10; Attack = 4; Defense = 1; splat = @{}; expected = 8 }
            @{ name = 'basic calculation with skew and clamp to max'; Power = 10; Attack = 4; Defense = 1; Skew = 1.05; splat = @{}; expected = 9 }
            @{ name = 'ignore skew uses 1 and avoids Get-Random'; Power = 10; Attack = 2; Defense = 1; Skew = 1.05; splat = @{ IgnoreSkew = $true }; expected = 4 }
            @{ name = 'ignore attack uses power/10 for baseDamage'; Power = 20; Attack = 5; Defense = 2; AtkMultiplier = 2.0; splat = @{ IgnoreAttack = $true }; expected = 2 }
            @{ name = 'as healing ignores defense multiplier'; Power = 50; Attack = 3; Defense = 100; DefMultiplier = 10.0; splat = @{ AsHealing = $true }; expected = 15 }
            @{ name = 'defense zero forces max multiplier 2'; Power = 10; Attack = 4; Defense = 0; splat = @{}; expected = 8 }
            @{ name = 'defMultiplier zero forces max multiplier 2'; Power = 10; Attack = 4; Defense = 10; DefMultiplier = 0.0; splat = @{}; expected = 8 }
            @{ name = 'min multiplier clamp at 0.01'; Power = 10; Attack = 1; Defense = 1000; splat = @{}; expected = 1 }
            @{ name = 'zero power -> zero damage'; Power = 0; Attack = 5; Defense = 2; splat = @{}; expected = 0 }
            @{ name = 'negative attack -> zero damage'; Power = 10; Attack = -1; Defense = 1; splat = @{}; expected = 0 }
            @{ name = 'negative power -> zero damage'; Power = -10; Attack = 5; Defense = 2; splat = @{}; expected = 0 }
            @{ name = 'everything is zero'; Power = 0; Attack = 0; Defense = 0; splat = @{}; expected = 0 }
        )
    }

    It '<name>' -ForEach $testCases {
        Mock Get-Random -MockWith { return ($Skew ?? 1.0) }

        $result = Get-Damage @splat -Power $Power -Attack $Attack -Defense $Defense `
            -AtkMultiplier ($AtkMultiplier ?? 1.0) -DefMultiplier ($DefMultiplier ?? 1.0)

        # Verify expected damage, plus ensure Get-Random was either called or not as appropriate
        $result | Should -Be $expected
        if ($splat.IgnoreSkew) {
            Should -Not -Invoke Get-Random
        } else {
            Should -Invoke Get-Random
        }
    }
}
