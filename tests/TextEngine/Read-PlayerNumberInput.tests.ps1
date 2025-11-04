Describe "Read-PlayerNumberInput tests" {
    BeforeAll {
        # Source functions
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }
        # Silence noisy console output
        Mock Write-Host { }
    }

    BeforeEach {
        # scripted Read-Host sequence for deterministic tests
        $script:readHostSequence = @()
        $script:readHostIndex = 0

        Mock Read-Host {
            param($Prompt)
            if ($script:readHostSequence.Count -eq 0) { throw "No scripted Read-Host values provided for test" }
            if ($script:readHostIndex -ge $script:readHostSequence.Count) { throw "Scripted Read-Host sequence exhausted" }
            $val = $script:readHostSequence[$script:readHostIndex]
            $script:readHostIndex++
            return $val
        }
    }

    It "returns integer when IntegerOnly and integer provided" {
        $State = @{}
        $script:readHostSequence = @('5')
        $result = Read-PlayerNumberInput -State $State -Min 1 -Max 10 -IntegerOnly
        $result | Should -Be 5
    }

    It "rejects non-integer then accepts integer when IntegerOnly is set" {
        $State = @{}
        # First is invalid (non-integer), second is valid
        $script:readHostSequence = @('5.5','6')
        $result = Read-PlayerNumberInput -State $State -Min 1 -Max 10 -IntegerOnly
        $result | Should -Be 6
    }

    It "accepts double when IntegerOnly not set" {
        $State = @{}
        $script:readHostSequence = @('3.14')
        $result = Read-PlayerNumberInput -State $State -Min 0 -Max 10
        # allow exact comparison for 3.14
        $result | Should -Be 3.14
    }

    It "enforces min/max and retries until valid" {
        $State = @{}
        # 0 is below min=1, then 3 is valid
        $script:readHostSequence = @('0','3')
        $result = Read-PlayerNumberInput -State $State -Min 1 -Max 5
        $result | Should -Be 3
    }

    It "returns $null when AllowNullChoice and empty input provided" {
        $State = @{}
        $script:readHostSequence = @('')
        $result = Read-PlayerNumberInput -State $State -Min 0 -Max 10 -AllowNullChoice
        $result | Should -Be $null
    }

    It "handles empty input when AllowNullChoice not set and then accepts a valid number" {
        $State = @{}
        $script:readHostSequence = @('','2')
        $result = Read-PlayerNumberInput -State $State -Min 1 -Max 5
        $result | Should -Be 2
    }

    It "accepts negative numbers within range" {
        $State = @{}
        $script:readHostSequence = @('-5')
        $result = Read-PlayerNumberInput -State $State -Min -10 -Max 0
        $result | Should -Be -5
    }

    It "handles conversion errors and accepts SuperDebug" {
        Mock Write-Debug
        $State = @{}
        $script:readHostSequence = @('nan', '4')
        $result = Read-PlayerNumberInput -State $State -Min 0 -Max 10 -SuperDebug
        $result | Should -Be 4
        Should -Invoke Write-Debug -Times 1
    }

    It "handles integer-only conversion errors and accepts SuperDebug" {
        Mock Write-Debug
        $State = @{}
        $script:readHostSequence = @('nan', '4')
        $result = Read-PlayerNumberInput -State $State -Min 0 -Max 10 -IntegerOnly -SuperDebug
        $result | Should -Be 4
        Should -Invoke Write-Debug -Times 1
    }
}
