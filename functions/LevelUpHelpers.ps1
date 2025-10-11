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

    # Vars
    $skillInfo = $State.data.skills.$Category.$Id

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

function Show-SkillsMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Character,

        [Parameter()]
        [string]$SkillCategory,

        [Parameter()]
        [string]$SkillAction,

        [Parameter()]
        [string]$SkillId,

        # Break the loop after one iteration
        [Parameter()]
        [switch]$OnlyOne
    )

    # Make a lookup table for easier handling
    $skillLookupTable = foreach ($category in $State.player.skills.GetEnumerator()) {
        foreach ($skill in $State.player.skills."$($category.Key)") {
            @{id = $skill.id; name = $State.data.skills."$($category.Key)"."$($skill.id)".name; category = $category.Key}
        }
        foreach ($skill in $State.player.spareSkills."$($category.Key)") {
            @{id = $skill.id; name = $State.data.spareSkills."$($category.Key)"."$($skill.id)".name; category = $category.Key}
        }
    }

    # Start clearing vars on the second loop onwards
    $firstLoop = $true

    while ($true) {
        if (-not $firstLoop) {
            $SkillCategory = $null
            $SkillAction = $null
            $SkillId = $null
            $SkillName = $null
            $swapSkillId = $null
            $swapSkillName = $null
        } else {
            $firstLoop = $false
        }

        # Display all current skills
        foreach ($category in $Character.skills.GetEnumerator()) {
            # Show the currently equipped skills
            if ($category.Value.Count -gt 0) {
                if ($category.Value.Count -ge $State.options.maxSkillsInCategory) { $color = 'White' } else { $color = 'Gray' }
                Write-Host -ForegroundColor $color "$($category.Key): $(($skillLookupTable | Where-Object -Property category -EQ $category.Key).name -join ' | ')" -NoNewline
            } else {
                Write-Host -ForegroundColor DarkGray "$($category.Key): (none)" -NoNewline
            }

            # Display how many others there are
            Write-Host -ForegroundColor DarkGray " ($($State.player.spareSkills.$($category.Key).Count))"
        }
        Write-Host ''

        # Get category
        if (-not $SkillCategory) {
            $SkillCategory = $State | Read-PlayerInput -Prompt 'Edit which skill category?' -Choices $Character.skills.Keys -AllowNullChoice
        }
        if (-not $SkillCategory) {
            Write-Host 'You stopped memorizing skills.'
            return
        }

        # Get action to perform on category
        if (-not $SkillAction) {
            $SkillAction = $State | Read-PlayerInput -Prompt 'Perform which action? (add/remove)' -Choices @('Add', 'Remove') -AllowNullChoice
        }
        if (-not $SkillAction) {
            Write-Host "You stopped editing your '$SkillCategory' skills."
            continue
        }

        # Sanity checks
        if ($SkillAction -eq 'add') {
            if ($State.player.spareSkills.$SkillCategory.Count -le 0) {
                Write-Host "You don't know any skills to add to '$SkillCategory'."
                continue
            }
        } elseif ($SkillAction -eq 'remove') {
            if ($State.player.skills.$SkillCategory.Count -le 0) {
                Write-Host "You don't know any skills to remove from '$SkillCategory'."
                continue
            }
        }

        # Get skill to perform the action on
        if (-not $SkillId) {
            switch ($SkillAction) {
                'add' { $availableSkills = $Character.spareSkills.$SkillCategory.id }
                'remove' { $availableSkills = $Character.skills.$SkillCategory.id }
                default { Write-Warning "Unknown skill action '$SkillAction'"; continue }
            }
            $availableSkillNames = ($skillLookupTable | Where-Object -Property id -In $availableSkills).name

            $SkillName = $State | Read-PlayerInput -Prompt "$SkillAction which skill? ($($availableSkillNames -join ', '))" -Choices $availableSkillNames -AllowNullChoice
            $SkillId = ($skillLookupTable | Where-Object -Property name -EQ $skillName).id
        } else {
            # id was provided, so add the name for print purposes
            $SkillName = $State.data.skills.$SkillCategory.$SkillId.name
        }
        if (-not $SkillId) {
            Write-Host "You stopped editing your '$SkillCategory' skills."
            continue
        }

        # If we need to do a swap, prompt for that
        if ($SkillAction -eq 'add' -and $Character.skills.$SkillCategory.Count -ge $State.options.maxSkillsInCategory) {
            $swapSkillName = $State | Read-PlayerInput -Prompt "'$SkillCategory' is full. Swap which skill with '$SkillName'? ($(($skillLookupTable | Where-Object -Property category -eq $SkillCategory).name -join ', '))" -Choices ($skillLookupTable | Where-Object -Property category -eq $SkillCategory).name -AllowNullChoice
            $swapSkillId = $skillLookupTable | Where-Object -Property name -EQ $swapSkillName
            if ([string]::IsNullOrEmpty($swapSkillId)) {
                Write-Host "You can't memorize '$SkillName' without forgetting another skill."
                continue
            }
        }

        # Perform the action
        # todo: there has to be a more DRY way to do this
        if ($swapSkillId) {
            Write-Host -ForegroundColor Yellow "🧠 You forgot how to use '$swapSkillName' (moved to memory vault)."
            $Character.spareSkills.$SkillCategory.Add(($Character.skills.$SkillCategory | Where-Object -Property id -EQ $swapSkillId)) | Out-Null
            $Character.skills.$SkillCategory.Remove(($Character.skills.$SkillCategory | Where-Object -Property id -EQ $swapSkillId))
        }
        switch ($SkillAction) {
            'add' {
                Write-Host -ForegroundColor Green "🎓 You memorized '$SkillName'."
                $Character.skills.$SkillCategory.Add(($Character.spareSkills.$SkillCategory | Where-Object -Property id -EQ $SkillId)) | Out-Null
                $Character.spareSkills.$SkillCategory.Remove(($Character.spareSkills.$SkillCategory | Where-Object -Property id -EQ $SkillId))
            }
            'remove' {
                Write-Host -ForegroundColor Yellow "🧠 You forgot how to use '$SkillName' (moved to memory vault)."
                $Character.spareSkills.$SkillCategory.Add(($Character.skills.$SkillCategory | Where-Object -Property id -EQ $SkillId)) | Out-Null
                $Character.skills.$SkillCategory.Remove(($Character.skills.$SkillCategory | Where-Object -Property id -EQ $SkillId))
            }
        }

        $State | Add-GlobalTime -Time '00:02:30'
        if ($OnlyOne) {
            return
        }
    }
}
