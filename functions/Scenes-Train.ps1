function Start-TrainScene {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [hashtable]$Scene
        # todo: make some use of $Scene - currently I have nothing here (can be removed??)
    )

    # player is entering the train, so player is definitely on board
    $State.game.train.playerOnBoard = $true

    # Restore BP and Focus when entering the train
    Write-Debug "restoring player's bp to $($State.player.attrib.bp.max) and mp to $($State.player.attrib.mp.max)"
    $State.player.attrib.bp.value = $State.player.attrib.bp.max
    $State.player.attrib.mp.value = $State.player.attrib.mp.max

    :trainSceneLoop while ($true) {
        $State | Show-TrainMenu
    }

    # todo: is this really where the exit will be? Maybe put this in exit-scene instead?
    # Restore BP and Focus when leaving the train
    Write-Debug "restoring player's bp to $($State.player.attrib.bp.max) and mp to $($State.player.attrib.mp.max)"
    $State.player.attrib.bp.value = $State.player.attrib.bp.max
    $State.player.attrib.mp.value = $State.player.attrib.mp.max

    <#
    todo:
    Done:
        - (base screen) -> plus some flavor text about what the train is doing (moving, stopped, etc.)
        - also on that screen: where headed, where from, and when you will arrive
        - show a menu of what time it is with ☀️ or 🌙 based on time of day, day number
        - menu option: browse inventory
        - menu option: use items
        - menu option: equip items
        - menu option: change train destination (available until late in the day, then locked)
        - menu option: sleep (how long) -> can heal at the cost of time
        - menu option: wait/sleep until the train stops
        - menu option: exit the train to explore (if at a station)
        - menu option: read (tutorials, descriptions of bestiary monsters you've seen, status effects, )
        - menu option: train (battle w/ the training dummy?)
        - menu option: party (inspect party members)
        - menu option: level up(?) - or learn skills, or similar - or have these be immediate when finding the stuff in explore mode
            -> I'd kind of like them to cost time though, since train time should be important
        - menu option: Skills (change out or remove skills to clean up your menu, or upgrade them?)
    Things the player should be able to do in the train that need implemented:
        - menu option: read (general advice, lore books you've found, etc.)
            -> add more books to read
        - menu option: craft (improve gear?) (merge with v ?)
        - menu option: shop (buy stuff from vendors you put on the train after unlocking them?)
        - menu option: party (chat with party members?)
        - menu option: wait (sleep, but in minutes instead of hours, or update sleep)
    #>
}

function Show-TrainMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )

    # First, write some headers
    $State | Write-GlobalTime
    $State | Write-TrainState

    # Sorted by category and line (groups of three)
    # todo: we can combine "Browse" and "Item" if the item list is more useful and sortable (then replace browse with craft/shop?)
    $availableActions = @(
        'Browse', 'Item', 'Equip'
        'Level Up', 'Read', 'Sleep'
        'Skills', 'Party', 'Training'
        'Save'
    )
    if ($State.game.train.stopped) {
        $availableActions += 'Explore'
    }
    if (
        (-not $State.game.train.stopped) -and
        ($null -ne $State.game.train.stationDecisionPoint) -and
        ($State.time.currentTime -lt $State.game.train.stationDecisionPoint)
    ) {
        $availableActions += 'Change Destination'
    }
    if ($State.game.train.stopped) {
        $availableActions += 'Depart'
    }

    # Write the actions
    $itemsInThisLine = 0
    foreach ($action in $availableActions) {
        if ($itemsInThisLine -eq 0) {
            # First item, so add the initial |
            Write-Host '| ' -NoNewline
        }
        # Write the actual choice
        Write-Host "$action | " -NoNewline
        $itemsInThisLine++
        if ($itemsInThisLine -ge 3) {
            # this is the third item, so terminate the line and reset
            Write-Host ''
            $itemsInThisLine = 0
        }
    }
    if ($itemsInThisLine -ne 0) { Write-Host '' } # terminate if we didn't in the loop

    # Read the input and perform the action
    $choice = $State | Read-PlayerInput -Choices $availableActions
    switch ($choice) {
        'browse' {
            $State | Show-Inventory
            $State | Add-GlobalTime -Time '00:01:00'
        }
        'item' {
            $State | Show-BattleCharacterInfo -Character $State.player # to show HP, etc. for informed item use
            Write-Host ''
            $State | Invoke-SpecialItem -Attacker $State.player
            $State | Add-GlobalTime -Time '00:01:00'
        }
        'equip' {
            # stats are shown in the helper function
            Write-Host ''
            $State | Invoke-SpecialEquip -Attacker $State.player
            # Handles time add within the helper function based on how many items are equipped
        }

        'level up' {
            $State | Show-BattleCharacterInfo -Character $State.player -Inspect -NoDescription # to show stats for informed leveling
            Write-Host ''
            $State | Show-LevelUpMenu
            # Handles time add within the helper function based on how many orbs are eaten
        }
        'read' {
            $State | Show-EncyclopediaMenu
            # Handles the time add within the helper function based on what's read
        }
        'sleep' {
            $State | Show-BattleCharacterInfo -Character $State.player # to show HP, etc. for informed sleeping
            Write-Host ''
            $State | Show-TrainSleepMenu
            # Directly handles the time add in the helper function (that's the main point of sleeping!)
        }

        'skills' {
            $State | Show-SkillsMenu -Character $State.player
            # Handles time adds in the helper function based on skills swapped
        }
        'party' {
            $partyMembers = $State.party.Count -gt 0 ? @($State.player.name, $State.party.name) : @($State.player.name)
            Write-Host "$($State.player.name)'s party:"
            Write-Host ($partyMembers -join ' | ')
            $choice = $State | Read-PlayerInput -Prompt 'Inspect which party member?' -Choices $partyMembers -AllowNullChoice

            $State | Add-GlobalTime -Time '00:01:00'
            if ([string]::IsNullOrEmpty($choice)) {
                Write-Host 'You changed your mind...'
            } else {
                # Get data
                if ($choice -ne $State.player.name) {
                    $character = $State.party | Where-Object -Property name -EQ $choice
                } else {
                    $character = $State.player
                }

                # display it (precisely)
                $State | Show-BattleCharacterInfo -Character $character -Inspect -Bestiary
                Write-Host ''
            }
        }
        'training' {
            $choice = $State | Read-PlayerInput -Prompt 'Fight the training dummy? (y/n, or <enter> to cancel)' -Choices @('yes', 'no') -AllowNullChoice
            if ($choice -eq 'yes') {
                $State | Exit-Scene -Type 'battle' -Id 'training-dummy'
            } else {
                Write-Host 'You changed your mind...'
                $State | Add-GlobalTime -Time '00:00:30'
            }
        }

        'save' {
            $State | Invoke-ManualSave
            # Saving does not take any time. That would be mean.
        }
        'explore' {
            Write-Host "You prepare to depart at $($State.game.train.lastStationName)."
            $State | Add-GlobalTime -Time '00:01:00'
            $State | Exit-Scene -Type 'explore' -Id $State.game.train.lastStation
        }
        'change destination' {
            $State | Show-TrainDecisionMenu
            # Already handles the time add in the helper function
        }
        'depart' {
            $choice = $State | Read-PlayerInput -Prompt "Depart from $($State.game.train.lastStationName) early? (y/n)" -Choices @('yes', 'no') -AllowNullChoice
            if ($choice -ne 'yes') {
                Write-Host 'You changed your mind...'
                $State | Add-GlobalTime -Time '00:00:30'
            } else {
                $State | Invoke-TrainDeparture -EarlyDeparture
            }
        }
    }
}

function Show-TrainSleepMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )

    # Get input
    while ($true) {
        $response = Read-Host -Prompt 'Sleep how long? (hours, or "T" to sleep until the next station, or <enter> to cancel)'
        try {
            # "T" handler
            if ($response -eq 'T') {
                if ($State.game.train.stopped) {
                    Write-Host 'The train is already stopped at a station!'
                    $response = $null
                } elseif ($null -eq $State.game.train.willArriveAt) {
                    Write-Host "You don't know when the train will arrive!"
                    $response = $null
                } else {
                    Write-Debug "calculating sleep time based on train travel time - arriving at $($State.game.train.willArriveAt) and current time is $($State.time.currentTime)"
                    $timeUntilTrainStops = $State.game.train.willArriveAt - $State.time.currentTime
                    $response = $timeUntilTrainStops.Hours
                    Write-Debug "time until train stops: $timeUntilTrainStops / to-sleep: $response"

                    # wait the rest of the time immediately, so we wake up right on time
                    $timeToWaitRightNow = $timeUntilTrainStops - (New-TimeSpan -Hours $response)
                    Write-Debug "waiting $timeToWaitRightNow immediately"
                    $State | Add-GlobalTime -Time $timeToWaitRightNow
                }
            }

            $sleepTime = [int]$response
            break
        } catch {
            Write-Host -ForegroundColor Yellow '❌ Invalid input; make a valid choice to continue! (Must be a whole number)'
        }
    }

    # Escape if desired ($null -> 0 as well)
    if ($sleepTime -le 0) {
        Write-Host 'You changed your mind...'
        $State | Add-GlobalTime -Time '00:00:30'
        return
    }

    # Sanity check to avoid going into a coma
    if ($sleepTime -gt 12) {
        $sleepTime = 12
        $wokeUpEarly = $true
    }

    # Perform the sleep
    Write-Host 'You drift off to sleep...'
    Write-Host -ForegroundColor DarkGray 'Sleeping' -NoNewline
    foreach ($hour in 1..$sleepTime) {
        # For each hour you sleep, bump time forward to avoid a massive leap
        Write-Host -ForegroundColor DarkGray '.' -NoNewline
        Start-Sleep -Seconds 1
        $State | Add-GlobalTime -Time '01:00:00'
    }
    Write-Host ''

    # Heal for however long you slept
    $fakeSleepStatus = @{
        id = 'train-sleep'
        guid = $null # just for tracking; not needed here as this isn't a status
        class = 'physical'
        type = 'healing'
        pow = 10
        atk = $State.player.attrib.hp.sleepMultiplier
    }
    # Expression is equivalent to "1% of max HP per hour", then multiplied by the "atk" of the sleepMultiplier (default 4)
    $State | Invoke-DamageEffect -Expression "$sleepTime * t / 100" -Status $fakeSleepStatus -Target $State.player -AsHealing

    # Restore BP and focus
    $State.player.attrib.bp.value = $State.player.attrib.bp.max
    $State.player.attrib.mp.value = $State.player.attrib.mp.max

    # Wake up
    if ($wokeUpEarly) { Write-Host "You couldn't stay asleep that long and woke up early..." }
    switch ($sleepTime) {
        { $_ -le 2 } { 'You wake up tired and disoriented, but somewhat refreshed.'; break }
        { $_ -le 4 } { 'You wake up refreshed, but still tired.'; break }
        { $_ -le 10 } { 'You wake up well-rested.'; break }
        default { 'You wake up well-rested and full of energy, but was it really okay to sleep that long...?' }
    }

    # Autosave
    $State | Invoke-AutoSave
}

function Show-EncyclopediaMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State
    )

    while($true) {
        # Get what sub-thing to read
        # todo: add more stuff to read!
        $books = @('Bestiary', 'Statuses', 'Tutorials')
        Write-Host "Available books: [ $($books -join ' | ') ]"
        $choice = $State | Read-PlayerInput -Prompt 'What will you read? (or <enter> to stop reading)' -Choices $books -AllowNullChoice

        if ([string]::IsNullOrWhiteSpace($choice)) {
            Write-Host 'You stopped reading.'
            break
        }

        switch ($choice) {
            'bestiary' { $State | Show-BestiaryBook }
            'statuses' { $State | Show-StatusBook }
            'tutorials' { $State | Show-TutorialBook }
            default {
                # Shouldn't happen but who knows
                Write-Host -ForegroundColor Yellow "❓ You can't find that book, so you give up."
            }
        }
    }

    # Time mgmt
    $State | Add-GlobalTime -Time '00:01:00'
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

    while ($true) {
        # Display all current skills
        foreach ($category in $Character.skills.GetEnumerator()) {
            # Show the currently equipped skills
            if ($category.Value.Count -gt 0) {
                if ($category.Value.Count -ge $State.options.maxSkillsInCategory) { $color = 'White' } else { $color = 'Gray' }
                Write-Host -ForegroundColor $color "$($category.Key): $($category.Value.id -join ' | ')" -NoNewline
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

        # Get skill to perform the action on
        if (-not $SkillId) {
            switch ($SkillAction) {
                'add' { $availableSkills = $Character.spareSkills.$SkillCategory.id }
                'remove' { $availableSkills = $Character.skills.$SkillCategory.id }
                default { Write-Warning "Unknown skill action '$SkillAction'"; continue }
            }
            $SkillId = $State | Read-PlayerInput -Prompt "$SkillAction which skill? ($($availableSkills -join ', '))" -Choices $availableSkills -AllowNullChoice
        }
        if (-not $SkillId) {
            Write-Host "You stopped editing your '$SkillCategory' skills."
            continue
        }

        # If we need to do a swap, prompt for that
        if ($SkillAction -eq 'add' -and $Character.skills.$SkillCategory.Count -ge $State.options.maxSkillsInCategory) {
            $swapSkillId = $State | Read-PlayerInput -Prompt "'$SkillCategory' is full. Swap which skill with '$SkillId'? ($($Character.skills.$SkillCategory.id -join ', '))" -Choices $Character.skills.$SkillCategory.id -AllowNullChoice
            if ([string]::IsNullOrEmpty($swapSkillId)) {
                Write-Host "You can't memorize '$SkillId' without forgetting another skill."
                continue
            }
        }

        # Perform the action
        # todo: there has to be a more DRY way to do this
        if ($swapSkillId) {
            Write-Host -ForegroundColor Yellow "🧠 You forgot how to use '$swapSkillId' (moved to memory vault)."
            $Character.spareSkills.$SkillCategory.Add(($Character.skills.$SkillCategory | Where-Object -Property id -EQ $swapSkillId)) | Out-Null
            $Character.skills.$SkillCategory.Remove(($Character.skills.$SkillCategory | Where-Object -Property id -EQ $swapSkillId))
        }
        switch ($SkillAction) {
            'add' {
                Write-Host -ForegroundColor Green "🎓 You memorized '$SkillId'."
                $Character.skills.$SkillCategory.Add(($Character.spareSkills.$SkillCategory | Where-Object -Property id -EQ $SkillId)) | Out-Null
                $Character.spareSkills.$SkillCategory.Remove(($Character.spareSkills.$SkillCategory | Where-Object -Property id -EQ $SkillId))
            }
            'remove' {
                Write-Host -ForegroundColor Yellow "🧠 You forgot how to use '$SkillId' (moved to memory vault)."
                $Character.spareSkills.$SkillCategory.Add(($Character.skills.$SkillCategory | Where-Object -Property id -EQ $SkillId)) | Out-Null
                $Character.skills.$SkillCategory.Remove(($Character.skills.$SkillCategory | Where-Object -Property id -EQ $SkillId))
            }
        }

        $State | Add-GlobalTime -Time '00:02:30'
        if ($OnlyOne) {
            return
        } else {
            $SkillCategory = $null
            $SkillAction = $null
            $SkillId = $null
            $swapSkillId = $null
        }
    }
}
