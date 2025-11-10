# Just a bunch of extra random tests to pad out code coverage; none of these exercise any extra logic beyond the main functions
Describe "TextEngine coverage tests" {
    BeforeAll {
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }
        Mock Write-Host { }
    }

    It "Get-DamageTypeFlavorInfo returns shape for all known types and handles standard/weapon class logic" {
        $types = @(
            @{ t='acid'; name='Acid' }, @{ t='bleed'; name='Bleed' }, @{ t='cold'; name='Cold' },
            @{ t='divine'; name='Divine' }, @{ t='earth'; name='Earth' }, @{ t='explosive'; name='Explosive' },
            @{ t='fire'; name='Fire' }, @{ t='force'; name='Force' }, @{ t='healing'; name='Healing' },
            @{ t='mp-healing'; name='Healing' }, @{ t='bp-healing'; name='Healing' }, @{ t='lightning'; name='Lightning' },
            @{ t='mental'; name='Mental' }, @{ t='piercing'; name='Piercing' }, @{ t='poison'; name='Poison' },
            @{ t='radiation'; name='Radiation' }, @{ t='slashing'; name='Slashing' }, @{ t='solar'; name='Solar' },
            @{ t='sonic'; name='Sonic' }, @{ t='visual'; name='Visual' }, @{ t='void'; name='Void' }, @{ t='water'; name='Water' }
        )

        foreach ($entry in $types) {
            $res = Get-DamageTypeFlavorInfo -Type $entry.t
            $res | Should -BeOfType 'System.Collections.Hashtable'
            $res.Keys | Should -Contain 'badge'
            $res.Keys | Should -Contain 'color'
            $res.Keys | Should -Contain 'name'
            $res.name | Should -Be $entry.name
        }

        # standard/weapon matching: physical class -> Weapon
        $r1 = Get-DamageTypeFlavorInfo -Class 'physical' -Type 'standard'
        $r1.name | Should -Be 'Weapon'

        # standard with magical class -> Weapon (per function)
        $r2 = Get-DamageTypeFlavorInfo -Class 'magical' -Type 'standard'
        $r2.name | Should -Be 'Weapon'

        # standard with unknown class -> Standard
        $r3 = Get-DamageTypeFlavorInfo -Class 'weird' -Type 'standard'
        $r3.name | Should -Be 'Standard'
    }

    It "Get-PercentageColor covers all threshold branches and divide-by-zero" {
        # Max <= 0
        Get-PercentageColor -Value 1 -Max 0 | Should -Be 'DarkRed'

        # >= 1
        Get-PercentageColor -Value 2 -Max 1 | Should -Be 'DarkGreen'

        # >= 0.8
        Get-PercentageColor -Value 8 -Max 10 | Should -Be 'Green'

        # >= 0.6
        Get-PercentageColor -Value 6 -Max 10 | Should -Be 'Yellow'

        # >= 0.4
        Get-PercentageColor -Value 4 -Max 10 | Should -Be 'DarkYellow'

        # >= 0.2
        Get-PercentageColor -Value 2 -Max 10 | Should -Be 'Red'

        # >= 0 (low)
        Get-PercentageColor -Value 0.1 -Max 1 | Should -Be 'DarkRed'
    }

    It "Get-PercentageHeartBadge covers all threshold branches and divide-by-zero" {
        # Max <= 0
        Get-PercentageHeartBadge -Value 1 -Max 0 | Should -Be '💔'

        # >= 1
        Get-PercentageHeartBadge -Value 2 -Max 1 | Should -Be '🩵'

        # >= 0.8
        Get-PercentageHeartBadge -Value 8 -Max 10 | Should -Be '💚'

        # >= 0.6
        Get-PercentageHeartBadge -Value 6 -Max 10 | Should -Be '💛'

        # >= 0.4
        Get-PercentageHeartBadge -Value 4 -Max 10 | Should -Be '🧡'

        # >= 0.2
        Get-PercentageHeartBadge -Value 2 -Max 10 | Should -Be '❤️'

        # >= 0 (low)
        Get-PercentageHeartBadge -Value 0.1 -Max 1 | Should -Be '❤️‍🩹'
    }

    It "Get-EquipmentSlotFlavorInfo returns all slots and individual slot info" {
    $all = Get-EquipmentSlotFlavorInfo -All
    # function returns an ordered dictionary; ensure it implements IDictionary and contains expected keys
    ($all -is [System.Collections.IDictionary]) | Should -BeTrue
    # check a few known keys exist
    $all.Keys | Should -Contain 'hat'
    $all.Keys | Should -Contain 'weapon'

        $hat = Get-EquipmentSlotFlavorInfo -Slot 'hat'
        $hat.name | Should -Be 'Head'
        $hat.badge | Should -Be '🎩'
    }
}
