Describe 'General repo tests' {
    BeforeAll {
        # Source all functions, even the ones we don't need, just in case we do need them
        Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions" | ForEach-Object { . $_.FullName }
    }

    BeforeDiscovery {
        # Get all function files in the repo
        $allFunctionFiles = foreach ($functionFile in (Get-ChildItem -Recurse -Filter '*.ps1' -Path "$PSScriptRoot/../../functions")) {
            # Kinda scuffed, but I don't care
            $functionsInFile = ((Get-Content $functionFile |
                Select-String '\s*function ([\w-]+) {$').Matches.Groups |
                Where-Object -Property Name -EQ '1').Value
            $baseFileName = $functionFile.BaseName

            foreach ($functionName in $functionsInFile) {
                @{
                    BaseFileName = $baseFileName
                    FunctionName = $functionName
                }
            }
        }
    }

    # Remind me to change this if I ever split the files up to one function per file
    It 'All functions should have tests: <_.FunctionName>' -ForEach $allFunctionFiles {
        "$PSScriptRoot/../$($_.BaseFileName)/$($_.FunctionName).tests.ps1" | Should -Exist
    }
}
