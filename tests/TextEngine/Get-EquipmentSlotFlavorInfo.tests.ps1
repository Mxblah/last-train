Describe 'Get-EquipmentSlotFlavorInfo tests' {
    BeforeAll {
        # Source all functions
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }
    }

    It 'Should return a hashtable with expected keys for a single slot' {
        $result = Get-EquipmentSlotFlavorInfo -Slot 'hat'

        $result | Should -BeOfType 'hashtable'
        $result.Keys | Should -Contain 'name'
        $result.Keys | Should -Contain 'badge'
        $result.Keys | Should -Contain 'color'
        $result.name | Should -BeOfType [string]
        $result.badge | Should -BeOfType [string]
        $result.color | Should -BeOfType [string]
    }

    It 'Should return a collection when asking for all slots' {
        $result = Get-EquipmentSlotFlavorInfo -All

        $result | Should -BeOfType [ordered]
        $result.Keys | Should -Contain 'hat'
        $result.Keys | Should -Contain 'weapon'
    }

    It 'Should return nothing for an unknown slot' {
        $result = Get-EquipmentSlotFlavorInfo -Slot 'not-real'

        $result | Should -BeNullOrEmpty
    }
}
