Describe 'Rename-ForUniquePropertyValues tests' {
    BeforeAll {
        # Source all functions, even the ones we don't need, just in case we do need them
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }
    }

    BeforeDiscovery {
        # Test data
        $allTestLists = @(
            @{
                name = 'Simple duplicates'
                list = @(@{ name = 'Name' }, @{ name = 'Name' }, @{ name = 'Name' })
                result = @(@{ name = 'Name 1' }, @{ name = 'Name 2' }, @{ name = 'Name 3' })
            }
            @{
                name = 'Mixed duplicates'
                list = @(@{ name = 'Alpha' }, @{ name = 'Beta' }, @{ name = 'Alpha' }, @{ name = 'Gamma' }, @{ name = 'Beta' })
                result = @(@{ name = 'Alpha 1' }, @{ name = 'Beta 1' }, @{ name = 'Alpha 2' }, @{ name = 'Gamma' }, @{ name = 'Beta 2' })
            }
            @{
                name = 'No duplicates'
                list = @(@{ name = 'One' }, @{ name = 'Two' }, @{ name = 'Three' })
                result = @(@{ name = 'One' }, @{ name = 'Two' }, @{ name = 'Three' })
            }
            @{
                name = 'Already suffixed'
                list = @(@{ name = 'Item' }, @{ name = 'Item 1' }, @{ name = 'Item' }, @{ name = 'Item 2' })
                result = @(@{ name = 'Item 3' }, @{ name = 'Item 1' }, @{ name = 'Item 4' }, @{ name = 'Item 2' })
            }
            @{
                name = 'Already suffixed out of order'
                list = @(@{ name = 'Item' }, @{ name = 'Item 3' }, @{ name = 'Item' }, @{ name = 'Item 2' })
                result = @(@{ name = 'Item 1' }, @{ name = 'Item 3' }, @{ name = 'Item 4' }, @{ name = 'Item 2' })
            }
            @{
                name = 'Mixed duplicates already suffixed'
                list = @(@{ name = 'Thing' }, @{ name = 'Thing 2' }, @{ name = 'Other' }, @{ name = 'Thing' }, @{ name = 'Other' }, @{ name = 'Other 1'})
                result = @(@{ name = 'Thing 1' }, @{ name = 'Thing 2' }, @{ name = 'Other 2' }, @{ name = 'Thing 3' }, @{ name = 'Other 3' }, @{ name = 'Other 1'})
            }
            @{
                name = 'Empty names'
                list = @(@{ name = '' }, @{ name = '' }, @{ name = 'NonEmpty' }, @{ name = '' })
                result = @(@{ name = ' 1' }, @{ name = ' 2' }, @{ name = 'NonEmpty' }, @{ name = ' 3' })
            }
            @{
                name = 'Single item'
                list = @(@{ name = 'Unique' })
                result = @(@{ name = 'Unique' })
            }
            @{
                name = 'Unique list'
                list = @(@{ name = 'A' }, @{ name = 'B' }, @{ name = 'C' }, @{ name = 'D' })
                result = @(@{ name = 'A' }, @{ name = 'B' }, @{ name = 'C' }, @{ name = 'D' })
            }
            @{
                name = 'High suffixes'
                list = @(@{ name = 'Thing 10' }, @{ name = 'Thing' }, @{ name = 'Thing 5' }, @{ name = 'Thing' })
                result = @(@{ name = 'Thing 10' }, @{ name = 'Thing 1' }, @{ name = 'Thing 5' }, @{ name = 'Thing 2' })
            }
            @{
                name = 'Property names other than "name"'
                list = @(@{ title = 'Title' }, @{ title = 'Title' }, @{ title = 'Title' })
                result = @(@{ title = 'Title 1' }, @{ title = 'Title 2' }, @{ title = 'Title 3' })
            }
        )
    }

    It 'Should correctly add suffixes to the list <name>' -ForEach $allTestLists {
        Rename-ForUniquePropertyValues -List $list -Property 'name' -SuffixType 'Number'

        $list.name | Should -Be $result.name
    }
}
