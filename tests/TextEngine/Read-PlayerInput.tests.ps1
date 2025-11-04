Describe "Read-PlayerInput tests" {
    BeforeAll {
        # Source all functions like other tests do
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }
        # Quiet noisy console output
        Mock Write-Host { }
    }

    BeforeEach {
        # reset our fake Read-Host sequence for each It block
        $script:readHostSequence = @()
        $script:readHostIndex = 0

        Mock Read-Host {
            param($Prompt)
            # If no scripted values were provided, that's a test bug — throw so the test fails fast
            if ($script:readHostSequence.Count -eq 0) { throw "No scripted Read-Host values provided for test" }

            # If we've exhausted provided scripted values, throw — this prevents accidental infinite loops
            if ($script:readHostIndex -ge $script:readHostSequence.Count) { throw "Scripted Read-Host sequence exhausted" }

            $val = $script:readHostSequence[$script:readHostIndex]
            $script:readHostIndex++
            return $val
        }
    }

    It "returns exact match for fully quoted input" {
        $State = @{}
        $Choices = @('attack','run')
        $script:readHostSequence = @('"attack"')

        $result = Read-PlayerInput -State $State -Choices $Choices

        $result | Should -Be 'attack'
    }

    It "handles leading-quote inputs (front quoted)" {
        $State = @{}
        $Choices = @('attack', 'back')
        # leading quote, should front-match
        $script:readHostSequence = @('"att')

        $result = Read-PlayerInput -State $State -Choices $Choices
        $result | Should -Be 'attack'
    }

    It "handles trailing-quote inputs (end quoted)" {
        $State = @{}
        $Choices = @('attack', 'attache')
        # trailing quote; should back-match
        $script:readHostSequence = @('ack"')

        $result = Read-PlayerInput -State $State -Choices $Choices
        $result | Should -Be 'attack'
    }

    It "handles lenient default matching and recovers from ambiguous first input" {
        $State = @{}
        $Choices = @('attack','attacker','run')
        # first input 'at' matches more than one -> will loop; then provide a quoted 'er"' to pick the exact response
        $script:readHostSequence = @('at', 'attack', 'er"')

        $result = Read-PlayerInput -State $State -Choices $Choices
        $result | Should -Be 'attacker'
    }

    It "returns `$null when AllowNullChoice is used and empty input provided" {
        $State = @{}
        $Choices = @('yes','no')
        $script:readHostSequence = @('') # first (and only) response is empty

        $result = Read-PlayerInput -State $State -Choices $Choices -AllowNullChoice
        $result | Should -Be $null
    }

    It "continues when input does not match" {
        $State = @{}
        $Choices = @('yes','no')
        $script:readHostSequence = @('', 'aaaaaaa', 'ye')

        $result = Read-PlayerInput -State $State -Choices $Choices
        $result | Should -Be 'yes'
    }

    It "accepts numeric exact input" {
        $State = @{}
        $Choices = @('1','go!','Attack')
        $script:readHostSequence = @('1')

        $result = Read-PlayerInput -State $State -Choices $Choices
        ($result -eq '1' -or $result -contains '1') | Should -BeTrue
    }

    It "accepts punctuation exact input" {
        $State = @{}
        $Choices = @('1','go!','Attack')
        $script:readHostSequence = @('go!')

        $result = Read-PlayerInput -State $State -Choices $Choices
        ($result -eq 'go!' -or $result -contains 'go!') | Should -BeTrue
    }

    It "is case-insensitive for partial matches" {
        $State = @{}
        $Choices = @('1','go!','Attack')
        $script:readHostSequence = @('att')

        $result = Read-PlayerInput -State $State -Choices $Choices
        ($result -eq 'Attack' -or $result -contains 'Attack') | Should -BeTrue
    }

    It 'Accepts SuperDebug' {
        Mock Write-Debug

        $State = @{}
        $Choices = @('1','go!','Attack')
        $script:readHostSequence = @('att')

        $result = Read-PlayerInput -State $State -Choices $Choices -SuperDebug
        ($result -eq 'Attack' -or $result -contains 'Attack') | Should -BeTrue

        Should -Invoke Write-Debug -Times 1
    }
}
