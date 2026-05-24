Describe 'New-Save' {
    BeforeAll {
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }
        $savesDir = Join-Path $TestDrive 'saves'

        Mock -CommandName Write-Host -MockWith { }
        Mock -CommandName Write-Debug -MockWith { }
        Mock -CommandName Import-Save -MockWith { param($Slot, $SavesRoot) return @{ id = $Slot; imported = $true } }
    }

    AfterEach {
        if (Test-Path $savesDir) { Get-ChildItem -Path $savesDir -Filter '*.save' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue }
    }

    It 'creates a save at explicit slot and calls Import-Save' {
        if (-not (Test-Path $savesDir)) { New-Item -ItemType Directory -Path $savesDir | Out-Null }

        $result = New-Save -Slot 7 -SavesRoot $savesDir
        $result.id | Should -Be 7
        (Test-Path (Join-Path $savesDir '7.save')) | Should -BeTrue
        Should -Invoke Import-Save -Times 1
    }

    It 'picks next available slot when Slot is 0' {
        if (-not (Test-Path $savesDir)) { New-Item -ItemType Directory -Path $savesDir | Out-Null }
        # create 1.save to force next available to be 2
        @{ id = 1 } | ConvertTo-Json -Compress | Out-File -FilePath (Join-Path $savesDir '1.save') -Encoding ascii

        $result = New-Save -Slot 0 -SavesRoot $savesDir
        $result.id | Should -Be 2
        (Test-Path (Join-Path $savesDir '2.save')) | Should -BeTrue
        Should -Invoke Import-Save -Times 1
    }

    It 'handles very large number of existing saves and picks next slot' {
        if (-not (Test-Path $savesDir)) { New-Item -ItemType Directory -Path $savesDir | Out-Null }

        # Mock Get-ChildItem to return a large collection so the >999 branch is hit
        Mock -CommandName Get-ChildItem -MockWith { 1..1001 | ForEach-Object { [PSCustomObject]@{ Name = "$.save" } } }

        $result = New-Save -Slot 0 -SavesRoot $savesDir
        # expected slot should be count + 1 -> 1002
        $result.id | Should -Be 1002
        Should -Invoke Import-Save -Times 1
    }

    It 'finds next available slot with real files present' {
        if (-not (Test-Path $savesDir)) { New-Item -ItemType Directory -Path $savesDir | Out-Null }
        @{ id = 1 } | ConvertTo-Json -Compress | Out-File -FilePath (Join-Path $savesDir '1.save') -Encoding ascii
        @{ id = 2 } | ConvertTo-Json -Compress | Out-File -FilePath (Join-Path $savesDir '2.save') -Encoding ascii

        $result = New-Save -Slot 0 -SavesRoot $savesDir
        $result.id | Should -Be 3
        (Test-Path (Join-Path $savesDir '3.save')) | Should -BeTrue
    }
}
