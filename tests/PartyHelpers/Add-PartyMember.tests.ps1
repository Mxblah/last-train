Describe 'Add-PartyMember tests' {
    BeforeAll {
        # Source all functions, even the ones we don't need, just in case we do need them
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }

        # Suppress output
        Mock Write-Host

        # Test data
        $characterData = @{
            character = @{
                alice = @{
                    id = 'alice'
                    name = 'Alice'
                }
                bob = @{
                    id = 'bob'
                    name = 'Bob'
                }
                charlie = @{
                    id = 'charlie'
                    name = 'Charlie'
                }
            }
        }
    }
    BeforeEach {
        # Per-test test data. This function mutates the state, so we need a fresh one for every test.
        $defaultState = @{
            data = $characterData
            party = New-Object -TypeName System.Collections.ArrayList
        }

        $oneMemberState = @{
            data = $characterData
            party = New-Object -TypeName System.Collections.ArrayList(,@($characterData.character.alice))
        }
        $twoMemberState = @{
            data = $characterData
            party = New-Object -TypeName System.Collections.ArrayList(,@($characterData.character.alice, $characterData.character.bob))
        }
        $allMemberState = @{
            data = $characterData
            party = New-Object -TypeName System.Collections.ArrayList(,$characterData.character)
        }
    }

    It 'Should add a party member to an empty party <_>' -ForEach @('alice', 'bob', 'charlie') {
        $defaultState | Add-PartyMember -Id $_

        $defaultState.party.Count | Should -Be 1
        $defaultState.party[0] | Should -Be $characterData.character.$_
    }

    It 'Should add a party member to a non-empty party <_>' -ForEach @('bob', 'charlie') {
        $oneMemberState | Add-PartyMember -Id $_

        $oneMemberState.party.Count | Should -Be 2
        $oneMemberState.party[1] | Should -Be $characterData.character.$_
    }

    It 'Should add a duplicate party member if required' {
        $twoMemberState | Add-PartyMember -Id 'alice'

        $twoMemberState.party.Count | Should -Be 3
        $twoMemberState.party[2] | Should -Be $characterData.character.alice
    }

    It 'Should add a party member when all members are already present' {
        $allMemberState | Add-PartyMember -Id 'alice'

        $allMemberState.party.Count | Should -Be 4
        $allMemberState.party[3] | Should -Be $characterData.character.alice
    }

    It 'All system messages should be written in Cyan color' {
        $defaultState | Add-PartyMember -Id 'alice'

        Should -Invoke Write-Host -ParameterFilter { $ForegroundColor -ne 'Cyan' } -Exactly 0
        Should -Invoke Write-Host -ParameterFilter { $ForegroundColor -eq 'Cyan' } -Times 1
    }
}
