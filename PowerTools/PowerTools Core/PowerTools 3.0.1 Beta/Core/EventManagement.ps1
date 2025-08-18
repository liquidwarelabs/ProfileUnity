# Core/EventManagement.ps1 - ProfileUnity Event Management Functions

function Get-ProUEvents {
    <#
    .SYNOPSIS
        Gets ProfileUnity system events.
    
    .DESCRIPTION
        Retrieves system events from the ProfileUnity server with filtering options.
    
    .PARAMETER Level
        Event level filter (Info, Warning, Error, Critical)
    
    .PARAMETER Source
        Event source filter
    
    .PARAMETER After
        Get events after this date/time
    
    .PARAMETER Before
        Get events before this date/time
    
    .PARAMETER Hours
        Get events from the last X hours
    
    .PARAMETER MaxEvents
        Maximum number of events to return
    
    .PARAMETER User
        Filter by username
    
    .EXAMPLE
        Get-ProUEvents -Hours 24
        
    .EXAMPLE
        Get-ProUEvents -Level Error -After "2024-01-01" -MaxEvents 100
        
    .EXAMPLE
        Get-ProUEvents -Source "Authentication" -User "john.doe"
    #>
    [CmdletBinding(DefaultParameterSetName = 'Hours')]
    param(
        [ValidateSet('Info', 'Warning', 'Error', 'Critical', 'Debug', 'All')]
        [string]$Level = 'All',
        
        [string]$Source,
        
        [Parameter(ParameterSetName = 'DateRange')]
        [datetime]$After,
        
        [Parameter(ParameterSetName = 'DateRange')]
        [datetime]$Before,
        
        [Parameter(ParameterSetName = 'Hours')]
        [int]$Hours = 24,
        
        [int]$MaxEvents = 1000,
        
        [string]$User
    )
    
    try {
        Write-Verbose "Retrieving ProfileUnity events..."
        
        # Build query parameters
        $queryParams = @()
        
        if ($Level -ne 'All') {
            $queryParams += "level=$Level"
        }
        
        if ($Source) {
            $queryParams += "source=$([System.Web.HttpUtility]::UrlEncode($Source))"
        }
        
        if ($PSCmdlet.ParameterSetName -eq 'Hours') {
            $queryParams += "hours=$Hours"
        }
        else {
            if ($After) {
                $queryParams += "after=$($After.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
            }
            if ($Before) {
                $queryParams += "before=$($Before.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
            }
        }
        
        if ($MaxEvents) {
            $queryParams += "maxEvents=$MaxEvents"
        }
        
        if ($User) {
            $queryParams += "user=$([System.Web.HttpUtility]::UrlEncode($User))"
        }
        
        $queryString = if ($queryParams.Count -gt 0) {
            "?" + ($queryParams -join "&")
        } else { "" }
        
        $response = Invoke-ProfileUnityApi -Endpoint "event$queryString"
        
        if (-not $response -or $response.Count -eq 0) {
            Write-Host "No events found matching the criteria" -ForegroundColor Yellow
            return
        }
        
        # Format events
        $events = $response | ForEach-Object {
            [PSCustomObject]@{
                Timestamp = $_.timestamp
                Level = $_.level
                Source = $_.source
                Message = $_.message
                User = $_.user
                Computer = $_.computer
                SessionId = $_.sessionId
                EventId = $_.eventId
                Details = $_.details
                Exception = $_.exception
            }
        }
        
        # Display summary
        $eventStats = $events | Group-Object Level
        Write-Host "`nEvent Summary:" -ForegroundColor Cyan
        Write-Host "  Total Events: $($events.Count)" -ForegroundColor Gray
        
        foreach ($stat in $eventStats) {
            $color = switch ($stat.Name) {
                'Critical' { 'Red' }
                'Error' { 'Red' }
                'Warning' { 'Yellow' }
                'Info' { 'Green' }
                'Debug' { 'Gray' }
                default { 'White' }
            }
            Write-Host "  $($stat.Name): $($stat.Count)" -ForegroundColor $color
        }
        
        return $events | Sort-Object Timestamp -Descending
    }
    catch {
        Write-Error "Failed to retrieve events: $_"
        throw
    }
}

function Get-ProUEventSources {
    <#
    .SYNOPSIS
        Gets available event sources.
    
    .DESCRIPTION
        Retrieves the list of available event sources from the ProfileUnity system.
    
    .EXAMPLE
        Get-ProUEventSources
    #>
    [CmdletBinding()]
    param()
    
    try {
        $response = Invoke-ProfileUnityApi -Endpoint "event/sources"
        
        if ($response) {
            return $response | ForEach-Object {
                [PSCustomObject]@{
                    Source = $_.source
                    Description = $_.description
                    EventCount = $_.eventCount
                    LastEvent = $_.lastEvent
                }
            } | Sort-Object Source
        }
    }
    catch {
        Write-Error "Failed to retrieve event sources: $_"
        throw
    }
}

function Watch-ProUEvents {
    <#
    .SYNOPSIS
        Monitors ProfileUnity events in real-time.
    
    .DESCRIPTION
        Continuously monitors and displays new ProfileUnity events as they occur.
    
    .PARAMETER Level
        Minimum event level to display
    
    .PARAMETER Source
        Filter by event source
    
    .PARAMETER User
        Filter by username
    
    .PARAMETER RefreshInterval
        Refresh interval in seconds (default: 5)
    
    .PARAMETER MaxDisplay
        Maximum number of events to display at once
    
    .EXAMPLE
        Watch-ProUEvents
        
    .EXAMPLE
        Watch-ProUEvents -Level Error -RefreshInterval 10
        
    .EXAMPLE
        Watch-ProUEvents -Source "Authentication" -User "john.doe"
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Info', 'Warning', 'Error', 'Critical', 'Debug', 'All')]
        [string]$Level = 'All',
        
        [string]$Source,
        
        [string]$User,
        
        [int]$RefreshInterval = 5,
        
        [int]$MaxDisplay = 50
    )
    
    try {
        Write-Host "Monitoring ProfileUnity events (Press Ctrl+C to stop)..." -ForegroundColor Yellow
        Write-Host "Refresh interval: $RefreshInterval seconds" -ForegroundColor Gray
        Write-Host "" -ForegroundColor Gray
        
        $lastEventTime = Get-Date
        $displayedEvents = @()
        
        while ($true) {
            try {
                # Get new events since last check
                $params = @{
                    After = $lastEventTime
                    MaxEvents = $MaxDisplay
                }
                
                if ($Level -ne 'All') {
                    $params.Level = $Level
                }
                if ($Source) {
                    $params.Source = $Source
                }
                if ($User) {
                    $params.User = $User
                }
                
                $newEvents = Get-ProUEvents @params -ErrorAction SilentlyContinue
                
                if ($newEvents -and $newEvents.Count -gt 0) {
                    # Filter out events we've already displayed
                    $uniqueEvents = $newEvents | Where-Object {
                        $event = $_
                        -not ($displayedEvents | Where-Object { 
                            $_.Timestamp -eq $event.Timestamp -and 
                            $_.EventId -eq $event.EventId 
                        })
                    }
                    
                    foreach ($event in $uniqueEvents) {
                        $color = switch ($event.Level) {
                            'Critical' { 'Red' }
                            'Error' { 'Red' }
                            'Warning' { 'Yellow' }
                            'Info' { 'Green' }
                            'Debug' { 'Gray' }
                            default { 'White' }
                        }
                        
                        $timeStr = (Get-Date $event.Timestamp).ToString('HH:mm:ss')
                        $sourceStr = if ($event.Source) { "[$($event.Source)]" } else { "" }
                        $userStr = if ($event.User) { "($($event.User))" } else { "" }
                        
                        Write-Host "$timeStr " -NoNewline -ForegroundColor Gray
                        Write-Host "$($event.Level.ToUpper()) " -NoNewline -ForegroundColor $color
                        Write-Host "$sourceStr " -NoNewline -ForegroundColor Cyan
                        Write-Host "$userStr " -NoNewline -ForegroundColor Magenta
                        Write-Host "$($event.Message)" -ForegroundColor White
                        
                        $displayedEvents += $event
                        
                        # Update last event time
                        $eventTime = Get-Date $event.Timestamp
                        if ($eventTime -gt $lastEventTime) {
                            $lastEventTime = $eventTime
                        }
                    }
                    
                    # Limit displayed events to prevent memory buildup
                    if ($displayedEvents.Count -gt $MaxDisplay * 2) {
                        $displayedEvents = $displayedEvents | Select-Object -Last $MaxDisplay
                    }
                }
                
                Start-Sleep -Seconds $RefreshInterval
            }
            catch {
                Write-Warning "Error retrieving events: $_"
                Start-Sleep -Seconds $RefreshInterval
            }
        }
    }
    catch {
        Write-Error "Failed to monitor events: $_"
        throw
    }
}

function Export-ProUEvents {
    <#
    .SYNOPSIS
        Exports ProfileUnity events to a file.
    
    .DESCRIPTION
        Exports events to CSV, JSON, or XML format for analysis or archival.
    
    .PARAMETER FilePath
        Output file path
    
    .PARAMETER Format
        Export format (CSV, JSON, XML)
    
    .PARAMETER Level
        Event level filter
    
    .PARAMETER After
        Export events after this date
    
    .PARAMETER Before
        Export events before this date
    
    .PARAMETER Hours
        Export events from the last X hours
    
    .PARAMETER MaxEvents
        Maximum number of events to export
    
    .EXAMPLE
        Export-ProUEvents -FilePath "C:\Events\ProfileUnity_Events.csv" -Hours 48
        
    .EXAMPLE
        Export-ProUEvents -FilePath "C:\Events\Errors.json" -Level Error -Format JSON
    #>
    [CmdletBinding(DefaultParameterSetName = 'Hours')]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [ValidateSet('CSV', 'JSON', 'XML')]
        [string]$Format = 'CSV',
        
        [ValidateSet('Info', 'Warning', 'Error', 'Critical', 'Debug', 'All')]
        [string]$Level = 'All',
        
        [Parameter(ParameterSetName = 'DateRange')]
        [datetime]$After,
        
        [Parameter(ParameterSetName = 'DateRange')]
        [datetime]$Before,
        
        [Parameter(ParameterSetName = 'Hours')]
        [int]$Hours = 24,
        
        [int]$MaxEvents = 10000
    )
    
    try {
        Write-Host "Exporting ProfileUnity events..." -ForegroundColor Yellow
        
        # Get events with specified parameters
        $params = @{
            Level = $Level
            MaxEvents = $MaxEvents
        }
        
        if ($PSCmdlet.ParameterSetName -eq 'Hours') {
            $params.Hours = $Hours
        }
        else {
            if ($After) { $params.After = $After }
            if ($Before) { $params.Before = $Before }
        }
        
        $events = Get-ProUEvents @params
        
        if (-not $events -or $events.Count -eq 0) {
            Write-Warning "No events found to export"
            return
        }
        
        # Ensure directory exists
        $directory = Split-Path $FilePath -Parent
        if ($directory -and -not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        
        # Export in specified format
        switch ($Format) {
            'CSV' {
                $events | Export-Csv -Path $FilePath -NoTypeInformation -Encoding UTF8
            }
            'JSON' {
                $events | ConvertTo-Json -Depth 10 | Set-Content -Path $FilePath -Encoding UTF8
            }
            'XML' {
                $events | Export-Clixml -Path $FilePath -Encoding UTF8
            }
        }
        
        Write-Host "Events exported successfully:" -ForegroundColor Green
        Write-Host "  File: $FilePath" -ForegroundColor Cyan
        Write-Host "  Format: $Format" -ForegroundColor Cyan
        Write-Host "  Events: $($events.Count)" -ForegroundColor Cyan
        
        return Get-Item $FilePath
    }
    catch {
        Write-Error "Failed to export events: $_"
        throw
    }
}

function Clear-ProUEventLog {
    <#
    .SYNOPSIS
        Clears ProfileUnity event log.
    
    .DESCRIPTION
        Clears events from the ProfileUnity event log with optional filtering.
    
    .PARAMETER Before
        Clear events before this date
    
    .PARAMETER Level
        Clear events of specific level
    
    .PARAMETER Source
        Clear events from specific source
    
    .PARAMETER Confirm
        Require confirmation before clearing
    
    .EXAMPLE
        Clear-ProUEventLog -Before (Get-Date).AddDays(-30)
        
    .EXAMPLE
        Clear-ProUEventLog -Level Debug -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [datetime]$Before,
        
        [ValidateSet('Info', 'Warning', 'Error', 'Critical', 'Debug')]
        [string]$Level,
        
        [string]$Source
    )
    
    try {
        $clearParams = @{}
        $description = "all events"
        
        if ($Before) {
            $clearParams.before = $Before.ToString('yyyy-MM-ddTHH:mm:ssZ')
            $description = "events before $($Before.ToString('yyyy-MM-dd HH:mm'))"
        }
        
        if ($Level) {
            $clearParams.level = $Level
            $description = "$Level level $description"
        }
        
        if ($Source) {
            $clearParams.source = $Source
            $description = "$description from source '$Source'"
        }
        
        if ($PSCmdlet.ShouldProcess($description, "Clear ProfileUnity events")) {
            $response = Invoke-ProfileUnityApi -Endpoint "event/clear" -Method POST -Body $clearParams
            
            if ($response) {
                Write-Host "Event log cleared successfully" -ForegroundColor Green
                Write-Host "  Cleared: $($response.clearedCount) events" -ForegroundColor Cyan
                return $response
            }
        }
    }
    catch {
        Write-Error "Failed to clear event log: $_"
        throw
    }
}

# Export functions
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
Export-ModuleMember -Function @(
    'Watch-ProUEvents',
    'Export-ProUEvents')
#>




