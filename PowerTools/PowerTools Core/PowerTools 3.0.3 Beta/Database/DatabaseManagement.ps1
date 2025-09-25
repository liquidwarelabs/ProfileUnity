# Database\DatabaseManagement.ps1 - ProfileUnity Database Management Functions (Enhanced)

function Get-ProUDatabaseConnectionStatus {
    <#
    .SYNOPSIS
        Gets ProfileUnity database connection status.
    
    .DESCRIPTION
        Returns the current database connection health and performance metrics.
    
    .EXAMPLE
        Get-ProUDatabaseConnectionStatus
    #>
    [CmdletBinding()]
    param()
    
    try {
        $response = Invoke-ProfileUnityApi -Endpoint "database/status"
        
        if ($response) {
            return [PSCustomObject]@{
                Status = $response.status
                Server = $response.server
                Database = $response.database
                Version = $response.version
                LastPing = $response.lastPing
                ResponseTime = $response.responseTimeMs
                ConnectionPool = $response.connectionPool
                ActiveConnections = $response.activeConnections
                MaxConnections = $response.maxConnections
            }
        }
    }
    catch {
        Write-Error "Failed to get database connection status: $_"
        throw
    }
}

function Get-ProUDatabaseConnectionString {
    <#
    .SYNOPSIS
        Gets ProfileUnity database connection string.
    
    .DESCRIPTION
        Retrieves the database connection string configuration.
    
    .EXAMPLE
        Get-ProUDatabaseConnectionString
    #>
    [CmdletBinding()]
    param()
    
    try {
        $response = Invoke-ProfileUnityApi -Endpoint "database/connectionstring"
        
        if ($response) {
            return [PSCustomObject]@{
                Server = $response.server
                Database = $response.database
                IntegratedSecurity = $response.integratedSecurity
                ConnectionTimeout = $response.connectionTimeout
                CommandTimeout = $response.commandTimeout
                Pooling = $response.pooling
                MaxPoolSize = $response.maxPoolSize
                MinPoolSize = $response.minPoolSize
                Encrypted = $response.encrypted
                TrustServerCertificate = $response.trustServerCertificate
            }
        }
    }
    catch {
        Write-Error "Failed to get database connection string: $_"
        throw
    }
}

function Copy-ProUDatabaseConnectionString {
    <#
    .SYNOPSIS
        Copies database connection string to clipboard.
    
    .DESCRIPTION
        Retrieves and copies the formatted database connection string to clipboard.
    
    .PARAMETER Formatted
        Return formatted connection string
    
    .EXAMPLE
        Copy-ProUDatabaseConnectionString
        
    .EXAMPLE
        Copy-ProUDatabaseConnectionString -Formatted
    #>
    [CmdletBinding()]
    param(
        [switch]$Formatted
    )
    
    try {
        $connectionInfo = Get-ProUDatabaseConnectionString
        
        if ($Formatted) {
            $connectionString = @"
Server=$($connectionInfo.Server)
Database=$($connectionInfo.Database)
Integrated Security=$($connectionInfo.IntegratedSecurity)
Connection Timeout=$($connectionInfo.ConnectionTimeout)
Command Timeout=$($connectionInfo.CommandTimeout)
Pooling=$($connectionInfo.Pooling)
Max Pool Size=$($connectionInfo.MaxPoolSize)
Min Pool Size=$($connectionInfo.MinPoolSize)
Encrypt=$($connectionInfo.Encrypted)
Trust Server Certificate=$($connectionInfo.TrustServerCertificate)
"@
        }
        else {
            $parts = @()
            $parts += "Server=$($connectionInfo.Server)"
            $parts += "Database=$($connectionInfo.Database)"
            if ($connectionInfo.IntegratedSecurity) {
                $parts += "Integrated Security=true"
            }
            $parts += "Connection Timeout=$($connectionInfo.ConnectionTimeout)"
            $parts += "Pooling=$($connectionInfo.Pooling)"
            if ($connectionInfo.MaxPoolSize) {
                $parts += "Max Pool Size=$($connectionInfo.MaxPoolSize)"
            }
            if ($connectionInfo.Encrypted) {
                $parts += "Encrypt=true"
            }
            if ($connectionInfo.TrustServerCertificate) {
                $parts += "Trust Server Certificate=true"
            }
            
            $connectionString = $parts -join ";"
        }
        
        $connectionString | Set-Clipboard
        Write-Host "Database connection string copied to clipboard" -ForegroundColor Green
        
        return $connectionString
    }
    catch {
        Write-Error "Failed to copy database connection string: $_"
        throw
    }
}

function New-ProUDatabaseBackup {
    <#
    .SYNOPSIS
        Creates a new ProfileUnity database backup.
    
    .DESCRIPTION
        Initiates a database backup operation with specified options.
    
    .PARAMETER Name
        Name for the backup
    
    .PARAMETER Path
        Backup file path (optional - server will use default if not specified)
    
    .PARAMETER Type
        Backup type: Full, Differential, or TransactionLog
    
    .PARAMETER Compress
        Compress the backup file
    
    .PARAMETER Verify
        Verify backup after creation
    
    .EXAMPLE
        New-ProUDatabaseBackup -Name "Daily_Backup_$(Get-Date -Format 'yyyyMMdd')"
        
    .EXAMPLE
        New-ProUDatabaseBackup -Name "Pre_Update_Backup" -Type "Full" -Compress -Verify
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [string]$Path,
        
        [ValidateSet('Full', 'Differential', 'TransactionLog')]
        [string]$Type = 'Full',
        
        [switch]$Compress,
        
        [switch]$Verify
    )
    
    try {
        Write-Host "Creating database backup: $Name" -ForegroundColor Yellow
        
        $body = @{
            name = $Name
            backupType = $Type
            compress = $Compress.ToBool()
            verify = $Verify.ToBool()
        }
        
        if ($Path) {
            $body.path = $Path
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "database/backup" -Method POST -Body $body
        
        if ($response) {
            Write-Host "Database backup initiated successfully" -ForegroundColor Green
            Write-Host "  Backup Name: $Name" -ForegroundColor Cyan
            Write-Host "  Backup Type: $Type" -ForegroundColor Cyan
            
            if ($response.taskId) {
                Write-Host "  Task ID: $($response.taskId)" -ForegroundColor Cyan
                Write-Host "Use 'Get-ProUTask -Id $($response.taskId)' to monitor progress" -ForegroundColor Yellow
            }
            
            return [PSCustomObject]@{
                Name = $Name
                Type = $Type
                TaskId = $response.taskId
                Path = if ($response.path) { $response.path } else { $Path }
                Started = Get-Date
                Status = "Initiated"
            }
        }
    }
    catch {
        Write-Error "Failed to create database backup: $_"
        throw
    }
}

function New-ProUClusterDatabaseBackup {
    <#
    .SYNOPSIS
        Creates a cluster-aware database backup.
    
    .DESCRIPTION
        Initiates a database backup operation in a clustered environment.
    
    .PARAMETER Name
        Name for the backup
    
    .PARAMETER Path
        Backup file path (should be accessible by all cluster nodes)
    
    .PARAMETER Type
        Backup type: Full, Differential, or TransactionLog
    
    .PARAMETER ClusterNode
        Specific cluster node to execute backup (optional)
    
    .PARAMETER Compress
        Compress the backup file
    
    .EXAMPLE
        New-ProUClusterDatabaseBackup -Name "Cluster_Backup_$(Get-Date -Format 'yyyyMMdd')" -Path "\\shared\backups\"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [string]$Path,
        
        [ValidateSet('Full', 'Differential', 'TransactionLog')]
        [string]$Type = 'Full',
        
        [string]$ClusterNode,
        
        [switch]$Compress
    )
    
    try {
        Write-Host "Creating cluster database backup: $Name" -ForegroundColor Yellow
        
        $body = @{
            name = $Name
            path = $Path
            backupType = $Type
            compress = $Compress.ToBool()
            clusterBackup = $true
        }
        
        if ($ClusterNode) {
            $body.clusterNode = $ClusterNode
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "database/cluster/backup" -Method POST -Body $body
        
        if ($response) {
            Write-Host "Cluster database backup initiated successfully" -ForegroundColor Green
            Write-Host "  Backup Name: $Name" -ForegroundColor Cyan
            Write-Host "  Backup Path: $Path" -ForegroundColor Cyan
            Write-Host "  Active Node: $($response.activeNode)" -ForegroundColor Cyan
            
            return [PSCustomObject]@{
                Name = $Name
                Type = $Type
                Path = $Path
                TaskId = $response.taskId
                ActiveNode = $response.activeNode
                Started = Get-Date
                Status = "Initiated"
            }
        }
    }
    catch {
        Write-Error "Failed to create cluster database backup: $_"
        throw
    }
}

function Get-ProUDatabaseBackup {
    <#
    .SYNOPSIS
        Gets database backup information.
    
    .DESCRIPTION
        Retrieves details about a specific database backup.
    
    .PARAMETER Id
        Backup ID to retrieve
    
    .PARAMETER Name
        Backup name to retrieve
    
    .EXAMPLE
        Get-ProUDatabaseBackup -Id "12345"
        
    .EXAMPLE
        Get-ProUDatabaseBackup -Name "Daily_Backup_20241201"
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$Id,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name
    )
    
    try {
        # Resolve name to ID if needed
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            Write-Verbose "Resolving backup name '$Name' to ID..."
            $backups = Get-ProUDatabaseBackupList
            $backup = $backups | Where-Object { $_.Name -eq $Name }
            
            if (-not $backup) {
                throw "Database backup '$Name' not found"
            }
            
            if ($backup -is [array] -and $backup.Count -gt 1) {
                throw "Multiple backups found with name '$Name'. Use -Id parameter instead."
            }
            
            $Id = $backup.Id
            Write-Verbose "Resolved to ID: $Id"
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "database/backup/$Id"
        
        if ($response) {
            return [PSCustomObject]@{
                Id = $response.id
                Name = $response.name
                Path = $response.path
                Size = $response.size
                SizeMB = [math]::Round($response.size / 1MB, 2)
                Created = $response.created
                Status = $response.status
                Duration = $response.duration
                Compressed = $response.compressed
                BackupType = $response.backupType
                DatabaseName = $response.databaseName
                ServerName = $response.serverName
                Verified = $response.verified
                FirstLSN = $response.firstLSN
                LastLSN = $response.lastLSN
                CheckpointLSN = $response.checkpointLSN
            }
        }
    }
    catch {
        Write-Error "Failed to get database backup: $_"
        throw
    }
}

function Get-ProUDatabaseBackupList {
    <#
    .SYNOPSIS
        Gets list of database backups.
    
    .DESCRIPTION
        Retrieves a list of all available database backups with optional filtering.
    
    .PARAMETER Type
        Filter by backup type
    
    .PARAMETER DaysBack
        Only show backups from the last N days
    
    .PARAMETER MaxResults
        Maximum number of results to return
    
    .EXAMPLE
        Get-ProUDatabaseBackupList
        
    .EXAMPLE
        Get-ProUDatabaseBackupList -Type "Full" -DaysBack 7
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Full', 'Differential', 'TransactionLog')]
        [string]$Type,
        
        [int]$DaysBack,
        
        [int]$MaxResults
    )
    
    try {
        $queryParams = @()
        
        if ($Type) {
            $queryParams += "type=$Type"
        }
        
        if ($DaysBack) {
            $startDate = (Get-Date).AddDays(-$DaysBack).ToString('yyyy-MM-dd')
            $queryParams += "startDate=$startDate"
        }
        
        if ($MaxResults) {
            $queryParams += "maxResults=$MaxResults"
        }
        
        $queryString = if ($queryParams.Count -gt 0) {
            "?" + ($queryParams -join "&")
        } else { "" }
        
        $response = Invoke-ProfileUnityApi -Endpoint "database/backup/list$queryString"
        
        if ($response) {
            return $response | ForEach-Object {
                [PSCustomObject]@{
                    Id = $_.id
                    Name = $_.name
                    Path = $_.path
                    Size = $_.size
                    SizeMB = [math]::Round($_.size / 1MB, 2)
                    Created = $_.created
                    Status = $_.status
                    Duration = $_.duration
                    Compressed = $_.compressed
                    BackupType = $_.backupType
                    DatabaseName = $_.databaseName
                    ServerName = $_.serverName
                }
            }
        }
    }
    catch {
        Write-Error "Failed to get database backup list: $_"
        throw
    }
}

function Start-ProUDatabaseBackupSchedule {
    <#
    .SYNOPSIS
        Starts a database backup schedule.
    
    .DESCRIPTION
        Manually triggers or starts an automated database backup schedule.
    
    .PARAMETER Id
        Schedule ID to start
    
    .PARAMETER Name
        Schedule name to start
    
    .PARAMETER Force
        Force start even if schedule is already running
    
    .EXAMPLE
        Start-ProUDatabaseBackupSchedule -Id "12345"
        
    .EXAMPLE
        Start-ProUDatabaseBackupSchedule -Name "Daily Full Backup" -Force
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$Id,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,
        
        [switch]$Force
    )
    
    try {
        # Resolve name to ID if needed
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            Write-Verbose "Resolving schedule name '$Name' to ID..."
            $schedules = Get-ProUDatabaseBackupScheduleList
            $schedule = $schedules | Where-Object { $_.Name -eq $Name }
            
            if (-not $schedule) {
                throw "Database backup schedule '$Name' not found"
            }
            
            if ($schedule -is [array] -and $schedule.Count -gt 1) {
                throw "Multiple schedules found with name '$Name'. Use -Id parameter instead."
            }
            
            $Id = $schedule.Id
            $scheduleName = $schedule.Name
            Write-Verbose "Resolved to ID: $Id"
        }
        else {
            # Get name for display
            $schedules = Get-ProUDatabaseBackupScheduleList
            $schedule = $schedules | Where-Object { $_.Id -eq $Id }
            $scheduleName = if ($schedule) { $schedule.Name } else { "ID: $Id" }
        }
        
        Write-Host "Starting database backup schedule: $scheduleName" -ForegroundColor Yellow
        
        $body = @{
            force = $Force.ToBool()
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "database/backup/schedule/$Id/start" -Method POST -Body $body
        
        if ($response) {
            Write-Host "Database backup schedule started successfully" -ForegroundColor Green
            
            if ($response.taskId) {
                Write-Host "  Task ID: $($response.taskId)" -ForegroundColor Cyan
            }
            
            return [PSCustomObject]@{
                ScheduleId = $Id
                ScheduleName = $scheduleName
                TaskId = $response.taskId
                Started = Get-Date
                Status = "Started"
            }
        }
    }
    catch {
        Write-Error "Failed to start database backup schedule: $_"
        throw
    }
}

function Get-ProUDatabaseBackupScheduleList {
    <#
    .SYNOPSIS
        Gets list of database backup schedules.
    
    .DESCRIPTION
        Retrieves all configured database backup schedules.
    
    .PARAMETER Enabled
        Filter by enabled/disabled status
    
    .EXAMPLE
        Get-ProUDatabaseBackupScheduleList
        
    .EXAMPLE
        Get-ProUDatabaseBackupScheduleList -Enabled $true
    #>
    [CmdletBinding()]
    param(
        [bool]$Enabled
    )
    
    try {
        $queryString = ""
        if ($PSBoundParameters.ContainsKey('Enabled')) {
            $queryString = "?enabled=$($Enabled.ToString().ToLower())"
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "database/backup/schedule/list$queryString"
        
        if ($response) {
            return $response | ForEach-Object {
                [PSCustomObject]@{
                    Id = $_.id
                    Name = $_.name
                    Type = $_.backupType
                    Schedule = $_.schedule
                    NextRun = $_.nextRun
                    LastRun = $_.lastRun
                    LastStatus = $_.lastStatus
                    Enabled = $_.enabled
                    Path = $_.path
                    Retention = $_.retention
                    Compress = $_.compress
                }
            }
        }
    }
    catch {
        Write-Error "Failed to get database backup schedule list: $_"
        throw
    }
}

function Invoke-ProUDatabaseSchedule {
    <#
    .SYNOPSIS
        Executes a database maintenance schedule.
    
    .DESCRIPTION
        Runs database maintenance tasks according to configured schedule.
    
    .PARAMETER Id
        Schedule ID to execute
    
    .PARAMETER Name
        Schedule name to execute
    
    .PARAMETER TaskType
        Specific task type to run
    
    .EXAMPLE
        Invoke-ProUDatabaseSchedule -Id "12345"
        
    .EXAMPLE
        Invoke-ProUDatabaseSchedule -Name "Weekly Maintenance" -TaskType "Reindex"
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$Id,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,
        
        [ValidateSet('Backup', 'Reindex', 'UpdateStats', 'CheckDB', 'Cleanup')]
        [string]$TaskType
    )
    
    try {
        # Resolve name to ID if needed
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            Write-Verbose "Resolving schedule name '$Name' to ID..."
            $schedules = Get-ProUDatabaseScheduleList
            $schedule = $schedules | Where-Object { $_.Name -eq $Name }
            
            if (-not $schedule) {
                throw "Database schedule '$Name' not found"
            }
            
            if ($schedule -is [array] -and $schedule.Count -gt 1) {
                throw "Multiple schedules found with name '$Name'. Use -Id parameter instead."
            }
            
            $Id = $schedule.Id
            Write-Verbose "Resolved to ID: $Id"
        }
        
        $body = @{}
        if ($TaskType) {
            $body.taskType = $TaskType
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "database/schedule/$Id/execute" -Method POST -Body $body
        
        if ($response) {
            Write-Host "Database schedule executed successfully" -ForegroundColor Green
            
            return [PSCustomObject]@{
                ScheduleId = $Id
                TaskId = $response.taskId
                TaskType = $TaskType
                Started = Get-Date
                Status = "Running"
            }
        }
    }
    catch {
        Write-Error "Failed to execute database schedule: $_"
        throw
    }
}

function New-ProUDatabaseBackupSchedule {
    <#
    .SYNOPSIS
        Creates a new database backup schedule.
    
    .DESCRIPTION
        Creates an automated database backup schedule with specified parameters.
    
    .PARAMETER Name
        Name for the backup schedule
    
    .PARAMETER Type
        Backup type: Full, Differential, or TransactionLog
    
    .PARAMETER Schedule
        Cron expression or schedule description
    
    .PARAMETER Path
        Backup file path template
    
    .PARAMETER Retention
        Number of backups to retain
    
    .PARAMETER Compress
        Compress backup files
    
    .PARAMETER Enabled
        Enable the schedule immediately
    
    .EXAMPLE
        New-ProUDatabaseBackupSchedule -Name "Daily Full Backup" -Type "Full" -Schedule "0 2 * * *" -Path "C:\Backups\Daily_Full_{date}.bak" -Retention 7 -Compress -Enabled
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [ValidateSet('Full', 'Differential', 'TransactionLog')]
        [string]$Type,
        
        [Parameter(Mandatory)]
        [string]$Schedule,
        
        [Parameter(Mandatory)]
        [string]$Path,
        
        [int]$Retention = 7,
        
        [switch]$Compress,
        
        [switch]$Enabled
    )
    
    try {
        Write-Host "Creating database backup schedule: $Name" -ForegroundColor Yellow
        
        $body = @{
            name = $Name
            backupType = $Type
            schedule = $Schedule
            path = $Path
            retention = $Retention
            compress = $Compress.ToBool()
            enabled = $Enabled.ToBool()
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "database/backup/schedule" -Method POST -Body $body
        
        if ($response) {
            Write-Host "Database backup schedule created successfully" -ForegroundColor Green
            Write-Host "  Name: $Name" -ForegroundColor Cyan
            Write-Host "  Type: $Type" -ForegroundColor Cyan
            Write-Host "  Schedule: $Schedule" -ForegroundColor Cyan
            Write-Host "  Enabled: $Enabled" -ForegroundColor Cyan
            
            return [PSCustomObject]@{
                Id = $response.id
                Name = $Name
                Type = $Type
                Schedule = $Schedule
                Path = $Path
                Retention = $Retention
                Compress = $Compress
                Enabled = $Enabled
                NextRun = $response.nextRun
            }
        }
    }
    catch {
        Write-Error "Failed to create database backup schedule: $_"
        throw
    }
}

function Remove-ProUDatabaseBackupSchedule {
    <#
    .SYNOPSIS
        Removes a database backup schedule.
    
    .DESCRIPTION
        Deletes a database backup schedule configuration.
    
    .PARAMETER Id
        Schedule ID to remove
    
    .PARAMETER Name
        Schedule name to remove
    
    .PARAMETER Force
        Skip confirmation prompt
    
    .EXAMPLE
        Remove-ProUDatabaseBackupSchedule -Id "12345"
        
    .EXAMPLE
        Remove-ProUDatabaseBackupSchedule -Name "Old Daily Backup" -Force
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$Id,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,
        
        [switch]$Force
    )
    
    try {
        # Resolve name to ID if needed
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            Write-Verbose "Resolving schedule name '$Name' to ID..."
            $schedules = Get-ProUDatabaseBackupScheduleList
            $schedule = $schedules | Where-Object { $_.Name -eq $Name }
            
            if (-not $schedule) {
                throw "Database backup schedule '$Name' not found"
            }
            
            if ($schedule -is [array] -and $schedule.Count -gt 1) {
                throw "Multiple schedules found with name '$Name'. Use -Id parameter instead."
            }
            
            $Id = $schedule.Id
            $scheduleName = $schedule.Name
            Write-Verbose "Resolved to ID: $Id"
        }
        else {
            # Get name for confirmation
            $schedules = Get-ProUDatabaseBackupScheduleList
            $schedule = $schedules | Where-Object { $_.Id -eq $Id }
            $scheduleName = if ($schedule) { $schedule.Name } else { "ID: $Id" }
        }
        
        if ($PSCmdlet.ShouldProcess($scheduleName, "Remove database backup schedule")) {
            if (-not $Force) {
                $confirm = Read-Host "Are you sure you want to remove backup schedule '$scheduleName'? (y/N)"
                if ($confirm -ne 'y' -and $confirm -ne 'Y') {
                    Write-Host "Operation cancelled" -ForegroundColor Yellow
                    return
                }
            }
            
            $response = Invoke-ProfileUnityApi -Endpoint "database/backup/schedule/$Id" -Method DELETE
            
            Write-Host "Database backup schedule removed: $scheduleName" -ForegroundColor Green
            return $response
        }
    }
    catch {
        Write-Error "Failed to remove database backup schedule: $_"
        throw
    }
}

function Restore-ProUDatabase {
    <#
    .SYNOPSIS
        Restores ProfileUnity database from backup.
    
    .DESCRIPTION
        Performs database restore operation from specified backup.
    
    .PARAMETER BackupId
        Backup ID to restore from
    
    .PARAMETER BackupName
        Backup name to restore from
    
    .PARAMETER BackupPath
        Direct path to backup file
    
    .PARAMETER DatabaseName
        Target database name (optional - defaults to original)
    
    .PARAMETER Replace
        Replace existing database
    
    .PARAMETER NoRecovery
        Restore with NORECOVERY (for log shipping)
    
    .EXAMPLE
        Restore-ProUDatabase -BackupId "12345" -Replace
        
    .EXAMPLE
        Restore-ProUDatabase -BackupName "Daily_Backup_20241201" -DatabaseName "ProfileUnity_Test"
    #>
    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$BackupId,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$BackupName,
        
        [Parameter(Mandatory, ParameterSetName = 'ByPath')]
        [string]$BackupPath,
        
        [string]$DatabaseName,
        
        [switch]$Replace,
        
        [switch]$NoRecovery
    )
    
    try {
        # Resolve backup to restore
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            Write-Verbose "Resolving backup name '$BackupName' to ID..."
            $backup = Get-ProUDatabaseBackup -Name $BackupName
            $BackupId = $backup.Id
            $backupInfo = "Name: $BackupName (ID: $BackupId)"
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'ById') {
            $backup = Get-ProUDatabaseBackup -Id $BackupId
            $backupInfo = "ID: $BackupId (Name: $($backup.Name))"
        }
        else {
            $backupInfo = "Path: $BackupPath"
        }
        
        Write-Host "Starting database restore..." -ForegroundColor Yellow
        Write-Host "  Backup: $backupInfo" -ForegroundColor Cyan
        
        $body = @{
            replace = $Replace.ToBool()
            noRecovery = $NoRecovery.ToBool()
        }
        
        if ($BackupId) {
            $body.backupId = $BackupId
        }
        elseif ($BackupPath) {
            $body.backupPath = $BackupPath
        }
        
        if ($DatabaseName) {
            $body.targetDatabase = $DatabaseName
            Write-Host "  Target Database: $DatabaseName" -ForegroundColor Cyan
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "database/restore" -Method POST -Body $body
        
        if ($response) {
            Write-Host "Database restore initiated successfully" -ForegroundColor Green
            
            if ($response.taskId) {
                Write-Host "  Task ID: $($response.taskId)" -ForegroundColor Cyan
                Write-Host "Use 'Get-ProUTask -Id $($response.taskId)' to monitor progress" -ForegroundColor Yellow
            }
            
            return [PSCustomObject]@{
                BackupId = $BackupId
                BackupPath = $BackupPath
                TargetDatabase = $DatabaseName
                TaskId = $response.taskId
                Started = Get-Date
                Status = "Initiated"
            }
        }
    }
    catch {
        Write-Error "Failed to restore database: $_"
        throw
    }
}

function Test-ProUDatabaseHealth {
    <#
    .SYNOPSIS
        Tests ProfileUnity database health.
    
    .DESCRIPTION
        Performs comprehensive database health check including integrity, performance, and configuration validation.
    
    .PARAMETER IncludePerformance
        Include performance metrics in health check
    
    .PARAMETER IncludeIntegrity
        Include integrity checks (may take longer)
    
    .PARAMETER MaxDuration
        Maximum duration for health check in minutes
    
    .EXAMPLE
        Test-ProUDatabaseHealth
        
    .EXAMPLE
        Test-ProUDatabaseHealth -IncludePerformance -IncludeIntegrity -MaxDuration 30
    #>
    [CmdletBinding()]
    param(
        [switch]$IncludePerformance,
        
        [switch]$IncludeIntegrity,
        
        [int]$MaxDuration = 15
    )
    
    try {
        Write-Host "Starting database health check..." -ForegroundColor Yellow
        
        $body = @{
            includePerformance = $IncludePerformance.ToBool()
            includeIntegrity = $IncludeIntegrity.ToBool()
            maxDurationMinutes = $MaxDuration
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "database/health" -Method POST -Body $body
        
        if ($response) {
            Write-Host "Database health check completed" -ForegroundColor Green
            
            $healthResult = [PSCustomObject]@{
                Overall = $response.overallHealth
                DatabaseSize = $response.databaseSize
                DatabaseSizeMB = [math]::Round($response.databaseSize / 1MB, 2)
                LogSize = $response.logSize
                LogSizeMB = [math]::Round($response.logSize / 1MB, 2)
                FragmentationLevel = $response.fragmentationLevel
                LastBackup = $response.lastBackup
                ConnectionCount = $response.connectionCount
                BlockedProcesses = $response.blockedProcesses
                LongRunningQueries = $response.longRunningQueries
                ErrorLogEntries = $response.errorLogEntries
                Recommendations = $response.recommendations
                Issues = $response.issues
                Warnings = $response.warnings
            }
            
            # Display summary
            Write-Host "`nHealth Check Summary:" -ForegroundColor Cyan
            Write-Host "  Overall Health: $($healthResult.Overall)" -ForegroundColor $(if ($healthResult.Overall -eq 'Good') { 'Green' } elseif ($healthResult.Overall -eq 'Warning') { 'Yellow' } else { 'Red' })
            Write-Host "  Database Size: $($healthResult.DatabaseSizeMB) MB" -ForegroundColor White
            Write-Host "  Log Size: $($healthResult.LogSizeMB) MB" -ForegroundColor White
            Write-Host "  Active Connections: $($healthResult.ConnectionCount)" -ForegroundColor White
            
            if ($healthResult.Issues -and $healthResult.Issues.Count -gt 0) {
                Write-Host "  Issues Found: $($healthResult.Issues.Count)" -ForegroundColor Red
                $healthResult.Issues | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
            }
            
            if ($healthResult.Warnings -and $healthResult.Warnings.Count -gt 0) {
                Write-Host "  Warnings: $($healthResult.Warnings.Count)" -ForegroundColor Yellow
                $healthResult.Warnings | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
            }
            
            if ($healthResult.Recommendations -and $healthResult.Recommendations.Count -gt 0) {
                Write-Host "  Recommendations: $($healthResult.Recommendations.Count)" -ForegroundColor Cyan
                $healthResult.Recommendations | ForEach-Object { Write-Host "    - $_" -ForegroundColor Cyan }
            }
            
            return $healthResult
        }
    }
    catch {
        Write-Error "Failed to test database health: $_"
        throw
    }
}

# Helper function to get database schedule list (referenced in other functions)
function Get-ProUDatabaseScheduleList {
    <#
    .SYNOPSIS
        Gets list of all database schedules.
    
    .DESCRIPTION
        Retrieves all configured database maintenance schedules.
    #>
    [CmdletBinding()]
    param()
    
    try {
        $response = Invoke-ProfileUnityApi -Endpoint "database/schedule/list"
        
        if ($response) {
            return $response | ForEach-Object {
                [PSCustomObject]@{
                    Id = $_.id
                    Name = $_.name
                    Type = $_.scheduleType
                    Schedule = $_.schedule
                    NextRun = $_.nextRun
                    LastRun = $_.lastRun
                    LastStatus = $_.lastStatus
                    Enabled = $_.enabled
                }
            }
        }
    }
    catch {
        Write-Error "Failed to get database schedule list: $_"
        throw
    }
}

# Export functions
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
Export-ModuleMember -Function @(
    'Get-ProUDatabaseConnectionString',
    'Copy-ProUDatabaseConnectionString',
    'New-ProUDatabaseBackup',
    'Get-ProUDatabaseBackup',
    'Get-ProUDatabaseBackupList',
    'New-ProUDatabaseBackupSchedule',
    'Restore-ProUDatabase')
#>




