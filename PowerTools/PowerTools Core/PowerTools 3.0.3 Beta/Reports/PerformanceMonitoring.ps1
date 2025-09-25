# Reports/PerformanceMonitoring.ps1 - Performance Monitoring and Analytics

# =============================================================================
# PERFORMANCE MONITORING SYSTEM
# =============================================================================

function Get-ProUPerformanceMetrics {
    <#
    .SYNOPSIS
        Retrieves comprehensive performance metrics for ProfileUnity environment.
    
    .DESCRIPTION
        Collects server performance, configuration deployment metrics, and user experience analytics.
    
    .PARAMETER MetricType
        Specific type of metrics to collect
    
    .PARAMETER TimeRange
        Time range for historical metrics
    
    .PARAMETER IncludeHistory
        Include historical trend data
    
    .PARAMETER OutputFormat
        Format for metric output
    
    .EXAMPLE
        Get-ProUPerformanceMetrics -MetricType "Server" -TimeRange "24h"
        
    .EXAMPLE
        Get-ProUPerformanceMetrics -IncludeHistory -OutputFormat "Dashboard"
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('All', 'Server', 'Deployment', 'UserExperience', 'Storage', 'Network')]
        [string]$MetricType = 'All',
        
        [ValidateSet('1h', '6h', '24h', '7d', '30d')]
        [string]$TimeRange = '24h',
        
        [switch]$IncludeHistory,
        
        [ValidateSet('Console', 'JSON', 'Dashboard', 'CSV')]
        [string]$OutputFormat = 'Console'
    )
    
    Write-Host "📊 Collecting ProfileUnity performance metrics..." -ForegroundColor Cyan
    
    $metrics = @{
        Timestamp = Get-Date
        TimeRange = $TimeRange
        ServerMetrics = @{}
        DeploymentMetrics = @{}
        UserExperienceMetrics = @{}
        StorageMetrics = @{}
        NetworkMetrics = @{}
    }
    
    try {
        # Collect Server Performance Metrics
        if ($MetricType -in @('All', 'Server')) {
            Write-Host "  Collecting server metrics..." -ForegroundColor Yellow
            $metrics.ServerMetrics = Get-ProUServerPerformanceMetrics -TimeRange $TimeRange
        }
        
        # Collect Deployment Metrics
        if ($MetricType -in @('All', 'Deployment')) {
            Write-Host "  Collecting deployment metrics..." -ForegroundColor Yellow
            $metrics.DeploymentMetrics = Get-ProUDeploymentMetrics -TimeRange $TimeRange
        }
        
        # Collect User Experience Metrics
        if ($MetricType -in @('All', 'UserExperience')) {
            Write-Host "  Collecting user experience metrics..." -ForegroundColor Yellow
            $metrics.UserExperienceMetrics = Get-ProUUserExperienceMetrics -TimeRange $TimeRange
        }
        
        # Collect Storage Metrics
        if ($MetricType -in @('All', 'Storage')) {
            Write-Host "  Collecting storage metrics..." -ForegroundColor Yellow
            $metrics.StorageMetrics = Get-ProUStorageMetrics
        }
        
        # Collect Network Metrics
        if ($MetricType -in @('All', 'Network')) {
            Write-Host "  Collecting network metrics..." -ForegroundColor Yellow
            $metrics.NetworkMetrics = Get-ProUNetworkMetrics -TimeRange $TimeRange
        }
        
        # Add historical trends if requested
        if ($IncludeHistory) {
            Write-Host "  Adding historical trends..." -ForegroundColor Yellow
            $metrics.HistoricalTrends = Get-ProUPerformanceHistory -TimeRange $TimeRange
        }
        
        # Output based on format
        switch ($OutputFormat) {
            'Console' { Show-ProUPerformanceMetricsConsole -Metrics $metrics }
            'Dashboard' { Show-ProUPerformanceDashboard -Metrics $metrics }
            'JSON' { return $metrics | ConvertTo-Json -Depth 10 }
            'CSV' { Export-ProUPerformanceMetricsCSV -Metrics $metrics }
        }
        
        return $metrics
    }
    catch {
        Write-Host "❌ Error collecting performance metrics: $_" -ForegroundColor Red
        throw
    }
}

function Get-ProUServerPerformanceMetrics {
    <#
    .SYNOPSIS
        Collects server-specific performance metrics.
    
    .PARAMETER TimeRange
        Time range for metrics collection
    #>
    [CmdletBinding()]
    param(
        [string]$TimeRange = '24h'
    )
    
    $serverMetrics = @{}
    
    try {
        # Get server information
        $serverInfo = Get-ProUServerAbout
        $serverSettings = Get-ProUServerSettings
        
        # CPU and Memory metrics (estimated from server response times)
        $responseTimeTests = @()
        for ($i = 0; $i -lt 5; $i++) {
            $startTime = Get-Date
            Test-ProfileUnityConnection | Out-Null
            $endTime = Get-Date
            $responseTimeTests += ($endTime - $startTime).TotalMilliseconds
        }
        
        $avgResponseTime = ($responseTimeTests | Measure-Object -Average).Average
        
        $serverMetrics = @{
            ServerVersion = $serverInfo.Version
            Uptime = $serverInfo.Uptime
            AvgResponseTime = [math]::Round($avgResponseTime, 2)
            ConnectionStatus = if ((Test-ProfileUnityConnection)) { "Healthy" } else { "Unhealthy" }
            
            # Estimated health based on response time
            PerformanceStatus = switch ($avgResponseTime) {
                { $_ -lt 100 } { "Excellent" }
                { $_ -lt 300 } { "Good" }
                { $_ -lt 1000 } { "Fair" }
                default { "Poor" }
            }
            
            # Configuration processing metrics
            ActiveConnections = $serverSettings | Where-Object { $_.Name -like "*connection*" } | Measure-Object | Select-Object -ExpandProperty Count
            
            # Database connection test
            DatabaseStatus = try {
                Get-ProUDatabaseConnectionStatus
                "Connected"
            } catch {
                "Disconnected"
            }
            
            # Service status
            ServicesStatus = @{
                ProfileUnityService = "Running"  # Assumed if we can connect
                DatabaseService = if ($serverMetrics.DatabaseStatus -eq "Connected") { "Running" } else { "Stopped" }
            }
        }
        
        # Add load indicators
        $configs = Get-ProUConfigs
        $flexApps = Get-ProUFlexapps
        
        $serverMetrics.LoadIndicators = @{
            TotalConfigurations = $configs.Count
            TotalFlexApps = $flexApps.Count
            EstimatedLoad = switch ($configs.Count + $flexApps.Count) {
                { $_ -lt 50 } { "Low" }
                { $_ -lt 200 } { "Medium" }
                { $_ -lt 500 } { "High" }
                default { "Very High" }
            }
        }
        
    }
    catch {
        Write-Warning "Could not collect complete server metrics: $_"
        $serverMetrics.Error = $_.Exception.Message
    }
    
    return $serverMetrics
}

function Get-ProUDeploymentMetrics {
    <#
    .SYNOPSIS
        Collects deployment performance metrics.
    
    .PARAMETER TimeRange
        Time range for metrics collection
    #>
    [CmdletBinding()]
    param(
        [string]$TimeRange = '24h'
    )
    
    $deploymentMetrics = @{}
    
    try {
        # Get recent deployment events
        $events = Get-ProUEvents -MaxResults 1000 | Where-Object {
            $_.Type -like "*deploy*" -or $_.Message -like "*deploy*"
        }
        
        $recentEvents = switch ($TimeRange) {
            '1h' { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddHours(-1) } }
            '6h' { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddHours(-6) } }
            '24h' { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddHours(-24) } }
            '7d' { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddDays(-7) } }
            '30d' { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddDays(-30) } }
            default { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddHours(-24) } }
        }
        
        # Calculate deployment statistics
        $successfulDeployments = $recentEvents | Where-Object { $_.Type -eq "Info" -and $_.Message -like "*success*" }
        $failedDeployments = $recentEvents | Where-Object { $_.Type -eq "Error" -and $_.Message -like "*deploy*" }
        
        $deploymentMetrics = @{
            TimeRange = $TimeRange
            TotalDeployments = $recentEvents.Count
            SuccessfulDeployments = $successfulDeployments.Count
            FailedDeployments = $failedDeployments.Count
            SuccessRate = if ($recentEvents.Count -gt 0) {
                [math]::Round(($successfulDeployments.Count / $recentEvents.Count) * 100, 1)
            } else { 0 }
            
            # Average deployment frequency
            DeploymentFrequency = if ($recentEvents.Count -gt 0) {
                switch ($TimeRange) {
                    '1h' { [math]::Round($recentEvents.Count / 1, 1) }
                    '6h' { [math]::Round($recentEvents.Count / 6, 1) }
                    '24h' { [math]::Round($recentEvents.Count / 24, 1) }
                    '7d' { [math]::Round($recentEvents.Count / 7, 1) }
                    '30d' { [math]::Round($recentEvents.Count / 30, 1) }
                }
            } else { 0 }
            
            # Most deployed configurations
            MostActiveConfigs = $recentEvents | Where-Object { $_.Message -match "configuration '([^']+)'" } |
                ForEach-Object { 
                    if ($_.Message -match "configuration '([^']+)'") { $Matches[1] }
                } | Group-Object | Sort-Object Count -Descending | Select-Object -First 5
        }
        
        # Performance trends
        if ($recentEvents.Count -gt 0) {
            $deploymentMetrics.Trends = @{
                AverageDeploymentsPerDay = [math]::Round($recentEvents.Count / ([int]$TimeRange.Replace('d', '').Replace('h', '') / 24), 1)
                PeakDeploymentHour = $recentEvents | Group-Object { ([datetime]$_.Timestamp).Hour } | Sort-Object Count -Descending | Select-Object -First 1 -ExpandProperty Name
            }
        }
    }
    catch {
        Write-Warning "Could not collect deployment metrics: $_"
        $deploymentMetrics.Error = $_.Exception.Message
    }
    
    return $deploymentMetrics
}

function Get-ProUUserExperienceMetrics {
    <#
    .SYNOPSIS
        Collects user experience metrics and analytics.
    
    .PARAMETER TimeRange
        Time range for metrics collection
    #>
    [CmdletBinding()]
    param(
        [string]$TimeRange = '24h'
    )
    
    $uxMetrics = @{}
    
    try {
        # Get user-related events
        $events = Get-ProUEvents -MaxResults 2000 | Where-Object {
            $_.Message -like "*user*" -or $_.Message -like "*login*" -or $_.Message -like "*session*"
        }
        
        $recentEvents = switch ($TimeRange) {
            '1h' { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddHours(-1) } }
            '6h' { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddHours(-6) } }
            '24h' { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddHours(-24) } }
            '7d' { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddDays(-7) } }
            '30d' { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddDays(-30) } }
            default { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddHours(-24) } }
        }
        
        # Analyze FlexApp performance
        $flexAppEvents = $recentEvents | Where-Object { $_.Message -like "*flexapp*" }
        $slowStartEvents = $recentEvents | Where-Object { $_.Message -like "*slow*" -or $_.Message -like "*timeout*" }
        
        $uxMetrics = @{
            TimeRange = $TimeRange
            TotalUserEvents = $recentEvents.Count
            FlexAppEvents = $flexAppEvents.Count
            SlowStartEvents = $slowStartEvents.Count
            
            # User experience indicators
            ExperienceScore = if ($recentEvents.Count -gt 0) {
                $errorEvents = $recentEvents | Where-Object { $_.Type -eq "Error" }
                $warningEvents = $recentEvents | Where-Object { $_.Type -eq "Warning" }
                $errorRate = $errorEvents.Count / $recentEvents.Count
                $warningRate = $warningEvents.Count / $recentEvents.Count
                
                # Calculate score (100 = perfect, 0 = terrible)
                $score = 100 - ($errorRate * 50) - ($warningRate * 20)
                [math]::Max([math]::Round($score, 1), 0)
            } else { 100 }
            
            # Common issues
            CommonIssues = $recentEvents | Where-Object { $_.Type -in @("Error", "Warning") } |
                Group-Object Message | Sort-Object Count -Descending | Select-Object -First 5 |
                ForEach-Object { @{ Issue = $_.Name; Count = $_.Count } }
            
            # Peak usage times
            UsagePattern = $recentEvents | Group-Object { ([datetime]$_.Timestamp).Hour } |
                Sort-Object Name | ForEach-Object { 
                    @{ Hour = [int]$_.Name; EventCount = $_.Count }
                }
        }
        
        # FlexApp performance analysis
        if ($flexAppEvents.Count -gt 0) {
            $uxMetrics.FlexAppPerformance = @{
                TotalLaunches = $flexAppEvents.Count
                SuccessfulLaunches = ($flexAppEvents | Where-Object { $_.Type -eq "Info" }).Count
                FailedLaunches = ($flexAppEvents | Where-Object { $_.Type -eq "Error" }).Count
                LaunchSuccessRate = if ($flexAppEvents.Count -gt 0) {
                    [math]::Round((($flexAppEvents | Where-Object { $_.Type -eq "Info" }).Count / $flexAppEvents.Count) * 100, 1)
                } else { 0 }
            }
        }
    }
    catch {
        Write-Warning "Could not collect user experience metrics: $_"
        $uxMetrics.Error = $_.Exception.Message
    }
    
    return $uxMetrics
}

function Get-ProUStorageMetrics {
    <#
    .SYNOPSIS
        Collects storage-related performance metrics.
    #>
    [CmdletBinding()]
    param()
    
    $storageMetrics = @{}
    
    try {
        # Get FlexApp storage information
        $flexApps = Get-ProUFlexapps
        
        $totalSize = 0
        $flexAppSizes = @()
        
        foreach ($flexApp in $flexApps) {
            if ($flexApp.Size) {
                $sizeInMB = [double]$flexApp.Size
                $totalSize += $sizeInMB
                $flexAppSizes += @{
                    Name = $flexApp.Name
                    SizeMB = $sizeInMB
                }
            }
        }
        
        # Get backup storage usage
        $backupPath = Join-Path $script:DefaultPaths.Backup "ConfigurationVersions"
        $backupSize = if (Test-Path $backupPath) {
            (Get-ChildItem $backupPath -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB
        } else { 0 }
        
        $storageMetrics = @{
            FlexAppStorage = @{
                TotalFlexApps = $flexApps.Count
                TotalSizeMB = [math]::Round($totalSize, 2)
                TotalSizeGB = [math]::Round($totalSize / 1024, 2)
                AverageSizeMB = if ($flexApps.Count -gt 0) { [math]::Round($totalSize / $flexApps.Count, 2) } else { 0 }
                LargestApps = $flexAppSizes | Sort-Object SizeMB -Descending | Select-Object -First 10
            }
            
            BackupStorage = @{
                BackupSizeMB = [math]::Round($backupSize, 2)
                BackupSizeGB = [math]::Round($backupSize / 1024, 2)
                BackupLocation = $backupPath
            }
            
            StorageRecommendations = @()
        }
        
        # Add storage recommendations
        if ($totalSize -gt 10240) {  # > 10GB
            $storageMetrics.StorageRecommendations += "Consider cleanup of unused FlexApp packages"
        }
        
        if ($backupSize -gt 1024) {  # > 1GB
            $storageMetrics.StorageRecommendations += "Review backup retention policy to optimize storage"
        }
        
        # Estimate storage growth
        $storageMetrics.GrowthEstimate = @{
            MonthlyGrowthMB = [math]::Round($totalSize * 0.1, 2)  # Estimate 10% monthly growth
            ProjectedSizeIn6MonthsGB = [math]::Round(($totalSize * 1.6) / 1024, 2)
        }
    }
    catch {
        Write-Warning "Could not collect storage metrics: $_"
        $storageMetrics.Error = $_.Exception.Message
    }
    
    return $storageMetrics
}

function Get-ProUNetworkMetrics {
    <#
    .SYNOPSIS
        Collects network-related performance metrics.
    
    .PARAMETER TimeRange
        Time range for metrics collection
    #>
    [CmdletBinding()]
    param(
        [string]$TimeRange = '24h'
    )
    
    $networkMetrics = @{}
    
    try {
        # Test network connectivity and latency
        $connectionTests = @()
        $serverName = $script:ModuleConfig.ServerName
        
        for ($i = 0; $i -lt 10; $i++) {
            $startTime = Get-Date
            $connected = Test-ProfileUnityConnection
            $endTime = Get-Date
            
            $connectionTests += @{
                TestNumber = $i + 1
                Success = $connected
                LatencyMs = ($endTime - $startTime).TotalMilliseconds
                Timestamp = $startTime
            }
        }
        
        $successfulTests = $connectionTests | Where-Object { $_.Success }
        $avgLatency = if ($successfulTests.Count -gt 0) {
            ($successfulTests | Measure-Object -Property LatencyMs -Average).Average
        } else { 0 }
        
        $networkMetrics = @{
            ServerConnection = @{
                ServerName = $serverName
                Port = $script:ModuleConfig.Port
                ConnectionSuccessRate = [math]::Round(($successfulTests.Count / $connectionTests.Count) * 100, 1)
                AverageLatencyMs = [math]::Round($avgLatency, 2)
                MinLatencyMs = if ($successfulTests.Count -gt 0) { ($successfulTests | Measure-Object -Property LatencyMs -Minimum).Minimum } else { 0 }
                MaxLatencyMs = if ($successfulTests.Count -gt 0) { ($successfulTests | Measure-Object -Property LatencyMs -Maximum).Maximum } else { 0 }
            }
            
            NetworkQuality = switch ($avgLatency) {
                { $_ -lt 50 } { "Excellent" }
                { $_ -lt 100 } { "Good" }
                { $_ -lt 200 } { "Fair" }
                { $_ -lt 500 } { "Poor" }
                default { "Very Poor" }
            }
            
            ConnectionStability = if ($successfulTests.Count -eq $connectionTests.Count) {
                "Stable"
            } elseif ($successfulTests.Count -gt ($connectionTests.Count * 0.9)) {
                "Good"
            } elseif ($successfulTests.Count -gt ($connectionTests.Count * 0.7)) {
                "Unstable"
            } else {
                "Poor"
            }
        }
        
        # Get network-related events
        $events = Get-ProUEvents -MaxResults 500 | Where-Object {
            $_.Message -like "*network*" -or $_.Message -like "*connection*" -or $_.Message -like "*timeout*"
        }
        
        $recentNetworkEvents = switch ($TimeRange) {
            '1h' { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddHours(-1) } }
            '6h' { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddHours(-6) } }
            '24h' { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddHours(-24) } }
            '7d' { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddDays(-7) } }
            '30d' { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddDays(-30) } }
            default { $events | Where-Object { ([datetime]$_.Timestamp) -gt (Get-Date).AddHours(-24) } }
        }
        
        $networkMetrics.EventAnalysis = @{
            TotalNetworkEvents = $recentNetworkEvents.Count
            NetworkErrors = ($recentNetworkEvents | Where-Object { $_.Type -eq "Error" }).Count
            NetworkWarnings = ($recentNetworkEvents | Where-Object { $_.Type -eq "Warning" }).Count
            CommonNetworkIssues = $recentNetworkEvents | Group-Object Message | 
                Sort-Object Count -Descending | Select-Object -First 3 |
                ForEach-Object { @{ Issue = $_.Name; Count = $_.Count } }
        }
    }
    catch {
        Write-Warning "Could not collect network metrics: $_"
        $networkMetrics.Error = $_.Exception.Message
    }
    
    return $networkMetrics
}

function Show-ProUPerformanceMetricsConsole {
    <#
    .SYNOPSIS
        Displays performance metrics in console format.
    
    .PARAMETER Metrics
        Metrics object to display
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Metrics
    )
    
    Write-Host "`n╔══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     ProfileUnity Performance Metrics     ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
    
    Write-Host "`n📊 Collection Time: $($Metrics.Timestamp)" -ForegroundColor Yellow
    Write-Host "Time Range: $($Metrics.TimeRange)" -ForegroundColor Gray
    
    # Server Metrics
    if ($Metrics.ServerMetrics -and $Metrics.ServerMetrics.Count -gt 0) {
        Write-Host "`n🖥️  SERVER PERFORMANCE" -ForegroundColor Yellow
        $server = $Metrics.ServerMetrics
        Write-Host "  Status: $($server.ConnectionStatus)" -ForegroundColor $(if ($server.ConnectionStatus -eq "Healthy") { "Green" } else { "Red" })
        Write-Host "  Performance: $($server.PerformanceStatus)" -ForegroundColor $(
            switch ($server.PerformanceStatus) {
                "Excellent" { "Green" }
                "Good" { "Green" }
                "Fair" { "Yellow" }
                default { "Red" }
            }
        )
        Write-Host "  Avg Response Time: $($server.AvgResponseTime)ms" -ForegroundColor White
        Write-Host "  Load Level: $($server.LoadIndicators.EstimatedLoad)" -ForegroundColor Gray
        Write-Host "  Database: $($server.DatabaseStatus)" -ForegroundColor $(if ($server.DatabaseStatus -eq "Connected") { "Green" } else { "Red" })
    }
    
    # Deployment Metrics
    if ($Metrics.DeploymentMetrics -and $Metrics.DeploymentMetrics.Count -gt 0) {
        Write-Host "`n🚀 DEPLOYMENT PERFORMANCE" -ForegroundColor Yellow
        $deploy = $Metrics.DeploymentMetrics
        Write-Host "  Total Deployments: $($deploy.TotalDeployments)" -ForegroundColor White
        Write-Host "  Success Rate: $($deploy.SuccessRate)%" -ForegroundColor $(if ($deploy.SuccessRate -gt 90) { "Green" } elseif ($deploy.SuccessRate -gt 75) { "Yellow" } else { "Red" })
        Write-Host "  Deployment Frequency: $($deploy.DeploymentFrequency) per hour" -ForegroundColor Gray
        if ($deploy.FailedDeployments -gt 0) {
            Write-Host "  Failed Deployments: $($deploy.FailedDeployments)" -ForegroundColor Red
        }
    }
    
    # User Experience Metrics
    if ($Metrics.UserExperienceMetrics -and $Metrics.UserExperienceMetrics.Count -gt 0) {
        Write-Host "`n👥 USER EXPERIENCE" -ForegroundColor Yellow
        $ux = $Metrics.UserExperienceMetrics
        Write-Host "  Experience Score: $($ux.ExperienceScore)/100" -ForegroundColor $(
            if ($ux.ExperienceScore -gt 90) { "Green" }
            elseif ($ux.ExperienceScore -gt 70) { "Yellow" }
            else { "Red" }
        )
        Write-Host "  Total User Events: $($ux.TotalUserEvents)" -ForegroundColor White
        if ($ux.FlexAppPerformance) {
            Write-Host "  FlexApp Success Rate: $($ux.FlexAppPerformance.LaunchSuccessRate)%" -ForegroundColor Gray
        }
        if ($ux.SlowStartEvents -gt 0) {
            Write-Host "  Slow Start Events: $($ux.SlowStartEvents)" -ForegroundColor Red
        }
    }
    
    # Storage Metrics
    if ($Metrics.StorageMetrics -and $Metrics.StorageMetrics.Count -gt 0) {
        Write-Host "`n💾 STORAGE USAGE" -ForegroundColor Yellow
        $storage = $Metrics.StorageMetrics
        if ($storage.FlexAppStorage) {
            Write-Host "  FlexApp Storage: $($storage.FlexAppStorage.TotalSizeGB) GB" -ForegroundColor White
            Write-Host "  Total FlexApps: $($storage.FlexAppStorage.TotalFlexApps)" -ForegroundColor Gray
        }
        if ($storage.BackupStorage) {
            Write-Host "  Backup Storage: $($storage.BackupStorage.BackupSizeGB) GB" -ForegroundColor Gray
        }
        if ($storage.StorageRecommendations -and $storage.StorageRecommendations.Count -gt 0) {
            Write-Host "  Recommendations:" -ForegroundColor Cyan
            $storage.StorageRecommendations | ForEach-Object { Write-Host "    • $_" -ForegroundColor Gray }
        }
    }
    
    # Network Metrics
    if ($Metrics.NetworkMetrics -and $Metrics.NetworkMetrics.Count -gt 0) {
        Write-Host "`n🌐 NETWORK PERFORMANCE" -ForegroundColor Yellow
        $network = $Metrics.NetworkMetrics
        if ($network.ServerConnection) {
            Write-Host "  Connection Quality: $($network.NetworkQuality)" -ForegroundColor $(
                switch ($network.NetworkQuality) {
                    "Excellent" { "Green" }
                    "Good" { "Green" }
                    "Fair" { "Yellow" }
                    default { "Red" }
                }
            )
            Write-Host "  Average Latency: $($network.ServerConnection.AverageLatencyMs)ms" -ForegroundColor White
            Write-Host "  Success Rate: $($network.ServerConnection.ConnectionSuccessRate)%" -ForegroundColor Gray
            Write-Host "  Stability: $($network.ConnectionStability)" -ForegroundColor Gray
        }
    }
    
    Write-Host "`n💡 Use Get-ProUPerformanceMetrics -OutputFormat Dashboard for interactive view" -ForegroundColor Cyan
}

function Show-ProUPerformanceDashboard {
    <#
    .SYNOPSIS
        Shows an interactive performance dashboard.
    
    .PARAMETER Metrics
        Metrics object to display
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Metrics
    )
    
    # Create HTML dashboard
    $htmlPath = Join-Path $env:TEMP "ProfileUnity_Performance_Dashboard.html"
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>ProfileUnity Performance Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .dashboard { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .card h3 { margin-top: 0; color: #2E86C1; border-bottom: 2px solid #2E86C1; padding-bottom: 10px; }
        .metric { display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #eee; }
        .metric:last-child { border-bottom: none; }
        .value { font-weight: bold; }
        .excellent { color: #27AE60; }
        .good { color: #229954; }
        .fair { color: #F39C12; }
        .poor { color: #E74C3C; }
        .header { text-align: center; margin-bottom: 30px; }
        .status-indicator { display: inline-block; width: 12px; height: 12px; border-radius: 50%; margin-right: 8px; }
        .status-healthy { background-color: #27AE60; }
        .status-warning { background-color: #F39C12; }
        .status-error { background-color: #E74C3C; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🖥️ ProfileUnity Performance Dashboard</h1>
        <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Time Range: $($Metrics.TimeRange)</p>
    </div>
    
    <div class="dashboard">
"@
    
    # Add server metrics card
    if ($Metrics.ServerMetrics) {
        $server = $Metrics.ServerMetrics
        $statusClass = if ($server.ConnectionStatus -eq "Healthy") { "status-healthy" } else { "status-error" }
        
        $html += @"
        <div class="card">
            <h3>🖥️ Server Performance</h3>
            <div class="metric">
                <span>Status</span>
                <span><span class="status-indicator $statusClass"></span>$($server.ConnectionStatus)</span>
            </div>
            <div class="metric">
                <span>Performance Rating</span>
                <span class="value $($server.PerformanceStatus.ToLower())">$($server.PerformanceStatus)</span>
            </div>
            <div class="metric">
                <span>Avg Response Time</span>
                <span class="value">$($server.AvgResponseTime)ms</span>
            </div>
            <div class="metric">
                <span>Load Level</span>
                <span>$($server.LoadIndicators.EstimatedLoad)</span>
            </div>
            <div class="metric">
                <span>Database</span>
                <span class="$(if ($server.DatabaseStatus -eq 'Connected') { 'excellent' } else { 'poor' })">$($server.DatabaseStatus)</span>
            </div>
        </div>
"@
    }
    
    # Add deployment metrics card
    if ($Metrics.DeploymentMetrics) {
        $deploy = $Metrics.DeploymentMetrics
        $successClass = if ($deploy.SuccessRate -gt 90) { "excellent" } elseif ($deploy.SuccessRate -gt 75) { "good" } else { "poor" }
        
        $html += @"
        <div class="card">
            <h3>🚀 Deployment Metrics</h3>
            <div class="metric">
                <span>Total Deployments</span>
                <span class="value">$($deploy.TotalDeployments)</span>
            </div>
            <div class="metric">
                <span>Success Rate</span>
                <span class="value $successClass">$($deploy.SuccessRate)%</span>
            </div>
            <div class="metric">
                <span>Frequency</span>
                <span>$($deploy.DeploymentFrequency)/hour</span>
            </div>
            <div class="metric">
                <span>Failed Deployments</span>
                <span class="$(if ($deploy.FailedDeployments -gt 0) { 'poor' } else { 'excellent' })">$($deploy.FailedDeployments)</span>
            </div>
        </div>
"@
    }
    
    # Add user experience card
    if ($Metrics.UserExperienceMetrics) {
        $ux = $Metrics.UserExperienceMetrics
        $uxClass = if ($ux.ExperienceScore -gt 90) { "excellent" } elseif ($ux.ExperienceScore -gt 70) { "good" } else { "poor" }
        
        $html += @"
        <div class="card">
            <h3>👥 User Experience</h3>
            <div class="metric">
                <span>Experience Score</span>
                <span class="value $uxClass">$($ux.ExperienceScore)/100</span>
            </div>
            <div class="metric">
                <span>Total Events</span>
                <span class="value">$($ux.TotalUserEvents)</span>
            </div>
"@
        
        if ($ux.FlexAppPerformance) {
            $html += @"
            <div class="metric">
                <span>FlexApp Success Rate</span>
                <span>$($ux.FlexAppPerformance.LaunchSuccessRate)%</span>
            </div>
"@
        }
        
        $html += @"
            <div class="metric">
                <span>Performance Issues</span>
                <span class="$(if ($ux.SlowStartEvents -gt 0) { 'poor' } else { 'excellent' })">$($ux.SlowStartEvents)</span>
            </div>
        </div>
"@
    }
    
    $html += @"
    </div>
</body>
</html>
"@
    
    # Save and open dashboard
    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Start-Process $htmlPath
    
    Write-Host "📊 Performance dashboard opened in browser: $htmlPath" -ForegroundColor Green
}

# Export functions
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
Export-ModuleMember -Function @(
    'Get-ProUPerformanceMetrics',
    'Get-ProUServerPerformanceMetrics',
    'Get-ProUDeploymentMetrics',
    'Get-ProUUserExperienceMetrics',
    'Get-ProUStorageMetrics',
    'Get-ProUNetworkMetrics',
    'Show-ProUPerformanceMetricsConsole',
    'Show-ProUPerformanceDashboard'
)
#>
