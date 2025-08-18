# Core/SearchFunctions.ps1 - ProfileUnity Global Search Functions with Name Resolution

function Search-ProUGlobal {
    <#
    .SYNOPSIS
        Performs a global search across ProfileUnity objects.
    
    .DESCRIPTION
        Searches across all ProfileUnity object types (configurations, filters, portability rules, etc.).
    
    .PARAMETER SearchTerm
        Search term to look for
    
    .PARAMETER ObjectType
        Specific object type to search (optional)
    
    .PARAMETER MaxResults
        Maximum number of results to return per object type
    
    .EXAMPLE
        Search-ProUGlobal -SearchTerm "test"
        
    .EXAMPLE
        Search-ProUGlobal -SearchTerm "admin" -ObjectType "Configuration" -MaxResults 10
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SearchTerm,
        
        [ValidateSet('Configuration', 'Filter', 'PortabilityRule', 'FlexApp', 'Template', 'All')]
        [string]$ObjectType = 'All',
        
        [int]$MaxResults = 50
    )
    
    try {
        Write-Verbose "Performing global search for: $SearchTerm"
        
        # Build query parameters
        $queryParams = @()
        $queryParams += "q=$([System.Web.HttpUtility]::UrlEncode($SearchTerm))"
        
        if ($ObjectType -ne 'All') {
            $queryParams += "type=$ObjectType"
        }
        
        if ($MaxResults) {
            $queryParams += "maxResults=$MaxResults"
        }
        
        $queryString = if ($queryParams.Count -gt 0) {
            "?" + ($queryParams -join "&")
        } else { "" }
        
        $response = Invoke-ProfileUnityApi -Endpoint "search$queryString"
        
        if (-not $response -or $response.Count -eq 0) {
            Write-Host "No results found for: $SearchTerm" -ForegroundColor Yellow
            return
        }
        
        # Process and format results
        $results = @{
            SearchTerm = $SearchTerm
            TotalResults = 0
            Configurations = @()
            Filters = @()
            PortabilityRules = @()
            FlexApps = @()
            Templates = @()
            Other = @()
        }
        
        foreach ($item in $response) {
            $searchResult = [PSCustomObject]@{
                Name = $item.name
                Type = $item.type
                Id = $item.id
                UUID = $item.uuid
                Description = $item.description
                LastModified = $item.lastModified
                ModifiedBy = $item.modifiedBy
                MatchReason = $item.matchReason
                Score = $item.score
            }
            
            switch ($item.type) {
                'Configuration' { $results.Configurations += $searchResult }
                'Filter' { $results.Filters += $searchResult }
                'PortabilityRule' { $results.PortabilityRules += $searchResult }
                'FlexApp' { $results.FlexApps += $searchResult }
                'Template' { $results.Templates += $searchResult }
                default { $results.Other += $searchResult }
            }
            
            $results.TotalResults++
        }
        
        # Display summary
        Write-Host "`nSearch Results for '$SearchTerm':" -ForegroundColor Cyan
        Write-Host "  Total Results: $($results.TotalResults)" -ForegroundColor Gray
        
        if ($results.Configurations.Count -gt 0) {
            Write-Host "  Configurations: $($results.Configurations.Count)" -ForegroundColor Green
        }
        if ($results.Filters.Count -gt 0) {
            Write-Host "  Filters: $($results.Filters.Count)" -ForegroundColor Green
        }
        if ($results.PortabilityRules.Count -gt 0) {
            Write-Host "  Portability Rules: $($results.PortabilityRules.Count)" -ForegroundColor Green
        }
        if ($results.FlexApps.Count -gt 0) {
            Write-Host "  FlexApps: $($results.FlexApps.Count)" -ForegroundColor Green
        }
        if ($results.Templates.Count -gt 0) {
            Write-Host "  Templates: $($results.Templates.Count)" -ForegroundColor Green
        }
        if ($results.Other.Count -gt 0) {
            Write-Host "  Other Objects: $($results.Other.Count)" -ForegroundColor Green
        }
        
        return $results
    }
    catch {
        Write-Error "Failed to perform global search: $_"
        throw
    }
}

function Find-ProUObject {
    <#
    .SYNOPSIS
        Finds a specific ProfileUnity object by name or ID with name resolution.
    
    .DESCRIPTION
        Locates a specific object across all ProfileUnity object types.
        Supports name resolution for ID/UUID parameters.
    
    .PARAMETER Name
        Object name to find (supports wildcards)
    
    .PARAMETER Id
        Object ID to find (supports name resolution)
    
    .PARAMETER UUID
        Object UUID to find (supports name resolution)
    
    .PARAMETER ExactMatch
        Require exact name match
    
    .PARAMETER ObjectType
        Specific object type to search within
    
    .EXAMPLE
        Find-ProUObject -Name "Production*"
        
    .EXAMPLE
        Find-ProUObject -Id "12345-abc-def"
        
    .EXAMPLE
        Find-ProUObject -Name "MyConfig" -ObjectType "Configuration"
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,
        
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$Id,
        
        [Parameter(Mandatory, ParameterSetName = 'ByUUID')]
        [string]$UUID,
        
        [Parameter(ParameterSetName = 'ByName')]
        [switch]$ExactMatch,
        
        [ValidateSet('Configuration', 'Filter', 'PortabilityRule', 'FlexApp', 'Template', 'All')]
        [string]$ObjectType = 'All'
    )
    
    try {
        switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                $searchTerm = if ($ExactMatch) {
                    "`"$Name`""  # Quoted for exact match
                } else {
                    $Name
                }
                
                $results = Search-ProUGlobal -SearchTerm $searchTerm -ObjectType $ObjectType
                
                # Filter results for closer name matches
                if (-not $ExactMatch -and $Name.Contains('*')) {
                    $pattern = $Name.Replace('*', '.*')
                    $allResults = @()
                    
                    foreach ($category in @('Configurations', 'Filters', 'PortabilityRules', 'FlexApps', 'Templates', 'Other')) {
                        $filteredResults = $results.$category | Where-Object { $_.Name -match $pattern }
                        $allResults += $filteredResults
                    }
                    
                    return $allResults | Sort-Object Score -Descending
                }
                
                return $results
            }
            
            'ById' {
                # Check if this is a name instead of an ID
                $resolvedId = Resolve-ProUObjectId -InputValue $Id -ObjectType $ObjectType
                if ($resolvedId -and $resolvedId -ne $Id) {
                    Write-Host "Resolved '$Id' to ID: $resolvedId" -ForegroundColor Green
                }
                
                $targetId = $resolvedId -or $Id
                
                # Search by ID - try each object type if ObjectType is 'All'
                $objectTypes = if ($ObjectType -eq 'All') {
                    @('Configuration', 'Filter', 'PortabilityRule', 'FlexApp', 'Template')
                } else {
                    @($ObjectType)
                }
                
                foreach ($type in $objectTypes) {
                    try {
                        $result = Search-ProUGlobal -SearchTerm $targetId -ObjectType $type
                        $match = $result.$($type + 's') | Where-Object { $_.Id -eq $targetId }
                        
                        if ($match) {
                            Write-Host "Found $type with ID: $targetId" -ForegroundColor Green
                            return $match
                        }
                    }
                    catch {
                        # Continue searching other types
                    }
                }
                
                Write-Warning "No object found with ID: $targetId"
                return $null
            }
            
            'ByUUID' {
                # Check if this is a name instead of a UUID
                $resolvedUUID = Resolve-ProUObjectUUID -InputValue $UUID -ObjectType $ObjectType
                if ($resolvedUUID -and $resolvedUUID -ne $UUID) {
                    Write-Host "Resolved '$UUID' to UUID: $resolvedUUID" -ForegroundColor Green
                }
                
                $targetUUID = $resolvedUUID -or $UUID
                
                # Search by UUID - try each object type if ObjectType is 'All'
                $objectTypes = if ($ObjectType -eq 'All') {
                    @('Configuration', 'Filter', 'PortabilityRule', 'FlexApp', 'Template')
                } else {
                    @($ObjectType)
                }
                
                foreach ($type in $objectTypes) {
                    try {
                        $result = Search-ProUGlobal -SearchTerm $targetUUID -ObjectType $type
                        $match = $result.$($type + 's') | Where-Object { $_.UUID -eq $targetUUID }
                        
                        if ($match) {
                            Write-Host "Found $type with UUID: $targetUUID" -ForegroundColor Green
                            return $match
                        }
                    }
                    catch {
                        # Continue searching other types
                    }
                }
                
                Write-Warning "No object found with UUID: $targetUUID"
                return $null
            }
        }
    }
    catch {
        Write-Error "Failed to find object: $_"
        throw
    }
}

function Search-ProUByModifiedDate {
    <#
    .SYNOPSIS
        Searches for objects modified within a date range.
    
    .DESCRIPTION
        Finds ProfileUnity objects that were modified within a specified date range.
    
    .PARAMETER After
        Find objects modified after this date
    
    .PARAMETER Before
        Find objects modified before this date
    
    .PARAMETER Days
        Find objects modified within the last X days
    
    .PARAMETER ObjectType
        Limit search to specific object type
    
    .EXAMPLE
        Search-ProUByModifiedDate -Days 7
        
    .EXAMPLE
        Search-ProUByModifiedDate -After "2024-01-01" -ObjectType "Configuration"
    #>
    [CmdletBinding(DefaultParameterSetName = 'Days')]
    param(
        [Parameter(ParameterSetName = 'DateRange')]
        [datetime]$After,
        
        [Parameter(ParameterSetName = 'DateRange')]
        [datetime]$Before,
        
        [Parameter(ParameterSetName = 'Days')]
        [int]$Days = 30,
        
        [ValidateSet('Configuration', 'Filter', 'PortabilityRule', 'FlexApp', 'Template', 'All')]
        [string]$ObjectType = 'All'
    )
    
    try {
        if ($PSCmdlet.ParameterSetName -eq 'Days') {
            $After = (Get-Date).AddDays(-$Days)
            $Before = Get-Date
        }
        
        Write-Host "Searching for objects modified between $($After.ToString('yyyy-MM-dd')) and $($Before.ToString('yyyy-MM-dd'))..." -ForegroundColor Yellow
        
        # Perform a broad search and filter by date
        $allResults = Search-ProUGlobal -SearchTerm "*" -ObjectType $ObjectType -MaxResults 1000
        
        $filteredResults = @()
        
        foreach ($category in @('Configurations', 'Filters', 'PortabilityRules', 'FlexApps', 'Templates', 'Other')) {
            $categoryResults = $allResults.$category | Where-Object {
                if ($_.LastModified) {
                    $modDate = [datetime]$_.LastModified
                    $modDate -ge $After -and $modDate -le $Before
                }
            }
            
            if ($categoryResults) {
                $filteredResults += $categoryResults
            }
        }
        
        if ($filteredResults.Count -eq 0) {
            Write-Host "No objects found modified in the specified date range" -ForegroundColor Yellow
            return
        }
        
        $filteredResults = $filteredResults | Sort-Object LastModified -Descending
        
        Write-Host "`nFound $($filteredResults.Count) objects:" -ForegroundColor Green
        foreach ($result in $filteredResults) {
            Write-Host "  $($result.Type): $($result.Name) (Modified: $($result.LastModified) by $($result.ModifiedBy))" -ForegroundColor Gray
        }
        
        return $filteredResults
    }
    catch {
        Write-Error "Failed to search by modified date: $_"
        throw
    }
}

function Search-ProUByUser {
    <#
    .SYNOPSIS
        Searches for objects created or modified by a specific user.
    
    .DESCRIPTION
        Finds ProfileUnity objects associated with a specific user.
    
    .PARAMETER Username
        Username to search for (supports wildcards)
    
    .PARAMETER ObjectType
        Limit search to specific object type
    
    .PARAMETER Action
        Search by creation or modification (default: both)
    
    .EXAMPLE
        Search-ProUByUser -Username "john.doe"
        
    .EXAMPLE
        Search-ProUByUser -Username "*admin*" -ObjectType "Configuration"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [ValidateSet('Configuration', 'Filter', 'PortabilityRule', 'FlexApp', 'Template', 'All')]
        [string]$ObjectType = 'All',
        
        [ValidateSet('Created', 'Modified', 'Both')]
        [string]$Action = 'Both'
    )
    
    try {
        Write-Host "Searching for objects associated with user: $Username" -ForegroundColor Yellow
        
        # Perform a broad search and filter by user
        $allResults = Search-ProUGlobal -SearchTerm "*" -ObjectType $ObjectType -MaxResults 1000
        
        $filteredResults = @()
        
        foreach ($category in @('Configurations', 'Filters', 'PortabilityRules', 'FlexApps', 'Templates', 'Other')) {
            $categoryResults = $allResults.$category | Where-Object {
                $matchesUser = $false
                
                if ($Action -in @('Modified', 'Both') -and $_.ModifiedBy) {
                    $matchesUser = $_.ModifiedBy -like $Username
                }
                
                if ($Action -in @('Created', 'Both') -and $_.CreatedBy) {
                    $matchesUser = $matchesUser -or ($_.CreatedBy -like $Username)
                }
                
                return $matchesUser
            }
            
            if ($categoryResults) {
                $filteredResults += $categoryResults
            }
        }
        
        if ($filteredResults.Count -eq 0) {
            Write-Host "No objects found for user: $Username" -ForegroundColor Yellow
            return
        }
        
        $filteredResults = $filteredResults | Sort-Object LastModified -Descending
        
        Write-Host "`nFound $($filteredResults.Count) objects for user '$Username':" -ForegroundColor Green
        foreach ($result in $filteredResults) {
            Write-Host "  $($result.Type): $($result.Name) (Modified by: $($result.ModifiedBy))" -ForegroundColor Gray
        }
        
        return $filteredResults
    }
    catch {
        Write-Error "Failed to search by user: $_"
        throw
    }
}

function Resolve-ProUObjectId {
    <#
    .SYNOPSIS
        Resolves an object name to its ID.
    
    .DESCRIPTION
        Internal helper function that resolves an object name to its ID.
        If the input is already an ID/UUID format, returns it unchanged.
    
    .PARAMETER InputValue
        The name or ID to resolve
    
    .PARAMETER ObjectType
        The type of object to search for
    
    .EXAMPLE
        Resolve-ProUObjectId -InputValue "MyConfig" -ObjectType "Configuration"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputValue,
        
        [ValidateSet('Configuration', 'Filter', 'PortabilityRule', 'FlexApp', 'Template', 'All')]
        [string]$ObjectType = 'All'
    )
    
    try {
        # Check if input looks like an ID/UUID (contains hyphens or is numeric)
        if ($InputValue -match '^[\da-f\-]+$' -or $InputValue -match '^\d+$') {
            return $InputValue
        }
        
        # Search for the object by name
        Write-Verbose "Resolving name '$InputValue' to ID..."
        $searchResults = Search-ProUGlobal -SearchTerm $InputValue -ObjectType $ObjectType
        
        # Find exact name match
        $allResults = @()
        foreach ($category in @('Configurations', 'Filters', 'PortabilityRules', 'FlexApps', 'Templates', 'Other')) {
            $allResults += $searchResults.$category
        }
        
        $exactMatch = $allResults | Where-Object { $_.Name -eq $InputValue }
        if ($exactMatch) {
            if ($exactMatch.Count -gt 1) {
                Write-Warning "Multiple objects found with name '$InputValue'. Using first match."
            }
            return $exactMatch[0].Id
        }
        
        # Look for partial matches
        $partialMatches = $allResults | Where-Object { $_.Name -like "*$InputValue*" }
        if ($partialMatches) {
            if ($partialMatches.Count -eq 1) {
                Write-Host "Found partial match: '$($partialMatches[0].Name)'" -ForegroundColor Yellow
                return $partialMatches[0].Id
            } else {
                Write-Warning "Multiple partial matches found for '$InputValue':"
                $partialMatches | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
                return $partialMatches[0].Id
            }
        }
        
        # No match found
        Write-Verbose "No object found with name: $InputValue"
        return $null
    }
    catch {
        Write-Verbose "Error resolving object ID: $_"
        return $null
    }
}

function Resolve-ProUObjectUUID {
    <#
    .SYNOPSIS
        Resolves an object name to its UUID.
    
    .DESCRIPTION
        Internal helper function that resolves an object name to its UUID.
        If the input is already a UUID format, returns it unchanged.
    
    .PARAMETER InputValue
        The name or UUID to resolve
    
    .PARAMETER ObjectType
        The type of object to search for
    
    .EXAMPLE
        Resolve-ProUObjectUUID -InputValue "MyConfig" -ObjectType "Configuration"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputValue,
        
        [ValidateSet('Configuration', 'Filter', 'PortabilityRule', 'FlexApp', 'Template', 'All')]
        [string]$ObjectType = 'All'
    )
    
    try {
        # Check if input looks like a UUID (contains hyphens and letters)
        if ($InputValue -match '^[\da-f\-]+$' -and $InputValue.Length -gt 8) {
            return $InputValue
        }
        
        # Search for the object by name
        Write-Verbose "Resolving name '$InputValue' to UUID..."
        $searchResults = Search-ProUGlobal -SearchTerm $InputValue -ObjectType $ObjectType
        
        # Find exact name match
        $allResults = @()
        foreach ($category in @('Configurations', 'Filters', 'PortabilityRules', 'FlexApps', 'Templates', 'Other')) {
            $allResults += $searchResults.$category
        }
        
        $exactMatch = $allResults | Where-Object { $_.Name -eq $InputValue }
        if ($exactMatch) {
            if ($exactMatch.Count -gt 1) {
                Write-Warning "Multiple objects found with name '$InputValue'. Using first match."
            }
            return $exactMatch[0].UUID
        }
        
        # Look for partial matches
        $partialMatches = $allResults | Where-Object { $_.Name -like "*$InputValue*" }
        if ($partialMatches) {
            if ($partialMatches.Count -eq 1) {
                Write-Host "Found partial match: '$($partialMatches[0].Name)'" -ForegroundColor Yellow
                return $partialMatches[0].UUID
            } else {
                Write-Warning "Multiple partial matches found for '$InputValue':"
                $partialMatches | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
                return $partialMatches[0].UUID
            }
        }
        
        # No match found
        Write-Verbose "No object found with name: $InputValue"
        return $null
    }
    catch {
        Write-Verbose "Error resolving object UUID: $_"
        return $null
    }
}

# Export functions
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
Export-ModuleMember -Function @(
    'Find-ProUObject', 
    'Search-ProUByModifiedDate',
    'Search-ProUByUser',
    'Resolve-ProUObjectId',
    'Resolve-ProUObjectUUID'
)
#>




