function Get-WeightedRandom {
    [CmdletBinding()]
    param(
        # The input array or arraylist must be made of hashtable-like objects with the property "weight" in them
        [Parameter(Mandatory = $true)]
        [object]$List
    )

    # Total weight; upper bound of the random chance
    $totalWeight = ($List.weight | Measure-Object -Sum).Sum
    $currentWeight = 1..$totalWeight | Get-Random
    Write-Debug "performing weighted random choice of array with $($List.Count) elements and total weight $totalWeight - selected $currentWeight"

    # Go through the array, subtracting weight as we go, until we run out. That's what we must have selected.
    foreach ($element in $List) {
        $currentWeight -= $element.weight
        Write-Debug "subtracted $($element.weight) for new running total $currentWeight"

        if ($currentWeight -le 0) {
            # I'd like to say *what* we're returning, but we don't know any properties besides weight
            Write-Debug 'running total <= 0; returning'
            return $element
        }
    }
}

<#
.NOTES
Deprecated. Use Convert-AllChildrenToArrayLists instead.
#>
function Convert-SpecificChildrenToArrayLists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Data,

        [Parameter()]
        [string[]]$CollectionList = @('activeEffects'),

        [Parameter()]
        [string[]]$ParentCollectionList = @('status', 'skills')
    )

    foreach ($collection in $CollectionList) {
        # simple collections that only need the top level to be an arraylist
        if ($null -ne $Data.$collection) {
            if ($Data.$collection.GetType().Name -ne 'ArrayList') {
                Write-Debug "changing $($Data.name) $collection type to arraylist"
                $Data.$collection = New-Object -TypeName System.Collections.ArrayList(,$Data.$collection)
            } else {
                Write-Debug "$collection is already arraylist for $($Data.name)"
            }
        } else {
            Write-Debug "$collection does not exist for $($Data.name)"
        }
    }
    foreach ($parentCollection in $ParentCollectionList) {
        # block for collections that need an extra step (but just one, due to the Clone() method)
        if ($null -ne $Data.$parentCollection) {
            foreach ($collectionRaw in $Data.$parentCollection.Clone().GetEnumerator()) {
                $collection = $collectionRaw.Key
                if ($Data.$parentCollection.$collection.GetType().Name -ne 'ArrayList') {
                    Write-Debug "changing $($Data.name) $parentCollection.$collection type to arraylist"
                    $Data.$parentCollection.$collection = New-Object -TypeName System.Collections.ArrayList(,$Data.$parentCollection.$collection)
                } else {
                    Write-Debug "$parentCollection.$collection is already arraylist for $($Data.name)"
                }
            }
        } else {
            Write-Debug "$parentCollection does not exist for $($Data.name)"
        }
    }
}

# Multi-use function that can handle any combination of arrays and hashtables, and recursively converts all arrays found into arraylists
function Convert-AllChildArraysToArrayLists {
    [CmdletBinding()]
    param(
        # Should be ArrayList, Hashtable, or Array
        [Parameter(Mandatory = $true)]
        [object]$Data,

        # For when "-Verbose -Debug" isn't verbose enough
        [Parameter()]
        [switch]$SuperDebug
    )
    Write-Verbose "`nUpdating all child arrays of collection with ID '$($Data.id)' / type '$($Data.GetType().Name)' to arraylists"

    # Handle arrays *or* maps by changing how we enumerate
    switch ($Data.GetType()) {
        { $_.BaseType -like '*Array' -or $_.Name -eq 'ArrayList' } {
            # This is an array or arraylist, so use just the object itself to enumerate
            $enumerator = $Data
            if ($SuperDebug) { Write-Debug "array-like collection; enumerator is collection (type $($enumerator.GetType().Name))" }
        }
        { $_.Name -like '*Hashtable' } {
            # This is a map, so use GetEnumerator to enumerate
            $enumerator = $Data.GetEnumerator()
            if ($SuperDebug) { Write-Debug "map-like collection; enumerator is collection (type $($enumerator.GetType().Name))" }
        }
        default { throw "'$_' is not a supported collection type; cannot determine enumerator!" }
    }

    # Main loop: build the list to convert and recursively iterate through child collections
    $conversionList = New-Object -TypeName System.Collections.ArrayList
    foreach ($child in $enumerator) {
        if ($enumerator.GetType().Name -in @('HashtableEnumerator', 'OrderedDictionaryEnumerator')) {
            # This is a map, so get the value before continuing
            $key = $child.Key
            $child = $child.Value
        }

        # null check!
        if ($null -eq $child) {
            if ($SuperDebug) {
                if ($SuperDebug) { Write-Debug "child (with key '$key' if applicable) is null; nothing to do" }
            }
            continue
        }

        switch ($child.GetType()) {
            { $_.BaseType -like '*Array' } {
                # This is an array, so iterate through it too
                if ($SuperDebug) { Write-Debug "will convert array '$($_.BaseType)/$($_.Name)' (from '$key')" }
                Convert-AllChildArraysToArrayLists -Data $child -SuperDebug:$SuperDebug

                # Once we're done iterating through it, mark it for conversion (can't convert here as we're iterating over the modified collection)
                if ($SuperDebug) { Write-Debug "marking conversion of '$($_.BaseType)/$($_.Name)' (from '$key')" }
                if ($key) {
                    # hashtable parent, so set via key
                    if ($SuperDebug) { Write-Debug '(via key due to hashtable parent)' }
                    $conversionList.Add(@{
                        key = $key
                        value = New-Object -TypeName System.Collections.ArrayList(,$child)
                    }) | Out-Null
                } else {
                    # array-like parent, so set via index
                    if ($SuperDebug) { Write-Debug '(via index due to array-like parent)' }
                    $conversionList.Add(@{
                        index = $Data.IndexOf($child)
                        value = New-Object -TypeName System.Collections.ArrayList(,$child)
                    }) | Out-Null
                }
            }
            { $_.Name -eq 'ArrayList' } {
                # This is an arraylist, so iterate through it, but don't convert it
                if ($SuperDebug) { Write-Debug "will recurse through arraylist '$($_.BaseType)/$($_.Name)' (from '$key')" }
                Convert-AllChildArraysToArrayLists -Data $child -SuperDebug:$SuperDebug
            }
            { $_.Name -like '*Hashtable' } {
                # This is a map, so recursively iterate through it using this same function
                if ($SuperDebug) { Write-Debug "will recurse through map '$($_.BaseType)/$($_.Name)' (from '$key')" }
                Convert-AllChildArraysToArrayLists -Data $child -SuperDebug:$SuperDebug
            }
            default {
                if ($SuperDebug) { Write-Debug "'$($_.BaseType)/$($_.Name)' (from '$key') is not a supported collection type or is already converted; nothing to do" }
            }
        }
    }

    # Do the final conversions now that we're done iterating
    if ($conversionList.Count -gt 0) {
        Write-Verbose "doing final conversion of $($conversionList.Count) items"
        foreach ($item in $conversionList) {
            if ($item.key) {
                if ($SuperDebug) { Write-Debug "doing actual conversion of hashtable-parented item with key $($item.key)" }
                $Data."$($item.key)" = $item.value
            } else {
                if ($SuperDebug) { Write-Debug "doing actual conversion of array-parented item with index $($item.index)" }
                $Data[$item.index] = $item.value
            }
        }
    }
}

function Get-HashtableValueFromPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Hashtable,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        # Returns the last hashtable before the value, and the key to get the value, instead of the value itself
        [Parameter()]
        [switch]$LastContainer
    )

    $lastFragment = $Path.Split('.')[-1]
    foreach ($pathFragment in ($Path.Split('.'))) {
        if ($pathFragment -ne $lastFragment) {
            # Not there yet, so continue into the next hashtable down
            $Hashtable = $Hashtable.$pathFragment
        } else {
            # This is the actual value
            Write-Debug "found last fragment '$lastFragment'"
            if ($LastContainer) {
                return @($Hashtable, $lastFragment)
            } else {
                return $Hashtable.$lastFragment
            }
        }
    }
}

function Set-HashtableValueFromPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Hashtable,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $lastFragment = $Path.Split('.')[-1]
    foreach ($pathFragment in ($Path.Split('.'))) {
        if ($pathFragment -ne $lastFragment) {
            # Not there yet, so continue into the next hashtable down
            if ($null -eq $Hashtable.$pathFragment) {
                # create if needed
                $Hashtable.$pathFragment = @{}
            }
            $Hashtable = $Hashtable.$pathFragment
        } else {
            # This is the actual value
            Write-Debug "found last fragment '$lastFragment'"
        }
    }
    Write-Debug "setting value at $Path to $Value"
    $Hashtable.$lastFragment = $Value
}

function Rename-ForUniquePropertyValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$List,

        [Parameter(Mandatory = $true)]
        [string]$Property,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Number')]
        [string]$SuffixType
    )

    # Get the dupes and init a hashtable to store how many times we've seen 'em
    $duplicateValues = ($List.$Property | Group-Object | Where-Object -Property Count -gt 1).Name
    $seen = @{}

    foreach ($item in $List) {
        if ($item.$Property -in $duplicateValues) {
            Write-Debug "$($item.$Property) is a duplicate; appending $SuffixType suffix"

            $seen."$($item.$Property)" += 1
            $item.$Property = "$($item.$Property) $($seen."$($item.$Property)")"
            Write-Debug "fixed: $($item.$Property)"
        }
    }
}
