Describe 'Adjust-Damage tests' {
    BeforeAll {
        # Source all functions so the function under test is available
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }

        # Suppress noisy host output in tests
        Mock Write-Host

        # Mock state
        $State = @{
            data = @{
                items = @{
                    'sword' = @{ equipData = @{ weaponData = @{ class = 'physical'; type = 'slashing'; typePercent = 0.5 } } }
                    'wand' = @{ equipData = @{ weaponData = @{ class = 'magical'; type = 'fire'; typePercent = 0.8 } } }
                    'allFire' = @{ equipData = @{ weaponData = @{ class = 'magical'; type = 'fire'; typePercent = 1.0 } } }
                }
            }
        }

        # Mock characters
        $basicPlayer = @{
            id = 'player'
            # no affinities
        }
        $playerAttacker = @{
            id = 'player'
            affinities = @{ element = @{ physical = @{ value = 0.10 }; slashing = @{ value = 0.20 }; fire = @{ value = 0.50 } } }
            resistances = @{ element = @{ physical = @{ value = 0.10 }; slashing = @{ value = 0.20 }; fire = @{ value = 0.50 } } }
        }
        $npcAttacker = @{
            id = 'golem'
            affinities = @{ element = @{ physical = @{ value = 0.20 }; slashing = @{ value = 1 } } }
            resistances = @{ element = @{ physical = @{ value = 0.50 }; slashing = @{ value = 0.20 }; fire = @{ value = 0.10 } } }
        }
        $dummyTarget = @{
            id = 'dummy'
            # no resists
        }

        # Mock functions
        Mock Find-EquippedItem -MockWith { return 'sword' }
    }

    BeforeDiscovery {
        # Test cases: basic affinity/resist combos, ignore switches, weapon split, non-player weapon handling.
        $cases = @(
            @{ name = 'no effects'; Damage = 100; Class = 'physical'; Type = 'slashing'; splat = @{}; expected = 100 }
            @{ name = 'zero damage returns zero' ; Damage = 0; Class = 'physical'; Type = 'slashing'; splat = @{}; expected = 0 }
            @{ name = 'attacker affinity' ; Damage = 100; Class = 'magical'; Type = 'fire'; Attacker = 'playerAttacker'; splat = @{}; expected = 150 }
            @{ name = 'defender resistance'; Damage = 100; Class = 'magical'; Type = 'fire'; Target = 'npcAttacker'; splat = @{}; expected = 90 }
            @{ name = 'affinity and resistance'; Damage = 100; Class = 'magical'; Type = 'fire'; Attacker = 'playerAttacker'; Target = 'npcAttacker'; splat = @{}; expected = 135 }
            @{ name = 'multiple affinities'; Damage = 100; Class = 'physical'; Type = 'slashing'; Attacker = 'playerAttacker'; splat = @{}; expected = 132 }
            @{ name = 'multiple affinities and resistances'; Damage = 100; Class = 'physical'; Type = 'slashing'; Attacker = 'playerAttacker'; Target = 'npcAttacker'; splat = @{}; expected = 53 }
            @{ name = 'ignore affinities'; Damage = 100; Class = 'physical'; Type = 'slashing'; Attacker = 'playerAttacker'; Target = 'npcAttacker'; splat = @{ IgnoreAffinity = $true }; expected = 40 }
            @{ name = 'ignore resistances'; Damage = 100; Class = 'physical'; Type = 'slashing'; Attacker = 'playerAttacker'; Target = 'npcAttacker'; splat = @{ IgnoreResistance = $true }; expected = 132 }
            @{ name = 'ignore both'; Damage = 100; Class = 'physical'; Type = 'slashing'; Attacker = 'playerAttacker'; Target = 'npcAttacker'; splat = @{ IgnoreAffinity = $true; IgnoreResistance = $true }; expected = 100 }
            @{ name = 'player weapon split (resist)' ; Damage = 100; Class = 'weapon'; Type = 'weapon'; Target = 'npcAttacker'; splat = @{}; expected = 45 }
            @{ name = 'player weapon split (affinity)' ; Damage = 100; Class = 'weapon'; Type = 'weapon'; Attacker = 'playerAttacker'; splat = @{}; expected = 121 }
            @{ name = 'player weapon no split (affinity)' ; Damage = 100; Class = 'weapon'; Type = 'weapon'; Attacker = 'playerAttacker'; weapon = 'allFire'; splat = @{}; expected = 150 }
            @{ name = 'player weapon no split (both)'; Damage = 100; Class = 'weapon'; Type = 'weapon'; Attacker = 'playerAttacker'; Target = 'npcAttacker'; weapon = 'allFire'; splat = @{}; expected = 135 }
            @{ name = 'npc weapon -> standard type'; Damage = 100; Class = 'weapon'; Type = 'weapon'; Attacker = 'npcAttacker'; splat = @{}; expected = 120 }
            @{ name = 'npc weapon -> standard type (with resists)'; Damage = 100; Class = 'weapon'; Type = 'weapon'; Attacker = 'npcAttacker'; Target = 'playerAttacker'; splat = @{}; expected = 108 }
        )
    }

    It '<name>' -ForEach $cases {
        # Set up the attacker/target objects based on var names
        $attackerObject = $null -ne $Attacker ? (Get-Variable -Name $Attacker -ValueOnly) : $basicPlayer
        $targetObject = $null -ne $Target ? (Get-Variable -Name $Target -ValueOnly) : $dummyTarget

        # Update the mock if needed
        if ($weapon) {
            Mock Find-EquippedItem -MockWith { return $weapon }
        }

        $result = Adjust-Damage @splat -Damage $Damage -Class $Class -Type $Type -Attacker $attackerObject -Target $targetObject

        $result | Should -Be $expected
    }
}
