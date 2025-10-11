# Loads and overwrites game data into the state
function Import-GameData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        # Print how long the load takes
        [Parameter()]
        [switch]$TimeStats
    )

    # Vars
    if ($TimeStats) {
        Write-Host -ForegroundColor Cyan "📚 Loading game data..."
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    }
    $dataDirectoryPath = (Get-Item "$PSScriptRoot/../data").FullName
    $allDataFiles = Get-ChildItem -Recurse -Filter '*.json' -Path "$PSScriptRoot/../data"
    $State.data = @{} # clear any previous, stale data

    # Main loop: import each file in the tree
    foreach ($file in $allDataFiles) {
        # Get content and state path from file path
        $content = Get-Content -Path $file.FullName | ConvertFrom-Json -AsHashtable
        $statePath = $file.FullName.Replace($dataDirectoryPath, '').Replace('.json', '') -replace '\\|/', '.' # get rid of the data dir, file extension, and path separators
        if ($statePath -like '.*') { $statePath = "data$statePath" } else { $statePath = "data.$statePath" } # not regex; just seeing if it starts with a dot or not

        # Set the value
        Set-HashtableValueFromPath -Hashtable $State -Value $content -Path $statePath
    }

    <#
        We don't have to use Convert-AllChildArraysToArrayLists here, because
        (1) Every collection here is a hashtable, except for some portions of the contents of each file, and
        (2) All the data is read-only, so we don't need to add/remove items.
    #>

    if ($TimeStats) {
        $stopwatch.Stop()
        Write-Host -ForegroundColor Cyan "✅📖 Loaded $($allDataFiles.Count) data files in $($stopwatch.Elapsed.TotalSeconds) seconds"
    }
}
