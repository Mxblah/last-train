Describe 'Get-SaveSlot' {
    BeforeAll {
        # Source functions under test
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }

        Mock -CommandName Write-Host -MockWith { }
        Mock -CommandName Write-Warning -MockWith { }
        Mock -CommandName Remove-Save -MockWith { }
    }

    Context 'Valid integer slot inputs' {
        BeforeDiscovery {
            $cases = @(
                @{ ReadInput = '3'; Expected = 3 }
                @{ ReadInput = '1'; Expected = 1 }
            )
        }

        It 'returns the integer for numeric input (<Slot>)' -ForEach $cases {
            $result = Get-SaveSlot -Slot $ReadInput
            $result | Should -Be $Expected
        }
    }

    Context 'Simple Read-Host responses' {
        BeforeDiscovery {
            $cases = @(
                @{ name = 'zero'; ReadInput = '0'; Expected = 0 }
                @{ name = 'blank'; ReadInput = ''; Expected = -1 }
                @{ name = 'A'; ReadInput = 'A'; Expected = -1 }
                @{ name = 'Z'; ReadInput = 'Z'; ShouldThrow = $true }
            )
        }

        It 'returns expected result for simple inputs (<name>)' -ForEach $cases {
            Mock -CommandName Read-Host -MockWith { return $ReadInput }
            if ($ShouldThrow) {
                { Get-SaveSlot } | Should -Throw
            } else {
                $result = Get-SaveSlot
                $result | Should -Be $Expected
            }
        }
    }

    Context 'Clean parameter with D (delete all) behavior' {
        It 'when Clean is true and D selected, calls Remove-Save and returns 0' {
            $result = Get-SaveSlot -Clean
            # Remove-Save mocked; the function should return 0
            $result | Should -Be 0
            Should -Invoke Remove-Save -Times 1
        }
    }

    Context 'Delete (D) with confirmation and cancellation' {
        It 'when user enters D and confirms, Remove-Save is called and returns 0' {
            # First Read-Host call should be D (the slot input)
            Mock -CommandName Read-Host -MockWith { 'D' }
            # For the confirmation prompt, return 'Y' when Prompt matches
            Mock -CommandName Read-Host -ParameterFilter { $Prompt -eq 'Really delete all saves? (Y to confirm)' } -MockWith { 'Y' }

            $result = Get-SaveSlot
            $result | Should -Be 0
            Should -Invoke Remove-Save -Times 1
        }

        It 'when user enters D and cancels, throws invalid slot' {
            Mock -CommandName Read-Host -MockWith { 'D' }
            # Confirm returns something other than 'Y'
            Mock -CommandName Read-Host -ParameterFilter { $Prompt -eq 'Really delete all saves? (Y to confirm)' } -MockWith { 'N' }

            { Get-SaveSlot } | Should -Throw
        }
    }
}
