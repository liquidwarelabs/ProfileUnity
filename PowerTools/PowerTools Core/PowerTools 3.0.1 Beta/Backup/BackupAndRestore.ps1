# BackupAndRestore.ps1 - ProfileUnity Backup and Restore Functions

function Backup-ProUEnvironment {
    <#
    .SYNOPSIS
        Creates a complete backup of the ProfileUnity environment.
    
    .DESCRIPTION
        Backs up configurations, filters, portability rules, FlexApps, and settings.
    
    .PARAMETER BackupPath
        Directory to save the backup
    
    .PARAMETER IncludeFlexApps
        Include FlexApp package exports
    
    .PARAMETER IncludeAuditLog
        Include recent audit log entries
    
    .PARAMETER CompressBackup
        Create a compressed backup archive
    
    .EXAMPLE
        Backup-ProUEnvironment -BackupPath "C:\Backups"
        
    .EXAMPLE
        Backup-ProUEnvironment -BackupPath "D:\Backups" -IncludeFlexApps -CompressBackup
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath,
        
        [switch]$IncludeFlexApps,
        
        [switch]$IncludeAuditLog,
        
        [switch]$CompressBackup
    )
    
    Begin {
        Assert-ProfileUnityConnection
        
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backupName = "ProfileUnity_Backup_$timestamp"
        $workingPath = Join-Path $BackupPath $backupName
        
        Write-Host "Starting ProfileUnity environment backup..." -ForegroundColor Cyan
        Write-Host "Backup location: $workingPath" -ForegroundColor Yellow
    }
    
    Process {
        try {
            # Create backup directory structure
            $directories = @(
                $workingPath,
                "$workingPath\Configurations",
                "$workingPath\Filters", 
                "$workingPath\PortabilityRules",
                "$workingPath\FlexApps",
                "$workingPath\Reports",
                "$workingPath\Metadata"
            )
            
            foreach ($dir in $directories) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            
            $backupSummary = @{
                BackupDate = Get-Date
                ServerName = $script:ModuleConfig.ServerName
                BackupPath = $workingPath
                Items = @{
                    Configurations = 0
                    Filters = 0
                    PortabilityRules = 0
                    FlexApps = 0
                }
                Errors = @()
            }
            
            # Backup configurations
            try {
                Write-Host "Backing up configurations..." -ForegroundColor Yellow
                $configurations = Get-ProUConfig
                
                foreach ($config in $configurations) {
                    try {
                        $configName = $config.name -replace '[\\/:*?"<>|]', '_'
                        $configPath = Join-Path "$workingPath\Configurations" "$configName.json"
                        
                        $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8
                        $backupSummary.Items.Configurations++
                        
                        Write-Host "  Exported: $($config.name)" -ForegroundColor Green
                    }
                    catch {
                        $error = "Failed to backup configuration '$($config.name)': $_"
                        $backupSummary.Errors += $error
                        Write-Warning $error
                    }
                }
            }
            catch {
                $error = "Failed to backup configurations: $_"
                $backupSummary.Errors += $error
                Write-Warning $error
            }
            
            # Backup filters
            try {
                Write-Host "Backing up filters..." -ForegroundColor Yellow
                $filters = Get-ProUFilter
                
                foreach ($filter in $filters) {
                    try {
                        $filterName = $filter.name -replace '[\\/:*?"<>|]', '_'
                        $filterPath = Join-Path "$workingPath\Filters" "$filterName.json"
                        
                        $filter | ConvertTo-Json -Depth 10 | Set-Content -Path $filterPath -Encoding UTF8
                        $backupSummary.Items.Filters++
                        
                        Write-Host "  Exported: $($filter.name)" -ForegroundColor Green
                    }
                    catch {
                        $error = "Failed to backup filter '$($filter.name)': $_"
                        $backupSummary.Errors += $error
                        Write-Warning $error
                    }
                }
            }
            catch {
                $error = "Failed to backup filters: $_"
                $backupSummary.Errors += $error
                Write-Warning $error
            }
            
            # Backup portability rules
            try {
                Write-Host "Backing up portability rules..." -ForegroundColor Yellow
                $portabilityRules = Get-ProUPortabilityRule
                
                foreach ($rule in $portabilityRules) {
                    try {
                        $ruleName = $rule.name -replace '[\\/:*?"<>|]', '_'
                        $rulePath = Join-Path "$workingPath\PortabilityRules" "$ruleName.json"
                        
                        $rule | ConvertTo-Json -Depth 10 | Set-Content -Path $rulePath -Encoding UTF8
                        $backupSummary.Items.PortabilityRules++
                        
                        Write-Host "  Exported: $($rule.name)" -ForegroundColor Green
                    }
                    catch {
                        $error = "Failed to backup portability rule '$($rule.name)': $_"
                        $backupSummary.Errors += $error
                        Write-Warning $error
                    }
                }
            }
            catch {
                $error = "Failed to backup portability rules: $_"
                $backupSummary.Errors += $error
                Write-Warning $error
            }
            
            # Backup FlexApps if requested
            if ($IncludeFlexApps) {
                try {
                    Write-Host "Backing up FlexApps..." -ForegroundColor Yellow
                    $flexApps = Get-ProUFlexApp
                    
                    # Create FlexApp inventory
                    $flexAppInventory = @()
                    
                    foreach ($flexApp in $flexApps) {
                        try {
                            $flexAppName = $flexApp.name -replace '[\\/:*?"<>|]', '_'
                            $packagePath = Join-Path "$workingPath\FlexApps" "$flexAppName.json"
                            
                            # Export FlexApp details
                            $flexApp | ConvertTo-Json -Depth 10 | Set-Content -Path $packagePath -Encoding UTF8
                            $flexAppInventory += $flexApp
                            $backupSummary.Items.FlexApps++
                            
                            Write-Host "  Exported: $($flexApp.name)" -ForegroundColor Green
                        }
                        catch {
                            $error = "Failed to backup FlexApp '$($flexApp.name)': $_"
                            $backupSummary.Errors += $error
                            Write-Warning $error
                        }
                    }
                    
                    # Save FlexApp inventory
                    $inventoryPath = Join-Path "$workingPath\FlexApps" "FlexApp_Inventory.json"
                    $flexAppInventory | ConvertTo-Json -Depth 10 | Set-Content -Path $inventoryPath -Encoding UTF8
                }
                catch {
                    $error = "Failed to backup FlexApps: $_"
                    $backupSummary.Errors += $error
                    Write-Warning $error
                }
            }
            
            # Include audit log if requested
            if ($IncludeAuditLog) {
                try {
                    Write-Host "Backing up audit log..." -ForegroundColor Yellow
                    $auditLog = Get-ProUAuditLog -Days 30
                    
                    if ($auditLog) {
                        $auditPath = Join-Path "$workingPath\Reports" "AuditLog_Last30Days.json"
                        $auditLog | ConvertTo-Json -Depth 10 | Set-Content -Path $auditPath -Encoding UTF8
                        Write-Host "  Exported audit log (last 30 days)" -ForegroundColor Green
                    }
                }
                catch {
                    $error = "Failed to backup audit log: $_"
                    $backupSummary.Errors += $error
                    Write-Warning $error
                }
            }
            
            # Save backup summary
            $summaryPath = Join-Path "$workingPath\Metadata" "BackupSummary.json"
            $backupSummary | ConvertTo-Json -Depth 10 | Set-Content -Path $summaryPath -Encoding UTF8
            
            # Create restore script
            $restoreScript = @"
# ProfileUnity Restore Script
# Generated: $(Get-Date)
# Backup: $workingPath

Write-Host "ProfileUnity Environment Restore" -ForegroundColor Cyan
Write-Host "Backup: $workingPath" -ForegroundColor Yellow

try {
    Import-Module ProfileUnity-PowerTools
    Connect-ProfileUnityServer
    
    Restore-ProUEnvironment -BackupPath "$workingPath"
    
    Write-Host "Restore completed successfully!" -ForegroundColor Green
}
catch {
    Write-Error "Restore failed: $_"
}

Write-Host "Review logs for any errors." -ForegroundColor Green
"@
            $restoreScript | Set-Content -Path "$workingPath\RestoreEnvironment.ps1" -Encoding UTF8
            
            # Compress backup if requested
            if ($CompressBackup) {
                Write-Host "Compressing backup..." -ForegroundColor Yellow
                $archivePath = "$BackupPath\$backupName.zip"
                
                try {
                    # Use .NET compression
                    Add-Type -AssemblyName System.IO.Compression.FileSystem
                    [System.IO.Compression.ZipFile]::CreateFromDirectory($workingPath, $archivePath)
                    
                    # Remove uncompressed directory
                    Remove-Item -Path $workingPath -Recurse -Force
                    
                    Write-Host "  Backup compressed: $archivePath" -ForegroundColor Green
                    $finalPath = $archivePath
                }
                catch {
                    Write-Warning "Compression failed: $_"
                    $finalPath = $workingPath
                }
            }
            else {
                $finalPath = $workingPath
            }
            
            # Display summary
            Write-Host "`nBackup Summary:" -ForegroundColor Cyan
            Write-Host "  Configurations: $($backupSummary.Items.Configurations)" -ForegroundColor Green
            Write-Host "  Filters: $($backupSummary.Items.Filters)" -ForegroundColor Green
            Write-Host "  Portability Rules: $($backupSummary.Items.PortabilityRules)" -ForegroundColor Green
            Write-Host "  FlexApps: $($backupSummary.Items.FlexApps)" -ForegroundColor Green
            
            if ($backupSummary.Errors.Count -gt 0) {
                Write-Host "  Errors: $($backupSummary.Errors.Count)" -ForegroundColor Red
            }
            
            Write-Host "`nBackup location: $finalPath" -ForegroundColor Green
            Write-LogMessage -Message "ProfileUnity backup completed: $finalPath" -Level Info
            
            return [PSCustomObject]@{
                BackupPath = $finalPath
                Summary = $backupSummary
                Success = $backupSummary.Errors.Count -eq 0
            }
        }
        catch {
            Write-Error "Backup failed: $_"
            Write-LogMessage -Message "ProfileUnity backup failed: $_" -Level Error
            throw
        }
    }
}

function Restore-ProUEnvironment {
    <#
    .SYNOPSIS
        Restores a ProfileUnity environment from backup.
    
    .DESCRIPTION
        Restores configurations, filters, and portability rules from a backup directory.
    
    .PARAMETER BackupPath
        Path to the backup directory or ZIP file
    
    .PARAMETER RestoreConfigurations
        Restore configurations (default: true)
    
    .PARAMETER RestoreFilters
        Restore filters (default: true)
    
    .PARAMETER RestorePortabilityRules
        Restore portability rules (default: true)
    
    .PARAMETER AddPrefix
        Prefix to add to restored items to avoid conflicts
    
    .PARAMETER WhatIf
        Show what would be restored without actually restoring
    
    .EXAMPLE
        Restore-ProUEnvironment -BackupPath "C:\Backups\ProfileUnity_Backup_20241201_143022"
        
    .EXAMPLE
        Restore-ProUEnvironment -BackupPath "C:\Backups\backup.zip" -AddPrefix "Restored_"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath,
        
        [bool]$RestoreConfigurations = $true,
        
        [bool]$RestoreFilters = $true,
        
        [bool]$RestorePortabilityRules = $true,
        
        [string]$AddPrefix = "",
        
        [switch]$WhatIf
    )
    
    Begin {
        Assert-ProfileUnityConnection
        
        Write-Host "Starting ProfileUnity environment restore..." -ForegroundColor Cyan
        Write-Host "Backup source: $BackupPath" -ForegroundColor Yellow
    }
    
    Process {
        try {
            $workingPath = $BackupPath
            $tempExtracted = $false
            
            # Extract ZIP if needed
            if ([System.IO.Path]::GetExtension($BackupPath) -eq '.zip') {
                Write-Host "Extracting backup archive..." -ForegroundColor Yellow
                
                $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) "ProfileUnity_Restore_$([Guid]::NewGuid().ToString('N')[0..7] -join '')"
                
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                [System.IO.Compression.ZipFile]::ExtractToDirectory($BackupPath, $tempPath)
                
                # Find the backup directory inside extracted content
                $backupDirs = Get-ChildItem -Path $tempPath -Directory | Where-Object { $_.Name -like "ProfileUnity_Backup_*" }
                if ($backupDirs) {
                    $workingPath = $backupDirs[0].FullName
                }
                else {
                    $workingPath = $tempPath
                }
                
                $tempExtracted = $true
                Write-Host "  Extracted to: $workingPath" -ForegroundColor Green
            }
            
            if (-not (Test-Path $workingPath)) {
                throw "Backup path not found: $workingPath"
            }
            
            # Load backup summary if available
            $summaryPath = Join-Path $workingPath "Metadata\BackupSummary.json"
            $backupInfo = $null
            if (Test-Path $summaryPath) {
                try {
                    $backupInfo = Get-Content $summaryPath -Raw | ConvertFrom-Json
                    Write-Host "Backup info: Created $($backupInfo.BackupDate) from server $($backupInfo.ServerName)" -ForegroundColor Gray
                }
                catch {
                    Write-Warning "Could not read backup summary"
                }
            }
            
            $restoreResults = @{
                Configurations = @{ Attempted = 0; Successful = 0; Failed = 0 }
                Filters = @{ Attempted = 0; Successful = 0; Failed = 0 }
                PortabilityRules = @{ Attempted = 0; Successful = 0; Failed = 0 }
                Errors = @()
            }
            
            # Restore configurations
            if ($RestoreConfigurations) {
                $configPath = Join-Path $workingPath "Configurations"
                if (Test-Path $configPath) {
                    Write-Host "Restoring configurations..." -ForegroundColor Yellow
                    
                    $configFiles = Get-ChildItem -Path $configPath -Filter "*.json"
                    $restoreResults.Configurations.Attempted = $configFiles.Count
                    
                    foreach ($configFile in $configFiles) {
                        try {
                            $configData = Get-Content $configFile.FullName -Raw | ConvertFrom-Json
                            $originalName = $configData.name
                            $newName = "$AddPrefix$originalName"
                            
                            if ($WhatIf) {
                                Write-Host "  Would restore: $originalName as $newName" -ForegroundColor Cyan
                            }
                            else {
                                # Modify name if prefix specified
                                if ($AddPrefix) {
                                    $configData.name = $newName
                                }
                                
                                # Import configuration
                                $result = New-ProUConfig -ConfigurationData $configData
                                
                                if ($result) {
                                    Write-Host "  Restored: $newName" -ForegroundColor Green
                                    $restoreResults.Configurations.Successful++
                                }
                                else {
                                    Write-Warning "  Failed to restore: $newName"
                                    $restoreResults.Configurations.Failed++
                                    $restoreResults.Errors += "Failed to restore configuration: $newName"
                                }
                            }
                        }
                        catch {
                            Write-Warning "  Error restoring $($configFile.Name): $_"
                            $restoreResults.Configurations.Failed++
                            $restoreResults.Errors += "Error restoring configuration $($configFile.Name): $_"
                        }
                    }
                }
                else {
                    Write-Host "No configurations found in backup" -ForegroundColor Yellow
                }
            }
            
            # Restore filters
            if ($RestoreFilters) {
                $filterPath = Join-Path $workingPath "Filters"
                if (Test-Path $filterPath) {
                    Write-Host "Restoring filters..." -ForegroundColor Yellow
                    
                    $filterFiles = Get-ChildItem -Path $filterPath -Filter "*.json"
                    $restoreResults.Filters.Attempted = $filterFiles.Count
                    
                    foreach ($filterFile in $filterFiles) {
                        try {
                            $filterData = Get-Content $filterFile.FullName -Raw | ConvertFrom-Json
                            $originalName = $filterData.name
                            $newName = "$AddPrefix$originalName"
                            
                            if ($WhatIf) {
                                Write-Host "  Would restore: $originalName as $newName" -ForegroundColor Cyan
                            }
                            else {
                                # Modify name if prefix specified
                                if ($AddPrefix) {
                                    $filterData.name = $newName
                                }
                                
                                # Import filter
                                $result = New-ProUFilter -FilterData $filterData
                                
                                if ($result) {
                                    Write-Host "  Restored: $newName" -ForegroundColor Green
                                    $restoreResults.Filters.Successful++
                                }
                                else {
                                    Write-Warning "  Failed to restore: $newName"
                                    $restoreResults.Filters.Failed++
                                    $restoreResults.Errors += "Failed to restore filter: $newName"
                                }
                            }
                        }
                        catch {
                            Write-Warning "  Error restoring $($filterFile.Name): $_"
                            $restoreResults.Filters.Failed++
                            $restoreResults.Errors += "Error restoring filter $($filterFile.Name): $_"
                        }
                    }
                }
                else {
                    Write-Host "No filters found in backup" -ForegroundColor Yellow
                }
            }
            
            # Restore portability rules
            if ($RestorePortabilityRules) {
                $portabilityPath = Join-Path $workingPath "PortabilityRules"
                if (Test-Path $portabilityPath) {
                    Write-Host "Restoring portability rules..." -ForegroundColor Yellow
                    
                    $ruleFiles = Get-ChildItem -Path $portabilityPath -Filter "*.json"
                    $restoreResults.PortabilityRules.Attempted = $ruleFiles.Count
                    
                    foreach ($ruleFile in $ruleFiles) {
                        try {
                            $ruleData = Get-Content $ruleFile.FullName -Raw | ConvertFrom-Json
                            $originalName = $ruleData.name
                            $newName = "$AddPrefix$originalName"
                            
                            if ($WhatIf) {
                                Write-Host "  Would restore: $originalName as $newName" -ForegroundColor Cyan
                            }
                            else {
                                # Modify name if prefix specified
                                if ($AddPrefix) {
                                    $ruleData.name = $newName
                                }
                                
                                # Import portability rule
                                $result = New-ProUPortabilityRule -RuleData $ruleData
                                
                                if ($result) {
                                    Write-Host "  Restored: $newName" -ForegroundColor Green
                                    $restoreResults.PortabilityRules.Successful++
                                }
                                else {
                                    Write-Warning "  Failed to restore: $newName"
                                    $restoreResults.PortabilityRules.Failed++
                                    $restoreResults.Errors += "Failed to restore portability rule: $newName"
                                }
                            }
                        }
                        catch {
                            Write-Warning "  Error restoring $($ruleFile.Name): $_"
                            $restoreResults.PortabilityRules.Failed++
                            $restoreResults.Errors += "Error restoring portability rule $($ruleFile.Name): $_"
                        }
                    }
                }
                else {
                    Write-Host "No portability rules found in backup" -ForegroundColor Yellow
                }
            }
            
            # Cleanup temp extraction
            if ($tempExtracted) {
                try {
                    Remove-Item -Path (Split-Path $workingPath -Parent) -Recurse -Force
                }
                catch {
                    Write-Warning "Could not cleanup temporary extraction: $_"
                }
            }
            
            # Display summary
            if (-not $WhatIf) {
                Write-Host "`nRestore Summary:" -ForegroundColor Cyan
                Write-Host "  Configurations: $($restoreResults.Configurations.Successful)/$($restoreResults.Configurations.Attempted)" -ForegroundColor $(if ($restoreResults.Configurations.Failed -eq 0) { 'Green' } else { 'Yellow' })
                Write-Host "  Filters: $($restoreResults.Filters.Successful)/$($restoreResults.Filters.Attempted)" -ForegroundColor $(if ($restoreResults.Filters.Failed -eq 0) { 'Green' } else { 'Yellow' })
                Write-Host "  Portability Rules: $($restoreResults.PortabilityRules.Successful)/$($restoreResults.PortabilityRules.Attempted)" -ForegroundColor $(if ($restoreResults.PortabilityRules.Failed -eq 0) { 'Green' } else { 'Yellow' })
                
                if ($restoreResults.Errors.Count -gt 0) {
                    Write-Host "  Errors: $($restoreResults.Errors.Count)" -ForegroundColor Red
                }
                
                Write-LogMessage -Message "ProfileUnity restore completed from: $BackupPath" -Level Info
            }
            
            return [PSCustomObject]@{
                BackupPath = $BackupPath
                Results = $restoreResults
                Success = $restoreResults.Errors.Count -eq 0
            }
        }
        catch {
            Write-Error "Restore failed: $_"
            Write-LogMessage -Message "ProfileUnity restore failed: $_" -Level Error
            throw
        }
    }
}

function Get-ProUBackupInfo {
    <#
    .SYNOPSIS
        Gets information about a ProfileUnity backup.
    
    .DESCRIPTION
        Analyzes a backup directory or ZIP file and returns information about its contents.
    
    .PARAMETER BackupPath
        Path to the backup directory or ZIP file
    
    .EXAMPLE
        Get-ProUBackupInfo -BackupPath "C:\Backups\ProfileUnity_Backup_20241201_143022"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath
    )
    
    try {
        if (-not (Test-Path $BackupPath)) {
            throw "Backup path not found: $BackupPath"
        }
        
        $workingPath = $BackupPath
        $tempExtracted = $false
        
        # Extract ZIP if needed
        if ([System.IO.Path]::GetExtension($BackupPath) -eq '.zip') {
            $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) "ProfileUnity_BackupInfo_$([Guid]::NewGuid().ToString('N')[0..7] -join '')"
            
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::ExtractToDirectory($BackupPath, $tempPath)
            
            # Find the backup directory
            $backupDirs = Get-ChildItem -Path $tempPath -Directory | Where-Object { $_.Name -like "ProfileUnity_Backup_*" }
            if ($backupDirs) {
                $workingPath = $backupDirs[0].FullName
            }
            else {
                $workingPath = $tempPath
            }
            
            $tempExtracted = $true
        }
        
        $backupInfo = @{
            BackupPath = $BackupPath
            BackupType = if ([System.IO.Path]::GetExtension($BackupPath) -eq '.zip') { 'Compressed' } else { 'Directory' }
            Contents = @{}
            Summary = $null
            Size = 0
        }
        
        # Get backup summary if available
        $summaryPath = Join-Path $workingPath "Metadata\BackupSummary.json"
        if (Test-Path $summaryPath) {
            $backupInfo.Summary = Get-Content $summaryPath -Raw | ConvertFrom-Json
        }
        
        # Analyze contents
        $configPath = Join-Path $workingPath "Configurations"
        if (Test-Path $configPath) {
            $configFiles = Get-ChildItem -Path $configPath -Filter "*.json"
            $backupInfo.Contents.Configurations = $configFiles.Count
        }
        
        $filterPath = Join-Path $workingPath "Filters"
        if (Test-Path $filterPath) {
            $filterFiles = Get-ChildItem -Path $filterPath -Filter "*.json"
            $backupInfo.Contents.Filters = $filterFiles.Count
        }
        
        $portPath = Join-Path $workingPath "PortabilityRules"
        if (Test-Path $portPath) {
            $portFiles = Get-ChildItem -Path $portPath -Filter "*.json"
            $backupInfo.Contents.PortabilityRules = $portFiles.Count
        }
        
        $flexAppPath = Join-Path $workingPath "FlexApps\FlexApp_Inventory.json"
        if (Test-Path $flexAppPath) {
            $flexAppInventory = Get-Content $flexAppPath -Raw | ConvertFrom-Json
            $backupInfo.Contents.FlexApps = $flexAppInventory.Count
        }
        
        # Calculate size
        if (Test-Path $BackupPath) {
            if ([System.IO.Path]::GetExtension($BackupPath) -eq '.zip') {
                $backupInfo.Size = (Get-Item $BackupPath).Length
            }
            else {
                $backupInfo.Size = (Get-ChildItem -Path $BackupPath -Recurse | Measure-Object -Property Length -Sum).Sum
            }
        }
        
        # Cleanup temp extraction
        if ($tempExtracted) {
            Remove-Item -Path (Split-Path $workingPath -Parent) -Recurse -Force
        }
        
        return $backupInfo
    }
    catch {
        Write-Error "Failed to get backup info: $_"
        throw
    }
}

function Compare-ProUBackups {
    <#
    .SYNOPSIS
        Compares two ProfileUnity backups.
    
    .DESCRIPTION
        Analyzes and compares the contents of two backup directories or ZIP files.
    
    .PARAMETER BackupPath1
        Path to the first backup
    
    .PARAMETER BackupPath2
        Path to the second backup
    
    .EXAMPLE
        Compare-ProUBackups -BackupPath1 "C:\Backups\Old_Backup" -BackupPath2 "C:\Backups\New_Backup"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath1,
        
        [Parameter(Mandatory)]
        [string]$BackupPath2
    )
    
    try {
        Write-Host "Comparing ProfileUnity backups..." -ForegroundColor Yellow
        
        $backup1Info = Get-ProUBackupInfo -BackupPath $BackupPath1
        $backup2Info = Get-ProUBackupInfo -BackupPath $BackupPath2
        
        Write-Host "`nBackup Comparison:" -ForegroundColor Cyan
        Write-Host "Backup 1: $BackupPath1" -ForegroundColor Gray
        Write-Host "Backup 2: $BackupPath2" -ForegroundColor Gray
        Write-Host ""
        
        # Compare contents
        $contentTypes = @('Configurations', 'Filters', 'PortabilityRules', 'FlexApps')
        
        foreach ($type in $contentTypes) {
            $count1 = if ($backup1Info.Contents.$type) { $backup1Info.Contents.$type } else { 0 }
            $count2 = if ($backup2Info.Contents.$type) { $backup2Info.Contents.$type } else { 0 }
            
            $comparison = if ($count1 -eq $count2) {
                "Same ($count1)"
            }
            elseif ($count1 -gt $count2) {
                "$count1 vs $count2 (+$($count1 - $count2))"
            }
            else {
                "$count1 vs $count2 ($($count1 - $count2))"
            }
            
            Write-Host "$type : $comparison" -ForegroundColor White
        }
        
        # Compare dates if available
        if ($backup1Info.Summary -and $backup2Info.Summary) {
            Write-Host "`nBackup Dates:" -ForegroundColor Yellow
            Write-Host "  Backup 1: $($backup1Info.Summary.BackupDate)" -ForegroundColor Gray
            Write-Host "  Backup 2: $($backup2Info.Summary.BackupDate)" -ForegroundColor Gray
        }
        
        # Compare sizes
        Write-Host "`nBackup Sizes:" -ForegroundColor Yellow
        Write-Host "  Backup 1: $([math]::Round($backup1Info.Size / 1MB, 2)) MB" -ForegroundColor Gray
        Write-Host "  Backup 2: $([math]::Round($backup2Info.Size / 1MB, 2)) MB" -ForegroundColor Gray
        
        # Use if/else instead of null-coalescing operator for PowerShell compatibility
        $config1Count = if ($backup1Info.Contents.Configurations) { $backup1Info.Contents.Configurations } else { 0 }
        $config2Count = if ($backup2Info.Contents.Configurations) { $backup2Info.Contents.Configurations } else { 0 }
        $filter1Count = if ($backup1Info.Contents.Filters) { $backup1Info.Contents.Filters } else { 0 }
        $filter2Count = if ($backup2Info.Contents.Filters) { $backup2Info.Contents.Filters } else { 0 }
        $port1Count = if ($backup1Info.Contents.PortabilityRules) { $backup1Info.Contents.PortabilityRules } else { 0 }
        $port2Count = if ($backup2Info.Contents.PortabilityRules) { $backup2Info.Contents.PortabilityRules } else { 0 }
        $flex1Count = if ($backup1Info.Contents.FlexApps) { $backup1Info.Contents.FlexApps } else { 0 }
        $flex2Count = if ($backup2Info.Contents.FlexApps) { $backup2Info.Contents.FlexApps } else { 0 }
        
        return [PSCustomObject]@{
            Backup1 = $backup1Info
            Backup2 = $backup2Info
            Differences = @{
                Configurations = $config1Count - $config2Count
                Filters = $filter1Count - $filter2Count
                PortabilityRules = $port1Count - $port2Count
                FlexApps = $flex1Count - $flex2Count
            }
        }
    }
    catch {
        Write-Error "Failed to compare backups: $_"
        throw
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Backup-ProUEnvironment',
    'Restore-ProUEnvironment', 
    'Get-ProUBackupInfo',
    'Compare-ProUBackups'
)