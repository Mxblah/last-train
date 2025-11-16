Describe 'Import-Save' {
    BeforeAll {
        # Source functions under test
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }

        $savesDir = Join-Path $TestDrive 'saves'

        Mock -CommandName Write-Host -MockWith { }
        Mock -CommandName Write-Warning -MockWith { }
        Mock -CommandName Import-GameData -MockWith { }
        Mock -CommandName New-Save -MockWith { param($Slot); return @{ id = $Slot; created = $true } } # fake semi-state is returned
    }

    AfterEach {
        # Clean up any test save files created in the TestDrive so we never touch repo saves
        if (Test-Path $savesDir) { Get-ChildItem -Path $savesDir -Filter '*.save' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
    }

    Context 'loading existing saves and create-if-not-present behavior' {
        It 'loads auto.save when it exists' {
            if (-not (Test-Path $savesDir)) { New-Item -ItemType Directory -Path $savesDir | Out-Null }
            @{ id = 9; data = 'fake' } | ConvertTo-Json -Compress | Out-File -FilePath (Join-Path $savesDir 'auto.save') -Encoding ascii

            $result = Import-Save -Slot -1 -SavesRoot $savesDir
            $result | Should -BeOfType 'hashtable'
            $result.id | Should -Be 9
            Should -Invoke Import-GameData -Times 1
        }

        It 'loads numeric slot when it exists' {
            if (-not (Test-Path $savesDir)) { New-Item -ItemType Directory -Path $savesDir | Out-Null }
            @{ id = 2; data = 'fake' } | ConvertTo-Json -Compress | Out-File -FilePath (Join-Path $savesDir '2.save') -Encoding ascii

            $result = Import-Save -Slot 2 -SavesRoot $savesDir
            $result | Should -BeOfType 'hashtable'
            $result.id | Should -Be 2
            Should -Invoke Import-GameData -Times 1
        }

        It 'creates a new save when missing and CreateIfNotPresent is set' {
            if (Test-Path $savesDir) { Remove-Item -Recurse -Force -Path $savesDir }

            $result = Import-Save -Slot 5 -CreateIfNotPresent -SavesRoot $savesDir
            $result.id | Should -Be 5
            Should -Invoke New-Save -Times 1
        }

        It 'throws when the save is missing and CreateIfNotPresent is not set' {
            if (Test-Path $savesDir) { Remove-Item -Recurse -Force -Path $savesDir }

            { Import-Save -Slot 6 -SavesRoot $savesDir } | Should -Throw
        }
    }
}
