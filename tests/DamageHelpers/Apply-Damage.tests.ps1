Describe 'Apply-Damage tests' {
    BeforeAll {
        # Source all functions so the function under test is available
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }

        # Suppress noisy host output in tests
        Mock Write-Host

        # Other mocks
        Mock Get-DamageTypeFlavorInfo -MockWith { return @{ color = 'White'; badge = '📋' } }
        Mock Kill-Character
    }

    BeforeDiscovery {
        # Each case describes initial bp/hp/max, damage, optional switches and expected outcomes
        $cases = @(
            @{ name = 'no damage'; Damage = 0; InitialBp = 10; InitialHp = 50; HpMax = 50; expectedBp = 10; expectedHp = 50; shouldKill = $false }
            @{ name = 'damage without barrier'; Damage = 20; InitialBp = 0; InitialHp = 50; HpMax = 50; expectedBp = 0; expectedHp = 30; shouldKill = $false }
            @{ name = 'barrier absorbs'; Damage = 5; InitialBp = 10; InitialHp = 50; HpMax = 50; expectedBp = 5; expectedHp = 50; shouldKill = $false }
            @{ name = 'barrier breaks exact'; Damage = 5; InitialBp = 5; InitialHp = 50; HpMax = 50; expectedBp = 0; expectedHp = 50; shouldKill = $false }
            @{ name = 'barrier breaks -> survives'; Damage = 8; InitialBp = 5; InitialHp = 4; HpMax = 4; expectedBp = 0; expectedHp = 1; shouldKill = $false }
            @{ name = 'barrier breaks -> leftover kills'; Damage = 10; InitialBp = 5; InitialHp = 4; HpMax = 4; expectedBp = 0; shouldKill = $true }
            @{ name = 'ignore barrier applies to hp'; Damage = 15; InitialBp = 10; InitialHp = 20; HpMax = 20; IgnoreBarrier = $true; expectedBp = 10; expectedHp = 5; shouldKill = $false }
            @{ name = 'healing increases hp'; Damage = 8; InitialBp = 10; InitialHp = 10; HpMax = 20; AsHealing = $true; expectedBp = 10; expectedHp = 18; shouldKill = $false }
            @{ name = 'healing caps at max'; Damage = 15; InitialBp = 0; InitialHp = 10; HpMax = 20; AsHealing = $true; expectedBp = 0; expectedHp = 20; shouldKill = $false }
            @{ name = 'kill with DoNotRemoveStatuses true'; Damage = 10; InitialBp = 0; InitialHp = 5; HpMax = 5; DoNotRemoveStatusesSwitch = $true; expectedBp = 0; shouldKill = $true }
        )
    }

    It '<name>' -ForEach $cases {
        # Build fresh target for each case
        $target = @{
            id = 'Dummy'
            attrib = @{
                bp = @{ value = $InitialBp }
                hp = @{ value = $InitialHp; max = $HpMax }
            }
        }

        # Build splat for Apply-Damage
        $splat = @{
            State = @{} # used in Kill-Character, but no data is needed because it's mocked
            Target = $target
            Damage = $Damage
            # class / type don't matter because Write-Host is mocked (only used here for output flavor)
            Class = 'physical'
            Type = 'standard'
        }
        if ($AsHealing) { $splat.AsHealing = $true }
        if ($IgnoreBarrier) { $splat.IgnoreBarrier = $true }
        if ($DoNotRemoveStatusesSwitch) { $splat.DoNotRemoveStatuses = $true }

        Apply-Damage @splat

        # Assertions
        $target.attrib.bp.value | Should -Be $expectedBp

        if ($shouldKill) {
            # On kill, Apply-Damage calls Kill-Character; HP value itself is not modified by Apply-Damage
            Should -Invoke Kill-Character
            if ($DoNotRemoveStatusesSwitch) {
                # Ensure Kill-Character was called with DoNotRemoveStatuses switch true
                Should -Invoke Kill-Character -ParameterFilter { $DoNotRemoveStatuses }
            } else {
                # Ensure Kill-Character was called with DoNotRemoveStatuses false (or omitted)
                Should -Invoke Kill-Character -ParameterFilter { -not $DoNotRemoveStatuses }
            }
            # HP should remain whatever it was before kill (Apply-Damage doesn't change it prior to Kill-Character)
            $target.attrib.hp.value | Should -Be $InitialHp
        } else {
            # Not killed: check hp value
            $target.attrib.hp.value | Should -Be $expectedHp
            # Ensure Kill-Character was not invoked
            Should -Not -Invoke Kill-Character
        }
    }
}
