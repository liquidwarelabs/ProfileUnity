# Configuration\VersionControl.ps1 - Version Control and Rollback System
# Relative Path: \Configuration\VersionControl.ps1

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
        Backup-ProUConfigurationState -ConfigurationName "Production" -BackupType "PreDeployment"
        
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
    
    try {
        Write-Host "Creating configuration state backup..." -ForegroundColor Cyan
        
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
        $backupRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ProfileUnity-Backups\ConfigurationVersions'
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
                $response = Invoke-ProfileUnityApi -Endpoint "configuration/$($config.id)/download?encoding=default" -OutFile $configBackupPath
                
                $backupResults += @{
                    Name = $config.Name
                    BackupPath = $configBackupPath
                    BackupTime = Get-Date
                    Success = $true
                }
                
                Write-Host "    Backup created: $configBackupPath" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to backup configuration '$($config.Name)': $_"
                $backupResults += @{
                    Name = $config.Name
                    BackupPath = $null
                    BackupTime = Get-Date
                    Success = $false
                    Error = $_.Exception.Message
                }
            }
        }
        
        # Create backup metadata
        $metadata = @{
            BackupId = [guid]::NewGuid().ToString()
            BackupType = $BackupType
            BackupTime = Get-Date
            Comment = $Comment
            Configurations = $backupResults
            CreatedBy = $env:USERNAME
            ComputerName = $env:COMPUTERNAME
        }
        
        $metadataPath = Join-Path $backupPath "backup-metadata.json"
        $metadata | ConvertTo-Json -Depth 5 | Out-File $metadataPath -Encoding UTF8
        
        Write-Host "Backup completed: $backupPath" -ForegroundColor Green
        Write-Host "  Configurations backed up: $($backupResults.Where({$_.Success}).Count)" -ForegroundColor Green
        Write-Host "  Backup ID: $($metadata.BackupId)" -ForegroundColor Gray
        
        # Clean up old backups
        if ($RetentionDays -gt 0) {
            $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
            $oldBackups = Get-ChildItem $backupRoot -Directory | Where-Object { $_.CreationTime -lt $cutoffDate }
            
            foreach ($oldBackup in $oldBackups) {
                try {
                    Remove-Item $oldBackup.FullName -Recurse -Force
                    Write-Verbose "Removed old backup: $($oldBackup.Name)"
                }
                catch {
                    Write-Verbose "Could not remove old backup '$($oldBackup.Name)': $_"
                }
            }
        }
        
        return $metadata
    }
    catch {
        Write-Error "Failed to create configuration backup: $_"
        throw
    }
}

function Restore-ProUConfigurationState {
    <#
    .SYNOPSIS
        Restores configurations from a backup.
    
    .DESCRIPTION
        Restores one or more configurations from a previously created backup.
    
    .PARAMETER BackupPath
        Path to the backup directory
    
    .PARAMETER ConfigurationName
        Name of specific configuration to restore (all if not specified)
    
    .PARAMETER Force
        Skip confirmation prompts
    
    .EXAMPLE
        Restore-ProUConfigurationState -BackupPath "C:\Backups\Backup_20241201_143022"
        
    .EXAMPLE
        Restore-ProUConfigurationState -BackupPath "C:\Backups\Backup_20241201_143022" -ConfigurationName "Production"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath,
        
        [string]$ConfigurationName,
        
        [switch]$Force
    )
    
    try {
        if (-not (Test-Path $BackupPath)) {
            throw "Backup path not found: $BackupPath"
        }
        
        # Read backup metadata
        $metadataPath = Join-Path $BackupPath "backup-metadata.json"
        if (-not (Test-Path $metadataPath)) {
            throw "Backup metadata not found: $metadataPath"
        }
        
        $metadata = Get-Content $metadataPath | ConvertFrom-Json
        
        Write-Host "Restoring from backup:" -ForegroundColor Cyan
        Write-Host "  Backup ID: $($metadata.BackupId)" -ForegroundColor Gray
        Write-Host "  Backup Time: $($metadata.BackupTime)" -ForegroundColor Gray
        Write-Host "  Backup Type: $($metadata.BackupType)" -ForegroundColor Gray
        Write-Host "  Comment: $($metadata.Comment)" -ForegroundColor Gray
        
        # Get configurations to restore
        $configurationsToRestore = $metadata.Configurations | Where-Object { $_.Success }
        
        if ($ConfigurationName) {
            $configurationsToRestore = $configurationsToRestore | Where-Object { $_.Name -eq $ConfigurationName }
        }
        
        if (-not $configurationsToRestore) {
            Write-Host "No configurations found to restore" -ForegroundColor Yellow
            return
        }
        
        Write-Host "Configurations to restore: $($configurationsToRestore.Count)" -ForegroundColor Yellow
        $configurationsToRestore | ForEach-Object { 
            Write-Host "  - $($_.Name)" -ForegroundColor White
        }
        
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("$($configurationsToRestore.Count) configurations", "Restore from backup")) {
            Write-Host "Restore cancelled" -ForegroundColor Yellow
            return
        }
        
        $restoreResults = @()
        
        foreach ($configBackup in $configurationsToRestore) {
            try {
                Write-Host "Restoring: $($configBackup.Name)" -ForegroundColor Yellow
                
                if (-not (Test-Path $configBackup.BackupPath)) {
                    throw "Backup file not found: $($configBackup.BackupPath)"
                }
                
                # Read and import the configuration
                $jsonContent = Get-Content $configBackup.BackupPath | ConvertFrom-Json
                $configObject = $jsonContent.configurations
                
                # Import the configuration
                Invoke-ProfileUnityApi -Endpoint 'configuration' -Method POST -Body $configObject
                
                $restoreResults += @{
                    Name = $configBackup.Name
                    Success = $true
                    RestoreTime = Get-Date
                }
                
                Write-Host "  Restored: $($configBackup.Name)" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to restore configuration '$($configBackup.Name)': $_"
                $restoreResults += @{
                    Name = $configBackup.Name
                    Success = $false
                    RestoreTime = Get-Date
                    Error = $_.Exception.Message
                }
            }
        }
        
        Write-Host "Restore completed" -ForegroundColor Green
        Write-Host "  Configurations restored: $($restoreResults.Where({$_.Success}).Count)" -ForegroundColor Green
        Write-Host "  Failed: $($restoreResults.Where({-not $_.Success}).Count)" -ForegroundColor $(if($restoreResults.Where({-not $_.Success}).Count -gt 0){'Red'}else{'Green'})
        
        return $restoreResults
    }
    catch {
        Write-Error "Failed to restore configuration state: $_"
        throw
    }
}

function Get-ProUConfigurationBackups {
    <#
    .SYNOPSIS
        Lists available configuration backups.
    
    .DESCRIPTION
        Shows all available configuration backups with metadata.
    
    .PARAMETER BackupType
        Filter by backup type
    
    .PARAMETER ConfigurationName
        Filter by configuration name
    
    .PARAMETER Days
        Show backups from the last N days
    
    .EXAMPLE
        Get-ProUConfigurationBackups
        
    .EXAMPLE
        Get-ProUConfigurationBackups -ConfigurationName "Production" -Days 7
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Automatic', 'Manual', 'PreDeployment', 'PreEdit', 'Scheduled')]
        [string]$BackupType,
        
        [string]$ConfigurationName,
        
        [int]$Days
    )
    
    try {
        $backupRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ProfileUnity-Backups\ConfigurationVersions'
        
        if (-not (Test-Path $backupRoot)) {
            Write-Host "No backup directory found: $backupRoot" -ForegroundColor Yellow
            return @()
        }
        
        $backupFolders = Get-ChildItem $backupRoot -Directory | Sort-Object CreationTime -Descending
        
        if ($Days) {
            $cutoffDate = (Get-Date).AddDays(-$Days)
            $backupFolders = $backupFolders | Where-Object { $_.CreationTime -ge $cutoffDate }
        }
        
        $backups = @()
        
        foreach ($folder in $backupFolders) {
            $metadataPath = Join-Path $folder.FullName "backup-metadata.json"
            
            if (Test-Path $metadataPath) {
                try {
                    $metadata = Get-Content $metadataPath | ConvertFrom-Json
                    
                    # Apply filters
                    if ($BackupType -and $metadata.BackupType -ne $BackupType) {
                        continue
                    }
                    
                    if ($ConfigurationName) {
                        $hasConfig = $metadata.Configurations | Where-Object { $_.Name -eq $ConfigurationName }
                        if (-not $hasConfig) {
                            continue
                        }
                    }
                    
                    $backups += [PSCustomObject]@{
                        BackupId = $metadata.BackupId
                        BackupPath = $folder.FullName
                        BackupTime = [DateTime]$metadata.BackupTime
                        BackupType = $metadata.BackupType
                        Comment = $metadata.Comment
                        ConfigurationCount = ($metadata.Configurations | Where-Object { $_.Success }).Count
                        CreatedBy = $metadata.CreatedBy
                        ComputerName = $metadata.ComputerName
                        FolderName = $folder.Name
                    }
                }
                catch {
                    Write-Verbose "Could not read backup metadata from '$($folder.Name)': $_"
                }
            }
        }
        
        return $backups
    }
    catch {
        Write-Error "Failed to get configuration backups: $_"
        return @()
    }
}

function Compare-ProUConfigurations {
    <#
    .SYNOPSIS
        Compares two ProfileUnity configurations.
    
    .DESCRIPTION
        Compares configurations and shows differences.
    
    .PARAMETER Configuration1
        Name of the first configuration
    
    .PARAMETER Configuration2
        Name of the second configuration
    
    .PARAMETER ShowDetails
        Show detailed differences
    
    .EXAMPLE
        Compare-ProUConfigurations -Configuration1 "Production" -Configuration2 "Test"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Configuration1,
        
        [Parameter(Mandatory)]
        [string]$Configuration2,
        
        [switch]$ShowDetails
    )
    
    try {
        Write-Host "Comparing configurations..." -ForegroundColor Cyan
        
        # Load both configurations
        $config1 = Get-ProUConfig | Where-Object { $_.Name -eq $Configuration1 }
        $config2 = Get-ProUConfig | Where-Object { $_.Name -eq $Configuration2 }
        
        if (-not $config1) {
            throw "Configuration '$Configuration1' not found"
        }
        
        if (-not $config2) {
            throw "Configuration '$Configuration2' not found"
        }
        
        # Get full configuration details
        $config1Details = Invoke-ProfileUnityApi -Endpoint "configuration/$($config1.id)"
        $config2Details = Invoke-ProfileUnityApi -Endpoint "configuration/$($config2.id)"
        
        $config1Data = $config1Details.tag
        $config2Data = $config2Details.tag
        
        Write-Host "Configuration Comparison:" -ForegroundColor Green
        Write-Host "  Config 1: $Configuration1" -ForegroundColor White
        Write-Host "  Config 2: $Configuration2" -ForegroundColor White
        Write-Host ""
        
        # Compare basic properties
        $differences = @()
        
        if ($config1Data.disabled -ne $config2Data.disabled) {
            $differences += "Enabled status differs: $(-not $config1Data.disabled) vs $(-not $config2Data.disabled)"
        }
        
        # Compare module counts
        $modules1Count = if ($config1Data.modules) { $config1Data.modules.Count } else { 0 }
        $modules2Count = if ($config2Data.modules) { $config2Data.modules.Count } else { 0 }
        
        if ($modules1Count -ne $modules2Count) {
            $differences += "Module count differs: $modules1Count vs $modules2Count"
        }
        
        # Compare ADMX template counts
        $admx1Count = if ($config1Data.AdministrativeTemplates) { $config1Data.AdministrativeTemplates.Count } else { 0 }
        $admx2Count = if ($config2Data.AdministrativeTemplates) { $config2Data.AdministrativeTemplates.Count } else { 0 }
        
        if ($admx1Count -ne $admx2Count) {
            $differences += "ADMX template count differs: $admx1Count vs $admx2Count"
        }
        
        if ($differences.Count -eq 0) {
            Write-Host "Configurations appear to be similar" -ForegroundColor Green
        } else {
            Write-Host "Differences found:" -ForegroundColor Yellow
            $differences | ForEach-Object {
                Write-Host "  - $_" -ForegroundColor White
            }
        }
        
        if ($ShowDetails) {
            Write-Host "`nDetailed comparison:" -ForegroundColor Cyan
            # Additional detailed comparison logic could be added here
            Write-Host "Detailed comparison not yet implemented" -ForegroundColor Yellow
        }
        
        return $differences
    }
    catch {
        Write-Error "Failed to compare configurations: $_"
        throw
    }
}

function New-ProUConfigurationCheckpoint {
    <#
    .SYNOPSIS
        Creates a checkpoint before making changes.
    
    .DESCRIPTION
        Creates a named checkpoint that can be restored later.
    
    .PARAMETER Name
        Name for the checkpoint
    
    .PARAMETER ConfigurationName
        Configuration to checkpoint
    
    .PARAMETER Description
        Description of what changes are being made
    
    .EXAMPLE
        New-ProUConfigurationCheckpoint -Name "BeforeADMXChanges" -ConfigurationName "Production"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [string]$ConfigurationName,
        
        [string]$Description = ""
    )
    
    try {
        $checkpointComment = "Checkpoint: $Name"
        if ($Description) {
            $checkpointComment += " - $Description"
        }
        
        $backup = Backup-ProUConfigurationState -ConfigurationName $ConfigurationName -BackupType "Manual" -Comment $checkpointComment
        
        # Create named checkpoint reference
        $checkpointsDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ProfileUnity-Backups\Checkpoints'
        if (-not (Test-Path $checkpointsDir)) {
            New-Item -ItemType Directory -Path $checkpointsDir -Force | Out-Null
        }
        
        $checkpointFile = Join-Path $checkpointsDir "$Name.json"
        $checkpointData = @{
            Name = $Name
            Description = $Description
            ConfigurationName = $ConfigurationName
            BackupId = $backup.BackupId
            BackupPath = Split-Path $backup.Configurations[0].BackupPath -Parent
            CreatedTime = Get-Date
            CreatedBy = $env:USERNAME
        }
        
        $checkpointData | ConvertTo-Json -Depth 3 | Out-File $checkpointFile -Encoding UTF8
        
        Write-Host "Checkpoint created: $Name" -ForegroundColor Green
        Write-Host "  Backup ID: $($backup.BackupId)" -ForegroundColor Gray
        
        return $checkpointData
    }
    catch {
        Write-Error "Failed to create checkpoint: $_"
        throw
    }
}

function Restore-ProUConfigurationCheckpoint {
    <#
    .SYNOPSIS
        Restores a configuration from a named checkpoint.
    
    .DESCRIPTION
        Restores configurations from a previously created checkpoint.
    
    .PARAMETER Name
        Name of the checkpoint to restore
    
    .PARAMETER Force
        Skip confirmation prompts
    
    .EXAMPLE
        Restore-ProUConfigurationCheckpoint -Name "BeforeADMXChanges"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [switch]$Force
    )
    
    try {
        $checkpointsDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ProfileUnity-Backups\Checkpoints'
        $checkpointFile = Join-Path $checkpointsDir "$Name.json"
        
        if (-not (Test-Path $checkpointFile)) {
            throw "Checkpoint '$Name' not found"
        }
        
        $checkpointData = Get-Content $checkpointFile | ConvertFrom-Json
        
        Write-Host "Restoring checkpoint: $Name" -ForegroundColor Cyan
        Write-Host "  Description: $($checkpointData.Description)" -ForegroundColor Gray
        Write-Host "  Created: $($checkpointData.CreatedTime)" -ForegroundColor Gray
        Write-Host "  Configuration: $($checkpointData.ConfigurationName)" -ForegroundColor Gray
        
        if (-not $Force -and -not $PSCmdlet.ShouldProcess("checkpoint '$Name'", "Restore configuration")) {
            Write-Host "Restore cancelled" -ForegroundColor Yellow
            return
        }
        
        $result = Restore-ProUConfigurationState -BackupPath $checkpointData.BackupPath -ConfigurationName $checkpointData.ConfigurationName -Force
        
        Write-Host "Checkpoint '$Name' restored successfully" -ForegroundColor Green
        
        return $result
    }
    catch {
        Write-Error "Failed to restore checkpoint: $_"
        throw
    }
}

# Export functions
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
Export-ModuleMember -Function @(
    'Backup-ProUConfigurationState',
    'Restore-ProUConfigurationState',
    'Get-ProUConfigurationBackups',
    'Compare-ProUConfigurations',
    'New-ProUConfigurationCheckpoint',
    'Restore-ProUConfigurationCheckpoint'
)
#>
