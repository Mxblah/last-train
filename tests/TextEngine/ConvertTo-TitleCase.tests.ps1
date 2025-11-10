Describe 'ConvertTo-TitleCase tests' {
    BeforeAll {
        # Source all functions
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }
    }

    BeforeDiscovery {
        $cases = @(
            @{ name = 'simple two words'; text = 'hello world'; expected = 'Hello World' }
            @{ name = 'single word'; text = 'single'; expected = 'Single' }
            @{ name = 'already title'; text = 'Already Title'; expected = 'Already Title' }
            @{ name = 'mixed case'; text = 'mIxEd CaSe'; expected = 'MIxEd CaSe' }
            @{ name = 'single letters'; text = 'a b c'; expected = 'A B C' }
            @{ name = 'multiple spaces'; text = 'multiple   spaces'; expected = 'Multiple   Spaces' }
            @{ name = 'leading and trailing spaces'; text = '  lead and trail  '; expected = '  Lead And Trail  ' }
            @{ name = 'punctuation'; text = 'hello,world!'; expected = 'Hello,world!' }
            @{ name = 'oops all spaces'; text = '    '; expected = '    ' }
            @{ name = 'just punctuation'; text = '!!?:()'; expected = '!!?:()' }
            @{ name = 'empty string'; text = ''; expected = '' }
            @{ name = 'null input'; text = $null; expected = '' }
        )
    }

    It 'Converts strings to title case and handles edge cases (<name>)' -ForEach $cases {
        $result = ConvertTo-TitleCase -String $text
        $result | Should -BeOfType [string]
        $result | Should -Be $expected
    }

    It 'Accepts SuperDebug' {
        Mock Write-Debug

        ConvertTo-TitleCase -String 'does not matter' -SuperDebug

        Should -Invoke Write-Debug -Times 1
    }
}
