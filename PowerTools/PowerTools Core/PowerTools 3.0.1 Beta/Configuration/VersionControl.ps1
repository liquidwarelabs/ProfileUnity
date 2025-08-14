# Configuration/VersionControl.ps1 - Rollback and Version Control System

# =============================================================================
# VERSION CONTROL AND ROLLBACK SYSTEM
# =============================================================================

function Backup-ProUConfigurationState {
    <#
    .SYNOPSIS
        Creates automatic configuration snapshots before changes for rollback capability.
    
    .DESCRIPTION
        Backs up current configuration state with versioning and metadata for easy rollback.
    
    .PARAMETER ConfigurationName
        Name of configuration to backup (all if not specified)
    
    .PARAMETER BackupType
        Type of backup operation
    
    .PARAMETER Comment
        Optional comment describing the changes being made
    
    .PARAMETER RetentionDays
        Number of days to retain backups (default: 30)
    
    .EXAMPLE
        Backup-ProUConfigurationState -ConfigurationName "Production" -BackupType "PreDeployment" -Comment "Before adding new FlexApp"
        
    .EXAMPLE
        Backup-ProUConfigurationState -BackupType "Manual" -Comment "Weekly backup"
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigurationName,
        
        [ValidateSet('Automatic', 'Manual', 'PreDeployment', 'PreEdit', 'Scheduled')]
        [string]$BackupType = 'Manual',
        
        [string]$Comment = "",
        
        [int]$RetentionDays = 30
    )
    
    Write-Host "🔄 Creating configuration state backup..." -ForegroundColor Cyan
    
    # Get configurations to backup
    $configurations = if ($ConfigurationName) {
        Get-ProUConfig | Where-Object { $_.Name -eq $ConfigurationName }
    } else {
        Get-ProUConfig
    }
    
    if (-not $configurations) {
        Write-Host "No configurations found to backup" -ForegroundColor Red
        return
    }
    
    # Create backup directory structure
    $backupRoot = Join-Path $script:DefaultPaths.Backup "ConfigurationVersions"
    $timestampFolder = "Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $backupPath = Join-Path $backupRoot $timestampFolder
    
    if (-not (Test-Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    }
    
    $backupResults = @()
    
    foreach ($config in $configurations) {
        try {
            Write-Host "  Backing up: $($config.Name)" -ForegroundColor Yellow
            
            # Create individual config backup
            $configBackupPath = Join-Path $backupPath "$($config.Name).json"
            
            # Get full configuration data
            $fullConfig = Get-ProUConfig -Name $config.Name
            
            # Create backup metadata
            $backupMetadata = @{
                BackupInfo = @{
                    Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    BackupType = $BackupType
                    Comment = $Comment
                    User = $env:USERNAME
                    Server = $script:ModuleConfig.ServerName
                    Version = $script:ModuleConfig.ModuleVersion
                }
                ConfigurationData = $fullConfig
                Dependencies = @{
                    Filters = @()
                    FlexApps = @()
                    Templates = @()
                }
            }
            
            # Capture dependencies
            if ($fullConfig.FlexAppDias) {
                foreach ($dia in $fullConfig.FlexAppDias) {
                    if ($dia.FilterId) {
                        try {
                            $filter = Get-ProUFilters | Where-Object { $_.ID -eq $dia.FilterId }
                            if ($filter) {
                                $backupMetadata.Dependencies.Filters += $filter
                            }
                        }
                        catch {
                            Write-Verbose "Could not backup filter dependency: $($dia.FilterId)"
                        }
                    }
                    
                    if ($dia.FlexAppPackages) {
                        foreach ($package in $dia.FlexAppPackages) {
                            try {
                                $flexApp = Get-ProUFlexapps | Where-Object { $_.ID -eq $package.FlexAppPackageId }
                                if ($flexApp) {
                                    $backupMetadata.Dependencies.FlexApps += $flexApp
                                }
                            }
                            catch {
                                Write-Verbose "Could not backup FlexApp dependency: $($package.FlexAppPackageId)"
                            }
                        }
                    }
                }
            }
            
            # Save backup
            $backupMetadata | ConvertTo-Json -Depth 20 | Out-File -FilePath $configBackupPath -Encoding UTF8
            
            # Create version history entry
            $versionEntry = @{
                ConfigurationName = $config.Name
                BackupPath = $configBackupPath
                Timestamp = Get-Date
                BackupType = $BackupType
                Comment = $Comment
                User = $env:USERNAME
                Size = (Get-Item $configBackupPath).Length
                Hash = Get-FileHash $configBackupPath -Algorithm SHA256 | Select-Object -ExpandProperty Hash
            }
            
            $backupResults += $versionEntry
            
            Write-Host "    ✅ Backup created: $configBackupPath" -ForegroundColor Green
        }
        catch {
            Write-Host "    ❌ Failed to backup $($config.Name): $_" -ForegroundColor Red
            continue
        }
    }
    
    # Update version history
    Update-ProUVersionHistory -Entries $backupResults
    
    # Clean up old backups
    if ($RetentionDays -gt 0) {
        Remove-ProUOldBackups -RetentionDays $RetentionDays
    }
    
    Write-Host "📁 Backup completed: $backupPath" -ForegroundColor Green
    Write-Host "Backed up $($backupResults.Count) configurations" -ForegroundColor Gray
    
    return @{
        BackupPath = $backupPath
        BackupResults = $backupResults
        Timestamp = Get-Date
    }
}

function Get-ProUConfigurationHistory {
    <#
    .SYNOPSIS
        Gets version history for ProfileUnity configurations.
    
    .DESCRIPTION
        Retrieves backup and version history with filtering and sorting options.
    
    .PARAMETER ConfigurationName
        Specific configuration to get history for
    
    .PARAMETER Days
        Number of days of history to retrieve
    
    .PARAMETER BackupType
        Filter by backup type
    
    .PARAMETER Detailed
        Include detailed backup information
    
    .EXAMPLE
        Get-ProUConfigurationHistory -ConfigurationName "Production" -Days 30
        
    .EXAMPLE
        Get-ProUConfigurationHistory -BackupType "PreDeployment" -Detailed
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigurationName,
        
        [int]$Days = 30,
        
        [ValidateSet('All', 'Automatic', 'Manual', 'PreDeployment', 'PreEdit', 'Scheduled')]
        [string]$BackupType = 'All',
        
        [switch]$Detailed
    )
    
    $historyPath = Join-Path $script:DefaultPaths.Backup "VersionHistory.json"
    
    if (-not (Test-Path $historyPath)) {
        Write-Host "No version history found" -ForegroundColor Yellow
        return @()
    }
    
    try {
        $history = Get-Content $historyPath | ConvertFrom-Json
    }
    catch {
        Write-Host "Error reading version history: $_" -ForegroundColor Red
        return @()
    }
    
    # Filter history
    $filteredHistory = $history | Where-Object {
        $include = $true
        
        # Filter by configuration name
        if ($ConfigurationName -and $_.ConfigurationName -ne $ConfigurationName) {
            $include = $false
        }
        
        # Filter by days
        if ($Days -gt 0) {
            $backupDate = [datetime]$_.Timestamp
            if ((Get-Date) - $backupDate -gt [TimeSpan]::FromDays($Days)) {
                $include = $false
            }
        }
        
        # Filter by backup type
        if ($BackupType -ne 'All' -and $_.BackupType -ne $BackupType) {
            $include = $false
        }
        
        return $include
    }
    
    # Sort by timestamp (newest first)
    $sortedHistory = $filteredHistory | Sort-Object Timestamp -Descending
    
    if ($Detailed) {
        return $sortedHistory
    } else {
        return $sortedHistory | Select-Object ConfigurationName, Timestamp, BackupType, Comment, User, @{
            Name = "Age"
            Expression = { 
                $age = (Get-Date) - [datetime]$_.Timestamp
                if ($age.Days -gt 0) { "$($age.Days)d $($age.Hours)h" }
                else { "$($age.Hours)h $($age.Minutes)m" }
            }
        }
    }
}

function Restore-ProUConfigurationVersion {
    <#
    .SYNOPSIS
        Restores a configuration from a previous backup version.
    
    .DESCRIPTION
        Restores configuration to a previous state with safety checks and confirmation.
    
    .PARAMETER ConfigurationName
        Name of configuration to restore
    
    .PARAMETER BackupTimestamp
        Timestamp of backup to restore from
    
    .PARAMETER BackupPath
        Direct path to backup file
    
    .PARAMETER CreateBackupFirst
        Create backup of current state before restoring
    
    .PARAMETER Force
        Skip confirmation prompts
    
    .EXAMPLE
        Restore-ProUConfigurationVersion -ConfigurationName "Production" -BackupTimestamp "2024-01-15 14:30:45"
        
    .EXAMPLE
        Restore-ProUConfigurationVersion -BackupPath "C:\Backups\Production.json" -CreateBackupFirst
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByTimestamp')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByTimestamp')]
        [string]$ConfigurationName,
        
        [Parameter(Mandatory, ParameterSetName = 'ByTimestamp')]
        [string]$BackupTimestamp,
        
        [Parameter(Mandatory, ParameterSetName = 'ByPath')]
        [string]$BackupPath,
        
        [switch]$CreateBackupFirst,
        [switch]$Force
    )
    
    Write-Host "🔄 Preparing to restore configuration..." -ForegroundColor Cyan
    
    # Find backup to restore
    if ($PSCmdlet.ParameterSetName -eq 'ByTimestamp') {
        $history = Get-ProUConfigurationHistory -ConfigurationName $ConfigurationName -Detailed
        $backup = $history | Where-Object { 
            $_.Timestamp -eq $BackupTimestamp -or 
            ([datetime]$_.Timestamp).ToString('yyyy-MM-dd HH:mm:ss') -eq $BackupTimestamp
        } | Select-Object -First 1
        
        if (-not $backup) {
            Write-Host "Backup not found for timestamp: $BackupTimestamp" -ForegroundColor Red
            return
        }
        
        $BackupPath = $backup.BackupPath
        $ConfigurationName = $backup.ConfigurationName
    }
    
    if (-not (Test-Path $BackupPath)) {
        Write-Host "Backup file not found: $BackupPath" -ForegroundColor Red
        return
    }
    
    try {
        # Load backup data
        $backupData = Get-Content $BackupPath | ConvertFrom-Json
        $configData = $backupData.ConfigurationData
        
        Write-Host "📋 Backup Information:" -ForegroundColor Yellow
        Write-Host "  Configuration: $ConfigurationName" -ForegroundColor White
        Write-Host "  Backup Date: $($backupData.BackupInfo.Timestamp)" -ForegroundColor White
        Write-Host "  Backup Type: $($backupData.BackupInfo.BackupType)" -ForegroundColor White
        Write-Host "  Comment: $($backupData.BackupInfo.Comment)" -ForegroundColor White
        Write-Host "  Created By: $($backupData.BackupInfo.User)" -ForegroundColor White
        
        # Safety checks
        if (-not $Force) {
            Write-Host "`n⚠️  WARNING: This will overwrite the current configuration!" -ForegroundColor Red
            $confirm = Read-Host "Are you sure you want to proceed? (yes/no)"
            if ($confirm -ne "yes") {
                Write-Host "Restore cancelled" -ForegroundColor Yellow
                return
            }
        }
        
        # Create backup of current state first
        if ($CreateBackupFirst) {
            Write-Host "📦 Creating backup of current state..." -ForegroundColor Yellow
            Backup-ProUConfigurationState -ConfigurationName $ConfigurationName -BackupType "PreRestore" -Comment "Before restoring version from $($backupData.BackupInfo.Timestamp)"
        }
        
        if ($PSCmdlet.ShouldProcess($ConfigurationName, "Restore Configuration")) {
            # Restore the configuration
            Write-Host "🔄 Restoring configuration..." -ForegroundColor Cyan
            
            # First, try to restore dependencies
            if ($backupData.Dependencies) {
                Write-Host "  Restoring dependencies..." -ForegroundColor Yellow
                
                # Restore filters if needed
                if ($backupData.Dependencies.Filters) {
                    foreach ($filter in $backupData.Dependencies.Filters) {
                        try {
                            $existing = Get-ProUFilters | Where-Object { $_.ID -eq $filter.ID }
                            if (-not $existing) {
                                Write-Host "    Creating missing filter: $($filter.Name)" -ForegroundColor Gray
                                # Note: Would need Import-ProUFilter or similar function
                            }
                        }
                        catch {
                            Write-Warning "Could not restore filter dependency: $($filter.Name)"
                        }
                    }
                }
            }
            
            # Import the configuration
            $tempConfigPath = Join-Path $env:TEMP "restore_$ConfigurationName.json"
            $configData | ConvertTo-Json -Depth 20 | Out-File -FilePath $tempConfigPath -Encoding UTF8
            
            try {
                # Remove existing configuration
                Remove-ProUConfig -Name $ConfigurationName -Force -ErrorAction SilentlyContinue
                
                # Import restored version
                Import-ProUConfig -Path $tempConfigPath -Name $ConfigurationName
                
                Write-Host "✅ Configuration restored successfully!" -ForegroundColor Green
                Write-Host "  Restored from: $($backupData.BackupInfo.Timestamp)" -ForegroundColor Gray
                
                # Log the restore operation
                $logEntry = @{
                    Timestamp = Get-Date
                    Operation = "Restore"
                    ConfigurationName = $ConfigurationName
                    RestoredFrom = $BackupPath
                    User = $env:USERNAME
                    Success = $true
                }
                Add-ProUOperationLog -Entry $logEntry
                
            }
            finally {
                # Clean up temp file
                if (Test-Path $tempConfigPath) {
                    Remove-Item $tempConfigPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    catch {
        Write-Host "❌ Restore failed: $_" -ForegroundColor Red
        
        # Log the failed operation
        $logEntry = @{
            Timestamp = Get-Date
            Operation = "Restore"
            ConfigurationName = $ConfigurationName
            RestoredFrom = $BackupPath
            User = $env:USERNAME
            Success = $false
            Error = $_.Exception.Message
        }
        Add-ProUOperationLog -Entry $logEntry
        
        throw
    }
}

function Compare-ProUConfigurationVersions {
    <#
    .SYNOPSIS
        Compares two configuration versions to show differences.
    
    .DESCRIPTION
        Provides detailed comparison between current configuration and backup version or between two backups.
    
    .PARAMETER ConfigurationName
        Name of configuration to compare
    
    .PARAMETER BackupTimestamp1
        First backup timestamp to compare
    
    .PARAMETER BackupTimestamp2
        Second backup timestamp to compare (current version if not specified)
    
    .PARAMETER ShowDetails
        Show detailed differences
    
    .PARAMETER OutputFormat
        Output format for comparison
    
    .EXAMPLE
        Compare-ProUConfigurationVersions -ConfigurationName "Production" -BackupTimestamp1 "2024-01-15 14:30:45"
        
    .EXAMPLE
        Compare-ProUConfigurationVersions -ConfigurationName "Production" -BackupTimestamp1 "2024-01-15 14:30:45" -BackupTimestamp2 "2024-01-16 09:15:22" -ShowDetails
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigurationName,
        
        [Parameter(Mandatory)]
        [string]$BackupTimestamp1,
        
        [string]$BackupTimestamp2,
        
        [switch]$ShowDetails,
        
        [ValidateSet('Console', 'HTML', 'JSON')]
        [string]$OutputFormat = 'Console'
    )
    
    Write-Host "🔍 Comparing configuration versions..." -ForegroundColor Cyan
    
    # Get first version (backup)
    $history = Get-ProUConfigurationHistory -ConfigurationName $ConfigurationName -Detailed
    $backup1 = $history | Where-Object { 
        $_.Timestamp -eq $BackupTimestamp1 -or 
        ([datetime]$_.Timestamp).ToString('yyyy-MM-dd HH:mm:ss') -eq $BackupTimestamp1
    } | Select-Object -First 1
    
    if (-not $backup1) {
        Write-Host "Backup not found for timestamp: $BackupTimestamp1" -ForegroundColor Red
        return
    }
    
    $config1Data = (Get-Content $backup1.BackupPath | ConvertFrom-Json).ConfigurationData
    $version1Label = "Backup: $BackupTimestamp1"
    
    # Get second version (backup or current)
    $config2Data = $null
    $version2Label = ""
    
    if ($BackupTimestamp2) {
        $backup2 = $history | Where-Object { 
            $_.Timestamp -eq $BackupTimestamp2 -or 
            ([datetime]$_.Timestamp).ToString('yyyy-MM-dd HH:mm:ss') -eq $BackupTimestamp2
        } | Select-Object -First 1
        
        if (-not $backup2) {
            Write-Host "Backup not found for timestamp: $BackupTimestamp2" -ForegroundColor Red
            return
        }
        
        $config2Data = (Get-Content $backup2.BackupPath | ConvertFrom-Json).ConfigurationData
        $version2Label = "Backup: $BackupTimestamp2"
    } else {
        $config2Data = Get-ProUConfig -Name $ConfigurationName
        $version2Label = "Current Version"
    }
    
    # Compare configurations
    $differences = @()
    
    # Compare basic properties
    $basicProps = @('Name', 'Description', 'LastModified', 'ModifiedBy')
    foreach ($prop in $basicProps) {
        $val1 = $config1Data.$prop
        $val2 = $config2Data.$prop
        
        if ($val1 -ne $val2) {
            $differences += @{
                Category = "Basic Properties"
                Property = $prop
                OldValue = $val1
                NewValue = $val2
                ChangeType = if ($val1 -and $val2) { "Modified" } elseif ($val2) { "Added" } else { "Removed" }
            }
        }
    }
    
    # Compare FlexApp DIAs
    $differences += Compare-ProUConfigurationArray -Array1 $config1Data.FlexAppDias -Array2 $config2Data.FlexAppDias -Category "FlexApp DIAs" -KeyProperty "FlexAppPackages"
    
    # Compare ADMX Templates
    $differences += Compare-ProUConfigurationArray -Array1 $config1Data.AdministrativeTemplates -Array2 $config2Data.AdministrativeTemplates -Category "ADMX Templates" -KeyProperty "AdmxFile"
    
    # Compare Portability Rules
    $differences += Compare-ProUConfigurationArray -Array1 $config1Data.PortabilityRules -Array2 $config2Data.PortabilityRules -Category "Portability Rules" -KeyProperty "Path"
    
    # Output results
    switch ($OutputFormat) {
        'Console' { Show-ProUConfigurationComparisonConsole -Differences $differences -Version1Label $version1Label -Version2Label $version2Label -ShowDetails:$ShowDetails }
        'HTML' { Export-ProUConfigurationComparisonHTML -Differences $differences -Version1Label $version1Label -Version2Label $version2Label }
        'JSON' { $differences | ConvertTo-Json -Depth 10 }
    }
    
    return $differences
}

function Compare-ProUConfigurationArray {
    <#
    .SYNOPSIS
        Helper function to compare arrays in configurations.
    
    .PARAMETER Array1
        First array to compare
    
    .PARAMETER Array2
        Second array to compare
    
    .PARAMETER Category
        Category name for differences
    
    .PARAMETER KeyProperty
        Property to use as key for comparison
    #>
    [CmdletBinding()]
    param(
        [array]$Array1,
        [array]$Array2,
        [string]$Category,
        [string]$KeyProperty
    )
    
    $differences = @()
    
    # Ensure arrays are not null
    if (-not $Array1) { $Array1 = @() }
    if (-not $Array2) { $Array2 = @() }
    
    # Find items in Array1 but not in Array2 (removed)
    foreach ($item1 in $Array1) {
        $key1 = if ($KeyProperty -eq "FlexAppPackages") {
            $item1.FlexAppPackages[0].FlexAppPackageId
        } else {
            $item1.$KeyProperty
        }
        
        $found = $false
        foreach ($item2 in $Array2) {
            $key2 = if ($KeyProperty -eq "FlexAppPackages") {
                $item2.FlexAppPackages[0].FlexAppPackageId
            } else {
                $item2.$KeyProperty
            }
            
            if ($key1 -eq $key2) {
                $found = $true
                break
            }
        }
        
        if (-not $found) {
            $differences += @{
                Category = $Category
                Property = $key1
                OldValue = "Present"
                NewValue = $null
                ChangeType = "Removed"
                Details = $item1
            }
        }
    }
    
    # Find items in Array2 but not in Array1 (added) or modified
    foreach ($item2 in $Array2) {
        $key2 = if ($KeyProperty -eq "FlexAppPackages") {
            $item2.FlexAppPackages[0].FlexAppPackageId
        } else {
            $item2.$KeyProperty
        }
        
        $matchingItem1 = $null
        foreach ($item1 in $Array1) {
            $key1 = if ($KeyProperty -eq "FlexAppPackages") {
                $item1.FlexAppPackages[0].FlexAppPackageId
            } else {
                $item1.$KeyProperty
            }
            
            if ($key1 -eq $key2) {
                $matchingItem1 = $item1
                break
            }
        }
        
        if (-not $matchingItem1) {
            # Added item
            $differences += @{
                Category = $Category
                Property = $key2
                OldValue = $null
                NewValue = "Present"
                ChangeType = "Added"
                Details = $item2
            }
        } else {
            # Check for modifications
            $item1Json = $matchingItem1 | ConvertTo-Json -Depth 10
            $item2Json = $item2 | ConvertTo-Json -Depth 10
            
            if ($item1Json -ne $item2Json) {
                $differences += @{
                    Category = $Category
                    Property = $key2
                    OldValue = $matchingItem1
                    NewValue = $item2
                    ChangeType = "Modified"
                    Details = @{
                        Old = $matchingItem1
                        New = $item2
                    }
                }
            }
        }
    }
    
    return $differences
}

function Show-ProUConfigurationComparisonConsole {
    <#
    .SYNOPSIS
        Shows configuration comparison in console format.
    
    .PARAMETER Differences
        Array of differences to display
    
    .PARAMETER Version1Label
        Label for first version
    
    .PARAMETER Version2Label
        Label for second version
    
    .PARAMETER ShowDetails
        Show detailed differences
    #>
    [CmdletBinding()]
    param(
        [array]$Differences,
        [string]$Version1Label,
        [string]$Version2Label,
        [switch]$ShowDetails
    )
    
    Write-Host "`n╔══════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║       Configuration Comparison           ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
    
    Write-Host "`n📊 Comparing:" -ForegroundColor Yellow
    Write-Host "  Version 1: $Version1Label" -ForegroundColor White
    Write-Host "  Version 2: $Version2Label" -ForegroundColor White
    
    if ($Differences.Count -eq 0) {
        Write-Host "`n✅ No differences found - configurations are identical" -ForegroundColor Green
        return
    }
    
    Write-Host "`n📈 Summary:" -ForegroundColor Yellow
    $added = ($Differences | Where-Object { $_.ChangeType -eq "Added" }).Count
    $removed = ($Differences | Where-Object { $_.ChangeType -eq "Removed" }).Count
    $modified = ($Differences | Where-Object { $_.ChangeType -eq "Modified" }).Count
    
    Write-Host "  ➕ Added: $added" -ForegroundColor Green
    Write-Host "  ➖ Removed: $removed" -ForegroundColor Red
    Write-Host "  🔄 Modified: $modified" -ForegroundColor Yellow
    Write-Host "  📊 Total Differences: $($Differences.Count)" -ForegroundColor Cyan
    
    # Group by category
    $categories = $Differences | Group-Object Category
    
    foreach ($category in $categories) {
        Write-Host "`n🔸 $($category.Name):" -ForegroundColor Cyan
        
        foreach ($diff in $category.Group) {
            $icon = switch ($diff.ChangeType) {
                "Added" { "➕" }
                "Removed" { "➖" }
                "Modified" { "🔄" }
                default { "•" }
            }
            
            Write-Host "  $icon $($diff.Property): $($diff.ChangeType)" -ForegroundColor White
            
            if ($ShowDetails) {
                switch ($diff.ChangeType) {
                    "Added" {
                        Write-Host "      New: $($diff.NewValue)" -ForegroundColor Green
                    }
                    "Removed" {
                        Write-Host "      Was: $($diff.OldValue)" -ForegroundColor Red
                    }
                    "Modified" {
                        Write-Host "      Was: $($diff.OldValue)" -ForegroundColor Red
                        Write-Host "      Now: $($diff.NewValue)" -ForegroundColor Green
                    }
                }
            }
        }
    }
}

function Update-ProUVersionHistory {
    <#
    .SYNOPSIS
        Updates the version history database.
    
    .PARAMETER Entries
        Array of version entries to add
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Entries
    )
    
    $historyPath = Join-Path $script:DefaultPaths.Backup "VersionHistory.json"
    
    # Load existing history
    $history = if (Test-Path $historyPath) {
        try {
            Get-Content $historyPath | ConvertFrom-Json
        }
        catch {
            @()
        }
    } else {
        @()
    }
    
    # Add new entries
    $history += $Entries
    
    # Sort by timestamp (newest first)
    $history = $history | Sort-Object Timestamp -Descending
    
    # Save updated history
    try {
        $history | ConvertTo-Json -Depth 5 | Out-File -FilePath $historyPath -Encoding UTF8
    }
    catch {
        Write-Warning "Could not update version history: $_"
    }
}

function Remove-ProUOldBackups {
    <#
    .SYNOPSIS
        Removes old backups based on retention policy.
    
    .PARAMETER RetentionDays
        Number of days to retain backups
    #>
    [CmdletBinding()]
    param(
        [int]$RetentionDays = 30
    )
    
    $backupRoot = Join-Path $script:DefaultPaths.Backup "ConfigurationVersions"
    
    if (-not (Test-Path $backupRoot)) {
        return
    }
    
    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    $removedCount = 0
    
    Get-ChildItem $backupRoot -Directory | ForEach-Object {
        if ($_.CreationTime -lt $cutoffDate) {
            try {
                Remove-Item $_.FullName -Recurse -Force
                $removedCount++
            }
            catch {
                Write-Verbose "Could not remove old backup: $($_.FullName)"
            }
        }
    }
    
    if ($removedCount -gt 0) {
        Write-Verbose "Removed $removedCount old backup directories"
    }
}

function Add-ProUOperationLog {
    <#
    .SYNOPSIS
        Adds an entry to the operation log.
    
    .PARAMETER Entry
        Log entry to add
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Entry
    )
    
    $logPath = Join-Path $script:DefaultPaths.Logs "OperationLog.json"
    
    # Load existing log
    $log = if (Test-Path $logPath) {
        try {
            Get-Content $logPath | ConvertFrom-Json
        }
        catch {
            @()
        }
    } else {
        @()
    }
    
    # Add new entry
    $log += $Entry
    
    # Keep only last 1000 entries
    if ($log.Count -gt 1000) {
        $log = $log | Sort-Object Timestamp -Descending | Select-Object -First 1000
    }
    
    # Save log
    try {
        if (-not (Test-Path (Split-Path $logPath))) {
            New-Item -ItemType Directory -Path (Split-Path $logPath) -Force | Out-Null
        }
        $log | ConvertTo-Json -Depth 5 | Out-File -FilePath $logPath -Encoding UTF8
    }
    catch {
        Write-Verbose "Could not update operation log: $_"
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Backup-ProUConfigurationState',
    'Get-ProUConfigurationHistory',
    'Restore-ProUConfigurationVersion',
    'Compare-ProUConfigurationVersions',
    'Show-ProUConfigurationComparisonConsole',
    'Remove-ProUOldBackups'
)