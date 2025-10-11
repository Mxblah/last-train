function Show-LevelUpMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )

    # Time penalty to ponder thy orb
    $State | Add-GlobalTime -Time '00:01:00'

    while ($true) {
        # Get all the available orbs
        $pearlescentOrbs = $State.items.'orb-pearlescent'.number
        if ($pearlescentOrbs -le 0) {
            Write-Host "You don't have any orbs!"
            Write-Host 'You changed your mind...'
            return
        }

        # Display header
        Write-Host -ForegroundColor White "Available orbs: ⚪ $pearlescentOrbs"

        # Display available stats, possible max, and delta to get them there
        $max = $State | Get-MaxStatBase
        Write-Host ''
        foreach ($stat in $State.player.stats.GetEnumerator()) {
            $base = $stat.Value.base

            # Get color based on % of max
            $color = switch ($base / $max) {
                { $_ -ge 1 } { 'DarkGreen'; break }
                { $_ -ge 0.875 } { 'Green'; break }
                { $_ -ge 0.75 } { 'Yellow'; break }
                { $_ -ge 0.625 } { 'DarkYellow'; break }
                { $_ -gt 0.5 } { 'Red'; break }
                default { 'DarkRed' }
            }

            # get the badge
            $badge = Get-AttribStatBadge -AttribOrStat $stat.Key

            Write-Host -ForegroundColor $color "${badge}: $base " -NoNewline
            Write-Host "/ $max (⏫ $($max - $base))"
        }

        # Ask what the player wants to do
        $response = $State | Read-PlayerInput -Prompt 'Increase which stat? (or <enter> to cancel)' -Choices @('pAtk', 'mAtk', 'pDef', 'mDef', 'acc', 'spd') -AllowNullChoice
        if ([string]::IsNullOrEmpty($response)) {
            Write-Host 'You stopped increasing your stats.'
            return
        }

        # Ask by how much
        $statToIncrease = $response
        $base = $State.player.stats.$statToIncrease.base
        $limitingFactor = [System.Math]::Min($pearlescentOrbs, ($max - $base))
        Write-Debug "limit is $limitingFactor due to orb count $pearlescentOrbs and delta $($max - $base)"
        if ($limitingFactor -lt 1) {
            Write-Host "Your body can't handle any more increases to $statToIncrease right now! Try a different stat."
            continue
        }
        $increaseAmount = $State | Read-PlayerInput -Prompt "Increase $statToIncrease by how much? (1-$limitingFactor, or <enter> to cancel)" -Choices (1..$limitingFactor) -AllowNullChoice

        # Validation handling
        if ([string]::IsNullOrEmpty($increaseAmount)) {
            Write-Host 'You changed your mind...'
            continue
        }

        # Do it
        $State.player.stats.$statToIncrease.base += $increaseAmount
        Write-Host -ForegroundColor Green "$(Get-AttribStatBadge -AttribOrStat $statToIncrease) $statToIncrease increased by $increaseAmount"
        if ($statToIncrease -like '*Def') {
            Write-Host -ForegroundColor Green "❤️ HP increased by $(2 * $increaseAmount)"
            $State.player.attrib.hp.base += (2 * $increaseAmount)
            $State.player.attrib.hp.max += (2 * $increaseAmount)
            $State.player.attrib.hp.value += (2 * $increaseAmount)
        } else {
            Write-Host -ForegroundColor Green "❤️ HP increased by $increaseAmount"
            $State.player.attrib.hp.base += $increaseAmount
            $State.player.attrib.hp.max += $increaseAmount
            $State.player.attrib.hp.value += $increaseAmount
        }
        $State | Update-CharacterValues -Character $State.player

        # Time and item cost
        $State | Remove-GameItem -Id 'orb-pearlescent' -Number $increaseAmount
        $State | Add-GlobalTime -Time (New-TimeSpan -Minutes $increaseAmount)

        # Cancel if we're out of orbs
        if ($State.items.'orb-pearlescent'.number -le 0) {
            Write-Host "You're out of orbs, so you decide to stop."
            return
        }
    }
}

# Was used in a previous calculation for Get-MaxStatBase; might be needed again sometime
function Get-StatTotal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )

    # Calculate stat total
    $statTotal = 0
    foreach ($stat in $State.player.stats.GetEnumerator()) {
        $statTotal += $stat.Value.base
    }

    Write-Debug "player's stat total is $statTotal"
    return $statTotal
}

function Get-ExtremeStat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true, ParameterSetName = 'Max')]
        [switch]$Highest,

        [Parameter(Mandatory = $true, ParameterSetName = 'Min')]
        [switch]$Lowest
    )

    $bases = foreach ($stat in $State.player.stats.GetEnumerator()) { $stat.Value.base }
    if ($Highest) {
        return (($bases | Sort-Object | Select-Object -First 1))
    } elseif ($Lowest) {
        return (($bases | Sort-Object | Select-Object -Last 1))
    } else {
        Write-Warning 'No argument passed to Get-ExtremeStat'
        return 0
    }
}

function Get-MaxStatBase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )

    # Get the lowest stat base and return 2x that
    return (($State | Get-ExtremeStat -Lowest) * 2)
}

function Add-SkillIfRoom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character,

        [Parameter(Mandatory = $true)]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    # If not the player, just add it normally
    if ($Character.id -ne 'player') {
        Write-Debug "adding skill $Category/$Id to $($Character.name)"
        $Character.skills.$Category.Add(@{ id = $Id }) | Out-Null
    } else {
        Write-Host -ForegroundColor Green "🎓 You learned how to use $($skillInfo.name)!"
        # Check if we're full on skills
        if ($Character.skills.$Category.Count -ge $State.options.maxSkillsInCategory) {
            Write-Host -ForegroundColor Yellow "🧠 But you can't memorize more than $($State.options.maxSkillsInCategory) '$Category' skills! You can swap memorized skills on the train."
            $Character.spareSkills.$Category.Add(@{ id = $Id }) | Out-Null

            # Allow the player to swap it out immediately if they want
            $choice = $State | Read-PlayerInput -Prompt 'Swap skills immediately? (y/n)' -Choices @('yes', 'no')
            if ($choice -eq 'yes') {
                $State | Show-SkillsMenu -Character $Character -SkillCategory $Category -SkillId $Id -SkillAction 'add' -OnlyOne
            }
        } else {
            # There's room, so add it normally
            $Character.skills.$Category.Add(@{ id = $Id }) | Out-Null
        }
    }
}
