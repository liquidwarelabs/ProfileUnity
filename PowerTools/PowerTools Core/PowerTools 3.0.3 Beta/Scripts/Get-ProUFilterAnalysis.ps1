# Get-ProUFilterAnalysis.ps1 - ProfileUnity Filter Usage Analysis
# Location: \Scripts\Get-ProUFilterAnalysis.ps1
# Compatible with: ProfileUnity PowerTools v3.0 / PowerShell 5.1+

<#
.SYNOPSIS
    Analyzes ProfileUnity filters and their usage across configurations and AD groups.

.DESCRIPTION
    This script retrieves all ProfileUnity filters and analyzes:
    - How many configurations each filter is used in
    - What Active Directory groups are associated with each filter
    - Filter details including type, priority, and status
    - Usage statistics and recommendations

.PARAMETER FilterName
    Optional filter name to analyze specific filters (supports wildcards)

.PARAMETER OutputFormat
    Output format: Table, List, or Detailed (default: Table)

.PARAMETER ExportPath
    Optional path to export results to CSV file

.PARAMETER IncludeUnused
    Include filters that are not used in any configurations

.EXAMPLE
    Get-ProUFilterAnalysis
    
.EXAMPLE
    Get-ProUFilterAnalysis -FilterName "*Test*" -OutputFormat Detailed
    
.EXAMPLE
    Get-ProUFilterAnalysis -ExportPath "C:\Reports\FilterAnalysis.csv" -IncludeUnused
#>

[CmdletBinding()]
param(
    [string]$FilterName,
    [ValidateSet('Table', 'List', 'Detailed')]
    [string]$OutputFormat = 'Table',
    [string]$ExportPath,
    [switch]$IncludeUnused
)

# Check if ProfileUnity PowerTools module is loaded
if (-not (Get-Module -Name "ProfileUnity-PowerTools" -ErrorAction SilentlyContinue)) {
    try {
        Import-Module "$PSScriptRoot\..\ProfileUnity-PowerTools.psm1" -Force -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to import ProfileUnity PowerTools module: $_"
        return
    }
}

function Get-FilterUsageAnalysis {
    <#
    .SYNOPSIS
        Analyzes filter usage across configurations and AD groups.
    #>
    [CmdletBinding()]
    param(
        [string]$NameFilter
    )
    
    try {
        Write-Verbose "Starting filter usage analysis..."
        
        # Get all filters with usage information
        Write-Verbose "Retrieving filters with usage information..."
        $filters = Get-ProUFilters -Name $NameFilter -IncludeUsage
        if (-not $filters) {
            Write-Warning "No filters found in ProfileUnity"
            return @()
        }
        
        Write-Verbose "Found $($filters.Count) filters to analyze"
        
        # Get AD groups information
        Write-Verbose "Retrieving AD groups..."
        $adGroups = @()
        try {
            $adGroups = Get-ProUADGroups -MaxResults 5000
            Write-Verbose "Found $($adGroups.Count) AD groups"
        }
        catch {
            Write-Warning "Could not retrieve AD groups: $_"
        }
        
        # Analyze each filter
        $analysisResults = @()
        
        foreach ($filter in $filters) {
            Write-Verbose "Analyzing filter: $($filter.Name)"
            
            # Get detailed filter information by editing the filter
            $filterDetails = $null
            try {
                Write-Verbose "Loading detailed information for filter: $($filter.Name)"
                Edit-ProUFilter -Name $filter.Name -Quiet
                
                # Get the loaded filter details from the global variable
                if ($global:CurrentFilter) {
                    $filterDetails = $global:CurrentFilter
                }
                elseif ($script:ModuleConfig.CurrentItems.Filter) {
                    $filterDetails = $script:ModuleConfig.CurrentItems.Filter
                }
            }
            catch {
                Write-Warning "Could not retrieve details for filter '$($filter.Name)': $_"
            }
            
            # Get configurations using this filter from the filter object
            $usedInConfigs = if ($filter.UsedInConfigs) { $filter.UsedInConfigs } else { @() }
            $configCount = if ($filter.ConfigCount) { $filter.ConfigCount } else { 0 }
            
            # If no configuration data, try to get it from the filter usage data
            if ($configCount -eq 0 -and $filter.UsedIn -and $filter.UsedIn -gt 0) {
                $configCount = $filter.UsedIn
                Write-Verbose "Using UsedIn value for configuration count: $configCount"
            }
            
            if ($configCount -gt 0) {
                Write-Verbose "Filter '$($filter.Name)' is used in $configCount configuration(s)"
            }
            else {
                Write-Verbose "Filter '$($filter.Name)' is not used in any configurations"
            }
            
            # Find AD groups associated with this filter by examining the JSON content
            $associatedGroups = @()
            $groupCount = 0
            
            if ($filterDetails) {
                Write-Verbose "Examining filter details for AD groups: $($filter.Name)"
                
                # Convert filter details to JSON to examine the structure
                $filterJson = $filterDetails | ConvertTo-Json -Depth 10
                Write-Verbose "Filter JSON structure: $($filterJson.Substring(0, [Math]::Min(500, $filterJson.Length)))..."
                
                # Look for AD group references in various parts of the filter
                if ($filterDetails.filterRules -and $filterDetails.filterRules.Count -gt 0) {
                    foreach ($rule in $filterDetails.filterRules) {
                        # Look for AD group references in filter rules
                        # AD group filters have ConditionType = 0 and MatchType = 0
                        $groupName = $null
                        
                        # Pattern 1: Direct AD group type
                        if ($rule.type -eq "ADGroup" -or $rule.filterType -eq "ADGroup" -or $rule.ruleType -eq "ADGroup") {
                            $groupName = if ($rule.name) { $rule.name } 
                                        elseif ($rule.groupName) { $rule.groupName } 
                                        elseif ($rule.value) { $rule.value }
                                        elseif ($rule.group) { $rule.group }
                        }
                        
                        # Pattern 2: AD group filters with ConditionType = 0 and MatchType = 0
                        elseif ($rule.ConditionType -eq 0 -and $rule.MatchType -eq 0 -and $rule.value) {
                            $groupName = $rule.value
                            Write-Verbose "Found AD group filter (ConditionType=0, MatchType=0): $groupName"
                        }
                        
                        # Pattern 3: Value that looks like AD group (DOMAIN\GroupName format)
                        elseif ($rule.value -and $rule.value -match '^[A-Za-z0-9_-]+\\[A-Za-z0-9_-]+$') {
                            $groupName = $rule.value
                            Write-Verbose "Found potential AD group in value: $groupName"
                        }
                        
                        # Pattern 4: Value that looks like AD group (GroupName format)
                        elseif ($rule.value -and $rule.value -match '^[A-Za-z0-9_-]+$' -and $rule.value.Length -gt 3) {
                            $groupName = $rule.value
                            Write-Verbose "Found potential AD group name: $groupName"
                        }
                        
                        if ($groupName) {
                            Write-Verbose "Processing AD group reference: $groupName"
                            
                            # Extract just the group name if it's in DOMAIN\GroupName format
                            $cleanGroupName = if ($groupName -match '^[A-Za-z0-9_-]+\\(.+)$') { 
                                $matches[1] 
                            } else { 
                                $groupName 
                            }
                            
                            # Find matching AD group
                            $matchingGroup = $adGroups | Where-Object { 
                                $_.Name -eq $cleanGroupName -or 
                                $_.SamAccountName -eq $cleanGroupName -or
                                $_.DistinguishedName -like "*$cleanGroupName*" -or
                                $_.Name -eq $groupName -or
                                $_.SamAccountName -eq $groupName -or
                                # Also check if the group name appears anywhere in the distinguished name
                                $_.DistinguishedName -like "*$groupName*" -or
                                $_.DistinguishedName -like "*$cleanGroupName*"
                            } | Select-Object -First 1
                            
                            if ($matchingGroup) {
                                $associatedGroups += [PSCustomObject]@{
                                    GroupName = $matchingGroup.Name
                                    SamAccountName = $matchingGroup.SamAccountName
                                    DistinguishedName = $matchingGroup.DistinguishedName
                                    GroupType = $matchingGroup.GroupType
                                    MemberCount = $matchingGroup.MemberCount
                                    OriginalReference = $groupName
                                }
                                $groupCount++
                            }
                            else {
                                # Add group even if not found in AD (might be deleted or renamed)
                                $associatedGroups += [PSCustomObject]@{
                                    GroupName = $cleanGroupName
                                    SamAccountName = "Not Found"
                                    DistinguishedName = "Not Found"
                                    GroupType = "Unknown"
                                    MemberCount = 0
                                    OriginalReference = $groupName
                                }
                                $groupCount++
                            }
                        }
                    }
                }
                
                # Also check for AD groups in other parts of the filter structure
                if ($filterDetails.rules -and $filterDetails.rules.Count -gt 0) {
                    foreach ($rule in $filterDetails.rules) {
                        if ($rule.type -eq "ADGroup" -or $rule.ruleType -eq "ADGroup") {
                            $groupName = if ($rule.name) { $rule.name } 
                                        elseif ($rule.groupName) { $rule.groupName } 
                                        elseif ($rule.value) { $rule.value }
                            
                            if ($groupName) {
                                Write-Verbose "Found AD group reference in rules: $groupName"
                                # Process similar to above...
                            }
                        }
                    }
                }
            }
            
            # Create analysis result
            $analysisResult = [PSCustomObject]@{
                FilterName = $filter.Name
                FilterId = $filter.Id
                FilterType = if ($filterDetails) { $filterDetails.filterType } else { "Unknown" }
                Description = if ($filterDetails) { $filterDetails.description } else { $filter.description }
                Priority = if ($filterDetails) { $filterDetails.priority } else { $filter.priority }
                Enabled = -not $filter.disabled
                ConfigCount = $configCount
                UsedInConfigs = $usedInConfigs
                GroupCount = $groupCount
                AssociatedGroups = $associatedGroups
                LastModified = if ($filterDetails) { $filterDetails.lastModified } else { $filter.lastModified }
                ModifiedBy = if ($filterDetails) { $filterDetails.modifiedBy } else { $filter.modifiedBy }
                IsUnused = ($configCount -eq 0)
            }
            
            $analysisResults += $analysisResult
        }
        
        return $analysisResults
    }
    catch {
        Write-Error "Failed to analyze filter usage: $_"
        throw
    }
}

function Format-AnalysisResults {
    <#
    .SYNOPSIS
        Formats the analysis results based on the specified output format.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Results,
        
        [ValidateSet('Table', 'List', 'Detailed')]
        [string]$Format,
        
        [switch]$IncludeUnused,
        
        [string]$ExportPath
    )
    
    # Filter out unused filters if not requested
    if (-not $IncludeUnused) {
        $Results = $Results | Where-Object { -not $_.IsUnused }
    }
    
    # Filter to only show filters with AD groups (GroupCount > 0)
    $Results = $Results | Where-Object { $_.GroupCount -gt 0 }
    
    # Export to CSV if requested (after filtering)
    if ($ExportPath) {
        try {
            $exportData = @()
            foreach ($result in $Results) {
                if ($result.AssociatedGroups -and $result.AssociatedGroups.Count -gt 0) {
                    foreach ($group in $result.AssociatedGroups) {
                        $exportData += [PSCustomObject]@{
                            FilterName = $result.FilterName
                            FilterType = $result.FilterType
                            Enabled = $result.Enabled
                            ConfigCount = $result.ConfigCount
                            UsedIn = $result.ConfigCount
                            Priority = $result.Priority
                            LastModified = $result.LastModified
                            ModifiedBy = $result.ModifiedBy
                            IsUnused = $result.IsUnused
                            ADGroupName = $group.GroupName
                            ADGroupSamAccountName = $group.SamAccountName
                            ADGroupDistinguishedName = $group.DistinguishedName
                            ADGroupType = $group.GroupType
                            ADGroupMemberCount = $group.MemberCount
                            OriginalReference = $group.OriginalReference
                        }
                    }
                }
            }
            $exportData | Export-Csv -Path $ExportPath -NoTypeInformation
            Write-Host "`nResults exported to: $ExportPath" -ForegroundColor Green
            Write-Host "Exported $($exportData.Count) rows with AD group details" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to export results to CSV: $_"
        }
    }
    
    switch ($Format) {
        'Table' {
            return $Results | Select-Object FilterName, FilterType, Enabled, ConfigCount, GroupCount, Priority, LastModified | 
                   Sort-Object ConfigCount -Descending
        }
        
        'List' {
            $output = @()
            foreach ($result in $Results) {
                $output += "Filter: $($result.FilterName)"
                $output += "  Type: $($result.FilterType)"
                $output += "  Enabled: $($result.Enabled)"
                $output += "  Used in $($result.ConfigCount) configuration(s)"
                $output += "  Associated with $($result.GroupCount) AD group(s)"
                $output += "  Priority: $($result.Priority)"
                
                if ($result.UsedInConfigs.Count -gt 0) {
                    $output += "  Configurations:"
                    foreach ($config in $result.UsedInConfigs) {
                        $status = if ($config.ConfigEnabled) { "Enabled" } else { "Disabled" }
                        $output += "    - $($config.ConfigName) ($status)"
                    }
                }
                
                if ($result.AssociatedGroups.Count -gt 0) {
                    $output += "  AD Groups:"
                    foreach ($group in $result.AssociatedGroups) {
                        $groupInfo = if ($group.SamAccountName -eq "Not Found") {
                            "$($group.GroupName) (Not Found in AD)"
                        } else {
                            "$($group.GroupName) ($($group.GroupType))"
                        }
                        $output += "    - $groupInfo"
                    }
                }
                
                $output += ""
            }
            return $output
        }
        
        'Detailed' {
            return $Results | Sort-Object ConfigCount -Descending
        }
    }
}

# Main execution function
function Invoke-ProUFilterAnalysis {
    [CmdletBinding()]
    param(
        [string]$FilterName,
        [ValidateSet('Table', 'List', 'Detailed')]
        [string]$OutputFormat = 'Table',
        [string]$ExportPath,
        [switch]$IncludeUnused
    )
    
    try {
        Write-Host "ProfileUnity Filter Analysis" -ForegroundColor Cyan
        Write-Host "============================" -ForegroundColor Cyan
        
        # Ensure connection to ProfileUnity
        if (-not (Get-ProfileUnityConnectionStatus)) {
            Write-Warning "Not connected to ProfileUnity server. Please run Connect-ProfileUnityServer first."
            return
        }
    
    # Perform analysis
    $analysisResults = Get-FilterUsageAnalysis -NameFilter $FilterName
    
    if (-not $analysisResults) {
        Write-Warning "No analysis results to display"
        return
    }
    
    # Format and display results
    $formattedResults = Format-AnalysisResults -Results $analysisResults -Format $OutputFormat -IncludeUnused:$IncludeUnused -ExportPath $ExportPath
    
    if ($OutputFormat -eq 'List') {
        $formattedResults | ForEach-Object { Write-Host $_ }
    }
    else {
        $formattedResults | Format-Table -AutoSize
    }
    
    # Display summary statistics
    Write-Host "`nSummary Statistics:" -ForegroundColor Yellow
    Write-Host "Total Filters Analyzed: $($analysisResults.Count)"
    Write-Host "Filters in Use: $(($analysisResults | Where-Object { -not $_.IsUnused }).Count)"
    Write-Host "Unused Filters: $(($analysisResults | Where-Object { $_.IsUnused }).Count)"
    # Calculate total configurations (sum of individual filter usage counts)
    $totalConfigurations = ($analysisResults | Measure-Object -Property ConfigCount -Sum).Sum
    Write-Host "Total Configurations: $totalConfigurations"
    Write-Host "Total AD Groups: $(($analysisResults | Measure-Object -Property GroupCount -Sum).Sum)"
    
    
    # Recommendations
    Write-Host "`nRecommendations:" -ForegroundColor Yellow
    $unusedFilters = $analysisResults | Where-Object { $_.IsUnused }
    if ($unusedFilters) {
        Write-Host "- Consider removing or reviewing $($unusedFilters.Count) unused filter(s)"
        $unusedFilters | ForEach-Object { Write-Host "  * $($_.FilterName)" }
    }
    
    $highPriorityUnused = $analysisResults | Where-Object { $_.IsUnused -and $_.Priority -lt 50 }
    if ($highPriorityUnused) {
        Write-Host "- Review high-priority unused filters:"
        $highPriorityUnused | ForEach-Object { Write-Host "  * $($_.FilterName) (Priority: $($_.Priority))" }
    }
    
    $disabledFilters = $analysisResults | Where-Object { -not $_.Enabled }
    if ($disabledFilters) {
        Write-Host "- Review $($disabledFilters.Count) disabled filter(s) for potential cleanup"
    }
    }
    catch {
        Write-Error "Filter analysis failed: $_"
        throw
    }
}

# Create an alias for the main function
Set-Alias -Name "Get-ProUFilterAnalysis" -Value "Invoke-ProUFilterAnalysis"

# If script is run directly (not dot-sourced), execute the analysis
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-ProUFilterAnalysis -FilterName $FilterName -OutputFormat $OutputFormat -ExportPath $ExportPath -IncludeUnused:$IncludeUnused
}
