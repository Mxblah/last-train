Describe 'Get-HashtableValueFromPath tests' {
    BeforeAll {
        # Source all functions so the function under test is available
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }
    }

    BeforeDiscovery {
        $testCases = @(
            @{   # simple flat hashtable lookup
                name = 'simple lookup'
                table = @{ a = 1; b = 2 }
                path = 'b'
                expect = 2
                lastContainer = $false
            }
            @{   # nested lookup
                name = 'nested lookup'
                table = @{ outer = @{ inner = 'value' } }
                path = 'outer.inner'
                expect = 'value'
                lastContainer = $false
            }
            @{   # actual integer keys do not work, but what kind of crazy person adds real integers as hashtable keys?
                name = 'integer-string keys'
                table = @{ '1' = 'one'; '2' = 'two' }
                path = '2'
                expect = 'two'
                lastContainer = $false
            }
            @{   # return last container instead of value
                name = 'last container'
                table = @{ foo = @{ bar = 99 } }
                path = 'foo.bar'
                # expect: container is the inner hashtable that contains the final key
                expect = @(@{ bar = 99 }, 'bar')
                lastContainer = $true
            }
            @{   # missing final key returns $null (function walks until last fragment and returns value)
                name = 'missing final key'
                table = @{ top = @{ existing = 5 } }
                path = 'top.missing'
                expect = $null
                lastContainer = $false
            }
            @{   # missing intermediate container -> should throw when trying to reference property on null
                name = 'missing intermediate container'
                table = @{ }
                path = 'nonexistent.child'
                expect = $null
                lastContainer = $false
            }
            @{   # empty path edge case
                name = 'empty path'
                table = @{ x = 1 }
                path = ''
                expect = 'throw'
                lastContainer = $false
            }
        )
    }

    It '<name>' -ForEach $testCases {
        if ($expect -eq 'throw') {
            { Get-HashtableValueFromPath -Hashtable $table -Path $path -LastContainer:$lastContainer } | Should -Throw
        } else {
            $result = Get-HashtableValueFromPath -Hashtable $table -Path $path -LastContainer:$lastContainer
            if ($lastContainer) {
                # expect is an array [container, key]
                $key = $expect[1]
                $expectedValue = $expect[0][$key]
                $result[0][$key] | Should -Be $expectedValue
                $result[1] | Should -Be $key
            } else {
                if ($null -eq $expect) {
                    $result | Should -BeNullOrEmpty
                } else {
                    $result | Should -Be $expect
                }
            }
        }
    }

    It 'Calls debug prints when SuperDebug is enabled' {
        $table = @{ outer = @{ inner = 'value' } }
        $path = 'outer.inner'

        Mock Write-Debug

        Get-HashtableValueFromPath -Hashtable $table -Path $path -SuperDebug

        Should -Invoke Write-Debug
    }
}
