function Add-PartyMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    # Get details and add
    $data = $State.data.character.$Id
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

    # Find the first matching party member and remove it
    $member = $State.party | Where-Object -Property id -EQ $Id | Select-Object -First 1
    if ($null -eq $member) {
        Write-Verbose "'$Id' not found in the party to remove"
        return
    }
    $State.party.Remove($member) | Out-Null

    # Inform
    Write-Host -ForegroundColor Cyan "$($member.name) has left $($State.player.name)'s party."
}
