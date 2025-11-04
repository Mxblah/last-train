Describe 'Get-AttribStatBadge tests' {
    BeforeAll {
        # Source all functions
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }
    }

    BeforeDiscovery {
        $cases = @('hp','bp','mp','pAtk','mAtk','pDef','mDef','acc','spd','unknown')
    }

    It 'Should return a non-empty string for any attrib (<_>)' -ForEach $cases {
        $result = Get-AttribStatBadge -AttribOrStat $_

        $result | Should -BeOfType [string]
        $result.Length | Should -BeGreaterThan 0
        [string]::IsNullOrWhiteSpace($result) | Should -Be $false
    }
}
