# Configuration/ConfigurationValidation.ps1 - Configuration Validation and Best Practices

# =============================================================================
# CONFIGURATION VALIDATION ENGINE
# =============================================================================

function Test-ProUBestPractices {
    <#
    .SYNOPSIS
        Tests ProfileUnity configurations against best practices and security guidelines.
    
    .DESCRIPTION
        Performs comprehensive validation including security, performance, and compliance checks.
    
    .PARAMETER ConfigurationName
        Name of specific configuration to test (tests all if not specified)
    
    .PARAMETER Category
        Specific category of tests to run
    
    .PARAMETER Detailed
        Include detailed recommendations and fixes
    
    .PARAMETER OutputFormat
        Output format for results
    
    .EXAMPLE
        Test-ProUBestPractices
        
    .EXAMPLE
        Test-ProUBestPractices -ConfigurationName "Production" -Category Security -Detailed
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigurationName,
        
        [ValidateSet('All', 'Security', 'Performance', 'Compliance', 'Maintenance')]
        [string]$Category = 'All',
        
        [switch]$Detailed,
        
        [ValidateSet('Console', 'JSON', 'HTML', 'Excel')]
        [string]$OutputFormat = 'Console'
    )
    
    Write-Host "🔍 Running ProfileUnity Best Practices Analysis..." -ForegroundColor Cyan
    
    # Get configurations to test
    $configurations = if ($ConfigurationName) {
        Get-ProUConfig | Where-Object { $_.Name -eq $ConfigurationName }
    } else {
        Get-ProUConfig
    }
    
    if (-not $configurations) {
        Write-Host "No configurations found to test" -ForegroundColor Red
        return
    }
    
    $allResults = @()
    
    foreach ($config in $configurations) {
        Write-Host "`n📋 Testing configuration: $($config.Name)" -ForegroundColor Yellow
        
        $configResults = @{
            ConfigurationName = $config.Name
            TestResults = @()
            OverallScore = 0
            SecurityScore = 0
            PerformanceScore = 0
            ComplianceScore = 0
            MaintenanceScore = 0
        }
        
        # Run test categories
        if ($Category -in @('All', 'Security')) {
            $configResults.TestResults += Test-ProUSecurityBestPractices -Configuration $config
        }
        if ($Category -in @('All', 'Performance')) {
            $configResults.TestResults += Test-ProUPerformanceBestPractices -Configuration $config
        }
        if ($Category -in @('All', 'Compliance')) {
            $configResults.TestResults += Test-ProUComplianceBestPractices -Configuration $config
        }
        if ($Category -in @('All', 'Maintenance')) {
            $configResults.TestResults += Test-ProUMaintenanceBestPractices -Configuration $config
        }
        
        # Calculate scores
        $configResults = Calculate-ProUBestPracticesScore -Results $configResults
        
        $allResults += $configResults
    }
    
    # Output results based on format
    switch ($OutputFormat) {
        'Console' { Show-ProUBestPracticesConsoleReport -Results $allResults -Detailed:$Detailed }
        'JSON' { Export-ProUBestPracticesJSON -Results $allResults }
        'HTML' { Export-ProUBestPracticesHTML -Results $allResults -Detailed:$Detailed }
        'Excel' { Export-ProUBestPracticesExcel -Results $allResults -Detailed:$Detailed }
    }
    
    return $allResults
}

function Test-ProUSecurityBestPractices {
    <#
    .SYNOPSIS
        Tests security-related best practices.
    
    .PARAMETER Configuration
        Configuration object to test
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Configuration
    )
    
    $securityTests = @()
    
    # Test 1: Check for sensitive data in configurations
    $securityTests += @{
        TestName = "Sensitive Data Exposure"
        Category = "Security"
        Severity = "High"
        Status = "Pass"
        Message = "No sensitive data found in configuration"
        Recommendation = ""
    }
    
    # Check for passwords, keys, or secrets
    $configJson = $Configuration | ConvertTo-Json -Depth 20
    $sensitivePatterns = @(
        'password\s*[:=]\s*["\']?[^"\s,}]+',
        'secret\s*[:=]\s*["\']?[^"\s,}]+',
        'key\s*[:=]\s*["\']?[^"\s,}]+',
        'token\s*[:=]\s*["\']?[^"\s,}]+'
    )
    
    foreach ($pattern in $sensitivePatterns) {
        if ($configJson -match $pattern) {
            $securityTests[-1].Status = "Fail"
            $securityTests[-1].Message = "Potential sensitive data found in configuration"
            $securityTests[-1].Recommendation = "Review configuration for hardcoded passwords, keys, or secrets. Use secure credential storage instead."
            break
        }
    }
    
    # Test 2: Filter validation
    $securityTests += @{
        TestName = "Filter Security"
        Category = "Security"
        Severity = "Medium"
        Status = "Pass"
        Message = "Filter assignments are properly configured"
        Recommendation = ""
    }
    
    # Check if configurations have appropriate filters
    $hasProperFilters = $false
    if ($Configuration.Filters -and $Configuration.Filters.Count -gt 0) {
        $hasProperFilters = $true
    } elseif ($Configuration.FlexAppDias) {
        foreach ($dia in $Configuration.FlexAppDias) {
            if ($dia.Filter -and $dia.Filter -ne "All Users") {
                $hasProperFilters = $true
                break
            }
        }
    }
    
    if (-not $hasProperFilters) {
        $securityTests[-1].Status = "Warning"
        $securityTests[-1].Message = "Configuration may be too broadly applied"
        $securityTests[-1].Recommendation = "Consider using specific filters to limit configuration scope and reduce security exposure."
    }
    
    # Test 3: ADMX Security Templates
    $securityTests += @{
        TestName = "ADMX Security Templates"
        Category = "Security"
        Severity = "Medium"
        Status = "Pass"
        Message = "Security-related ADMX templates are configured"
        Recommendation = ""
    }
    
    if ($Configuration.AdministrativeTemplates) {
        $securityTemplates = $Configuration.AdministrativeTemplates | Where-Object {
            $_.AdmxFile -match '(security|firewall|defender|encryption|bitlocker)'
        }
        
        if ($securityTemplates.Count -eq 0) {
            $securityTests[-1].Status = "Warning"
            $securityTests[-1].Message = "No security-focused ADMX templates found"
            $securityTests[-1].Recommendation = "Consider adding Windows Security, Windows Defender, or BitLocker ADMX templates for enhanced security."
        }
    } else {
        $securityTests[-1].Status = "Info"
        $securityTests[-1].Message = "No ADMX templates configured"
        $securityTests[-1].Recommendation = "Consider adding security-related ADMX templates for policy enforcement."
    }
    
    # Test 4: Privilege Escalation Risks
    $securityTests += @{
        TestName = "Privilege Escalation"
        Category = "Security"
        Severity = "High"
        Status = "Pass"
        Message = "No privilege escalation risks detected"
        Recommendation = ""
    }
    
    # Check for risky FlexApp configurations
    if ($Configuration.FlexAppDias) {
        foreach ($dia in $Configuration.FlexAppDias) {
            if ($dia.FlexAppPackages) {
                foreach ($package in $dia.FlexAppPackages) {
                    # Check for admin rights or system access
                    if ($package.RequiresElevation -eq "true" -or $package.RunAsAdmin -eq "true") {
                        $securityTests[-1].Status = "Warning"
                        $securityTests[-1].Message = "FlexApp packages with elevated privileges detected"
                        $securityTests[-1].Recommendation = "Review FlexApp packages that require administrative privileges. Ensure they are from trusted sources and properly scoped."
                        break
                    }
                }
            }
        }
    }
    
    return $securityTests
}

function Test-ProUPerformanceBestPractices {
    <#
    .SYNOPSIS
        Tests performance-related best practices.
    
    .PARAMETER Configuration
        Configuration object to test
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Configuration
    )
    
    $performanceTests = @()
    
    # Test 1: FlexApp DIA Configuration Optimization
    $performanceTests += @{
        TestName = "FlexApp DIA Optimization"
        Category = "Performance"
        Severity = "Medium"
        Status = "Pass"
        Message = "FlexApp DIA configurations are optimized"
        Recommendation = ""
    }
    
    if ($Configuration.FlexAppDias) {
        $totalPackages = 0
        $jitEnabled = 0
        $cacheEnabled = 0
        
        foreach ($dia in $Configuration.FlexAppDias) {
            if ($dia.FlexAppPackages) {
                foreach ($package in $dia.FlexAppPackages) {
                    $totalPackages++
                    if ($package.UseJit -eq "true") { $jitEnabled++ }
                    if ($package.CacheLocal -eq "true") { $cacheEnabled++ }
                }
            }
        }
        
        if ($totalPackages -gt 0) {
            $jitPercent = ($jitEnabled / $totalPackages) * 100
            $cachePercent = ($cacheEnabled / $totalPackages) * 100
            
            if ($jitPercent -lt 50) {
                $performanceTests[-1].Status = "Warning"
                $performanceTests[-1].Message = "Low JIT usage detected ($([math]::Round($jitPercent))% of packages)"
                $performanceTests[-1].Recommendation = "Enable Just-In-Time provisioning for better performance and reduced storage requirements."
            }
            
            if ($cachePercent -lt 70) {
                $performanceTests[-1].Status = "Warning"
                $performanceTests[-1].Message = "Low local caching usage ($([math]::Round($cachePercent))% of packages)"
                $performanceTests[-1].Recommendation = "Enable local caching for frequently used applications to improve startup performance."
            }
        }
    } else {
        $performanceTests[-1].Status = "Info"
        $performanceTests[-1].Message = "No FlexApp DIAs configured"
    }
    
    # Test 2: ADMX Template Optimization
    $performanceTests += @{
        TestName = "ADMX Template Count"
        Category = "Performance"
        Severity = "Low"
        Status = "Pass"
        Message = "ADMX template count is reasonable"
        Recommendation = ""
    }
    
    if ($Configuration.AdministrativeTemplates) {
        $templateCount = $Configuration.AdministrativeTemplates.Count
        if ($templateCount -gt 50) {
            $performanceTests[-1].Status = "Warning"
            $performanceTests[-1].Message = "High number of ADMX templates ($templateCount)"
            $performanceTests[-1].Recommendation = "Consider consolidating ADMX templates or splitting configuration into multiple targeted configs to improve processing performance."
        }
    }
    
    # Test 3: Sequence Optimization
    $performanceTests += @{
        TestName = "Processing Sequence"
        Category = "Performance"
        Severity = "Low"
        Status = "Pass"
        Message = "Processing sequences are properly ordered"
        Recommendation = ""
    }
    
    # Check for optimal sequencing (critical items first)
    if ($Configuration.FlexAppDias -and $Configuration.AdministrativeTemplates) {
        $avgFlexAppSequence = ($Configuration.FlexAppDias.FlexAppPackages.Sequence | ForEach-Object { [int]$_ } | Measure-Object -Average).Average
        $avgADMXSequence = ($Configuration.AdministrativeTemplates.Sequence | ForEach-Object { [int]$_ } | Measure-Object -Average).Average
        
        # ADMX should generally process before FlexApps
        if ($avgADMXSequence -gt $avgFlexAppSequence) {
            $performanceTests[-1].Status = "Info"
            $performanceTests[-1].Message = "Consider reordering sequences for optimal performance"
            $performanceTests[-1].Recommendation = "Process ADMX templates (policies) before FlexApp packages for better startup performance."
        }
    }
    
    return $performanceTests
}

function Test-ProUComplianceBestPractices {
    <#
    .SYNOPSIS
        Tests compliance-related best practices.
    
    .PARAMETER Configuration
        Configuration object to test
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Configuration
    )
    
    $complianceTests = @()
    
    # Test 1: Documentation and Naming Standards
    $complianceTests += @{
        TestName = "Documentation Standards"
        Category = "Compliance"
        Severity = "Medium"
        Status = "Pass"
        Message = "Configuration follows documentation standards"
        Recommendation = ""
    }
    
    if ([string]::IsNullOrWhiteSpace($Configuration.Description)) {
        $complianceTests[-1].Status = "Warning"
        $complianceTests[-1].Message = "Configuration lacks description"
        $complianceTests[-1].Recommendation = "Add a meaningful description to document the configuration's purpose and scope."
    }
    
    # Check naming convention
    if ($Configuration.Name -match '^[a-zA-Z0-9\-_\s]+$' -and $Configuration.Name.Length -le 50) {
        # Good naming convention
    } else {
        $complianceTests[-1].Status = "Info"
        $complianceTests[-1].Message = "Configuration name may not follow naming standards"
        $complianceTests[-1].Recommendation = "Use descriptive names with alphanumeric characters, hyphens, underscores, and spaces only."
    }
    
    # Test 2: Change Tracking
    $complianceTests += @{
        TestName = "Change Tracking"
        Category = "Compliance"
        Severity = "Low"
        Status = "Pass"
        Message = "Change tracking information is available"
        Recommendation = ""
    }
    
    if (-not $Configuration.LastModified -or -not $Configuration.ModifiedBy) {
        $complianceTests[-1].Status = "Warning"
        $complianceTests[-1].Message = "Missing change tracking information"
        $complianceTests[-1].Recommendation = "Ensure proper change tracking is enabled to maintain audit trails."
    }
    
    # Test 3: Filter Scope Validation
    $complianceTests += @{
        TestName = "Scope Control"
        Category = "Compliance"
        Severity = "High"
        Status = "Pass"
        Message = "Configuration scope is properly controlled"
        Recommendation = ""
    }
    
    # Check for overly broad configurations
    $hasBroadScope = $false
    if ($Configuration.FlexAppDias) {
        foreach ($dia in $Configuration.FlexAppDias) {
            if ($dia.Filter -in @("All Users", "Everyone", "") -or -not $dia.Filter) {
                $hasBroadScope = $true
                break
            }
        }
    }
    
    if ($hasBroadScope) {
        $complianceTests[-1].Status = "Warning"
        $complianceTests[-1].Message = "Configuration has broad scope (affects all users)"
        $complianceTests[-1].Recommendation = "Consider using specific filters to limit configuration impact for compliance and testing purposes."
    }
    
    return $complianceTests
}

function Test-ProUMaintenanceBestPractices {
    <#
    .SYNOPSIS
        Tests maintenance-related best practices.
    
    .PARAMETER Configuration
        Configuration object to test
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Configuration
    )
    
    $maintenanceTests = @()
    
    # Test 1: Configuration Complexity
    $maintenanceTests += @{
        TestName = "Configuration Complexity"
        Category = "Maintenance"
        Severity = "Medium"
        Status = "Pass"
        Message = "Configuration complexity is manageable"
        Recommendation = ""
    }
    
    $complexity = 0
    if ($Configuration.FlexAppDias) { $complexity += $Configuration.FlexAppDias.Count * 2 }
    if ($Configuration.AdministrativeTemplates) { $complexity += $Configuration.AdministrativeTemplates.Count }
    if ($Configuration.PortabilityRules) { $complexity += $Configuration.PortabilityRules.Count }
    
    if ($complexity -gt 30) {
        $maintenanceTests[-1].Status = "Warning"
        $maintenanceTests[-1].Message = "High configuration complexity (score: $complexity)"
        $maintenanceTests[-1].Recommendation = "Consider splitting complex configurations into smaller, focused configurations for easier maintenance."
    }
    
    # Test 2: Update Frequency Assessment
    $maintenanceTests += @{
        TestName = "Update Frequency"
        Category = "Maintenance"
        Severity = "Low"
        Status = "Pass"
        Message = "Configuration update frequency is appropriate"
        Recommendation = ""
    }
    
    if ($Configuration.LastModified) {
        $daysSinceUpdate = ((Get-Date) - [datetime]$Configuration.LastModified).Days
        if ($daysSinceUpdate -gt 90) {
            $maintenanceTests[-1].Status = "Info"
            $maintenanceTests[-1].Message = "Configuration hasn't been updated in $daysSinceUpdate days"
            $maintenanceTests[-1].Recommendation = "Review configuration for relevance and consider updates or retirement if no longer needed."
        }
    }
    
    # Test 3: Dependency Analysis
    $maintenanceTests += @{
        TestName = "Dependency Management"
        Category = "Maintenance"
        Severity = "Medium"
        Status = "Pass"
        Message = "Dependencies are properly managed"
        Recommendation = ""
    }
    
    # Check for broken references
    $brokenReferences = @()
    if ($Configuration.FlexAppDias) {
        foreach ($dia in $Configuration.FlexAppDias) {
            if ($dia.FilterId) {
                try {
                    $filter = Get-ProUFilters | Where-Object { $_.ID -eq $dia.FilterId }
                    if (-not $filter) {
                        $brokenReferences += "Filter ID $($dia.FilterId) not found"
                    }
                }
                catch {
                    $brokenReferences += "Could not validate filter $($dia.FilterId)"
                }
            }
        }
    }
    
    if ($brokenReferences.Count -gt 0) {
        $maintenanceTests[-1].Status = "Fail"
        $maintenanceTests[-1].Message = "Broken references detected: $($brokenReferences -join '; ')"
        $maintenanceTests[-1].Recommendation = "Fix broken references to ensure configuration functions properly."
    }
    
    return $maintenanceTests
}

function Calculate-ProUBestPracticesScore {
    <#
    .SYNOPSIS
        Calculates overall scores for best practices results.
    
    .PARAMETER Results
        Results object to calculate scores for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Results
    )
    
    $totalTests = $Results.TestResults.Count
    if ($totalTests -eq 0) {
        return $Results
    }
    
    $passedTests = ($Results.TestResults | Where-Object { $_.Status -eq "Pass" }).Count
    $warningTests = ($Results.TestResults | Where-Object { $_.Status -eq "Warning" }).Count
    $failedTests = ($Results.TestResults | Where-Object { $_.Status -eq "Fail" }).Count
    
    # Overall score (Pass=100, Warning=50, Fail=0, Info=75)
    $totalScore = 0
    foreach ($test in $Results.TestResults) {
        switch ($test.Status) {
            "Pass" { $totalScore += 100 }
            "Warning" { $totalScore += 50 }
            "Info" { $totalScore += 75 }
            "Fail" { $totalScore += 0 }
        }
    }
    
    $Results.OverallScore = if ($totalTests -gt 0) { [math]::Round($totalScore / $totalTests, 1) } else { 0 }
    
    # Category scores
    $securityTests = $Results.TestResults | Where-Object { $_.Category -eq "Security" }
    if ($securityTests) {
        $securityScore = 0
        foreach ($test in $securityTests) {
            switch ($test.Status) {
                "Pass" { $securityScore += 100 }
                "Warning" { $securityScore += 50 }
                "Info" { $securityScore += 75 }
                "Fail" { $securityScore += 0 }
            }
        }
        $Results.SecurityScore = [math]::Round($securityScore / $securityTests.Count, 1)
    }
    
    # Similar calculations for other categories...
    
    return $Results
}

function Show-ProUBestPracticesConsoleReport {
    <#
    .SYNOPSIS
        Shows best practices results in console format.
    
    .PARAMETER Results
        Results to display
    
    .PARAMETER Detailed
        Show detailed information
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Results,
        
        [switch]$Detailed
    )
    
    Write-Host "`n╔══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     ProfileUnity Best Practices Report   ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
    
    foreach ($configResult in $Results) {
        Write-Host "`n📋 Configuration: $($configResult.ConfigurationName)" -ForegroundColor Yellow
        Write-Host "Overall Score: $($configResult.OverallScore)%" -ForegroundColor $(
            if ($configResult.OverallScore -ge 80) { "Green" }
            elseif ($configResult.OverallScore -ge 60) { "Yellow" }
            else { "Red" }
        )
        
        # Group results by status
        $passed = $configResult.TestResults | Where-Object { $_.Status -eq "Pass" }
        $warnings = $configResult.TestResults | Where-Object { $_.Status -eq "Warning" }
        $failed = $configResult.TestResults | Where-Object { $_.Status -eq "Fail" }
        $info = $configResult.TestResults | Where-Object { $_.Status -eq "Info" }
        
        Write-Host "✅ Passed: $($passed.Count)  ⚠️  Warnings: $($warnings.Count)  ❌ Failed: $($failed.Count)  ℹ️  Info: $($info.Count)" -ForegroundColor Gray
        
        if ($Detailed) {
            # Show detailed results
            foreach ($category in @("Security", "Performance", "Compliance", "Maintenance")) {
                $categoryTests = $configResult.TestResults | Where-Object { $_.Category -eq $category }
                if ($categoryTests) {
                    Write-Host "`n🔸 $category Tests:" -ForegroundColor Cyan
                    foreach ($test in $categoryTests) {
                        $icon = switch ($test.Status) {
                            "Pass" { "✅" }
                            "Warning" { "⚠️" }
                            "Fail" { "❌" }
                            "Info" { "ℹ️" }
                        }
                        Write-Host "  $icon $($test.TestName): $($test.Message)" -ForegroundColor White
                        if ($test.Recommendation -and $test.Status -in @("Warning", "Fail")) {
                            Write-Host "     💡 $($test.Recommendation)" -ForegroundColor Gray
                        }
                    }
                }
            }
        }
    }
    
    # Summary
    $totalConfigs = $Results.Count
    $avgScore = if ($totalConfigs -gt 0) { [math]::Round(($Results | ForEach-Object { $_.OverallScore } | Measure-Object -Average).Average, 1) } else { 0 }
    
    Write-Host "`n📊 Summary:" -ForegroundColor Yellow
    Write-Host "Configurations Tested: $totalConfigs" -ForegroundColor White
    Write-Host "Average Score: $avgScore%" -ForegroundColor White
}

function Get-ProUConfigurationHealthScore {
    <#
    .SYNOPSIS
        Gets a quick health score for configurations without full testing.
    
    .PARAMETER ConfigurationName
        Specific configuration to score
    
    .EXAMPLE
        Get-ProUConfigurationHealthScore -ConfigurationName "Production"
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigurationName
    )
    
    $configurations = if ($ConfigurationName) {
        Get-ProUConfig | Where-Object { $_.Name -eq $ConfigurationName }
    } else {
        Get-ProUConfig
    }
    
    $results = @()
    
    foreach ($config in $configurations) {
        $score = 100  # Start with perfect score
        $factors = @()
        
        # Deduct points for missing elements
        if ([string]::IsNullOrWhiteSpace($config.Description)) {
            $score -= 10
            $factors += "Missing description"
        }
        
        if (-not $config.LastModified) {
            $score -= 15
            $factors += "No modification tracking"
        }
        
        # Check for complexity
        $complexity = 0
        if ($config.FlexAppDias) { $complexity += $config.FlexAppDias.Count }
        if ($config.AdministrativeTemplates) { $complexity += $config.AdministrativeTemplates.Count }
        
        if ($complexity -gt 30) {
            $score -= 20
            $factors += "High complexity"
        } elseif ($complexity -gt 20) {
            $score -= 10
            $factors += "Moderate complexity"
        }
        
        # Check age
        if ($config.LastModified) {
            $age = ((Get-Date) - [datetime]$config.LastModified).Days
            if ($age -gt 180) {
                $score -= 15
                $factors += "Old configuration (${age} days)"
            } elseif ($age -gt 90) {
                $score -= 5
                $factors += "Aging configuration (${age} days)"
            }
        }
        
        $score = [math]::Max($score, 0)  # Don't go below 0
        
        $results += [PSCustomObject]@{
            Name = $config.Name
            HealthScore = $score
            Grade = switch ($score) {
                { $_ -ge 90 } { "A" }
                { $_ -ge 80 } { "B" }
                { $_ -ge 70 } { "C" }
                { $_ -ge 60 } { "D" }
                default { "F" }
            }
            Factors = $factors
            Complexity = $complexity
            Age = if ($config.LastModified) { ((Get-Date) - [datetime]$config.LastModified).Days } else { $null }
        }
    }
    
    return $results
}

# Export functions
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
Export-ModuleMember -Function @(
    'Test-ProUBestPractices',
    'Test-ProUSecurityBestPractices',
    'Test-ProUPerformanceBestPractices',
    'Test-ProUComplianceBestPractices',
    'Test-ProUMaintenanceBestPractices',
    'Get-ProUConfigurationHealthScore',
    'Show-ProUBestPracticesConsoleReport'
)
#>
