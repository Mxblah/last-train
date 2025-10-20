Describe 'Set-HashtableValueFromPath tests' {
    BeforeAll {
        # Source functions
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }
    }

    BeforeDiscovery {
        $cases = @(
            @{   # simple set on flat hashtable
                name = 'simple set'
                table = @{ a = 1 }
                path = 'b'
                value = 2
                expect = @{ a = 1; b = 2 }
                shouldThrow = $false
            }
            @{   # nested set should create intermediate hashtables
                name = 'nested create'
                table = @{}
                path = 'outer.inner'
                value = 'x'
                expect = @{ outer = @{ inner = 'x' } }
                shouldThrow = $false
            }
            @{   # overwrite existing value
                name = 'overwrite existing'
                table = @{ top = @{ key = 'old' } }
                path = 'top.key'
                value = 'new'
                expect = @{ top = @{ key = 'new' } }
                shouldThrow = $false
            }
            @{   # conflict: intermediate key is scalar -> expect throw
                name = 'scalar intermediate conflict'
                table = @{ foo = 'not_a_map' }
                path = 'foo.bar'
                value = 1
                expect = $null
                shouldThrow = $true
            }
            @{   # empty path should throw
                name = 'empty path'
                table = @{ }
                path = ''
                value = 'v'
                expect = $null
                shouldThrow = $true
            }
        )
    }

    It '<name>' -ForEach $cases {
        if ($shouldThrow) {
            { Set-HashtableValueFromPath -Hashtable $table -Path $path -Value $value } | Should -Throw
        } else {
            Set-HashtableValueFromPath -Hashtable $table -Path $path -Value $value
            ($table | ConvertTo-Json -Depth 10) | Should -Be ($expect | ConvertTo-Json -Depth 10)
        }
    }

    It 'Calls debug prints when SuperDebug is enabled' {
        $table = @{ }
        $path = 'a.b.c'
        $value = 42

        Mock Write-Debug

        Set-HashtableValueFromPath -Hashtable $table -Path $path -Value $value -SuperDebug

        Should -Invoke Write-Debug
    }
}
