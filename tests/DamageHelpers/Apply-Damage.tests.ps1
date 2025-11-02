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
            @{ name = 'no damage'; Damage = 0; InitialBp = 10; InitialHp = 50; HpMax = 50; expectedBp = 10; expectedHp = 50 }
            @{ name = 'damage without barrier'; Damage = 20; InitialBp = 0; InitialHp = 50; HpMax = 50; expectedBp = 0; expectedHp = 30 }
            @{ name = 'barrier absorbs'; Damage = 5; InitialBp = 10; InitialHp = 50; HpMax = 50; expectedBp = 5; expectedHp = 50 }
            @{ name = 'barrier breaks exact'; Damage = 5; InitialBp = 5; InitialHp = 50; HpMax = 50; expectedBp = 0; expectedHp = 50 }
            @{ name = 'barrier breaks -> survives'; Damage = 8; InitialBp = 5; InitialHp = 4; HpMax = 4; expectedBp = 0; expectedHp = 1 }
            @{ name = 'barrier breaks -> leftover kills'; Damage = 10; InitialBp = 5; InitialHp = 4; HpMax = 4; expectedBp = 0; shouldKill = $true }
            @{ name = 'ignore barrier applies to hp'; Damage = 15; InitialBp = 10; InitialHp = 20; HpMax = 20; IgnoreBarrier = $true; expectedBp = 10; expectedHp = 5 }
            @{ name = 'healing increases hp'; Damage = 8; InitialBp = 10; InitialHp = 10; HpMax = 20; AsHealing = $true; expectedBp = 10; expectedHp = 18 }
            @{ name = 'healing caps at max'; Damage = 15; InitialBp = 0; InitialHp = 10; HpMax = 20; AsHealing = $true; expectedBp = 0; expectedHp = 20 }
            @{ name = 'kill with DoNotRemoveStatuses true'; Damage = 10; InitialBp = 0; InitialHp = 5; HpMax = 5; DoNotRemoveStatusesSwitch = $true; expectedBp = 0; shouldKill = $true }
            # BP-specific cases (attribute 'bp' should only affect BP and not carry over to HP)
            @{ name = 'bp attribute reduces bp only'; Damage = 5; InitialBp = 10; InitialHp = 50; HpMax = 50; Attribute = 'bp'; expectedBp = 5; expectedHp = 50 }
            @{ name = 'bp attribute breaks exact'; Damage = 5; InitialBp = 5; InitialHp = 50; HpMax = 50; Attribute = 'bp'; expectedBp = 0; expectedHp = 50 }
            @{ name = 'bp attribute breaks leftover ignored for hp'; Damage = 8; InitialBp = 5; InitialHp = 10; HpMax = 10; Attribute = 'bp'; expectedBp = 0; expectedHp = 10 }
            @{ name = 'bp healing not overflow'; Damage = 3; InitialBp = 0; Attribute = 'bp'; AsHealing = $true; expectedBp = 3 }
            @{ name = 'bp healing caps at max'; Damage = 8; InitialBp = 9; Attribute = 'bp'; AsHealing = $true; expectedBp = 10 }
            # MP-specific cases (attribute 'mp' should skip BP and operate on MP)
            @{ name = 'mp damage reduces mp'; Damage = 3; InitialBp = 10; InitialMp = 10; MpMax = 10; Attribute = 'mp'; expectedBp = 10; expectedMp = 7 }
            @{ name = 'mp damage underflow sets to zero'; Damage = 15; InitialBp = 0; InitialMp = 5; MpMax = 5; Attribute = 'mp'; expectedBp = 0; expectedMp = 0 }
            @{ name = 'mp healing not overflow'; Damage = 3; InitialBp = 10; InitialMp = 5; MpMax = 10; Attribute = 'mp'; AsHealing = $true; expectedBp = 10; expectedMp = 8 }
            @{ name = 'mp healing caps at max'; Damage = 8; InitialBp = 0; InitialMp = 5; MpMax = 10; Attribute = 'mp'; AsHealing = $true; expectedBp = 0; expectedMp = 10 }
        )
    }

    It '<name>' -ForEach $cases {
        # Build fresh target for each case
        $target = @{
            id = 'Dummy'
            attrib = @{
                bp = @{ value = $InitialBp; max = $BpMax ?? 10 }
                hp = @{ value = $InitialHp; max = $HpMax }
            }
        }

        # If the test case supplies MP fields, include them
        if ($PSBoundParameters.ContainsKey('InitialMp') -or ($InitialMp -ne $null)) {
            $target.attrib.mp = @{ value = $InitialMp; max = $MpMax }
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
        if ($Attribute) { $splat.Attribute = $Attribute }
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

        # Only verify these if set
        if ($expectedBp) {
            $target.attrib.bp.value | Should -Be $expectedBp
        }
        if ($expectedMp) {
            $target.attrib.mp.value | Should -Be $expectedMp
        }
    }
}
