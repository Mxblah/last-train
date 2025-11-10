Describe 'Enrich-Text tests' {
    BeforeAll {
        # Source all functions
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }

        Mock Write-Debug
    }

    It 'Expands simple state variables' {
        $State = @{ player = @{ name = 'Hero' } }
        $msg = 'Hello ${player.name}!'
        $result = Enrich-Text -State $State -Message $msg

        $result | Should -Be 'Hello Hero!'
    }

    It 'Returns unchanged string when no variables present' {
        $State = @{}
        $msg = 'Nothing to expand here.'
        $result = Enrich-Text -State $State -Message $msg

        $result | Should -Be $msg
    }

    It 'Handles missing referenced values without throwing' {
        $State = @{ }
        $msg = 'Missing ${this.does.not.exist} value'
        { Enrich-Text -State $State -Message $msg } | Should -Not -Throw
        $result = Enrich-Text -State $State -Message $msg
        $result | Should -Be 'Missing  value'
    }

    It 'Expands collections by default join' {
        $State = @{ data = @{ list = @(1,2,3) } }
        $msg = 'List: ${data.list}'
        $result = Enrich-Text -State $State -Message $msg
        $result | Should -Be 'List: 1 2 3' # default separator, since we don't use -join or anything
    }

    It 'Handles battle:current special expression and nested property' {
        $alice = @{ name = 'Alice'; title = 'Scout' }
        $bob = @{ name = 'Bob'; title = 'Guard' }
        $State = @{ game = @{ battle = @{ characters = @($alice, $bob); currentTurn = @{ characterName = 'Bob' } } } }
        $msg = 'Current: ${battle:current.name} (${battle:current.title})'
        $result = Enrich-Text -State $State -Message $msg
        $result | Should -Be 'Current: Bob (Guard)'
    }

    It 'Handles when referenced value is a collection directly' {
        $a = @{ name = 'A' }
        $b = @{ name = 'B' }
        $State = @{ game = @{ battle = @{ characters = @($a, $b); currentTurn = @{ characterName = 'A' } } }; party = @($a,$b) }
        $msg = 'Chars: ${game.battle.characters}'
        $result = Enrich-Text -State $State -Message $msg

        # Yes, this looks kind of silly, but it's better than throwing so it's the expected behavior.
        $result | Should -BeOfType [string]
        $result | Should -Be 'Chars: System.Collections.Hashtable System.Collections.Hashtable'
    }

    It 'Accepts SuperDebug' {
        Mock Write-Debug

        Enrich-Text -State @{} -Message 'does not matter' -SuperDebug

        Should -Invoke Write-Debug -Times 1
    }
}
