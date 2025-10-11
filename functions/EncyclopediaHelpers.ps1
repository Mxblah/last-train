function Show-BestiaryBook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )

    while($true) {
        # Get what creature to read about
        $creatures = $State.player.encyclopedia.bestiary

        if ($creatures.Count -le 0) {
            # Escape hatch
            Write-Host "You haven't encountered any monsters to put in the bestiary yet!"
            $choice = $null
        } else {
            # Print / read choice
            Write-Host "Available creatures: [ $(($creatures.Values | Sort-Object) -join ' | ') ]"
            $choice = $State | Read-PlayerInput -Prompt 'Which creature will you read about? (or <enter> to stop reading)' -Choices ($creatures.Values | Sort-Object) -AllowNullChoice
        }

        if ([string]::IsNullOrWhiteSpace($choice)) {
            Write-Host 'You stopped reading the Bestiary.'
            return
        }

        # Get inspect data about the creature
        $id = ($creatures.GetEnumerator() | Where-Object -Property Value -EQ $choice).Key
        $creatureData = $State.data.character.$id
        $State | Invoke-SpecialInspect -Attacker $State.player -Target $creatureData -Skill @{id = 'bestiary'}
        Write-Host ''

        # Time mgmt
        $State | Add-GlobalTime -Time '00:00:30'
    }
}

function Show-StatusBook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )

    while($true) {
        # Get available statuses
        $statuses = foreach ($status in $State.data.status.GetEnumerator()) { $status.Value }
        $statuses = $statuses | Sort-Object -Property name

        # Print / read choice
        Write-Host "Available statuses: [ $($statuses.name -join ' | ') ]"
        $choice = $State | Read-PlayerInput -Prompt 'Which status will you read about? (or <enter> to stop reading)' -Choices $statuses.name -AllowNullChoice

        if ([string]::IsNullOrWhiteSpace($choice)) {
            Write-Host 'You stopped reading the Status Glossary.'
            return
        }

        # Return data about the status
        $statusData = $statuses | Where-Object -Property name -EQ $choice
        Write-Host -ForegroundColor $statusData.color "$($statusData.badge) $($statusData.name): " -NoNewline
        Write-Host ($State | Enrich-Text $statusData.description)
        Write-Host ''

        # Time mgmt
        $State | Add-GlobalTime -Time '00:00:30'
    }
}

function Show-TutorialBook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )

    while($true) {
        # Get available tutorials
        $tutorials = foreach ($tut in $State.data.scenes.tutorial.GetEnumerator()) { $tut.Value }
        $tutorials = $tutorials | Sort-Object -Property id

        # Print / read choice
        Write-Host "Available tutorials: [ $($tutorials.id -join ' | ') ]"
        $choice = $State | Read-PlayerInput -Prompt 'Which tutorial will you read? (or <enter> to stop reading)' -Choices $tutorials.id -AllowNullChoice

        if ([string]::IsNullOrWhiteSpace($choice)) {
            Write-Host 'You stopped reading about Tutorials.'
            return
        }

        # Time mgmt
        $State | Add-GlobalTime -Time '00:00:30'

        # Play the tutorial, as it's just a cutscene in disguise
        $State | Exit-Scene -Type 'tutorial' -Id $choice
    }
}
