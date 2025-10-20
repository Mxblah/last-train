Describe 'Get-RandomPercent tests' {
    BeforeAll {
        # Source all functions, even the ones we don't need, just in case we do need them
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }
    }

    It 'Should return a value between 0 and 1' {
        Mock Get-Random
        Get-RandomPercent

        Should -Invoke Get-Random -Times 1 -ParameterFilter { $Minimum -eq 0 -and $Maximum -eq 1 }
    }

    It 'Should return one value of type double' {
        $result = Get-RandomPercent

        $result | Should -BeLessOrEqual 1
        $result | Should -BeGreaterOrEqual 0
        $result | Should -BeOfType [double]
    }

    It 'Should return the same value when a seed is used' {
        $first = Get-RandomPercent -Seed 42
        $second = Get-RandomPercent -Seed 42

        $first | Should -Be $second
    }

    It 'Should return different values when a seed is not used' {
        # Don't actually compare them because it *could* randomly be the same, I suppose, but just assume Get-Random does it right
        Mock Get-Random

        Get-RandomPercent

        Should -Invoke Get-Random -Times 1 -ParameterFilter { -not $SetSeed }
    }
}
