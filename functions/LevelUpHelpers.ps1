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
        $orbs = @{}
        foreach ($orbType in @('orb-pearlescent', 'orb-opalescent', 'orb-roseate')) {
            $orbs."$($orbType.Replace('orb-', ''))" = $State.items.$orbType.number ?? 0
        }
        if (($orbs.Values | Measure-Object -Sum).Sum -le 0) {
            Write-Host "You don't have any orbs left!"
            return
        }

        # Display header
        Write-Host -ForegroundColor White "Available orbs: 🤍 $($orbs.pearlescent) 🖤 $($orbs.opalescent) 🩷 $($orbs.roseate)"

        # Display available stats, possible max, and delta to get them there
        $max = $State | Get-MaxStatBase
        Write-Host ''
        foreach ($stat in $State.player.stats.GetEnumerator()) {
            $base = $stat.Value.base

            # Get color based on % of max
            $color = switch ($base / $max) {
                { $_ -ge 1 } { 'DarkGreen'; break }
                { $_ -ge 0.8 } { 'Green'; break }
                { $_ -ge 0.7 } { 'Yellow'; break }
                { $_ -ge 0.6 } { 'DarkYellow'; break }
                { $_ -gt 0.5 } { 'Red'; break }
                default { 'DarkRed' }
            }

            # get the badge
            $badge = Get-AttribStatBadge -AttribOrStat $stat.Key

            Write-Host -ForegroundColor $color "${badge}: $base " -NoNewline
            Write-Host "/ $max (⏫ $($max - $base))"
        }

        # Ask what the player wants to do
        $choice = $State | Read-PlayerInput -Prompt 'Consume which type of orb? (or <enter> to cancel)' -Choices $orbs.Keys -AllowNullChoice
        $splat = @{
            Orbs    = $orbs
            OrbType = $choice
        }

        # Make sure we have some of that orb available
        if ($choice -and $orbs.$choice -le 0) {
            Write-Host "You don't have any $choice orbs!"
            continue
        }

        # Spend the orbs and return that data here for processing
        # Subfunctions are responsible for producing submenus and doing actual stat changes, then returning the number spent so this function can handle items and time
        $orbsSpent = switch ($choice) {
            { [string]::IsNullOrEmpty($_) } {
                Write-Host 'You stopped increasing your stats.'
                return
            }
            'pearlescent' {
                $State | Invoke-SingleStatLevelUp -Max $max @splat
            }
            'opalescent' {
                # Does not need $Max, as we're guaranteed to increase the lowest stat(s)
                $State | Invoke-AllStatLevelUp @splat
            }
            'roseate' {
                # Does not need $Max, as we're guaranteed to increase the lowest stat(s)
                $State | Invoke-LowestStatLevelUp -Number 2 @splat
            }
            default {
                Write-Warning "Unknown orb type '$_'"
                continue
            }
        }

        # Update stats no matter which orb was used
        $State | Update-CharacterValues -Character $State.player

        # Time and item cost
        $State | Remove-GameItem -Id "orb-$choice" -Number $orbsSpent
        $State | Add-GlobalTime -Time (New-TimeSpan -Minutes $orbsSpent)
    }
}

function Invoke-SingleStatLevelUp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Orbs,

        [Parameter(Mandatory = $true)]
        [string]$OrbType,

        [Parameter()]
        [int]$Power = 1,

        [Parameter(Mandatory = $true)]
        [int]$Max
    )

    # Vars
    $orbNumber = $orbs.$OrbType

    while ($true) {
        # Get the stat to increase
        $response = $State | Read-PlayerInput -Prompt 'Increase which stat? (or <enter> to cancel)' -Choices @('pAtk', 'mAtk', 'pDef', 'mDef', 'acc', 'spd') -AllowNullChoice
        if ([string]::IsNullOrEmpty($response)) {
            Write-Host 'You changed your mind...'
            return 0
        }

        # Ask by how much
        $statToIncrease = $response
        $base = $State.player.stats.$statToIncrease.base
        $limitingFactor = [System.Math]::Floor([System.Math]::Min($orbNumber, ($Max - $base)) / $Power)
        Write-Debug "limit is $limitingFactor due to orb count $orbNumber, power $Power, and delta $($Max - $base)"
        if ($limitingFactor -lt 1) {
            Write-Host "Your body can't handle any more increases to $statToIncrease right now! Try a different stat."
            continue
        }
        $orbsToSpend = $State | Read-PlayerNumberInput -Prompt "Increase $statToIncrease how many times? (1-$limitingFactor, or <enter> to cancel)" -Min 1 -Max $limitingFactor -IntegerOnly -AllowNullChoice

        # Validation handling
        if ([string]::IsNullOrEmpty($orbsToSpend)) {
            Write-Host 'You changed your mind...'
            continue
        }

        # Do it
        $increaseAmount = $Power * $orbsToSpend
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
        return $orbsToSpend
    }
}

function Invoke-AllStatLevelUp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Orbs,

        [Parameter(Mandatory = $true)]
        [string]$OrbType,

        [Parameter()]
        [int]$Power = 1
    )

    # Vars
    $orbNumber = $orbs.$OrbType

    # Ask by how much
    $orbsToSpend = $State | Read-PlayerNumberInput -Prompt "Increase all stats how many times? (1-$orbNumber, or <enter> to cancel)" -Min 1 -Max $orbNumber -IntegerOnly -AllowNullChoice
    if ([string]::IsNullOrEmpty($orbsToSpend)) {
        Write-Host 'You changed your mind...'
        return 0
    }

    # Do it
    $increaseAmount = $Power * $orbsToSpend
    foreach ($stat in $State.player.stats.GetEnumerator()) {
        $State.player.stats."$($stat.Key)".base += $increaseAmount
        Write-Host -ForegroundColor Green "$(Get-AttribStatBadge -AttribOrStat $stat.Key) $($stat.Key) increased by $increaseAmount"
    }

    # HP increases by 2 for each def stat and 1 for the other four, so +8 total per orb
    $hpBoost = 8 * $increaseAmount
    $State.player.attrib.hp.base += $hpBoost
    $State.player.attrib.hp.max += $hpBoost
    $State.player.attrib.hp.value += $hpBoost
    Write-Host -ForegroundColor Green "❤️ HP increased by $hpBoost"

    return $orbsToSpend
}

function Invoke-LowestStatLevelUp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Orbs,

        [Parameter(Mandatory = $true)]
        [string]$OrbType,

        [Parameter()]
        [int]$Power = 1,

        # A 6 here should be identical to Invoke-AllStatLevelUp, which makes me wonder if that function can be eliminated...?
        [Parameter()]
        [ValidateRange(1, 6)]
        [int]$Number = 1
    )

    # Vars
    $orbNumber = $orbs.$OrbType

    # Ask by how much
    $orbsToSpend = $State | Read-PlayerNumberInput -Prompt "Increase lowest $Number stats how many times? (1-$orbNumber, or <enter> to cancel)" -Min 1 -Max $orbNumber -IntegerOnly -AllowNullChoice
    if ([string]::IsNullOrEmpty($orbsToSpend)) {
        Write-Host 'You changed your mind...'
        return 0
    }

    # Perform each increase in a loop, to ensure we keep increasing the lowest stats if the stats we increase first become higher than other stats
    foreach ($i in 1..$orbsToSpend) {
        # Get the lowest $Number stats
        # In case of ties, the implicit stat order will ensure the first stats listed in the player object are increased.
        $statBases = foreach ($stat in $State.player.stats.GetEnumerator()) {@{id = $stat.Key; base = $stat.Value.base}}
        $statsToIncrease = $statBases | Sort-Object -Property base | Select-Object -ExpandProperty id -First 2

        # Do it
        $hpBoost = 0
        foreach ($stat in $statsToIncrease) {
            $State.player.stats.$stat.base += $Power
            Write-Host -ForegroundColor Green "$(Get-AttribStatBadge -AttribOrStat $stat) $stat increased by $Power"
            if ($stat -like '*Def') { $hpBoost += 2 * $Power } else { $hpBoost += $Power }
        }

        $State.player.attrib.hp.base += $hpBoost
        $State.player.attrib.hp.max += $hpBoost
        $State.player.attrib.hp.value += $hpBoost
        Write-Host -ForegroundColor Green "❤️ HP increased by $hpBoost"
    }

    return $orbsToSpend
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
        return (($bases | Sort-Object | Select-Object -Last 1))
    } elseif ($Lowest) {
        return (($bases | Sort-Object | Select-Object -First 1))
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
            @{id = $skill.id; name = $State.data.skills."$($category.Key)"."$($skill.id)".name; category = $category.Key }
        }
        foreach ($skill in $State.player.spareSkills."$($category.Key)") {
            @{id = $skill.id; name = $State.data.spareSkills."$($category.Key)"."$($skill.id)".name; category = $category.Key }
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
            $swapSkillName = $State | Read-PlayerInput -Prompt "'$SkillCategory' is full. Swap which skill with '$SkillName'? ($(($skillLookupTable | Where-Object -Property category -EQ $SkillCategory).name -join ', '))" -Choices ($skillLookupTable | Where-Object -Property category -EQ $SkillCategory).name -AllowNullChoice
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
