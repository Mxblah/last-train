Describe 'Remove-PartyMember tests' {
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
		$threeMemberState = @{
			data = $characterData
			party = New-Object -TypeName System.Collections.ArrayList(,@($characterData.character.alice, $characterData.character.bob, $characterData.character.charlie))
		}
		$dupState = @{
			data = $characterData
			party = New-Object -TypeName System.Collections.ArrayList(,@($characterData.character.alice, $characterData.character.alice))
		}
	}

	It 'Should remove a party member from a one-member party' {
		$oneMemberState | Remove-PartyMember -Id 'alice'

		$oneMemberState.party.Count | Should -Be 0
	}

	It 'Should remove only the first matching instance when duplicates exist' {
		$dupState | Remove-PartyMember -Id 'alice'

		$dupState.party.Count | Should -Be 1
		$dupState.party[0] | Should -Be $characterData.character.alice
	}

	It 'Should remove a member from the middle of the party' {
		$threeMemberState | Remove-PartyMember -Id 'bob'

		$threeMemberState.party.Count | Should -Be 2
		$threeMemberState.party[0] | Should -Be $characterData.character.alice
		$threeMemberState.party[1] | Should -Be $characterData.character.charlie
	}

	It 'Should do nothing when the member is not found in an empty party' {
		$defaultState | Remove-PartyMember -Id 'alice'

		$defaultState.party.Count | Should -Be 0
	}

	It 'Should do nothing when the member is not found in a non-empty party' {
		$oneMemberState | Remove-PartyMember -Id 'bob'

		$oneMemberState.party.Count | Should -Be 1
		$oneMemberState.party[0] | Should -Be $characterData.character.alice
	}

    It 'All system messages should be written in Cyan color' {
        $defaultState | Add-PartyMember -Id 'alice'

        Should -Invoke Write-Host -ParameterFilter { $ForegroundColor -ne 'Cyan' } -Exactly 0
        Should -Invoke Write-Host -ParameterFilter { $ForegroundColor -eq 'Cyan' } -Times 1
    }
}
