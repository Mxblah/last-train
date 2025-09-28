<#
.SYNOPSIS
Expand variables in text that references the game state.
#>
function Enrich-Text {
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName, ValueFromRemainingArguments, Position = 1)]
        [string]$Message,

        [Parameter()]
        [switch]$SuperDebug
    )

    # Regex extract the things we need to substitute (if any)
    $result = $Message | Select-String -Pattern '\$\{[^${}]*\}' -AllMatches
    if ($SuperDebug) { Write-Debug "Enriching the following variables: [$($result.Matches.Value -join ', ')]" }

    foreach ($match in ($result.Matches | Select-Object -Property Value -Unique)) {
        # Look up the value in the state through a recursive-ish function
        $cleanKey = $match.Value -replace '\$|\{|\}', ''
        $value = $State
        foreach ($key in ($cleanKey -split '\.')) {
            $value = $value.$key
        }

        # Perform the substitution
        Write-Debug "Replacing $($match.Value) with $value"
        $Message = $Message -replace [regex]::Escape($match.Value), $value
    }

    return $Message
}

<#
.SYNOPSIS
Read player input and match against a list of available responses
#>
function Read-PlayerInput {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [object]$State,

        [Parameter()]
        [string]$Prompt = '> ',

        [Parameter(Mandatory = $true)]
        [string[]]$Choices,

        [Parameter()]
        [switch]$AllowNullChoice,

        [Parameter()]
        [switch]$SuperDebug
    )
    if ($SuperDebug) {
        Write-Debug "reading input with possible choices [$($Choices -join ', ')]"
    }
    while ($true) {
        # Read input
        $response = Read-Host -Prompt ($State | Enrich-Text $Prompt)
        $cleanResponse = $response -replace "[`"']", ''

        # Check to see if the input matches any of the available responses, handling quotes
        $matchedResponses = switch ($response) {
            { $_ -like '"*"' -or $_ -like "'*'" } {
                # Quote-wrapped; exact match
                foreach ($possibleResponse in $Choices) {
                    if ($possibleResponse -eq $cleanResponse) {
                        # No need to keep checking the list if we find an exact match
                        Write-Debug "User input exactly matched $possibleResponse; breaking"
                        $possibleResponse
                        break
                    }
                }
                break
            }

            { $_ -like '"*' -or $_ -like "'*" } {
                # Leading quote; exact on the front but otherwise lenient
                foreach ($possibleResponse in $Choices) {
                    if ($possibleResponse -like "$cleanResponse*") {
                        Write-Debug "User input front-matched $possibleResponse"
                        $possibleResponse
                    }
                }
                break
            }

            { $_ -like '*"' -or $_ -like "*'" } {
                # Ending quote; opposite logic to leading quote
                foreach ($possibleResponse in $Choices) {
                    if ($possibleResponse -like "*$cleanResponse") {
                        Write-Debug "User input back-matched $possibleResponse"
                        $possibleResponse
                    }
                }
                break
            }

            default {
                # Regular lenient match
                foreach ($possibleResponse in $Choices) {
                    if ($possibleResponse.toLower().Contains($response.toLower())) {
                        Write-Debug "User input matched response $possibleResponse"
                        $possibleResponse
                    }
                }
            }
        }

        switch ($matchedResponses.Count) {
            {$_ -eq 0 -or [string]::IsNullOrWhiteSpace($response)} {
                if ($AllowNullChoice -and [string]::IsNullOrWhiteSpace($response)) {
                    # If null choice is allowed, let 'em go
                    Write-Host -ForegroundColor Yellow "🚫 No selection made."
                    return $null
                } else {
                    # No responses matched, so we don't know what to do with this input
                    Write-Host -ForegroundColor Yellow "❌ Invalid input; make a valid choice to continue!`nCurrently available responses are [$($Choices -join ', ')$($AllowNullChoice ? ', <empty>' : '')]"
                    break
                }
            }

            1 {
                # Exactly one response matched, so handle that one
                Write-Debug "One matched response: returning '$matchedResponses'"
                Write-Host ''
                return $matchedResponses
            }

            default {
                # More than one response matched, so the user input is indeterminate
                Write-Host -ForegroundColor Yellow "❓ Input matched more than one possible response; please be more specific or use `"quotes`" for exact matching!`nResponses matched: [$($matchedResponses -join ', ')]"
            }
        }
    }
}

function ConvertTo-TitleCase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [string]$String,

        [Parameter()]
        [switch]$SuperDebug
    )

    if ($SuperDebug) {
        Write-Debug "capitalizing '$String'"
    }

    $resultArray = foreach ($word in $String -split ' ') {
        if ($word.Length -ge 2) {
            "$($word.Substring(0,1).ToUpper())$($word.Substring(1))"
        } elseif ($word.Length -eq 1) {
            "$($word.Substring(0,1).ToUpper())"
        } else {
            $word
        }
    }
    $result = $resultArray -join ' '

    if ($SuperDebug) {
        Write-Debug "(now '$result')"
    }
    return $result
}

function Get-DamageTypeFlavorInfo {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Class,

        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    # It's just a big lookup table. That's it.
    $flavorMap = switch ($Type) {
        # Standout damage types
        { $_ -match 'standard|weapon' } {
            if ($Class -eq 'physical') {
                @{ badge = '⚔️'; color = 'White'; name = 'Weapon' }
            } elseif ($Class -eq 'magical') {
                @{ badge = '🪄'; color = 'Blue'; name = 'Weapon' }
            } else {
                # Don't know; use the default
                @{ badge = '🩸'; color = 'DarkRed'; name = 'Standard' }
            }
        }

        # Types that are actually classes in disguise
        'physical' { @{ badge = '⚔️'; color = 'White'; name = 'Physical' } }
        'magical' { @{ badge = '🪄'; color = 'Blue'; name = 'Magical' } }

        # Regular damage types
        'acid' { @{ badge = '🧪'; color = 'DarkGreen'; name = 'Acid' } }
        'bleed' { @{ badge = '🩸'; color = 'DarkRed'; name = 'Bleed' } }
        'cold' { @{ badge = '❄️'; color = 'Cyan'; name = 'Cold' } }
        'divine' { @{ badge = '🪽'; color = 'White'; name = 'Divine' } }
        'earth' { @{ badge = '🪨'; color = 'DarkYellow'; name = 'Earth' } }
        'explosive' { @{ badge = '💥'; color = 'DarkYellow'; name = 'Explosive' } }
        'fire' { @{ badge = '🔥'; color = 'Red'; name = 'Fire' } }
        'force' { @{ badge = '✨'; color = 'Magenta'; name = 'Force' } }
        'healing' { @{ badge = '💖'; color = 'Green'; name = 'Healing' } }
        'lightning' { @{ badge = '⚡'; color = 'Yellow'; name = 'Lightning' } }
        'mental' { @{ badge = '🧠'; color = 'Magenta'; name = 'Mental' } }
        'piercing' { @{ badge = '🗡️'; color = 'White'; name = 'Piercing' } }
        'poison' { @{ badge = '💉'; color = 'DarkGreen'; name = 'Poison' } }
        'radiation' { @{ badge = '☢️'; color = 'Yellow'; name = 'Radiation' } }
        'slashing' { @{ badge = '🔪'; color = 'White'; name = 'Slashing' } }
        'solar' { @{ badge = '☀️'; color = 'Red'; name = 'Solar' } }
        'sonic' { @{ badge = '🎶'; color = 'DarkGreen'; name = 'Sonic' } }
        'visual' { @{ badge = '👁️'; color = 'DarkMagenta'; name = 'Visual' } }
        'void' { @{ badge = '🌑'; color = 'Black'; name = 'Void' } }
        default { @{ badge = '🩸'; color = 'DarkRed' ; name = 'Unknown'} }
    }
    return $flavorMap
}

function Get-AttribStatBadge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AttribOrStat
    )

    $badge = switch ($AttribOrStat) {
        'hp' { '❤️' }
        'bp' { '🛡️' }
        'mp' { '✨' }

        'pAtk' { '✊' }
        'mAtk' { '🪄' }
        'pDef' { '🛡️' }
        'mDef' { '🔮' }
        'acc' { '🎯' }
        'spd' { '👟' }

        default { '❓' }
    }

    return $badge
}

function Get-PercentageColor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [double]$Value,

        [Parameter(Mandatory = $true)]
        [double]$Max
    )

    # divide-by-zero protection
    if ($Max -le 0) { $color = 'DarkRed' } else {
        # get color based on how full the value is
        $color = switch ($Value / $Max) {
            { $_ -ge 1 } { 'DarkGreen'; break }
            { $_ -ge 0.8 } { 'Green'; break }
            { $_ -ge 0.6 } { 'Yellow'; break }
            { $_ -ge 0.4 } { 'DarkYellow'; break }
            { $_ -ge 0.2 } { 'Red'; break }
            { $_ -ge 0 } { 'DarkRed'; break }
            default { 'Magenta' }
        }
    }

    return $color
}

function Get-EquipmentSlotFlavorInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Slot')]
        [string]$Slot,

        [Parameter(Mandatory = $true, ParameterSetName = 'All')]
        [switch]$All
    )

    # another lookup table yeehaw
    $allSlots = [ordered]@{
        # Normal slots
        hat = @{ name = 'Head'; badge = '🎩'; color = 'Gray' }
        upperFace = @{ name = 'Face (upper)'; badge = '🕶️'; color = 'Gray' }
        lowerFace = @{ name = 'Face (lower)'; badge = '😷'; color = 'Gray' }
        neck = @{ name = 'Neck'; badge = '🧣'; color = 'Gray' }
        chest = @{ name = 'Chest'; badge = '👕'; color = 'Gray' }
        legs = @{ name = 'Legs'; badge = '👖'; color = 'Gray' }
        hands = @{ name = 'Hands'; badge = '🧤'; color = 'Gray' }
        ringMajor = @{ name = 'Ring (major)'; badge = '💍'; color = 'Gray' }
        ringMinor = @{ name = 'Ring (minor)'; badge = '💍'; color = 'Gray' }
        socks = @{ name = 'Socks'; badge = '🧦'; color = 'Gray' }
        shoes = @{ name = 'Shoes'; badge = '👟'; color = 'Gray' }

        # Special slots
        barrier = @{ name = 'Barrier'; badge = '🛡️'; color = 'Magenta' }
        offhand = @{ name = 'Offhand'; badge = '✋'; color = 'Magenta' }
        weapon = @{ name = 'Weapon'; badge = '⚔️'; color = 'Magenta' }
    }

    if ($All) {
        return $allSlots
    } else {
        return $allSlots.$Slot
    }
}
