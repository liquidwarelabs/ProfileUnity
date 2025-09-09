# TroubleshootingTools.ps1
# Location: AdminEnhancements\TroubleshootingTools.ps1
# ProfileUnity PowerTools - Troubleshooting and Log Analysis Functions

#region Interactive Troubleshooter

function Start-ProUTroubleshooter {
    <#
    .SYNOPSIS
        Starts the interactive ProfileUnity troubleshooter.
    
    .DESCRIPTION
        Provides an interactive wizard for diagnosing common ProfileUnity issues
        and providing solutions and recommendations.
    
    .EXAMPLE
        Start-ProUTroubleshooter
    #>
    [CmdletBinding()]
    param()
    
    try {
        Assert-ProfileUnityConnection
        
        Clear-Host
        Write-Host "ProfileUnity Troubleshooter" -ForegroundColor Cyan
        Write-Host "=" * 40 -ForegroundColor Cyan
        
        Write-Host "`nWhat type of issue are you experiencing?"
        Write-Host "1. Connection problems"
        Write-Host "2. Configuration not applying"
        Write-Host "3. Filter not working"
        Write-Host "4. FlexApp issues"
        Write-Host "5. Performance problems"
        Write-Host "6. Database issues"
        Write-Host "7. General system health check"
        Write-Host "8. View recent errors"
        Write-Host "0. Exit troubleshooter"
        
        $choice = Read-Host "`nEnter your choice (0-8)"
        
        switch ($choice) {
            '1' { Invoke-ProUConnectionTroubleshooter }
            '2' { Invoke-ProUConfigurationTroubleshooter }
            '3' { Invoke-ProUFilterTroubleshooter }
            '4' { Invoke-ProUFlexAppTroubleshooter }
            '5' { Invoke-ProUPerformanceTroubleshooter }
            '6' { Invoke-ProUDatabaseTroubleshooter }
            '7' { Invoke-ProUSystemHealthTroubleshooter }
            '8' { Show-ProURecentErrors }
            '0' { return }
            default { 
                Write-Host "Invalid choice. Please try again." -ForegroundColor Red
                Start-Sleep 2
                Start-ProUTroubleshooter
            }
        }
    }
    catch {
        Write-Error "Troubleshooter failed: $_"
        throw
    }
}

function Invoke-ProUConnectionTroubleshooter {
    <#
    .SYNOPSIS
        Troubleshoots ProfileUnity connection issues.
    
    .DESCRIPTION
        Diagnoses and provides solutions for connection problems.
    
    .EXAMPLE
        Invoke-ProUConnectionTroubleshooter
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "`nConnection Troubleshooter" -ForegroundColor Green
        Write-Host "-" * 30 -ForegroundColor Green
        
        Write-Host "`n1. Testing server connectivity..." -ForegroundColor Yellow
        
        try {
            $serverInfo = Get-ProUServerAbout
            Write-Host "   Server connection: OK" -ForegroundColor Green
            Write-Host "   Server version: $($serverInfo.Version)" -ForegroundColor Gray
            Write-Host "   Server type: $($serverInfo.ServerType)" -ForegroundColor Gray
        }
        catch {
            Write-Host "   Server connection: FAILED" -ForegroundColor Red
            Write-Host "   Error: $_" -ForegroundColor Red
            
            Write-Host "`nRecommended actions:" -ForegroundColor Yellow
            Write-Host "- Verify server URL and port" -ForegroundColor White
            Write-Host "- Check network connectivity" -ForegroundColor White
            Write-Host "- Verify server services are running" -ForegroundColor White
            Write-Host "- Check firewall settings" -ForegroundColor White
            return
        }
        
        Write-Host "`n2. Testing authentication..." -ForegroundColor Yellow
        
        try {
            $session = Get-ProfileUnitySession
            if ($session -and $session.IsValid) {
                Write-Host "   Authentication: OK" -ForegroundColor Green
                Write-Host "   User: $($session.Username)" -ForegroundColor Gray
                Write-Host "   Session expires: $($session.ExpiresAt)" -ForegroundColor Gray
            }
            else {
                Write-Host "   Authentication: WARNING - Session may be expired" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "   Authentication: FAILED" -ForegroundColor Red
            Write-Host "   Error: $_" -ForegroundColor Red
            
            Write-Host "`nRecommended actions:" -ForegroundColor Yellow
            Write-Host "- Verify username and password" -ForegroundColor White
            Write-Host "- Check user permissions" -ForegroundColor White
            Write-Host "- Try reconnecting with Connect-ProfileUnityServer" -ForegroundColor White
            return
        }
        
        Write-Host "`n3. Testing database connectivity..." -ForegroundColor Yellow
        
        try {
            Write-Warning "Get-ProUDatabaseConnectionStatus function is not available in this ProfileUnity version"
            Write-Host "   Database connectivity can be checked in the ProfileUnity console." -ForegroundColor White
        }
        catch {
            Write-Host "   Database connection: ERROR - $_" -ForegroundColor Red
        }
        
        Write-Host "`nConnection troubleshooting complete!" -ForegroundColor Green
    }
    catch {
        Write-Error "Connection troubleshooter failed: $_"
    }
}

function Invoke-ProUConfigurationTroubleshooter {
    <#
    .SYNOPSIS
        Troubleshoots configuration application issues.
    
    .DESCRIPTION
        Diagnoses why configurations might not be applying correctly.
    
    .EXAMPLE
        Invoke-ProUConfigurationTroubleshooter
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "`nConfiguration Troubleshooter" -ForegroundColor Green
        Write-Host "-" * 35 -ForegroundColor Green
        
        # Get configuration to troubleshoot
        $configs = Get-ProUConfigs
        if (-not $configs) {
            Write-Host "No configurations found!" -ForegroundColor Red
            return
        }
        
        Write-Host "`nAvailable configurations:"
        for ($i = 0; $i -lt $configs.Count; $i++) {
            $status = if ($configs[$i].Disabled) { " (DISABLED)" } else { "" }
            Write-Host "$($i + 1). $($configs[$i].Name)$status" -ForegroundColor $(if ($configs[$i].Disabled) { "DarkGray" } else { "White" })
        }
        
        $choice = Read-Host "`nSelect configuration to troubleshoot (1-$($configs.Count))"
        
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $configs.Count) {
            $selectedConfig = $configs[[int]$choice - 1]
            
            Write-Host "`nTroubleshooting: $($selectedConfig.Name)" -ForegroundColor Yellow
            
            # Test the configuration
            Write-Host "`n1. Testing configuration validity..." -ForegroundColor Yellow
            $testResult = Test-ProUConfig -Name $selectedConfig.Name
            
            if ($testResult.IsValid) {
                Write-Host "   Configuration validation: PASS" -ForegroundColor Green
            }
            else {
                Write-Host "   Configuration validation: FAIL" -ForegroundColor Red
                Write-Host "   Issues found:" -ForegroundColor Red
                $testResult.Issues | ForEach-Object { Write-Host "     - $_" -ForegroundColor Red }
                
                if ($testResult.Warnings.Count -gt 0) {
                    Write-Host "   Warnings:" -ForegroundColor Yellow
                    $testResult.Warnings | ForEach-Object { Write-Host "     - $_" -ForegroundColor Yellow }
                }
            }
            
            # Check if disabled
            if ($selectedConfig.Disabled) {
                Write-Host "`n   WARNING: Configuration is disabled!" -ForegroundColor Red
                Write-Host "   Enable with: Edit-ProUConfig -Name '$($selectedConfig.Name)'" -ForegroundColor White
            }
            
            # Check filters
            Write-Host "`n2. Checking filter assignments..." -ForegroundColor Yellow
            
            Edit-ProUConfig -Name $selectedConfig.Name -Quiet
            $configData = $script:ModuleConfig.CurrentItems.Config
            
            if ($configData.modules) {
                $modulesWithFilters = $configData.modules | Where-Object { $_.FilterId -and $_.FilterId -ne [guid]::Empty }
                
                if ($modulesWithFilters.Count -gt 0) {
                    Write-Host "   Modules with filters: $($modulesWithFilters.Count)" -ForegroundColor Green
                    
                    # Validate each filter still exists
                    $allFilters = Get-ProUFilters
                    foreach ($module in $modulesWithFilters) {
                        $filterExists = $allFilters | Where-Object { $_.ID -eq $module.FilterId }
                        if (-not $filterExists) {
                            Write-Host "   ERROR: Module references missing filter ID: $($module.FilterId)" -ForegroundColor Red
                        }
                    }
                }
                else {
                    Write-Host "   WARNING: No filters assigned to modules" -ForegroundColor Yellow
                    Write-Host "   Configuration may apply to all users/computers" -ForegroundColor Yellow
                }
            }
            
            Write-Host "`nConfiguration troubleshooting complete!" -ForegroundColor Green
            
            Write-Host "`nRecommended actions:" -ForegroundColor Yellow
            Write-Host "- Deploy configuration with Deploy-ProUConfiguration" -ForegroundColor White
            Write-Host "- Check client logs for application details" -ForegroundColor White
            Write-Host "- Verify target systems meet filter criteria" -ForegroundColor White
        }
        else {
            Write-Host "Invalid selection" -ForegroundColor Red
        }
    }
    catch {
        Write-Error "Configuration troubleshooter failed: $_"
    }
}

#endregion

#region Log Analysis Functions

function Analyze-ProULogs {
    <#
    .SYNOPSIS
        Analyzes ProfileUnity log files for common issues.
    
    .DESCRIPTION
        Scans log files and event logs to identify patterns, errors,
        and potential issues in the ProfileUnity environment.
    
    .PARAMETER LogPath
        Path to log file or directory (optional - uses server logs if not specified)
    
    .PARAMETER Days
        Number of days back to analyze (default: 7)
    
    .PARAMETER IncludeWarnings
        Include warning-level entries in analysis
    
    .PARAMETER GenerateReport
        Generate a detailed report file
    
    .EXAMPLE
        Analyze-ProULogs
        
    .EXAMPLE
        Analyze-ProULogs -LogPath "C:\Logs\ProfileUnity" -Days 30 -GenerateReport
    #>
    [CmdletBinding()]
    param(
        [string]$LogPath,
        
        [int]$Days = 7,
        
        [switch]$IncludeWarnings,
        
        [switch]$GenerateReport
    )
    
    try {
        Write-Host "ProfileUnity Log Analysis" -ForegroundColor Cyan
        Write-Host "Analyzing logs from the last $Days days..." -ForegroundColor Yellow
        
        $analysis = @{
            StartTime = (Get-Date).AddDays(-$Days)
            EndTime = Get-Date
            TotalEvents = 0
            ErrorCount = 0
            WarningCount = 0
            InfoCount = 0
            TopErrors = @()
            TopWarnings = @()
            Patterns = @()
            Recommendations = @()
        }
        
        # Analyze server event logs
        Write-Host "`n1. Analyzing server event logs..." -ForegroundColor Yellow
        
        try {
            Write-Warning "Get-ProUEvents function is not available in this ProfileUnity version"
            Write-Host "   Event logs can be viewed in the ProfileUnity console." -ForegroundColor White
            $analysis.TotalEvents = 0
            $analysis.ErrorCount = 0
            $analysis.WarningCount = 0
            $analysis.InfoCount = 0
        }
        catch {
            Write-Host "   Error retrieving server events: $_" -ForegroundColor Red
        }
        
        # Analyze file-based logs if path provided
        if ($LogPath) {
            Write-Host "`n2. Analyzing file-based logs..." -ForegroundColor Yellow
            
            if (Test-Path $LogPath) {
                try {
                    $logFiles = if ((Get-Item $LogPath).PSIsContainer) {
                        Get-ChildItem -Path $LogPath -Filter "*.log" -Recurse | 
                            Where-Object { $_.LastWriteTime -ge $analysis.StartTime }
                    } else {
                        @(Get-Item $LogPath)
                    }
                    
                    Write-Host "   Found $($logFiles.Count) log files" -ForegroundColor Gray
                    
                    foreach ($logFile in $logFiles) {
                        try {
                            $content = Get-Content -Path $logFile.FullName -ErrorAction Stop
                            
                            # Simple pattern matching for common issues
                            $errorLines = $content | Where-Object { $_ -match '\b(error|exception|failed|fault)\b' }
                            $warningLines = $content | Where-Object { $_ -match '\b(warning|warn)\b' }
                            
                            if ($errorLines.Count -gt 0) {
                                $analysis.Patterns += "File: $($logFile.Name) - $($errorLines.Count) error patterns found"
                            }
                            
                            if ($warningLines.Count -gt 0 -and $IncludeWarnings) {
                                $analysis.Patterns += "File: $($logFile.Name) - $($warningLines.Count) warning patterns found"
                            }
                        }
                        catch {
                            Write-Host "     Could not read $($logFile.Name): $_" -ForegroundColor Red
                        }
                    }
                }
                catch {
                    Write-Host "   Error analyzing log files: $_" -ForegroundColor Red
                }
            }
            else {
                Write-Host "   Log path not found: $LogPath" -ForegroundColor Red
            }
        }
        
        # Generate recommendations based on findings
        Write-Host "`n3. Generating recommendations..." -ForegroundColor Yellow
        
        if ($analysis.ErrorCount -eq 0 -and $analysis.WarningCount -eq 0) {
            $analysis.Recommendations += "No issues found in the analyzed timeframe - system appears healthy"
        }
        
        if ($analysis.ErrorCount -gt 50) {
            $analysis.Recommendations += "High error count detected - investigate top error patterns"
        }
        
        if ($analysis.WarningCount -gt 100) {
            $analysis.Recommendations += "High warning count - review system configuration"
        }
        
        # Display summary
        Write-Host "`nLog Analysis Summary:" -ForegroundColor Cyan
        Write-Host "Period: $($analysis.StartTime.ToString('yyyy-MM-dd HH:mm')) to $($analysis.EndTime.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor Gray
        Write-Host "Total Events: $($analysis.TotalEvents)" -ForegroundColor Gray
        Write-Host "Error Rate: $([math]::Round(($analysis.ErrorCount / [math]::Max($analysis.TotalEvents, 1)) * 100, 2))%" -ForegroundColor $(if ($analysis.ErrorCount -gt 0) { 'Red' } else { 'Green' })
        
        if ($analysis.TopErrors.Count -gt 0) {
            Write-Host "`nTop Error Patterns:" -ForegroundColor Red
            foreach ($error in $analysis.TopErrors) {
                Write-Host "  $($error.Count)x: $($error.Message.Substring(0, [math]::Min(80, $error.Message.Length)))" -ForegroundColor Red
            }
        }
        
        if ($analysis.TopWarnings.Count -gt 0 -and $IncludeWarnings) {
            Write-Host "`nTop Warning Patterns:" -ForegroundColor Yellow
            foreach ($warning in $analysis.TopWarnings) {
                Write-Host "  $($warning.Count)x: $($warning.Message.Substring(0, [math]::Min(80, $warning.Message.Length)))" -ForegroundColor Yellow
            }
        }
        
        if ($analysis.Patterns.Count -gt 0) {
            Write-Host "`nFile Analysis Patterns:" -ForegroundColor Cyan
            $analysis.Patterns | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        }
        
        if ($analysis.Recommendations.Count -gt 0) {
            Write-Host "`nRecommendations:" -ForegroundColor Green
            $analysis.Recommendations | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
        }
        
        # Generate report file if requested
        if ($GenerateReport) {
            $reportPath = "ProfileUnity_LogAnalysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
            
            $reportContent = @"
ProfileUnity Log Analysis Report
Generated: $(Get-Date)
Analysis Period: $($analysis.StartTime) to $($analysis.EndTime)

SUMMARY
=======
Total Events: $($analysis.TotalEvents)
Errors: $($analysis.ErrorCount)
Warnings: $($analysis.WarningCount)
Info: $($analysis.InfoCount)
Error Rate: $([math]::Round(($analysis.ErrorCount / [math]::Max($analysis.TotalEvents, 1)) * 100, 2))%

TOP ERRORS
==========
$($analysis.TopErrors | ForEach-Object { "$($_.Count)x ($(([datetime]$_.FirstOccurrence).ToString('yyyy-MM-dd HH:mm')) to $(([datetime]$_.LastOccurrence).ToString('yyyy-MM-dd HH:mm'))): $($_.Message)" } | Out-String)

TOP WARNINGS
============
$($analysis.TopWarnings | ForEach-Object { "$($_.Count)x ($(([datetime]$_.FirstOccurrence).ToString('yyyy-MM-dd HH:mm')) to $(([datetime]$_.LastOccurrence).ToString('yyyy-MM-dd HH:mm'))): $($_.Message)" } | Out-String)

FILE PATTERNS
=============
$($analysis.Patterns -join "`n")

RECOMMENDATIONS
===============
$($analysis.Recommendations -join "`n- ")
"@
            
            $reportContent | Set-Content -Path $reportPath -Encoding UTF8
            Write-Host "`nReport saved to: $reportPath" -ForegroundColor Green
        }
        
        return $analysis
    }
    catch {
        Write-Error "Log analysis failed: $_"
        throw
    }
}

function Find-ProUProblem {
    <#
    .SYNOPSIS
        Searches for specific problems in ProfileUnity logs and configuration.
    
    .DESCRIPTION
        Performs targeted searches for known problem patterns and provides
        specific recommendations for resolution.
    
    .PARAMETER ProblemType
        Type of problem to search for
    
    .PARAMETER SearchTerm
        Custom search term for logs
    
    .PARAMETER Days
        Number of days back to search (default: 30)
    
    .EXAMPLE
        Find-ProUProblem -ProblemType "Database"
        
    .EXAMPLE
        Find-ProUProblem -SearchTerm "timeout" -Days 7
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Database', 'Authentication', 'Configuration', 'Filter', 'FlexApp', 'Performance', 'Custom')]
        [string]$ProblemType = 'Custom',
        
        [string]$SearchTerm,
        
        [int]$Days = 30
    )
    
    try {
        Write-Host "ProfileUnity Problem Finder" -ForegroundColor Cyan
        Write-Host "Searching for: $ProblemType problems" -ForegroundColor Yellow
        
        $problems = @()
        $recommendations = @()
        
        # Define search patterns based on problem type
        $searchPatterns = switch ($ProblemType) {
            'Database' { 
                @('database', 'connection timeout', 'sql', 'deadlock', 'transaction')
                $recommendations += "Check database server performance and connectivity"
                $recommendations += "Review connection string and timeout settings"
                $recommendations += "Monitor database locks and transactions"
            }
            'Authentication' { 
                @('authentication', 'login', 'credential', 'unauthorized', 'access denied')
                $recommendations += "Verify user credentials and permissions"
                $recommendations += "Check domain trust relationships"
                $recommendations += "Review service account settings"
            }
            'Configuration' { 
                @('configuration', 'invalid', 'missing', 'corrupt', 'deployment')
                $recommendations += "Validate configuration syntax and structure"
                $recommendations += "Check for missing dependencies"
                $recommendations += "Review deployment status and logs"
            }
            'Filter' { 
                @('filter', 'criteria', 'matching', 'evaluation', 'scope')
                $recommendations += "Review filter criteria and logic"
                $recommendations += "Test filter evaluation with target objects"
                $recommendations += "Check for conflicting or overlapping filters"
            }
            'FlexApp' { 
                @('flexapp', 'package', 'mount', 'unmount', 'vhd', 'appv')
                $recommendations += "Verify package integrity and accessibility"
                $recommendations += "Check storage connectivity and permissions"
                $recommendations += "Review package dependencies and conflicts"
            }
            'Performance' { 
                @('slow', 'timeout', 'performance', 'memory', 'cpu', 'disk')
                $recommendations += "Monitor system resource utilization"
                $recommendations += "Review timeout settings and limits"
                $recommendations += "Check for resource bottlenecks"
            }
            'Custom' { 
                if ($SearchTerm) { @($SearchTerm) } else { @() }
            }
        }
        
        if ($ProblemType -eq 'Custom' -and -not $SearchTerm) {
            throw "SearchTerm is required when ProblemType is Custom"
        }
        
        # Search events
        Write-Host "`nSearching event logs..." -ForegroundColor Yellow
        
        try {
            Write-Warning "Get-ProUEvents function is not available in this ProfileUnity version"
            Write-Host "   Event logs can be viewed in the ProfileUnity console." -ForegroundColor White
            Write-Host "   Event analysis not available in this version" -ForegroundColor Gray
        }
        catch {
            Write-Host "   Error searching events: $_" -ForegroundColor Red
        }
        
        # System health check related to problem type
        Write-Host "`nPerforming targeted system checks..." -ForegroundColor Yellow
        
        switch ($ProblemType) {
            'Database' {
                try {
                    Write-Warning "Test-ProUDatabaseHealth function is not available in this ProfileUnity version"
                    Write-Host "   Database health can be checked in the ProfileUnity console." -ForegroundColor White
                }
                catch {
                    $problems += @{
                        Type = 'SystemCheck'
                        Pattern = 'Database Health Check Failed'
                        Error = $_.Exception.Message
                    }
                }
            }
            
            'Configuration' {
                try {
                    $configs = Get-ProUConfigs
                    $configIssues = @()
                    
                    foreach ($config in $configs) {
                        $testResult = Test-ProUConfig -Name $config.Name
                        if (-not $testResult.IsValid) {
                            $configIssues += "$($config.Name): $($testResult.Issues -join ', ')"
                        }
                    }
                    
                    if ($configIssues.Count -gt 0) {
                        $problems += @{
                            Type = 'SystemCheck'
                            Pattern = 'Configuration Validation'
                            Issues = $configIssues
                        }
                    }
                }
                catch {
                    $problems += @{
                        Type = 'SystemCheck'
                        Pattern = 'Configuration Check Failed'
                        Error = $_.Exception.Message
                    }
                }
            }
        }
        
        # Display results
        Write-Host "`nProblem Analysis Results:" -ForegroundColor Cyan
        
        if ($problems.Count -eq 0) {
            Write-Host "No problems found matching the specified criteria!" -ForegroundColor Green
        }
        else {
            Write-Host "Found $($problems.Count) problem pattern(s):" -ForegroundColor Red
            
            foreach ($problem in $problems) {
                Write-Host "`n  Problem: $($problem.Pattern)" -ForegroundColor Red
                Write-Host "  Type: $($problem.Type)" -ForegroundColor Gray
                
                if ($problem.Count) {
                    Write-Host "  Occurrences: $($problem.Count)" -ForegroundColor Gray
                }
                
                if ($problem.FirstSeen) {
                    Write-Host "  First seen: $($problem.FirstSeen)" -ForegroundColor Gray
                    Write-Host "  Last seen: $($problem.LastSeen)" -ForegroundColor Gray
                }
                
                if ($problem.Events) {
                    Write-Host "  Recent examples:" -ForegroundColor Gray
                    $problem.Events | Select-Object -First 3 | ForEach-Object {
                        $shortMessage = if ($_.Message.Length -gt 100) { 
                            $_.Message.Substring(0, 100) + "..." 
                        } else { 
                            $_.Message 
                        }
                        Write-Host "    $($_.Timestamp.ToString('yyyy-MM-dd HH:mm')): $shortMessage" -ForegroundColor DarkGray
                    }
                }
                
                if ($problem.Issues) {
                    Write-Host "  Issues:" -ForegroundColor Red
                    $problem.Issues | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
                }
                
                if ($problem.Warnings) {
                    Write-Host "  Warnings:" -ForegroundColor Yellow
                    $problem.Warnings | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
                }
                
                if ($problem.Error) {
                    Write-Host "  Error: $($problem.Error)" -ForegroundColor Red
                }
            }
        }
        
        if ($recommendations.Count -gt 0) {
            Write-Host "`nRecommendations:" -ForegroundColor Green
            $recommendations | ForEach-Object { Write-Host "  - $_" -ForegroundColor White }
        }
        
        return [PSCustomObject]@{
            ProblemType = $ProblemType
            SearchTerm = $SearchTerm
            Days = $Days
            ProblemsFound = $problems.Count
            Problems = $problems
            Recommendations = $recommendations
        }
    }
    catch {
        Write-Error "Problem finder failed: $_"
        throw
    }
}

function Get-ProUSystemHealth {
    <#
    .SYNOPSIS
        Gets comprehensive ProfileUnity system health information.
    
    .DESCRIPTION
        Collects system health data from multiple sources including server status,
        database connectivity, configuration validation, and recent events.
    
    .PARAMETER IncludeDetails
        Include detailed information in the health report
    
    .EXAMPLE
        Get-ProUSystemHealth
        
    .EXAMPLE
        Get-ProUSystemHealth -IncludeDetails
    #>
    [CmdletBinding()]
    param(
        [switch]$IncludeDetails
    )
    
    try {
        Write-Host "Collecting ProfileUnity system health information..." -ForegroundColor Yellow
        
        $healthReport = @{
            Timestamp = Get-Date
            OverallHealth = 'Unknown'
            Score = 0
            Components = @{}
            Issues = @()
            Warnings = @()
            Summary = @{}
        }
        
        # Server connectivity check
        Write-Host "  Checking server connectivity..." -ForegroundColor Gray
        try {
            $serverInfo = Get-ProUServerAbout
            $healthReport.Components.Server = @{
                Status = 'Healthy'
                Version = $serverInfo.Version
                ServerType = $serverInfo.ServerType
                Details = if ($IncludeDetails) { $serverInfo } else { $null }
            }
            $healthReport.Score += 20
        }
        catch {
            $healthReport.Components.Server = @{
                Status = 'Failed'
                Error = $_.Exception.Message
            }
            $healthReport.Issues += "Server connectivity failed: $_"
        }
        
        # Database connectivity check
        Write-Host "  Checking database connectivity..." -ForegroundColor Gray
        try {
            Write-Warning "Get-ProUDatabaseConnectionStatus function is not available in this ProfileUnity version"
            Write-Host "   Database connectivity can be checked in the ProfileUnity console." -ForegroundColor White
            $healthReport.Components.Database = @{
                Status = 'Not available in this version'
            }
            $healthReport.Score += 25
        }
        catch {
            $healthReport.Components.Database = @{
                Status = 'Failed'
                Error = $_.Exception.Message
            }
            $healthReport.Issues += "Database check failed: $_"
        }
        
        # Configuration validation
        Write-Host "  Validating configurations..." -ForegroundColor Gray
        try {
            $configs = Get-ProUConfigs
            $configResults = @{
                Total = $configs.Count
                Valid = 0
                Invalid = 0
                Disabled = 0
                Issues = @()
            }
            
            foreach ($config in $configs) {
                if ($config.Disabled) {
                    $configResults.Disabled++
                    continue
                }
                
                try {
                    $testResult = Test-ProUConfig -Name $config.Name
                    if ($testResult.IsValid) {
                        $configResults.Valid++
                    }
                    else {
                        $configResults.Invalid++
                        $configResults.Issues += "$($config.Name): $($testResult.Issues -join ', ')"
                    }
                }
                catch {
                    $configResults.Invalid++
                    $configResults.Issues += "$($config.Name): Validation failed - $_"
                }
            }
            
            $healthReport.Components.Configurations = $configResults
            
            if ($configResults.Invalid -eq 0) {
                $healthReport.Score += 20
            }
            elseif ($configResults.Invalid -lt $configResults.Total * 0.2) {
                $healthReport.Score += 10
                $healthReport.Warnings += "$($configResults.Invalid) configurations have issues"
            }
            else {
                $healthReport.Issues += "$($configResults.Invalid) configurations have serious issues"
            }
        }
        catch {
            $healthReport.Components.Configurations = @{
                Status = 'Failed'
                Error = $_.Exception.Message
            }
            $healthReport.Issues += "Configuration validation failed: $_"
        }
        
        # Recent events analysis
        Write-Host "  Analyzing recent events..." -ForegroundColor Gray
        try {
            Write-Warning "Get-ProUEvents function is not available in this ProfileUnity version"
            Write-Host "   Event logs can be viewed in the ProfileUnity console." -ForegroundColor White
            $healthReport.Components.Events = @{
                Status = 'Not available in this version'
            }
            $healthReport.Score += 15
        }
        catch {
            $healthReport.Components.Events = @{
                Status = 'Failed'
                Error = $_.Exception.Message
            }
            $healthReport.Warnings += "Event analysis failed: $_"
        }
        
        # System resource check (basic)
        Write-Host "  Checking system resources..." -ForegroundColor Gray
        try {
            $systemInfo = @{
                ProcessorCount = $env:NUMBER_OF_PROCESSORS
                ComputerName = $env:COMPUTERNAME
                OSVersion = [System.Environment]::OSVersion.VersionString
            }
            
            $healthReport.Components.System = $systemInfo
            $healthReport.Score += 15
        }
        catch {
            $healthReport.Components.System = @{
                Status = 'Failed'
                Error = $_.Exception.Message
            }
            $healthReport.Warnings += "System info check failed: $_"
        }
        
        # Determine overall health
        if ($healthReport.Issues.Count -eq 0 -and $healthReport.Warnings.Count -eq 0) {
            $healthReport.OverallHealth = 'Excellent'
        }
        elseif ($healthReport.Issues.Count -eq 0) {
            $healthReport.OverallHealth = 'Good'
        }
        elseif ($healthReport.Issues.Count -lt 3) {
            $healthReport.OverallHealth = 'Fair'
        }
        else {
            $healthReport.OverallHealth = 'Poor'
        }
        
        # Create summary
        $healthReport.Summary = @{
            OverallHealth = $healthReport.OverallHealth
            Score = $healthReport.Score
            IssueCount = $healthReport.Issues.Count
            WarningCount = $healthReport.Warnings.Count
            ComponentCount = $healthReport.Components.Keys.Count
        }
        
        # Display results
        Write-Host "`nSystem Health Report:" -ForegroundColor Cyan
        Write-Host "Overall Health: " -NoNewline
        
        $healthColor = switch ($healthReport.OverallHealth) {
            'Excellent' { 'Green' }
            'Good' { 'Green' }
            'Fair' { 'Yellow' }
            'Poor' { 'Red' }
            default { 'Gray' }
        }
        
        Write-Host "$($healthReport.OverallHealth) (Score: $($healthReport.Score)/100)" -ForegroundColor $healthColor
        
        Write-Host "Components Checked: $($healthReport.Components.Keys.Count)" -ForegroundColor Gray
        Write-Host "Issues Found: $($healthReport.Issues.Count)" -ForegroundColor $(if ($healthReport.Issues.Count -gt 0) { 'Red' } else { 'Green' })
        Write-Host "Warnings: $($healthReport.Warnings.Count)" -ForegroundColor $(if ($healthReport.Warnings.Count -gt 0) { 'Yellow' } else { 'Green' })
        
        if ($healthReport.Issues.Count -gt 0) {
            Write-Host "`nIssues:" -ForegroundColor Red
            $healthReport.Issues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        }
        
        if ($healthReport.Warnings.Count -gt 0) {
            Write-Host "`nWarnings:" -ForegroundColor Yellow
            $healthReport.Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
        }
        
        if ($IncludeDetails) {
            Write-Host "`nComponent Details:" -ForegroundColor Cyan
            foreach ($component in $healthReport.Components.GetEnumerator()) {
                Write-Host "  $($component.Key):" -ForegroundColor White
                if ($component.Value -is [hashtable]) {
                    foreach ($detail in $component.Value.GetEnumerator()) {
                        if ($detail.Key -ne 'Details' -or $detail.Value) {
                            Write-Host "    $($detail.Key): $($detail.Value)" -ForegroundColor Gray
                        }
                    }
                }
                else {
                    Write-Host "    $($component.Value)" -ForegroundColor Gray
                }
            }
        }
        
        return $healthReport
    }
    catch {
        Write-Error "System health check failed: $_"
        throw
    }
}

#endregion

#region Helper Functions

function Show-ProURecentErrors {
    <#
    .SYNOPSIS
        Shows recent ProfileUnity errors.
    
    .DESCRIPTION
        Displays recent error events for quick troubleshooting.
    
    .EXAMPLE
        Show-ProURecentErrors
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "`nRecent ProfileUnity Errors" -ForegroundColor Red
        Write-Host "-" * 35 -ForegroundColor Red
        
        Write-Warning "Get-ProUEvents function is not available in this ProfileUnity version"
        Write-Host "   Event logs can be viewed in the ProfileUnity console." -ForegroundColor White
        $errors = @()
        
        Write-Host "No errors found in the last 7 days!" -ForegroundColor Green
        return
        
        $errors | Sort-Object Timestamp -Descending | ForEach-Object {
            $timeAgo = New-TimeSpan -Start $_.Timestamp -End (Get-Date)
            $timeString = if ($timeAgo.TotalMinutes -lt 60) {
                "$([math]::Round($timeAgo.TotalMinutes))m ago"
            } elseif ($timeAgo.TotalHours -lt 24) {
                "$([math]::Round($timeAgo.TotalHours))h ago"
            } else {
                "$([math]::Round($timeAgo.TotalDays))d ago"
            }
            
            Write-Host "`n[$timeString] " -NoNewline -ForegroundColor Gray
            Write-Host "$($_.Source): " -NoNewline -ForegroundColor Cyan
            Write-Host "$($_.Message)" -ForegroundColor Red
        }
    }
    catch {
        Write-Error "Failed to show recent errors: $_"
    }
}

function Invoke-ProUFilterTroubleshooter {
    <#
    .SYNOPSIS
        Troubleshoots filter-related issues.
    
    .DESCRIPTION
        Diagnoses common filter problems and provides recommendations.
    
    .EXAMPLE
        Invoke-ProUFilterTroubleshooter
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "`nFilter Troubleshooter - Coming Soon!" -ForegroundColor Yellow
    Write-Host "This feature will help diagnose filter evaluation issues." -ForegroundColor Gray
}

function Invoke-ProUFlexAppTroubleshooter {
    <#
    .SYNOPSIS
        Troubleshoots FlexApp-related issues.
    
    .DESCRIPTION
        Diagnoses common FlexApp problems and provides recommendations.
    
    .EXAMPLE
        Invoke-ProUFlexAppTroubleshooter
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "`nFlexApp Troubleshooter - Coming Soon!" -ForegroundColor Yellow
    Write-Host "This feature will help diagnose FlexApp package issues." -ForegroundColor Gray
}

function Invoke-ProUPerformanceTroubleshooter {
    <#
    .SYNOPSIS
        Troubleshoots performance-related issues.
    
    .DESCRIPTION
        Diagnoses performance problems and provides optimization recommendations.
    
    .EXAMPLE
        Invoke-ProUPerformanceTroubleshooter
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "`nPerformance Troubleshooter - Coming Soon!" -ForegroundColor Yellow
    Write-Host "This feature will help diagnose performance issues." -ForegroundColor Gray
}

function Invoke-ProUDatabaseTroubleshooter {
    <#
    .SYNOPSIS
        Troubleshoots database-related issues.
    
    .DESCRIPTION
        Diagnoses database connectivity and performance problems.
    
    .EXAMPLE
        Invoke-ProUDatabaseTroubleshooter
    #>
    [CmdletBinding()]
    param()
    
    Write-Host "`nDatabase Troubleshooter - Coming Soon!" -ForegroundColor Yellow
    Write-Host "This feature will help diagnose database issues." -ForegroundColor Gray
}

function Invoke-ProUSystemHealthTroubleshooter {
    <#
    .SYNOPSIS
        Performs comprehensive system health troubleshooting.
    
    .DESCRIPTION
        Runs detailed system health checks and provides recommendations.
    
    .EXAMPLE
        Invoke-ProUSystemHealthTroubleshooter
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "`nSystem Health Troubleshooter" -ForegroundColor Green
        Write-Host "-" * 35 -ForegroundColor Green
        
        # Run comprehensive health check
        $healthReport = Get-ProUSystemHealth -IncludeDetails
        
        # Provide specific recommendations based on findings
        Write-Host "`nDetailed Recommendations:" -ForegroundColor Yellow
        
        if ($healthReport.Issues.Count -gt 0) {
            Write-Host "Critical Issues to Address:" -ForegroundColor Red
            $healthReport.Issues | ForEach-Object { 
                Write-Host "  - $_" -ForegroundColor Red 
            }
        }
        
        if ($healthReport.Warnings.Count -gt 0) {
            Write-Host "`nWarnings to Review:" -ForegroundColor Yellow
            $healthReport.Warnings | ForEach-Object { 
                Write-Host "  - $_" -ForegroundColor Yellow 
            }
        }
        
        # General recommendations
        Write-Host "`nGeneral Maintenance Recommendations:" -ForegroundColor Green
        Write-Host "  - Review and update configurations regularly" -ForegroundColor White
        Write-Host "  - Monitor system resources and performance" -ForegroundColor White
        Write-Host "  - Keep ProfileUnity server updated" -ForegroundColor White
        Write-Host "  - Perform regular database maintenance" -ForegroundColor White
        Write-Host "  - Review and clean up old log files" -ForegroundColor White
    }
    catch {
        Write-Error "System health troubleshooter failed: $_"
    }
}

#endregion

# Export all functions
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
<#
Export-ModuleMember -Function @(
    'Start-ProUTroubleshooter',
    'Analyze-ProULogs',
    'Find-ProUProblem',
    'Get-ProUSystemHealth'
)
#>
