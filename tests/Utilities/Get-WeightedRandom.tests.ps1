Describe 'Get-WeightedRandom tests' {
    BeforeAll {
        # Source all functions, even the ones we don't need, just in case we do need them
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }
    }

    BeforeDiscovery {
        $testData = @(
            @{
                name = 'basic asymmetric list'
                list = @(@{ id = 'a'; weight = 1 }, @{ id = 'b'; weight = 5 })
                results = @(@{ random = 1; result = 'a' }, @{ random = 2; result = 'b' }, @{ random = 5; result = 'b' }, @{ random = 6; result = 'b' })
            }
            @{   # single element list should always return that element regardless of random
                name = 'single element list'
                list = @(@{ id = 'only'; weight = 10 })
                results = @(@{ random = 1; result = 'only' }, @{ random = 5; result = 'only' }, @{ random = 10; result = 'only' })
            }
            @{   # two elements, weights 1 and 3, cover boundaries
                name = 'two elements boundaries'
                list = @(@{ id = 'A'; weight = 1 }, @{ id = 'B'; weight = 3 })
                results = @(@{ random = 1; result = 'A' }, @{ random = 2; result = 'B' }, @{ random = 4; result = 'B' })
            }
            @{   # three equal weights
                name = 'three equal weights'
                list = @(@{ id = 'X'; weight = 2 }, @{ id = 'Y'; weight = 2 }, @{ id = 'Z'; weight = 2 })
                results = @(@{ random = 1; result = 'X' }, @{ random = 3; result = 'Y' }, @{ random = 6; result = 'Z' })
            }
            @{   # accept ArrayList input
                name = 'arraylist input'
                list = (New-Object System.Collections.ArrayList(,@(@{ id = 'one'; weight = 2 }, @{ id = 'two'; weight = 1 })))
                results = @(@{ random = 1; result = 'one' }, @{ random = 3; result = 'two' })
            }
            @{   # skewed distribution 1 and 9
                name = 'skewed distribution'
                list = @(@{ id = 'minor'; weight = 1 }, @{ id = 'major'; weight = 9 })
                results = @(@{ random = 1; result = 'minor' }, @{ random = 5; result = 'major' })
            }
            @{   # zero total weight (edge case) - throw
                name = 'zero total weight'
                list = @(@{ id = 'none'; weight = 0 }, @{ id = 'none2'; weight = 0 })
                results = @(@{ random = 1; result = 'throw' })
            }
            @{   # empty list (edge case) - throw
                name = 'empty list'
                list = @()
                results = @(@{ random = 1; result = 'throw' })
            }
        )
    }

    Context '<name>' -ForEach $testData {
        It 'Returns the correct result (<random>:<result>)' -ForEach $results {
            Mock Get-Random -MockWith { return $random }

            if ($result -eq 'throw') {
                { Get-WeightedRandom -List $list } | Should -Throw
            } else {
                $output = Get-WeightedRandom -List $list
                $output.id | Should -Be $result
            }
        }
    }
}
