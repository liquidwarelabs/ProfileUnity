# Filters.ps1 - ProfileUnity Filter Management Functions
# Location: \Filters\Filters.ps1
# Compatible with: ProfileUnity PowerTools v3.0 / PowerShell 5.1+

function Get-ProUFilters {
    <#
    .SYNOPSIS
        Gets ProfileUnity filters.
    
    .DESCRIPTION
        Retrieves all filters or filters by name. Can optionally include usage information
        showing which configurations each filter is used in.
    
    .PARAMETER Name
        Optional name filter (supports wildcards)
    
    .PARAMETER IncludeUsage
        Include usage information showing which configurations each filter is used in
    
    .EXAMPLE
        Get-ProUFilters
        
    .EXAMPLE
        Get-ProUFilters -Name "*Test*"
        
    .EXAMPLE
        Get-ProUFilters -IncludeUsage
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [switch]$IncludeUsage
    )
    
    try {
        Write-Verbose "Retrieving filters..."
        $response = Invoke-ProfileUnityApi -Endpoint "filter"
        
        # Handle different response formats consistently
        $filters = if ($response.Tag.Rows) { 
            $response.Tag.Rows 
        } elseif ($response.tag) { 
            $response.tag 
        } elseif ($response) { 
            $response 
        } else { 
            @() 
        }
        
        if (-not $filters) {
            Write-Warning "No filters found"
            return
        }
        
        # Filter by name if specified
        if ($Name) {
            $filters = $filters | Where-Object { $_.Name -like $Name }
        }
        
        # Add usage information if requested
        if ($IncludeUsage) {
            Write-Verbose "Retrieving filter usage information..."
            $usageData = @{}
            
            try {
                $usageResponse = Invoke-ProfileUnityApi -Endpoint "filter/usedin"
                if ($usageResponse -and $usageResponse.Tag -and $usageResponse.Tag.Rows) {
                    foreach ($usage in $usageResponse.Tag.Rows) {
                        $filterId = $usage.Id
                        if ($filterId -and -not $usageData.ContainsKey($filterId)) {
                            $usageData[$filterId] = @{
                                UsedIn = $usage.UsedIn
                                FilterName = $usage.Name
                                FilterId = $usage.Id
                            }
                        }
                    }
                }
                elseif ($usageResponse -and $usageResponse.tag) {
                    # Handle different response format
                    foreach ($usage in $usageResponse.tag) {
                        $filterId = $usage.Id
                        if ($filterId -and -not $usageData.ContainsKey($filterId)) {
                            $usageData[$filterId] = @{
                                UsedIn = $usage.UsedIn
                                FilterName = $usage.Name
                                FilterId = $usage.Id
                            }
                        }
                    }
                }
            }
            catch {
                Write-Warning "Could not retrieve filter usage information: $_"
            }
            
            # Add usage information to each filter
            foreach ($filter in $filters) {
                if ($usageData.ContainsKey($filter.Id)) {
                    $filter | Add-Member -NotePropertyName "UsedIn" -NotePropertyValue $usageData[$filter.Id].UsedIn -Force
                    $filter | Add-Member -NotePropertyName "ConfigCount" -NotePropertyValue $usageData[$filter.Id].UsedIn -Force
                }
                else {
                    $filter | Add-Member -NotePropertyName "UsedIn" -NotePropertyValue 0 -Force
                    $filter | Add-Member -NotePropertyName "ConfigCount" -NotePropertyValue 0 -Force
                }
            }
        }
        
        return $filters
    }
    catch {
        Write-Error "Failed to retrieve filters: $_"
        throw
    }
}

function Edit-ProUFilter {
    <#
    .SYNOPSIS
        Loads a ProfileUnity filter for editing.
    
    .DESCRIPTION
        Retrieves a filter and stores it in memory for editing.
    
    .PARAMETER Name
        The exact name of the filter to edit
    
    .PARAMETER Quiet
        Suppress confirmation messages
    
    .EXAMPLE
        Edit-ProUFilter -Name "Test Filter"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [switch]$Quiet
    )
    
    try {
        # Get all filters
        $filters = Get-ProUFilters
        $filter = $filters | Where-Object { $_.Name -eq $Name }
        
        if (-not $filter) {
            throw "Filter '$Name' not found"
        }
        
        Write-Verbose "Loading filter ID: $($filter.Id)"
        
        # Get full filter details
        $response = Invoke-ProfileUnityApi -Endpoint "filter/$($filter.Id)"
        
        if (-not $response -or -not $response.tag) {
            throw "Failed to load filter details"
        }
        
        $filterData = $response.tag
        
        # Store in module config with null checking
        if (-not $script:ModuleConfig) {
            $script:ModuleConfig = @{ CurrentItems = @{} }
        }
        if (-not $script:ModuleConfig.CurrentItems) {
            $script:ModuleConfig.CurrentItems = @{}
        }
        $script:ModuleConfig.CurrentItems.Filter = $filterData
        
        # Also set global variable for backward compatibility
        $global:CurrentFilter = $filterData
        
        if (-not $Quiet) {
            Write-Host "Filter '$Name' loaded for editing" -ForegroundColor Green
            Write-Host "Type: $($filterData.filterType)" -ForegroundColor Cyan
            Write-Host "Priority: $($filterData.priority)" -ForegroundColor Cyan
            
            # Show filter criteria summary if available
            if ($filterData.criteria) {
                Write-Host "Criteria: $($filterData.criteria.Count) rules" -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Error "Failed to edit filter: $_"
        throw
    }
}

function Save-ProUFilter {
    <#
    .SYNOPSIS
        Saves the currently edited ProfileUnity filter.
    
    .DESCRIPTION
        Saves changes made to the current filter back to the server.
    
    .PARAMETER Force
        Skip confirmation prompt
    
    .EXAMPLE
        Save-ProUFilter
        
    .EXAMPLE
        Save-ProUFilter -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param([switch]$Force) 
    
    if ($Force -or $PSCmdlet.ShouldProcess("filter on ProfileUnity server", "Save")) {
        Save-ProfileUnityItem -ItemType 'filter' -Force:$Force -Confirm:$false
    }
    else {
        Write-Host "Save cancelled" -ForegroundColor Yellow
    }
}

function New-ProUFilter {
    <#
    .SYNOPSIS
        Creates a new ProfileUnity filter.
    
    .DESCRIPTION
        Creates a new filter with basic settings.
    
    .PARAMETER Name
        Name of the new filter
    
    .PARAMETER Type
        Filter type (User, Computer, etc.)
    
    .PARAMETER Description
        Optional description
    
    .PARAMETER Priority
        Filter priority (default: 100)
    
    .EXAMPLE
        New-ProUFilter -Name "Test Filter" -Type "User" -Description "Test filter"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [ValidateSet('User', 'Computer', 'Group', 'OU')]
        [string]$Type,
        
        [string]$Description = "",
        
        [int]$Priority = 100
    )
    
    try {
        # Check if filter already exists
        $existingFilters = Get-ProUFilters
        if ($existingFilters | Where-Object { $_.Name -eq $Name }) {
            throw "Filter '$Name' already exists"
        }
        
        Write-Verbose "Creating new filter: $Name"
        
        # Create complete filter object with all required fields
        $newFilter = @{
            Name = $Name
            Description = $Description
            FilterType = $Type
            Priority = $Priority
            Disabled = $false
            Comments = ""
            # Filter criteria and rules
            FilterRules = @()
            Connections = 0
            MachineClasses = 0
            OperatingSystems = 0
            SystemEvents = 0
            RuleAggregate = 0
            ClientId = $null
            ClientSecret = $null
        }
        
        # Create the filter - use direct object, not wrapped
        $response = Invoke-ProfileUnityApi -Endpoint "filter" -Method POST -Body $newFilter
        
        # Validate response
        if ($response -and $response.type -eq "success") {
            Write-Host "Filter '$Name' created successfully" -ForegroundColor Green
            Write-Verbose "Filter ID: $($response.tag.id)"
            return $response.tag
        }
        elseif ($response -and $response.type -eq "error") {
            throw "Server error: $($response.message)"
        }
        else {
            throw "Unexpected response from server: $($response | ConvertTo-Json -Depth 2)"
        }
    }
    catch {
        Write-Error "Failed to create filter: $_"
        throw
    }
}

function Remove-ProUFilter {
    <#
    .SYNOPSIS
        Removes a ProfileUnity filter.
    
    .DESCRIPTION
        Deletes a filter from the ProfileUnity server.
    
    .PARAMETER Name
        Name of the filter to remove
    
    .PARAMETER Force
        Skip confirmation prompt
    
    .EXAMPLE
        Remove-ProUFilter -Name "Old Filter"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [switch]$Force
    )
    
    try {
        $filters = Get-ProUFilters
        $filter = $filters | Where-Object { $_.Name -eq $Name }
        
        if (-not $filter) {
            throw "Filter '$Name' not found"
        }
        
        if ($Force -or $PSCmdlet.ShouldProcess($Name, "Remove filter")) {
            $response = Invoke-ProfileUnityApi -Endpoint "filter/$($filter.Id)" -Method DELETE
            Write-Host "Filter '$Name' removed successfully" -ForegroundColor Green
            return $response
        }
        else {
            Write-Host "Remove cancelled" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "Failed to remove filter: $_"
        throw
    }
}

function Copy-ProUFilter {
    <#
    .SYNOPSIS
        Copies an existing ProfileUnity filter.
    
    .DESCRIPTION
        Copies an existing filter with a new name.
    
    .PARAMETER SourceName
        Name of the filter to copy
    
    .PARAMETER NewName
        Name for the new filter
    
    .PARAMETER Description
        Optional new description
    
    .EXAMPLE
        Copy-ProUFilter -SourceName "Production Filter" -NewName "Test Filter"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceName,
        
        [Parameter(Mandatory)]
        [string]$NewName,
        
        [string]$Description
    )
    
    try {
        # Find source filter
        $filters = Get-ProUFilters
        $sourceFilter = $filters | Where-Object { $_.Name -eq $SourceName }
        
        if (-not $sourceFilter) {
            throw "Source filter '$SourceName' not found"
        }
        
        Write-Verbose "Copying filter ID: $($sourceFilter.ID)"
        
        # Get full filter details
        $response = Invoke-ProfileUnityApi -Endpoint "filter/$($sourceFilter.ID)"
        
        if ($response -and $response.tag) {
            # Update the copy with new name
            $copiedFilter = $response.tag
            $copiedFilter.name = $NewName
            
            if ($Description) {
                $copiedFilter.description = $Description
            }
            else {
                $copiedFilter.description = "Copy of $SourceName - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            }
            
            # Remove ID so it creates a new filter
            $copiedFilter.PSObject.Properties.Remove('id')
            
            # Save the new filter
            $saveResponse = Invoke-ProfileUnityApi -Endpoint "filter" -Method POST -Body @{
                filter = $copiedFilter
            }
            
            Write-Host "Filter copied successfully" -ForegroundColor Green
            Write-Host "  Source: $SourceName" -ForegroundColor Cyan
            Write-Host "  New: $NewName" -ForegroundColor Cyan
            
            return $saveResponse
        }
    }
    catch {
        Write-Error "Failed to copy filter: $_"
        throw
    }
}

function Test-ProUFilter {
    <#
    .SYNOPSIS
        Tests a ProfileUnity filter for issues.
    
    .DESCRIPTION
        Validates filter settings and checks for common problems.
    
    .PARAMETER Name
        Name of the filter to test
    
    .EXAMPLE
        Test-ProUFilter -Name "Test Filter"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    try {
        $filters = Get-ProUFilters
        $filter = $filters | Where-Object { $_.Name -eq $Name }
        
        if (-not $filter) {
            throw "Filter '$Name' not found"
        }
        
        Write-Verbose "Testing filter: $Name"
        
        # Get detailed filter
        $response = Invoke-ProfileUnityApi -Endpoint "filter/$($filter.Id)"
        $filterData = $response.tag
        
        $issues = @()
        $warnings = @()
        
        # Basic validation
        if (-not $filterData.name) {
            $issues += "Missing filter name"
        }
        
        if (-not $filterData.filterType) {
            $issues += "Missing filter type"
        }
        
        if (-not $filterData.criteria -or $filterData.criteria.Count -eq 0) {
            $warnings += "Filter has no criteria defined"
        }
        
        if ($filterData.priority -lt 1 -or $filterData.priority -gt 999) {
            $warnings += "Filter priority should be between 1 and 999"
        }
        
        $isValid = $issues.Count -eq 0
        
        $result = [PSCustomObject]@{
            FilterName = $Name
            IsValid = $isValid
            Issues = $issues
            Warnings = $warnings
            CriteriaCount = if ($filterData.criteria) { $filterData.criteria.Count } else { 0 }
            TestDate = Get-Date
        }
        
        # Display results
        if ($isValid) {
            Write-Host "Filter '$Name' validation: PASSED" -ForegroundColor Green
        }
        else {
            Write-Host "Filter '$Name' validation: FAILED" -ForegroundColor Red
            $issues | ForEach-Object { Write-Host "  ERROR: $_" -ForegroundColor Red }
        }
        
        if ($warnings.Count -gt 0) {
            $warnings | ForEach-Object { Write-Host "  WARNING: $_" -ForegroundColor Yellow }
        }
        
        return $result
    }
    catch {
        Write-Error "Failed to test filter: $_"
        throw
    }
}

function Get-ProUFilterTypes {
    <#
    .SYNOPSIS
        Gets available filter types.
    
    .DESCRIPTION
        Retrieves the list of available filter types.
    
    .EXAMPLE
        Get-ProUFilterTypes
    #>
    [CmdletBinding()]
    param()
    
    try {
        $response = Invoke-ProfileUnityApi -Endpoint "filter/types"
        
        if ($response) {
            return $response | ForEach-Object {
                [PSCustomObject]@{
                    FilterType = $_.type
                    DisplayName = $_.displayName
                    Description = $_.description
                }
            }
        }
        else {
            # Return common filter types if API doesn't provide them
            return @(
                [PSCustomObject]@{ FilterType = 'User'; DisplayName = 'User'; Description = 'User-based filter' }
                [PSCustomObject]@{ FilterType = 'Computer'; DisplayName = 'Computer'; Description = 'Computer-based filter' }
                [PSCustomObject]@{ FilterType = 'Group'; DisplayName = 'Group'; Description = 'Group-based filter' }
                [PSCustomObject]@{ FilterType = 'OU'; DisplayName = 'Organizational Unit'; Description = 'OU-based filter' }
            )
        }
    }
    catch {
        Write-Error "Failed to retrieve filter types: $_"
        throw
    }
}

# Export functions
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
# Export-ModuleMember removed to prevent conflicts when dot-sourcing
<#
Export-ModuleMember -Function @(
    'Get-ProUFilters',
    'Edit-ProUFilter',
    'Save-ProUFilter',
    'New-ProUFilter',
    'Remove-ProUFilter',
    'Copy-ProUFilter',
    'Test-ProUFilter',
    'Get-ProUFilterTypes'
)
#>