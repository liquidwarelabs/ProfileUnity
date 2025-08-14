# Core/AutoCompletion.ps1 - Auto-Completion and IntelliSense Helpers for ProfileUnity PowerTools

# =============================================================================
# AUTO-COMPLETION REGISTRATION
# =============================================================================

# Configuration Name Completers
Register-ArgumentCompleter -CommandName @(
    'Edit-ProUConfig', 'Remove-ProUConfig', 'Copy-ProUConfig', 'Test-ProUConfig',
    'Export-ProUConfig', 'Deploy-ProUConfiguration', 'Get-ProUConfigScript'
) -ParameterName 'Name' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    try {
        $configs = Get-ProUConfig -ErrorAction SilentlyContinue
        $configs | Where-Object { $_.Name -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                "'$($_.Name)'",
                $_.Name,
                'ParameterValue',
                "Configuration: $($_.Description)"
            )
        }
    }
    catch {
        # Return empty if can't retrieve configs
    }
}

# Filter Name Completers
Register-ArgumentCompleter -CommandName @(
    'Edit-ProUFilter', 'Remove-ProUFilter', 'Copy-ProUFilter', 'Test-ProUFilter',
    'Export-ProUFilter', 'Add-ProUFlexAppDia', 'Add-ProUAdmx'
) -ParameterName @('Name', 'FilterName') -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    try {
        $filters = Get-ProUFilters -ErrorAction SilentlyContinue
        $filters | Where-Object { $_.Name -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                "'$($_.Name)'",
                $_.Name,
                'ParameterValue',
                "Filter: $($_.Description)"
            )
        }
    }
    catch {
        # Return empty if can't retrieve filters
    }
}

# FlexApp Name Completers
Register-ArgumentCompleter -CommandName @(
    'Edit-ProUFlexapp', 'Remove-ProUFlexapp', 'Enable-ProUFlexapp', 'Disable-ProUFlexapp',
    'Add-ProUFlexAppDia', 'Remove-ProUFlexAppDia', 'Enable-ProUFlexAppDia', 'Disable-ProUFlexAppDia'
) -ParameterName @('Name', 'DIAName') -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    try {
        $flexApps = Get-ProUFlexapps -ErrorAction SilentlyContinue
        $flexApps | Where-Object { $_.Name -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                "'$($_.Name)'",
                $_.Name,
                'ParameterValue',
                "FlexApp: $($_.Description)"
            )
        }
    }
    catch {
        # Return empty if can't retrieve FlexApps
    }
}

# Server Name Completers (for connection)
Register-ArgumentCompleter -CommandName 'Connect-ProfileUnityServer' -ParameterName 'ServerName' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    # Get recent servers from registry or config
    $recentServers = @()
    try {
        $configPath = Join-Path $env:APPDATA "ProfileUnity-PowerTools\RecentServers.json"
        if (Test-Path $configPath) {
            $recentConfig = Get-Content $configPath | ConvertFrom-Json
            $recentServers = $recentConfig.Servers
        }
    }
    catch {
        # Use default common server names if config not available
        $recentServers = @('localhost', 'profileunity-server', 'pu-prod', 'pu-dev', 'pu-test')
    }
    
    $recentServers | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(
            $_,
            $_,
            'ParameterValue',
            "Recent server: $_"
        )
    }
}

# Path Completers for common operations
Register-ArgumentCompleter -CommandName @(
    'Export-ProUConfig', 'Import-ProUConfig', 'Backup-ProUEnvironment',
    'Export-ProUHealthReport', 'Enable-ProUDetailedLogging'
) -ParameterName @('Path', 'SavePath', 'OutputPath', 'LogPath', 'BackupPath') -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    # Provide common paths based on parameter context
    $commonPaths = @()
    
    switch -Wildcard ($parameterName) {
        '*Export*' -or '*Output*' {
            $commonPaths += [Environment]::GetFolderPath('MyDocuments')
            $commonPaths += [Environment]::GetFolderPath('Desktop')
            $commonPaths += Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ProfileUnity-Exports'
        }
        '*Backup*' {
            $commonPaths += Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ProfileUnity-Backups'
            $commonPaths += "C:\Backups"
            $commonPaths += "\\server\backups"
        }
        '*Log*' {
            $commonPaths += Join-Path $env:TEMP 'ProfileUnity-Logs'
            $commonPaths += Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ProfileUnity-PowerTools\Logs'
        }
    }
    
    # Add current directory and parent
    $commonPaths += Get-Location
    $commonPaths += Split-Path (Get-Location) -Parent
    
    $commonPaths | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(
            "'$_'",
            $_,
            'ParameterValue',
            "Path: $_"
        )
    }
}

# Template Name Completers
Register-ArgumentCompleter -CommandName @(
    'New-ProUConfig', 'New-ProUConfigurationTemplate', 'Deploy-ProUTemplate'
) -ParameterName 'Template' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    try {
        $templates = Get-ProUTemplate -ErrorAction SilentlyContinue
        $templates | Where-Object { $_.Name -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                "'$($_.Name)'",
                $_.Name,
                'ParameterValue',
                "Template: $($_.Description)"
            )
        }
    }
    catch {
        # Provide built-in template names
        $builtInTemplates = @('RemoteAccess', 'KioskMode', 'DeveloperWorkstation', 'ExecutiveDesktop', 'SharedComputer')
        $builtInTemplates | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new(
                $_,
                $_,
                'ParameterValue',
                "Built-in template: $_"
            )
        }
    }
}

# Help Topic Completers
Register-ArgumentCompleter -CommandName 'Get-ProUHelp' -ParameterName 'Topic' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    
    $helpTopics = @(
        'Getting Started', 'Configurations', 'FlexApp', 'ADMX', 'Filters', 
        'Troubleshooting', 'Deployment', 'Security', 'Performance', 'Integration'
    )
    
    $helpTopics | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(
            "'$_'",
            $_,
            'ParameterValue',
            "Help topic: $_"
        )
    }
}

# =============================================================================
# INTELLISENSE HELPERS
# =============================================================================

function Get-ProUIntelliSenseData {
    <#
    .SYNOPSIS
        Retrieves IntelliSense data for ProfileUnity objects.
    
    .PARAMETER ObjectType
        Type of object to get IntelliSense data for
    
    .PARAMETER Refresh
        Force refresh of cached data
    
    .EXAMPLE
        Get-ProUIntelliSenseData -ObjectType Configuration
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Configuration', 'Filter', 'FlexApp', 'Template', 'Server')]
        [string]$ObjectType,
        
        [switch]$Refresh
    )
    
    # Use cached data unless refresh requested
    $cacheKey = "IntelliSense_$ObjectType"
    if (-not $Refresh -and $script:ModuleConfig.IntelliSenseCache -and $script:ModuleConfig.IntelliSenseCache[$cacheKey]) {
        $cacheData = $script:ModuleConfig.IntelliSenseCache[$cacheKey]
        $cacheAge = (Get-Date) - $cacheData.Timestamp
        if ($cacheAge.TotalMinutes -lt 5) {  # 5-minute cache
            return $cacheData.Data
        }
    }
    
    # Retrieve fresh data
    $data = switch ($ObjectType) {
        'Configuration' {
            try {
                Get-ProUConfig | Select-Object Name, Description, LastModified, ModifiedBy
            }
            catch { @() }
        }
        'Filter' {
            try {
                Get-ProUFilters | Select-Object Name, Description, Type, Criteria
            }
            catch { @() }
        }
        'FlexApp' {
            try {
                Get-ProUFlexapps | Select-Object Name, Description, Version, Size
            }
            catch { @() }
        }
        'Template' {
            try {
                Get-ProUTemplate | Select-Object Name, Description, Category, Components
            }
            catch { @() }
        }
        'Server' {
            try {
                @{
                    ServerInfo = Get-ProUServerAbout
                    Settings = Get-ProUServerSettings
                    Status = Test-ProfileUnityConnection
                }
            }
            catch { @{} }
        }
    }
    
    # Cache the data
    if (-not $script:ModuleConfig.IntelliSenseCache) {
        $script:ModuleConfig.IntelliSenseCache = @{}
    }
    
    $script:ModuleConfig.IntelliSenseCache[$cacheKey] = @{
        Data = $data
        Timestamp = Get-Date
    }
    
    return $data
}

function Show-ProUObjectPreview {
    <#
    .SYNOPSIS
        Shows a quick preview of a ProfileUnity object.
    
    .PARAMETER ObjectType
        Type of object to preview
    
    .PARAMETER Name
        Name of the object to preview
    
    .EXAMPLE
        Show-ProUObjectPreview -ObjectType Configuration -Name "Production"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Configuration', 'Filter', 'FlexApp')]
        [string]$ObjectType,
        
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    try {
        $object = switch ($ObjectType) {
            'Configuration' { Get-ProUConfig | Where-Object { $_.Name -eq $Name } }
            'Filter' { Get-ProUFilters | Where-Object { $_.Name -eq $Name } }
            'FlexApp' { Get-ProUFlexapps | Where-Object { $_.Name -eq $Name } }
        }
        
        if (-not $object) {
            Write-Host "Object '$Name' not found" -ForegroundColor Red
            return
        }
        
        Write-Host "`n=== $ObjectType: $Name ===" -ForegroundColor Cyan
        
        switch ($ObjectType) {
            'Configuration' {
                Write-Host "Description: $($object.Description)" -ForegroundColor White
                Write-Host "Last Modified: $($object.LastModified)" -ForegroundColor Gray
                Write-Host "Modified By: $($object.ModifiedBy)" -ForegroundColor Gray
                
                # Show module counts
                if ($object.Modules) {
                    Write-Host "Modules:" -ForegroundColor Yellow
                    $object.Modules | ForEach-Object {
                        Write-Host "  $($_.Type): $($_.Count)" -ForegroundColor White
                    }
                }
            }
            'Filter' {
                Write-Host "Description: $($object.Description)" -ForegroundColor White
                Write-Host "Type: $($object.Type)" -ForegroundColor Gray
                if ($object.Criteria) {
                    Write-Host "Criteria: $($object.Criteria.Count) rules" -ForegroundColor Gray
                }
            }
            'FlexApp' {
                Write-Host "Description: $($object.Description)" -ForegroundColor White
                Write-Host "Version: $($object.Version)" -ForegroundColor Gray
                Write-Host "Size: $($object.Size)" -ForegroundColor Gray
                Write-Host "Status: $($object.Status)" -ForegroundColor Gray
            }
        }
        
        Write-Host "`nCommon Actions:" -ForegroundColor Yellow
        switch ($ObjectType) {
            'Configuration' {
                Write-Host "  Edit-ProUConfig -Name '$Name'" -ForegroundColor Cyan
                Write-Host "  Deploy-ProUConfiguration -Name '$Name'" -ForegroundColor Cyan
                Write-Host "  Test-ProUConfig -Name '$Name'" -ForegroundColor Cyan
            }
            'Filter' {
                Write-Host "  Edit-ProUFilter -Name '$Name'" -ForegroundColor Cyan
                Write-Host "  Copy-ProUFilter -Name '$Name'" -ForegroundColor Cyan
            }
            'FlexApp' {
                Write-Host "  Add-ProUFlexAppDia -DIAName '$Name'" -ForegroundColor Cyan
                Write-Host "  Edit-ProUFlexapp -Name '$Name'" -ForegroundColor Cyan
            }
        }
    }
    catch {
        Write-Host "Error retrieving object preview: $_" -ForegroundColor Red
    }
}

function Get-ProUSmartSuggestions {
    <#
    .SYNOPSIS
        Provides smart suggestions based on command context and history.
    
    .PARAMETER LastCommand
        The last command executed (for context)
    
    .PARAMETER CurrentContext
        Current working context
    
    .EXAMPLE
        Get-ProUSmartSuggestions -LastCommand "Get-ProUConfig"
    #>
    [CmdletBinding()]
    param(
        [string]$LastCommand,
        [string]$CurrentContext
    )
    
    $suggestions = @()
    
    # Context-based suggestions
    if ($LastCommand -like "*Get-ProUConfig*") {
        $suggestions += @{
            Command = "Edit-ProUConfig -Name '<ConfigName>'"
            Description = "Edit a configuration from the list"
            Priority = 1
        }
        $suggestions += @{
            Command = "Deploy-ProUConfiguration -Name '<ConfigName>'"
            Description = "Deploy a configuration"
            Priority = 2
        }
    }
    
    if ($LastCommand -like "*Edit-ProUConfig*") {
        $suggestions += @{
            Command = "Save-ProUConfig"
            Description = "Save your configuration changes"
            Priority = 1
        }
        $suggestions += @{
            Command = "Test-ProUConfig"
            Description = "Validate the configuration"
            Priority = 2
        }
        $suggestions += @{
            Command = "Show-ProUConfigurationSummary"
            Description = "View current configuration summary"
            Priority = 3
        }
    }
    
    # Check current loaded configuration
    $currentConfig = $script:ModuleConfig.CurrentItems.Config
    if ($currentConfig) {
        $suggestions += @{
            Command = "Save-ProUConfig"
            Description = "Save changes to '$($currentConfig.Name)'"
            Priority = 1
        }
    }
    
    # Common workflow suggestions
    if (-not (Test-ProfileUnityConnection -ErrorAction SilentlyContinue)) {
        $suggestions += @{
            Command = "Connect-ProfileUnityServer"
            Description = "Connect to ProfileUnity server"
            Priority = 1
        }
    }
    
    # Sort by priority and return top suggestions
    return $suggestions | Sort-Object Priority | Select-Object -First 5
}

function Enable-ProUAutoComplete {
    <#
    .SYNOPSIS
        Enables enhanced auto-completion features for ProfileUnity PowerTools.
    
    .PARAMETER Features
        Specific features to enable
    
    .EXAMPLE
        Enable-ProUAutoComplete -Features @('ObjectNames', 'Paths', 'SmartSuggestions')
    #>
    [CmdletBinding()]
    param(
        [string[]]$Features = @('ObjectNames', 'Paths', 'SmartSuggestions', 'History')
    )
    
    Write-Host "Enabling ProfileUnity auto-completion features..." -ForegroundColor Cyan
    
    foreach ($feature in $Features) {
        switch ($feature) {
            'ObjectNames' {
                Write-Host "  ✓ Object name completion" -ForegroundColor Green
                # Already registered above
            }
            'Paths' {
                Write-Host "  ✓ Path completion" -ForegroundColor Green
                # Already registered above
            }
            'SmartSuggestions' {
                Write-Host "  ✓ Smart command suggestions" -ForegroundColor Green
                $script:ModuleConfig.SmartSuggestions = $true
            }
            'History' {
                Write-Host "  ✓ Command history integration" -ForegroundColor Green
                $script:ModuleConfig.HistoryIntegration = $true
            }
        }
    }
    
    # Set up PSReadLine integration if available
    if (Get-Module -Name PSReadLine -ListAvailable) {
        try {
            Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
            Set-PSReadLineOption -PredictionSource History
            Write-Host "  ✓ PSReadLine integration enabled" -ForegroundColor Green
        }
        catch {
            Write-Host "  ⚠ PSReadLine integration failed: $_" -ForegroundColor Yellow
        }
    }
    
    Write-Host "`nAuto-completion features enabled! Start typing ProfileUnity commands and press Tab for suggestions." -ForegroundColor Yellow
}

function Update-ProUAutoCompleteCache {
    <#
    .SYNOPSIS
        Updates the auto-completion cache with fresh data.
    
    .PARAMETER Force
        Force update even if cache is recent
    
    .EXAMPLE
        Update-ProUAutoCompleteCache -Force
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )
    
    Write-Host "Updating auto-completion cache..." -ForegroundColor Cyan
    
    $objectTypes = @('Configuration', 'Filter', 'FlexApp', 'Template', 'Server')
    
    foreach ($type in $objectTypes) {
        try {
            $data = Get-ProUIntelliSenseData -ObjectType $type -Refresh:$Force
            Write-Host "  ✓ $type data cached ($($data.Count) items)" -ForegroundColor Green
        }
        catch {
            Write-Host "  ✗ Failed to cache $type data: $_" -ForegroundColor Red
        }
    }
    
    Write-Host "Auto-completion cache updated!" -ForegroundColor Green
}

# =============================================================================
# SAVE RECENT SERVERS FOR COMPLETION
# =============================================================================

function Save-ProURecentServer {
    <#
    .SYNOPSIS
        Saves a server to the recent servers list for auto-completion.
    
    .PARAMETER ServerName
        Server name to save
    
    .EXAMPLE
        Save-ProURecentServer -ServerName "profileunity-prod"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerName
    )
    
    try {
        $configDir = Join-Path $env:APPDATA "ProfileUnity-PowerTools"
        $configPath = Join-Path $configDir "RecentServers.json"
        
        # Create directory if needed
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }
        
        # Load existing config
        $recentConfig = if (Test-Path $configPath) {
            Get-Content $configPath | ConvertFrom-Json
        } else {
            @{ Servers = @() }
        }
        
        # Add server to list (avoid duplicates)
        if ($ServerName -notin $recentConfig.Servers) {
            $recentConfig.Servers = @($ServerName) + $recentConfig.Servers
        } else {
            # Move to front
            $recentConfig.Servers = @($ServerName) + ($recentConfig.Servers | Where-Object { $_ -ne $ServerName })
        }
        
        # Keep only last 10 servers
        $recentConfig.Servers = $recentConfig.Servers | Select-Object -First 10
        
        # Save config
        $recentConfig | ConvertTo-Json | Out-File -FilePath $configPath -Encoding UTF8
    }
    catch {
        Write-Verbose "Could not save recent server: $_"
    }
}

# Initialize auto-completion when module loads
if ($PSVersionTable.PSVersion.Major -ge 5) {
    Enable-ProUAutoComplete -Features @('ObjectNames', 'Paths') -ErrorAction SilentlyContinue
}

# Export functions
Export-ModuleMember -Function @(
    'Get-ProUIntelliSenseData',
    'Show-ProUObjectPreview',
    'Get-ProUSmartSuggestions',
    'Enable-ProUAutoComplete',
    'Update-ProUAutoCompleteCache',
    'Save-ProURecentServer'
)