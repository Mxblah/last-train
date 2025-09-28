function Add-PartyMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    # Get details and add
    $data = Get-Content "$PSScriptRoot/../data/character/$Id.json" | ConvertFrom-Json -AsHashtable
    $State.party.Add($data) | Out-Null

    # Inform
    Write-Host -ForegroundColor Cyan "$($data.name) has joined $($State.player.name)'s party!"
}

function Remove-PartyMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    # Get details and remove
    $data = $State.party | Where-Object -Property id -EQ $Id
    if ($data) {
        $State.party.Remove($data)
    } else {
        Write-Verbose "'$Id' not found in the party to remove"
        return
    }

    # Inform
    Write-Host -ForegroundColor Cyan "$($data.name) has left $($State.player.name)'s party."
}
