# ReportsAndAudit.ps1 - ProfileUnity Reports and Audit Functions

function Get-ProUAuditLog {
    <#
    .SYNOPSIS
        Gets ProfileUnity audit log entries.
    
    .DESCRIPTION
        Retrieves audit log entries with optional filtering.
    
    .PARAMETER Days
        Number of days back to retrieve (default: 7)
    
    .PARAMETER Username
        Filter by username
    
    .PARAMETER Action
        Filter by action type
    
    .PARAMETER MaxResults
        Maximum number of results (default: 100)
    
    .EXAMPLE
        Get-ProUAuditLog -Days 30
        
    .EXAMPLE
        Get-ProUAuditLog -Username "administrator" -Action "Configuration"
    #>
    [CmdletBinding()]
    param(
        [int]$Days = 7,
        
        [string]$Username,
        
        [ValidateSet('Configuration', 'Filter', 'Portability', 'FlexApp', 'User', 'System')]
        [string]$Action,
        
        [int]$MaxResults = 100
    )
    
    try {
        Write-Verbose "Retrieving audit log entries..."
        
        $endpoint = "audit"
        $queryParams = @()
        
        if ($Days) {
            $startDate = (Get-Date).AddDays(-$Days).ToString('yyyy-MM-dd')
            $queryParams += "startDate=$startDate"
        }
        
        if ($Username) {
            $queryParams += "username=$Username"
        }
        
        if ($Action) {
            $queryParams += "action=$Action"
        }
        
        if ($MaxResults) {
            $queryParams += "limit=$MaxResults"
        }
        
        if ($queryParams.Count -gt 0) {
            $endpoint += "?" + ($queryParams -join "&")
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint $endpoint
        
        if ($response -and $response.Tag) {
            $entries = $response.Tag.Rows
            
            $entries | ForEach-Object {
                [PSCustomObject]@{
                    Timestamp = $_.timestamp
                    Username = $_.username
                    Action = $_.action
                    Target = $_.target
                    Details = $_.details
                    IPAddress = $_.ipAddress
                    Success = $_.success
                }
            }
        }
    }
    catch {
        Write-Error "Failed to retrieve audit log: $_"
        throw
    }
}

function Get-ProUReport {
    <#
    .SYNOPSIS
        Generates ProfileUnity reports.
    
    .DESCRIPTION
        Creates various reports from ProfileUnity data.
    
    .PARAMETER ReportType
        Type of report to generate
    
    .PARAMETER Format
        Output format (HTML, CSV, JSON)
    
    .PARAMETER SavePath
        Path to save the report
    
    .PARAMETER Days
        Number of days for time-based reports
    
    .EXAMPLE
        Get-ProUReport -ReportType Summary -Format HTML -SavePath "C:\Reports"
        
    .EXAMPLE
        Get-ProUReport -ReportType Usage -Days 30 -Format CSV
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Summary', 'Usage', 'Configuration', 'FlexApp', 'Audit', 'Performance')]
        [string]$ReportType,
        
        [ValidateSet('HTML', 'CSV', 'JSON', 'XML')]
        [string]$Format = 'HTML',
        
        [string]$SavePath,
        
        [int]$Days = 30
    )
    
    try {
        Write-Host "Generating $ReportType report..." -ForegroundColor Yellow
        
        $reportData = switch ($ReportType) {
            'Summary' {
                Get-ProfileUnitySummaryReport
            }
            'Usage' {
                Get-ProfileUnityUsageReport -Days $Days
            }
            'Configuration' {
                Get-ProfileUnityConfigurationReport
            }
            'FlexApp' {
                Get-ProfileUnityFlexAppReport
            }
            'Audit' {
                Get-ProfileUnityAuditReport -Days $Days
            }
            'Performance' {
                Get-ProfileUnityPerformanceReport -Days $Days
            }
        }
        
        if (-not $reportData) {
            Write-Warning "No data available for $ReportType report"
            return
        }
        
        # Format and save report
        $output = Format-Report -Data $reportData -Type $ReportType -Format $Format
        
        if ($SavePath) {
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $fileName = "ProfileUnity_${ReportType}_Report_$timestamp.$($Format.ToLower())"
            $fullPath = Join-Path $SavePath $fileName
            
            $output | Set-Content -Path $fullPath -Encoding UTF8
            Write-Host "Report saved: $fullPath" -ForegroundColor Green
            return Get-Item $fullPath
        }
        else {
            return $output
        }
    }
    catch {
        Write-Error "Failed to generate report: $_"
        throw
    }
}

function Get-ProfileUnitySummaryReport {
    <#
    .SYNOPSIS
        Gets a summary report of ProfileUnity environment.
    #>
    [CmdletBinding()]
    param()
    
    $summary = @{
        GeneratedAt = Get-Date
        Server = $script:ModuleConfig.ServerName
        Configurations = @()
        Filters = @()
        FlexApps = @()
        Users = @()
        Statistics = @{}
    }
    
    try {
        # Get configurations
        $configs = Get-ProUConfig
        $summary.Configurations = $configs | ForEach-Object {
            @{
                Name = $_.Name
                Enabled = $_.Enabled
                LastModified = $_.LastModified
                DeployCount = $_.DeployCount
            }
        }
        
        # Get filters
        $filters = Get-ProUFilters
        $summary.Filters = $filters | ForEach-Object {
            @{
                Name = $_.Name
                Type = $_.Type
                Enabled = $_.Enabled
                Priority = $_.Priority
            }
        }
        
        # Get FlexApps
        $flexApps = Get-ProUFlexapps
        $summary.FlexApps = $flexApps | ForEach-Object {
            @{
                Name = $_.Name
                Version = $_.Version
                Enabled = $_.Enabled
                SizeMB = $_.SizeMB
            }
        }
        
        # Calculate statistics
        $summary.Statistics = @{
            TotalConfigurations = $configs.Count
            EnabledConfigurations = ($configs | Where-Object { $_.Enabled }).Count
            TotalFilters = $filters.Count
            TotalFlexApps = $flexApps.Count
            FlexAppSizeMB = ($flexApps | Measure-Object -Property SizeMB -Sum).Sum
        }
        
        return $summary
    }
    catch {
        Write-Warning "Error gathering summary data: $_"
        return $summary
    }
}

function Get-ProfileUnityUsageReport {
    <#
    .SYNOPSIS
        Gets a usage report for the specified time period.
    #>
    [CmdletBinding()]
    param(
        [int]$Days = 30
    )
    
    $usage = @{
        Period = "$Days days"
        StartDate = (Get-Date).AddDays(-$Days)
        EndDate = Get-Date
        AuditEntries = @()
        UserActivity = @()
        ConfigurationDeployments = @()
    }
    
    try {
        # Get audit entries
        $auditEntries = Get-ProUAuditLog -Days $Days -MaxResults 1000
        $usage.AuditEntries = $auditEntries
        
        # Analyze user activity
        $userActivity = $auditEntries | Group-Object -Property Username | ForEach-Object {
            @{
                Username = $_.Name
                ActionCount = $_.Count
                LastActivity = ($_.Group | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
                Actions = $_.Group | Group-Object -Property Action | ForEach-Object {
                    @{
                        Action = $_.Name
                        Count = $_.Count
                    }
                }
            }
        }
        $usage.UserActivity = $userActivity
        
        return $usage
    }
    catch {
        Write-Warning "Error gathering usage data: $_"
        return $usage
    }
}

function Get-ProfileUnityConfigurationReport {
    <#
    .SYNOPSIS
        Gets a detailed configuration report.
    #>
    [CmdletBinding()]
    param()
    
    try {
        $configs = Get-ProUConfig -Detailed
        
        return $configs | ForEach-Object {
            $moduleCount = if ($_.modules) { $_.modules.Count } else { 0 }
            $admxCount = if ($_.AdministrativeTemplates) { $_.AdministrativeTemplates.Count } else { 0 }
            $diaCount = if ($_.FlexAppDias) { $_.FlexAppDias.Count } else { 0 }
            
            @{
                Name = $_.name
                Description = $_.description
                Enabled = -not $_.disabled
                ModuleCount = $moduleCount
                ADMXTemplates = $admxCount
                FlexAppDIAs = $diaCount
                LastModified = $_.lastModified
                ModifiedBy = $_.modifiedBy
                DeployCount = $_.deployCount
            }
        }
    }
    catch {
        Write-Warning "Error gathering configuration data: $_"
        return @()
    }
}

function Get-ProfileUnityFlexAppReport {
    <#
    .SYNOPSIS
        Gets a FlexApp usage and status report.
    #>
    [CmdletBinding()]
    param()
    
    try {
        $flexApps = Get-ProUFlexapps
        
        return $flexApps | ForEach-Object {
            @{
                Name = $_.Name
                Version = $_.Version
                Type = $_.Type
                Enabled = $_.Enabled
                SizeMB = $_.SizeMB
                Created = $_.Created
                Modified = $_.Modified
                Path = $_.Path
                CloudPath = $_.CloudPath
            }
        }
    }
    catch {
        Write-Warning "Error gathering FlexApp data: $_"
        return @()
    }
}

function Get-ProfileUnityAuditReport {
    <#
    .SYNOPSIS
        Gets an audit activity report.
    #>
    [CmdletBinding()]
    param(
        [int]$Days = 30
    )
    
    try {
        $auditEntries = Get-ProUAuditLog -Days $Days -MaxResults 5000
        
        # Group by action type
        $actionSummary = $auditEntries | Group-Object -Property Action | ForEach-Object {
            @{
                Action = $_.Name
                Count = $_.Count
                SuccessRate = [math]::Round(($_.Group | Where-Object { $_.Success }).Count / $_.Count * 100, 2)
            }
        }
        
        # Group by user
        $userSummary = $auditEntries | Group-Object -Property Username | ForEach-Object {
            @{
                Username = $_.Name
                Actions = $_.Count
                LastActivity = ($_.Group | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
            }
        }
        
        return @{
            Period = "$Days days"
            TotalEntries = $auditEntries.Count
            ActionSummary = $actionSummary
            UserSummary = $userSummary
            RecentEntries = $auditEntries | Sort-Object Timestamp -Descending | Select-Object -First 50
        }
    }
    catch {
        Write-Warning "Error gathering audit data: $_"
        return @{}
    }
}

function Get-ProfileUnityPerformanceReport {
    <#
    .SYNOPSIS
        Gets a performance and health report.
    #>
    [CmdletBinding()]
    param(
        [int]$Days = 7
    )
    
    $performance = @{
        Period = "$Days days"
        GeneratedAt = Get-Date
        ServerInfo = @{}
        Metrics = @{}
        Recommendations = @()
    }
    
    try {
        # Get server information
        $serverResponse = Invoke-ProfileUnityApi -Endpoint "server/about"
        if ($serverResponse) {
            $performance.ServerInfo = @{
                Version = $serverResponse.version
                BuildDate = $serverResponse.buildDate
                License = $serverResponse.license
            }
        }
        
        # Calculate some basic metrics
        $configs = Get-ProUConfig
        $flexApps = Get-ProUFlexapps
        $filters = Get-ProUFilters
        
        $performance.Metrics = @{
            TotalConfigurations = $configs.Count
            DisabledConfigurations = ($configs | Where-Object { -not $_.Enabled }).Count
            TotalFlexApps = $flexApps.Count
            FlexAppSizeGB = [math]::Round(($flexApps | Measure-Object -Property SizeMB -Sum).Sum / 1024, 2)
            TotalFilters = $filters.Count
        }
        
        # Generate recommendations
        if ($performance.Metrics.DisabledConfigurations -gt 0) {
            $performance.Recommendations += "Consider removing or archiving $($performance.Metrics.DisabledConfigurations) disabled configuration(s)"
        }
        
        if ($performance.Metrics.FlexAppSizeGB -gt 100) {
            $performance.Recommendations += "FlexApp storage usage is high ($($performance.Metrics.FlexAppSizeGB) GB) - consider cleanup"
        }
        
        return $performance
    }
    catch {
        Write-Warning "Error gathering performance data: $_"
        return $performance
    }
}

function Format-Report {
    <#
    .SYNOPSIS
        Formats report data into the specified output format.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Data,
        
        [Parameter(Mandatory)]
        [string]$Type,
        
        [Parameter(Mandatory)]
        [string]$Format
    )
    
    switch ($Format.ToUpper()) {
        'JSON' {
            return $Data | ConvertTo-Json -Depth 10
        }
        'CSV' {
            # For CSV, we need to flatten the data structure
            return ConvertTo-CsvReport -Data $Data -ReportType $Type
        }
        'XML' {
            # Convert to XML (simplified)
            return ConvertTo-XmlReport -Data $Data -ReportType $Type
        }
        'HTML' {
            return ConvertTo-HtmlReport -Data $Data -ReportType $Type
        }
        default {
            throw "Unsupported format: $Format"
        }
    }
}

function ConvertTo-HtmlReport {
    <#
    .SYNOPSIS
        Converts report data to HTML format.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Data,
        
        [Parameter(Mandatory)]
        [string]$ReportType
    )
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>ProfileUnity $ReportType Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #2E75B6; }
        h2 { color: #5A9BD3; margin-top: 30px; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .summary { background-color: #f9f9f9; padding: 15px; border-left: 4px solid #2E75B6; }
        .metric { display: inline-block; margin: 10px; padding: 10px; background-color: #e7f3ff; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>ProfileUnity $ReportType Report</h1>
"@
    
    # Add generation timestamp
    $html += "<div class='summary'><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>"
    
    # Format based on report type
    switch ($ReportType) {
        'Summary' {
            $html += "<h2>Statistics</h2>"
            if ($Data.Statistics) {
                $html += "<div>"
                foreach ($stat in $Data.Statistics.GetEnumerator()) {
                    $html += "<div class='metric'><strong>$($stat.Key):</strong> $($stat.Value)</div>"
                }
                $html += "</div>"
            }
            
            if ($Data.Configurations) {
                $html += "<h2>Configurations</h2>"
                $html += ConvertTo-HtmlTable -Data $Data.Configurations
            }
        }
        'Usage' {
            if ($Data.UserActivity) {
                $html += "<h2>User Activity</h2>"
                $html += ConvertTo-HtmlTable -Data $Data.UserActivity
            }
        }
        'Configuration' {
            $html += "<h2>Configuration Details</h2>"
            $html += ConvertTo-HtmlTable -Data $Data
        }
        default {
            $html += "<pre>$($Data | ConvertTo-Json -Depth 5)</pre>"
        }
    }
    
    $html += "</body></html>"
    return $html
}

function ConvertTo-HtmlTable {
    <#
    .SYNOPSIS
        Converts array data to HTML table.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Data
    )
    
    if (-not $Data -or $Data.Count -eq 0) {
        return "<p>No data available</p>"
    }
    
    $html = "<table>"
    
    # Get headers from first item
    $firstItem = $Data[0]
    $headers = if ($firstItem -is [hashtable]) {
        $firstItem.Keys
    } else {
        $firstItem.PSObject.Properties.Name
    }
    
    # Table headers
    $html += "<tr>"
    foreach ($header in $headers) {
        $html += "<th>$header</th>"
    }
    $html += "</tr>"
    
    # Table rows
    foreach ($item in $Data) {
        $html += "<tr>"
        foreach ($header in $headers) {
            $value = if ($item -is [hashtable]) {
                $item[$header]
            } else {
                $item.$header
            }
            $html += "<td>$value</td>"
        }
        $html += "</tr>"
    }
    
    $html += "</table>"
    return $html
}

function ConvertTo-CsvReport {
    <#
    .SYNOPSIS
        Converts report data to CSV format.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Data,
        
        [Parameter(Mandatory)]
        [string]$ReportType
    )
    
    # Flatten complex data structures for CSV
    switch ($ReportType) {
        'Summary' {
            $flatData = @()
            if ($Data.Configurations) {
                $flatData += $Data.Configurations | ForEach-Object {
                    [PSCustomObject]@{
                        Type = 'Configuration'
                        Name = $_.Name
                        Enabled = $_.Enabled
                        LastModified = $_.LastModified
                    }
                }
            }
            return $flatData | ConvertTo-Csv -NoTypeInformation
        }
        default {
            if ($Data -is [array]) {
                return $Data | ConvertTo-Csv -NoTypeInformation
            } else {
                return $Data | ConvertTo-Json | ConvertFrom-Json | ConvertTo-Csv -NoTypeInformation
            }
        }
    }
}

function ConvertTo-XmlReport {
    <#
    .SYNOPSIS
        Converts report data to XML format.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Data,
        
        [Parameter(Mandatory)]
        [string]$ReportType
    )
    
    # Simple XML conversion
    $xml = "<?xml version='1.0' encoding='UTF-8'?>"
    $xml += "<ProfileUnityReport Type='$ReportType' Generated='$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')'>"
    $xml += "<![CDATA[$($Data | ConvertTo-Json -Depth 10)]]>"
    $xml += "</ProfileUnityReport>"
    
    return $xml
}

function Export-ProUHealthCheck {
    <#
    .SYNOPSIS
        Performs a comprehensive health check and exports results.
    
    .DESCRIPTION
        Runs multiple validation checks and creates a health report.
    
    .PARAMETER SavePath
        Directory to save the health check report
    
    .EXAMPLE
        Export-ProUHealthCheck -SavePath "C:\Reports"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SavePath
    )
    
    try {
        Write-Host "Performing ProfileUnity health check..." -ForegroundColor Yellow
        
        $healthCheck = @{
            Timestamp = Get-Date
            Server = $script:ModuleConfig.ServerName
            Checks = @()
            Issues = @()
            Warnings = @()
            Summary = @{}
        }
        
        # Configuration checks
        Write-Host "  Checking configurations..." -ForegroundColor Gray
        $configs = Get-ProUConfig
        foreach ($config in $configs) {
            $result = Test-ProUConfig -Name $config.Name
            $healthCheck.Checks += @{
                Type = 'Configuration'
                Name = $config.Name
                Issues = $result.Issues
                Warnings = $result.Warnings
                Valid = $result.IsValid
            }
            $healthCheck.Issues += $result.Issues
            $healthCheck.Warnings += $result.Warnings
        }
        
        # Filter checks
        Write-Host "  Checking filters..." -ForegroundColor Gray
        $filters = Get-ProUFilters
        foreach ($filter in $filters) {
            $result = Test-ProUFilter -Name $filter.Name
            $healthCheck.Checks += @{
                Type = 'Filter'
                Name = $filter.Name
                Issues = $result.Issues
                Warnings = $result.Warnings
                Valid = $result.IsValid
            }
            $healthCheck.Issues += $result.Issues
            $healthCheck.Warnings += $result.Warnings
        }
        
        # FlexApp checks
        Write-Host "  Checking FlexApps..." -ForegroundColor Gray
        $flexApps = Get-ProUFlexapps
        foreach ($flexApp in $flexApps) {
            $result = Test-ProUFlexapp -Name $flexApp.Name
            $healthCheck.Checks += @{
                Type = 'FlexApp'
                Name = $flexApp.Name
                Issues = $result.Issues
                Warnings = $result.Warnings
                Valid = $result.IsValid
            }
            $healthCheck.Issues += $result.Issues
            $healthCheck.Warnings += $result.Warnings
        }
        
        # Summary
        $healthCheck.Summary = @{
            TotalChecks = $healthCheck.Checks.Count
            TotalIssues = $healthCheck.Issues.Count
            TotalWarnings = $healthCheck.Warnings.Count
            HealthScore = if ($healthCheck.Checks.Count -gt 0) {
                [math]::Round(($healthCheck.Checks | Where-Object { $_.Valid }).Count / $healthCheck.Checks.Count * 100, 2)
            } else { 100 }
        }
        
        # Save report
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $reportFile = Join-Path $SavePath "ProfileUnity_HealthCheck_$timestamp.json"
        
        $healthCheck | ConvertTo-Json -Depth 10 | Set-Content -Path $reportFile -Encoding UTF8
        
        Write-Host "`nHealth Check Complete:" -ForegroundColor Cyan
        Write-Host "  Health Score: $($healthCheck.Summary.HealthScore)%" -ForegroundColor $(if ($healthCheck.Summary.HealthScore -ge 90) { 'Green' } elseif ($healthCheck.Summary.HealthScore -ge 70) { 'Yellow' } else { 'Red' })
        Write-Host "  Total Issues: $($healthCheck.Summary.TotalIssues)" -ForegroundColor $(if ($healthCheck.Summary.TotalIssues -eq 0) { 'Green' } else { 'Red' })
        Write-Host "  Total Warnings: $($healthCheck.Summary.TotalWarnings)" -ForegroundColor $(if ($healthCheck.Summary.TotalWarnings -eq 0) { 'Green' } else { 'Yellow' })
        Write-Host "  Report saved: $reportFile" -ForegroundColor Green
        
        return Get-Item $reportFile
    }
    catch {
        Write-Error "Failed to perform health check: $_"
        throw
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-ProUAuditLog',
    'Get-ProUReport',
    'Export-ProUHealthCheck'
)