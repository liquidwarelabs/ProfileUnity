# Filters.ps1 - ProfileUnity Filter Management Functions

function Get-ProUFilters {
    <#
    .SYNOPSIS
        Gets ProfileUnity filters.
    
    .DESCRIPTION
        Retrieves all filters or filters by name.
    
    .PARAMETER Name
        Optional name filter (supports wildcards)
    
    .PARAMETER Type
        Filter by type (User, Computer, Group, OU, etc.)
    
    .PARAMETER Enabled
        Filter by enabled/disabled status
    
    .EXAMPLE
        Get-ProUFilters
        
    .EXAMPLE
        Get-ProUFilters -Name "*Domain*" -Type Computer
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        
        [ValidateSet('User', 'Computer', 'Group', 'OU', 'IPRange', 'Custom')]
        [string]$Type,
        
        [bool]$Enabled
    )
    
    try {
        Write-Verbose "Retrieving filters..."
        $response = Invoke-ProfileUnityApi -Endpoint "filter"
        
        if (-not $response -or -not $response.Tag) {
            Write-Warning "No filters found"
            return
        }
        
        $filters = $response.Tag.Rows
        
        # Apply filters
        if ($Name) {
            $filters = $filters | Where-Object { $_.name -like $Name }
        }
        
        if ($Type) {
            $filters = $filters | Where-Object { $_.filterType -eq $Type }
        }
        
        if ($PSBoundParameters.ContainsKey('Enabled')) {
            $filters = $filters | Where-Object { -not $_.disabled -eq $Enabled }
        }
        
        # Format output
        $filters | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.name
                ID = $_.id
                Type = $_.filterType
                Priority = $_.priority
                Enabled = -not $_.disabled
                Description = $_.description
                CreatedBy = $_.createdBy
                ModifiedBy = $_.modifiedBy
                LastModified = $_.lastModified
            }
        }
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
        Edit-ProUFilter -Name "Domain Computers"
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
        
        Write-Verbose "Loading filter ID: $($filter.ID)"
        
        # Get full filter details
        $response = Invoke-ProfileUnityApi -Endpoint "filter/$($filter.ID)"
        
        if (-not $response -or -not $response.tag) {
            throw "Failed to load filter details"
        }
        
        $filterData = $response.tag
        
        # Store in module config
        $script:ModuleConfig.CurrentItems.Filter = $filterData
        
        # Also set global variable for backward compatibility
        $global:CurrentFilter = $filterData
        
        if (-not $Quiet) {
            Write-Host "Filter '$Name' loaded for editing" -ForegroundColor Green
            Write-Host "Type: $($filterData.filterType)" -ForegroundColor Cyan
            Write-Host "Priority: $($filterData.priority)" -ForegroundColor Cyan
            
            # Show filter criteria summary
            if ($filterData.FilterCriteria) {
                Write-Host "Criteria: $($filterData.FilterCriteria.Count) conditions" -ForegroundColor Cyan
            }
        }
        
        return $filterData
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
    param(
        [switch]$Force
    )
    
    # Get current filter
    $currentFilter = $script:ModuleConfig.CurrentItems.Filter
    if (-not $currentFilter -and $global:CurrentFilter) {
        $currentFilter = $global:CurrentFilter
    }
    
    if (-not $currentFilter) {
        throw "No filter loaded for editing. Use Edit-ProUFilter first."
    }
    
    $filterName = $currentFilter.name
    
    if ($Force -or $PSCmdlet.ShouldProcess($filterName, "Save filter")) {
        try {
            Write-Verbose "Saving filter: $filterName"
            
            # Prepare the filter object
            $filterToSave = @{
                Filters = $currentFilter
            }
            
            $response = Invoke-ProfileUnityApi -Endpoint "filter" -Method POST -Body $filterToSave
            
            if ($response) {
                Write-Host "Filter '$filterName' saved successfully" -ForegroundColor Green
                Write-LogMessage -Message "Filter '$filterName' saved by $env:USERNAME" -Level Info
                
                # Clear current filter after successful save
                $script:ModuleConfig.CurrentItems.Filter = $null
                $global:CurrentFilter = $null
                
                return $response
            }
        }
        catch {
            Write-Error "Failed to save filter: $_"
            throw
        }
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
        Creates a new filter with specified criteria.
    
    .PARAMETER Name
        Name for the new filter
    
    .PARAMETER Type
        Type of filter (User, Computer, Group, etc.)
    
    .PARAMETER Description
        Description of the filter
    
    .PARAMETER Priority
        Filter priority (default: 50)
    
    .EXAMPLE
        New-ProUFilter -Name "Test Users" -Type User -Description "Test user group"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [ValidateSet('User', 'Computer', 'Group', 'OU', 'IPRange', 'Custom')]
        [string]$Type,
        
        [string]$Description = "Created by PowerTools",
        
        [ValidateRange(1, 100)]
        [int]$Priority = 50
    )
    
    try {
        # Create new filter object
        $newFilter = @{
            name = $Name
            description = $Description
            filterType = $Type
            priority = $Priority
            disabled = $false
            FilterCriteria = @()
        }
        
        # Add default criteria based on type
        switch ($Type) {
            'User' {
                $newFilter.FilterCriteria += @{
                    criteriaType = "UserName"
                    operator = "Equals"
                    value = ""
                }
            }
            'Computer' {
                $newFilter.FilterCriteria += @{
                    criteriaType = "ComputerName"
                    operator = "Equals"
                    value = ""
                }
            }
            'Group' {
                $newFilter.FilterCriteria += @{
                    criteriaType = "GroupMembership"
                    operator = "MemberOf"
                    value = ""
                }
            }
            'OU' {
                $newFilter.FilterCriteria += @{
                    criteriaType = "OrganizationalUnit"
                    operator = "InOU"
                    value = ""
                }
            }
            'IPRange' {
                $newFilter.FilterCriteria += @{
                    criteriaType = "IPAddress"
                    operator = "InRange"
                    value = ""
                }
            }
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "filter" -Method POST -Body @{
            Filters = $newFilter
        }
        
        Write-Host "Filter '$Name' created successfully" -ForegroundColor Green
        Write-Host "Edit the filter to add specific criteria" -ForegroundColor Yellow
        
        return $response
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
        # Find filter
        $filters = Get-ProUFilters
        $filter = $filters | Where-Object { $_.Name -eq $Name }
        
        if (-not $filter) {
            throw "Filter '$Name' not found"
        }
        
        # Check if filter is in use
        $usageResponse = Invoke-ProfileUnityApi -Endpoint "filter/usedin"
        if ($usageResponse) {
            $usage = $usageResponse | Where-Object { $_.filterId -eq $filter.ID }
            if ($usage) {
                Write-Warning "Filter '$Name' is in use by the following configurations:"
                $usage | ForEach-Object {
                    Write-Warning "  - $($_.configurationName)"
                }
                
                if (-not $Force) {
                    if (-not (Confirm-Action -Title "Filter In Use" -Message "Filter is in use. Delete anyway?")) {
                        Write-Host "Delete cancelled" -ForegroundColor Yellow
                        return
                    }
                }
            }
        }
        
        if ($Force -or $PSCmdlet.ShouldProcess($Name, "Remove filter")) {
            Write-Verbose "Deleting filter ID: $($filter.ID)"
            
            $response = Invoke-ProfileUnityApi -Endpoint "filter/remove" -Method DELETE -Body @{
                ids = @($filter.ID)
            }
            
            Write-Host "Filter '$Name' deleted successfully" -ForegroundColor Green
            Write-LogMessage -Message "Filter '$Name' deleted by $env:USERNAME" -Level Info
            
            return $response
        }
        else {
            Write-Host "Delete cancelled" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "Failed to delete filter: $_"
        throw
    }
}

function Copy-ProUFilter {
    <#
    .SYNOPSIS
        Creates a copy of a ProfileUnity filter.
    
    .DESCRIPTION
        Copies an existing filter with a new name.
    
    .PARAMETER SourceName
        Name of the filter to copy
    
    .PARAMETER NewName
        Name for the new filter
    
    .EXAMPLE
        Copy-ProUFilter -SourceName "Domain Users" -NewName "Test Users"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceName,
        
        [Parameter(Mandatory)]
        [string]$NewName
    )
    
    try {
        # Find source filter
        $filters = Get-ProUFilters
        $sourceFilter = $filters | Where-Object { $_.Name -eq $SourceName }
        
        if (-not $sourceFilter) {
            throw "Source filter '$SourceName' not found"
        }
        
        Write-Verbose "Copying filter ID: $($sourceFilter.ID)"
        
        # Copy the filter
        $response = Invoke-ProfileUnityApi -Endpoint "filter/$($sourceFilter.ID)/copy" -Method POST
        
        if ($response -and $response.tag) {
            # Update the copy with new name
            $copiedFilter = $response.tag
            $copiedFilter.name = $NewName
            $copiedFilter.description = "Copy of $SourceName - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            
            # Save the updated filter
            $saveResponse = Invoke-ProfileUnityApi -Endpoint "filter" -Method POST -Body @{
                Filters = $copiedFilter
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
        Tests a ProfileUnity filter against AD objects.
    
    .DESCRIPTION
        Validates filter criteria and optionally tests against specific objects.
    
    .PARAMETER Name
        Name of the filter to test
    
    .PARAMETER TestUser
        Username to test against the filter
    
    .PARAMETER TestComputer
        Computer name to test against the filter
    
    .EXAMPLE
        Test-ProUFilter -Name "Domain Users"
        
    .EXAMPLE
        Test-ProUFilter -Name "IT Users" -TestUser "jsmith"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [string]$TestUser,
        
        [string]$TestComputer
    )
    
    try {
        Write-Host "Testing filter: $Name" -ForegroundColor Yellow
        
        # Load the filter
        Edit-ProUFilter -Name $Name -Quiet
        
        $filter = $script:ModuleConfig.CurrentItems.Filter
        if (-not $filter) {
            throw "Failed to load filter"
        }
        
        $issues = @()
        $warnings = @()
        
        # Check if filter is disabled
        if ($filter.disabled) {
            $warnings += "Filter is disabled"
        }
        
        # Check for criteria
        if (-not $filter.FilterCriteria -or $filter.FilterCriteria.Count -eq 0) {
            $issues += "Filter has no criteria defined"
        }
        else {
            # Validate each criterion
            foreach ($criterion in $filter.FilterCriteria) {
                if ([string]::IsNullOrWhiteSpace($criterion.value)) {
                    $warnings += "Criterion '$($criterion.criteriaType)' has no value specified"
                }
            }
        }
        
        # Test against specific objects if provided
        if ($TestUser -or $TestComputer) {
            Write-Host "`nTesting against objects:" -ForegroundColor Cyan
            
            if ($TestUser) {
                Write-Host "  User: $TestUser" -ForegroundColor Gray
                # Would need actual AD lookup here
                Write-Host "    [Test functionality not implemented]" -ForegroundColor Yellow
            }
            
            if ($TestComputer) {
                Write-Host "  Computer: $TestComputer" -ForegroundColor Gray
                # Would need actual AD lookup here
                Write-Host "    [Test functionality not implemented]" -ForegroundColor Yellow
            }
        }
        
        # Display results
        Write-Host "`nTest Results:" -ForegroundColor Cyan
        
        if ($issues.Count -eq 0 -and $warnings.Count -eq 0) {
            Write-Host "  No issues found" -ForegroundColor Green
        }
        else {
            if ($issues.Count -gt 0) {
                Write-Host "  Issues:" -ForegroundColor Red
                $issues | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
            }
            
            if ($warnings.Count -gt 0) {
                Write-Host "  Warnings:" -ForegroundColor Yellow
                $warnings | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
            }
        }
        
        # Clear the loaded filter
        $script:ModuleConfig.CurrentItems.Filter = $null
        $global:CurrentFilter = $null
        
        return [PSCustomObject]@{
            FilterName = $Name
            FilterType = $filter.filterType
            Priority = $filter.priority
            CriteriaCount = if ($filter.FilterCriteria) { $filter.FilterCriteria.Count } else { 0 }
            Issues = $issues
            Warnings = $warnings
            IsValid = $issues.Count -eq 0
        }
    }
    catch {
        Write-Error "Failed to test filter: $_"
        throw
    }
}

function Export-ProUFilter {
    <#
    .SYNOPSIS
        Exports a ProfileUnity filter to JSON.
    
    .DESCRIPTION
        Exports filter settings to a JSON file.
    
    .PARAMETER Name
        Name of the filter to export
    
    .PARAMETER SavePath
        Directory to save the export
    
    .EXAMPLE
        Export-ProUFilter -Name "Domain Users" -SavePath "C:\Backups"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [string]$SavePath
    )
    
    try {
        if (-not (Test-Path $SavePath)) {
            throw "Save path does not exist: $SavePath"
        }
        
        # Find filter
        $filters = Get-ProUFilters
        $filter = $filters | Where-Object { $_.Name -eq $Name }
        
        if (-not $filter) {
            throw "Filter '$Name' not found"
        }
        
        Write-Verbose "Exporting filter ID: $($filter.ID)"
        
        # Build output filename
        $safeFileName = ConvertTo-SafeFileName -FileName $Name
        $outputFile = Join-Path $SavePath "$safeFileName.json"
        
        # Download the filter
        $endpoint = "filter/download?ids=$($filter.ID)"
        Invoke-ProfileUnityApi -Endpoint $endpoint -Method POST -OutFile $outputFile
        
        Write-Host "Filter exported: $outputFile" -ForegroundColor Green
        return Get-Item $outputFile
    }
    catch {
        Write-Error "Failed to export filter: $_"
        throw
    }
}

function Export-ProUFilterAll {
    <#
    .SYNOPSIS
        Exports all ProfileUnity filters.
    
    .DESCRIPTION
        Exports all filters to JSON files in the specified directory.
    
    .PARAMETER SavePath
        Directory to save the exports
    
    .PARAMETER IncludeDisabled
        Include disabled filters
    
    .EXAMPLE
        Export-ProUFilterAll -SavePath "C:\Backups\Filters"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SavePath,
        
        [switch]$IncludeDisabled
    )
    
    try {
        if (-not (Test-Path $SavePath)) {
            New-Item -ItemType Directory -Path $SavePath -Force | Out-Null
        }
        
        $filters = Get-ProUFilters
        
        if (-not $IncludeDisabled) {
            $filters = $filters | Where-Object { $_.Enabled }
        }
        
        if (-not $filters) {
            Write-Warning "No filters found to export"
            return
        }
        
        Write-Host "Exporting $($filters.Count) filters..." -ForegroundColor Cyan
        
        $exported = 0
        $failed = 0
        
        foreach ($filter in $filters) {
            try {
                Export-ProUFilter -Name $filter.Name -SavePath $SavePath
                $exported++
            }
            catch {
                Write-Warning "Failed to export '$($filter.Name)': $_"
                $failed++
            }
        }
        
        Write-Host "`nExport Summary:" -ForegroundColor Cyan
        Write-Host "  Exported: $exported" -ForegroundColor Green
        if ($failed -gt 0) {
            Write-Host "  Failed: $failed" -ForegroundColor Red
        }
        
        return [PSCustomObject]@{
            ExportPath = $SavePath
            TotalFilters = $filters.Count
            Exported = $exported
            Failed = $failed
        }
    }
    catch {
        Write-Error "Failed to export filters: $_"
        throw
    }
}

function Import-ProUFilter {
    <#
    .SYNOPSIS
        Imports a ProfileUnity filter from JSON.
    
    .DESCRIPTION
        Imports a filter from a JSON file.
    
    .PARAMETER JsonFile
        Path to the JSON file to import
    
    .PARAMETER NewName
        Optional new name for the imported filter
    
    .EXAMPLE
        Import-ProUFilter -JsonFile "C:\Backups\filter.json"
    #>
    [CmdletBinding()]
    param(
        [string]$JsonFile,
        
        [string]$NewName
    )
    
    try {
        # Get file path if not provided
        if (-not $JsonFile) {
            $JsonFile = Get-FileName -Filter $script:FileFilters.Json -Title "Select Filter JSON"
            if (-not $JsonFile) {
                Write-Host "No file selected" -ForegroundColor Yellow
                return
            }
        }
        
        if (-not (Test-Path $JsonFile)) {
            throw "File not found: $JsonFile"
        }
        
        Write-Verbose "Importing filter from: $JsonFile"
        
        # Read and parse JSON
        $jsonContent = Get-Content $JsonFile -Raw | ConvertFrom-Json
        
        # Extract filter object
        $filterObject = if ($jsonContent.Filters) { 
            $jsonContent.Filters 
        } else { 
            $jsonContent 
        }
        
        # Update name if specified
        if ($NewName) {
            $filterObject.name = $NewName
        }
        else {
            # Add import suffix to avoid conflicts
            $filterObject.name = "$($filterObject.name) - Imported $(Get-Date -Format 'yyyyMMdd-HHmm')"
        }
        
        # Clear ID to create new
        $filterObject.ID = $null
        
        # Import the filter
        $response = Invoke-ProfileUnityApi -Endpoint "filter/import" -Method POST -Body @($filterObject)
        
        if ($response) {
            Write-Host "Filter imported successfully: $($filterObject.name)" -ForegroundColor Green
            return $response
        }
    }
    catch {
        Write-Error "Failed to import filter: $_"
        throw
    }
}

function Import-ProUFilterAll {
    <#
    .SYNOPSIS
        Imports multiple ProfileUnity filters from a directory.
    
    .DESCRIPTION
        Imports all JSON filter files from a directory.
    
    .PARAMETER SourceDir
        Directory containing JSON files to import
    
    .EXAMPLE
        Import-ProUFilterAll -SourceDir "C:\Backups\Filters"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceDir
    )
    
    try {
        if (-not (Test-Path $SourceDir)) {
            throw "Source directory not found: $SourceDir"
        }
        
        $jsonFiles = Get-ChildItem -Path $SourceDir -Filter "*.json"
        
        if (-not $jsonFiles) {
            Write-Warning "No JSON files found in: $SourceDir"
            return
        }
        
        Write-Host "Importing $($jsonFiles.Count) filter files..." -ForegroundColor Cyan
        
        $imported = 0
        $failed = 0
        
        foreach ($file in $jsonFiles) {
            try {
                Write-Host "  Processing: $($file.Name)" -NoNewline
                Import-ProUFilter -JsonFile $file.FullName
                $imported++
                Write-Host " [OK]" -ForegroundColor Green
            }
            catch {
                $failed++
                Write-Host " [FAILED]" -ForegroundColor Red
                Write-Warning "    Error: $_"
            }
        }
        
        Write-Host "`nImport Summary:" -ForegroundColor Cyan
        Write-Host "  Imported: $imported" -ForegroundColor Green
        if ($failed -gt 0) {
            Write-Host "  Failed: $failed" -ForegroundColor Red
        }
        
        return [PSCustomObject]@{
            SourceDirectory = $SourceDir
            TotalFiles = $jsonFiles.Count
            Imported = $imported
            Failed = $failed
        }
    }
    catch {
        Write-Error "Failed to import filters: $_"
        throw
    }
}

function Add-ProUFilterCriteria {
    <#
    .SYNOPSIS
        Adds criteria to the currently edited filter.
    
    .DESCRIPTION
        Adds a new criterion to the filter being edited.
    
    .PARAMETER CriteriaType
        Type of criteria to add
    
    .PARAMETER Operator
        Comparison operator
    
    .PARAMETER Value
        Value for the criteria
    
    .EXAMPLE
        Add-ProUFilterCriteria -CriteriaType "UserName" -Operator "StartsWith" -Value "admin"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('UserName', 'ComputerName', 'GroupMembership', 'OrganizationalUnit', 
                     'IPAddress', 'OSVersion', 'Domain')]
        [string]$CriteriaType,
        
        [Parameter(Mandatory)]
        [ValidateSet('Equals', 'NotEquals', 'StartsWith', 'EndsWith', 'Contains', 
                     'NotContains', 'MemberOf', 'NotMemberOf', 'InOU', 'NotInOU', 'InRange')]
        [string]$Operator,
        
        [Parameter(Mandatory)]
        [string]$Value
    )
    
    # Get current filter
    $currentFilter = $script:ModuleConfig.CurrentItems.Filter
    if (-not $currentFilter -and $global:CurrentFilter) {
        $currentFilter = $global:CurrentFilter
    }
    
    if (-not $currentFilter) {
        throw "No filter loaded for editing. Use Edit-ProUFilter first."
    }
    
    try {
        # Initialize criteria array if needed
        if (-not $currentFilter.FilterCriteria) {
            $currentFilter | Add-Member -NotePropertyName FilterCriteria -NotePropertyValue @() -Force
        }
        
        # Create new criterion
        $newCriterion = @{
            criteriaType = $CriteriaType
            operator = $Operator
            value = $Value
            enabled = $true
        }
        
        # Add to filter
        $currentFilter.FilterCriteria += $newCriterion
        
        # Update both storage locations
        $script:ModuleConfig.CurrentItems.Filter = $currentFilter
        $global:CurrentFilter = $currentFilter
        
        Write-Host "Criteria added to filter" -ForegroundColor Green
        Write-Host "  Type: $CriteriaType" -ForegroundColor Cyan
        Write-Host "  Operator: $Operator" -ForegroundColor Cyan
        Write-Host "  Value: $Value" -ForegroundColor Cyan
        Write-Host "Use Save-ProUFilter to save changes" -ForegroundColor Yellow
    }
    catch {
        Write-Error "Failed to add filter criteria: $_"
        throw
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-ProUFilters',
    'Edit-ProUFilter',
    'Save-ProUFilter',
    'New-ProUFilter',
    'Remove-ProUFilter',
    'Copy-ProUFilter',
    'Test-ProUFilter',
    'Export-ProUFilter',
    'Export-ProUFilterAll',
    'Import-ProUFilter',
    'Import-ProUFilterAll',
    'Add-ProUFilterCriteria'
)