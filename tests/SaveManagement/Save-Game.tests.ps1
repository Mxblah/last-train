Describe 'Save-Game' {
    BeforeAll {
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }

        $savesDir = Join-Path $TestDrive 'saves'

        Mock -CommandName Write-Host -MockWith { }
        Mock -CommandName Write-Verbose -MockWith { }
    }

    AfterEach {
        if (Test-Path $savesDir) { Get-ChildItem -Path $savesDir -Filter '*.save' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
    }

    It 'writes manual save and autosave when options.autosave is enabled' {
        if (-not (Test-Path $savesDir)) { New-Item -ItemType Directory -Path $savesDir | Out-Null }

        $state = @{
            id = 5
            data = @{ secret = 'keep' }
            options = @{ autosave = $true }
        }

        $state | Save-Game -Slot 5 -SavesRoot $savesDir

        (Test-Path (Join-Path $savesDir '5.save')) | Should -BeTrue
        (Test-Path (Join-Path $savesDir 'auto.save')) | Should -BeTrue

        $saved = Get-Content -Raw -Path (Join-Path $savesDir '5.save') | ConvertFrom-Json -AsHashtable
        $saved.id | Should -Be 5
        # data should have been offloaded and not present in saved json
        $saved.ContainsKey('data') | Should -BeFalse
    }

    It 'does only autosave when Auto switch is used' {
        if (-not (Test-Path $savesDir)) { New-Item -ItemType Directory -Path $savesDir | Out-Null }

        $state = @{
            id = 8
            data = @{ secret = 'keep' }
            options = @{ autosave = $true }
        }

        $state | Save-Game -Auto -SavesRoot $savesDir

        # manual saved file should not exist for Auto-only call
        (Test-Path (Join-Path $savesDir '8.save')) | Should -BeFalse
        (Test-Path (Join-Path $savesDir 'auto.save')) | Should -BeTrue
    }

    It 'does not autosave when autosave option is disabled' {
        if (-not (Test-Path $savesDir)) { New-Item -ItemType Directory -Path $savesDir | Out-Null }

        $state = @{
            id = 11
            data = @{ secret = 'keep' }
            options = @{ autosave = $false }
        }

        $state | Save-Game -Slot 11 -SavesRoot $savesDir

        (Test-Path (Join-Path $savesDir '11.save')) | Should -BeTrue
        (Test-Path (Join-Path $savesDir 'auto.save')) | Should -BeFalse
    }

    It 'does not do anything when autosave option is disabled and -Auto is specified' {
        if (-not (Test-Path $savesDir)) { New-Item -ItemType Directory -Path $savesDir | Out-Null }

        $state = @{
            id = 11
            data = @{ secret = 'keep' }
            options = @{ autosave = $false }
        }

        $state | Save-Game -Auto -SavesRoot $savesDir

        Get-ChildItem $savesDir | Should -BeNullOrEmpty
        Should -Invoke Write-Verbose
    }

    It 'changes slot when Slot param differs from state id' {
        if (-not (Test-Path $savesDir)) { New-Item -ItemType Directory -Path $savesDir | Out-Null }

        $state = @{
            id = 1
            data = @{ secret = 'keep' }
            options = @{ autosave = $true }
        }

        $state | Save-Game -Slot 10 -SavesRoot $savesDir

        (Test-Path (Join-Path $savesDir '10.save')) | Should -BeTrue
        $saved = Get-Content -Raw -Path (Join-Path $savesDir '10.save') | ConvertFrom-Json -AsHashtable
        $saved.id | Should -Be 10
    }
}
