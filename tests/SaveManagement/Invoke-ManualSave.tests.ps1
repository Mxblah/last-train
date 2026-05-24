Describe 'Invoke-ManualSave' {
    BeforeAll {
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }

        $savesDir = Join-Path $TestDrive 'saves'
        $state = @{ id = 1; data = @{}; options = @{ autosave = $false } }

        Mock -CommandName Write-Host -MockWith { }
        Mock -CommandName Save-Game -MockWith { }
    }

    It 'invokes Save-Game when numeric response is provided' {
        Mock -CommandName Read-Host -MockWith { return '7' }

        Invoke-ManualSave -State $state -SavesRoot $savesDir

        Should -Invoke Save-Game -Times 1 -ParameterFilter { 7 -eq $Slot }
    }

    It 'handles non-int response as cancelled' {
        Mock -CommandName Read-Host -MockWith { return 'abc' }

        Invoke-ManualSave -State $state -SavesRoot $savesDir

        Should -Invoke Write-Host -Times 1
    }

    It 'treats 0 as auto (current) slot and calls Save-Game' {
        Mock -CommandName Read-Host -MockWith { return '0' }

        Invoke-ManualSave -State $state -SavesRoot $savesDir

        Should -Invoke Save-Game -Times 1 -ParameterFilter { $null -eq $Slot }
    }
}
