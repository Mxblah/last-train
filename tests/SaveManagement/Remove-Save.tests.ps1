Describe 'Remove-Save' {
    BeforeAll {
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }
        $savesDir = Join-Path $TestDrive 'saves'

        Mock -CommandName Write-Host -MockWith { }
        Mock -CommandName Write-Warning -MockWith { }
    }

    AfterEach {
        if (Test-Path $savesDir) { Get-ChildItem -Path $savesDir -Filter '*.save' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
    }

    It 'removes all saves when -All is used' {
        if (-not (Test-Path $savesDir)) { New-Item -ItemType Directory -Path $savesDir | Out-Null }
        @{ id = 1 } | ConvertTo-Json -Compress | Out-File -FilePath (Join-Path $savesDir '1.save') -Encoding ascii
        @{ id = 2 } | ConvertTo-Json -Compress | Out-File -FilePath (Join-Path $savesDir '2.save') -Encoding ascii

        Remove-Save -All -SavesRoot $savesDir

        (Get-ChildItem -Path $savesDir -Filter '*.save') | Should -BeNullOrEmpty
    }

    It 'removes a single slot if present' {
        if (-not (Test-Path $savesDir)) { New-Item -ItemType Directory -Path $savesDir | Out-Null }
        @{ id = 3 } | ConvertTo-Json -Compress | Out-File -FilePath (Join-Path $savesDir '3.save') -Encoding ascii

        Remove-Save -Slot 3 -SavesRoot $savesDir

        (Test-Path (Join-Path $savesDir '3.save')) | Should -Be $false
    }

    It 'warns when slot does not exist' {
        if (Test-Path $savesDir) { Get-ChildItem -Path $savesDir -Filter '*.save' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }

        Remove-Save -Slot 99 -SavesRoot $savesDir
        Should -Invoke Write-Warning -Times 1
    }
}
