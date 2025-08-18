# Core\AutoCompletion.ps1 - Auto-completion and IntelliSense Functions
# Relative Path: \Core\AutoCompletion.ps1

# =============================================================================
# AUTO-COMPLETION AND INTELLISENSE FUNCTIONS
# =============================================================================

function Get-ProUIntelliSenseData {
    <#
    .SYNOPSIS
        Provides IntelliSense data for ProfileUnity PowerTools commands.
    
    .DESCRIPTION
        Returns contextual help and suggestions for ProfileUnity commands.
    
    .PARAMETER CommandName
        The command to provide IntelliSense for
    
    .PARAMETER ParameterName
        The parameter to provide suggestions for
    
    .EXAMPLE
        Get-ProUIntelliSenseData -CommandName "Edit-ProUConfig"
    #>
    [CmdletBinding()]
    param(
        [string]$CommandName,
        [string]$ParameterName
    )
    
    $intelliSenseData = @{}
    
    # Configuration commands
    if ($CommandName -like "*Config*") {
        $intelliSenseData.Configurations = try {
            Get-ProUConfig | Select-Object -ExpandProperty name
        } catch {
            @()
        }
        
        $intelliSenseData.Suggestions = @(
            "Use Get-ProUConfig to list all configurations",
            "Use Edit-ProUConfig -Name '<ConfigName>' to load for editing",
            "Use Save-ProUConfig to save changes"
        )
    }
    
    # Filter commands
    if ($CommandName -like "*Filter*") {
        $intelliSenseData.Filters = try {
            Get-ProUFilters | Select-Object -ExpandProperty name
        } catch {
            @()
        }
        
        $intelliSenseData.Suggestions = @(
            "Use Get-ProUFilters to list all filters",
            "Use Edit-ProUFilter -Name '<FilterName>' to load for editing"
        )
    }
    
    # Command-specific suggestions
    switch -Wildcard ($CommandName) {
        '*Get*' {
            $intelliSenseData.Suggestions += @(
                "Get commands retrieve data from ProfileUnity server",
                "No changes are made to server data"
            )
        }
        
        '*Edit*' {
            $intelliSenseData.Suggestions += @(
                "Edit commands load items into memory for modification",
                "Remember to use Save command to persist changes"
            )
        }
        
        '*Save*' {
            $intelliSenseData.Suggestions += @(
                "Save commands persist changes to ProfileUnity server",
                "Use -Force to skip confirmation prompts"
            )
        }
        
        '*Export*' {
            $intelliSenseData.Suggestions += @(
                "Export commands save ProfileUnity items to JSON files",
                "Specify -SavePath parameter for output directory"
            )
        }
        
        '*Import*' {
            $intelliSenseData.Suggestions += @(
                "Import commands load ProfileUnity items from JSON files",
                "Use -JsonFile parameter to specify source file"
            )
        }
        
        '*Remove*' {
            $intelliSenseData.Suggestions += @(
                "Remove commands delete items from ProfileUnity server",
                "This action cannot be undone - use with caution"
            )
        }
    }
    
    return $intelliSenseData
}

function Show-ProUObjectPreview {
    <#
    .SYNOPSIS
        Shows a preview of ProfileUnity objects for IntelliSense.
    
    .DESCRIPTION
        Displays preview information about ProfileUnity configurations, filters, etc.
    
    .PARAMETER ObjectType
        Type of object to preview
    
    .PARAMETER Name
        Name of the specific object
    
    .EXAMPLE
        Show-ProUObjectPreview -ObjectType "Configuration" -Name "Test Config"
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Configuration', 'Filter', 'FlexApp', 'PortRule')]
        [string]$ObjectType,
        
        [string]$Name
    )
    
    try {
        Write-Host "=== ${ObjectType}: ${Name} ===" -ForegroundColor Cyan
        
        switch ($ObjectType) {
            'Configuration' {
                $config = Get-ProUConfig -Name $Name
                if ($config) {
                    Write-Host "ID: $($config.id)" -ForegroundColor Gray
                    Write-Host "Enabled: $(-not $config.disabled)" -ForegroundColor $(if($config.disabled){'Red'}else{'Green'})
                    Write-Host "Description: $($config.description)" -ForegroundColor Gray
                }
            }
            
            'Filter' {
                $filter = Get-ProUFilters -Name $Name
                if ($filter) {
                    Write-Host "ID: $($filter.id)" -ForegroundColor Gray
                    Write-Host "Type: $($filter.filterType)" -ForegroundColor Gray
                    Write-Host "Description: $($filter.description)" -ForegroundColor Gray
                }
            }
            
            default {
                Write-Host "Preview not available for $ObjectType" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "Could not load preview for $ObjectType '$Name'" -ForegroundColor Red
    }
}

function Get-ProUSmartSuggestions {
    <#
    .SYNOPSIS
        Provides smart suggestions based on current context.
    
    .DESCRIPTION
        Analyzes current ProfileUnity context and suggests next actions.
    
    .PARAMETER LastCommand
        The last command executed
    
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
            Command = "Update-ProUConfig -Name '<ConfigName>'"
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
            Command = "Show-ProUConfigurationSummary"
            Description = "View current configuration summary"
            Priority = 2
        }
    }
    
    # Check current loaded items
    if ($script:ModuleConfig -and $script:ModuleConfig.CurrentItems -and $script:ModuleConfig.CurrentItems.Config) {
        $suggestions += @{
            Command = "Save-ProUConfig"
            Description = "Save changes to current configuration"
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
    
    .DESCRIPTION
        Sets up tab completion and IntelliSense for ProfileUnity commands.
    
    .PARAMETER Features
        Array of features to enable
    
    .EXAMPLE
        Enable-ProUAutoComplete -Features @('ObjectNames', 'Paths')
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('ObjectNames', 'Paths', 'Parameters', 'All')]
        [string[]]$Features = @('ObjectNames')
    )
    
    try {
        if ($Features -contains 'All') {
            $Features = @('ObjectNames', 'Paths', 'Parameters')
        }
        
        foreach ($feature in $Features) {
            switch ($feature) {
                'ObjectNames' {
                    Write-Verbose "Enabling object name completion"
                    # Tab completion for configuration names
                    Register-ArgumentCompleter -CommandName Edit-ProUConfig -ParameterName Name -ScriptBlock {
                        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
                        try {
                            Get-ProUConfig | Where-Object { $_.name -like "*$wordToComplete*" } | 
                                ForEach-Object { "'$($_.name)'" }
                        } catch {
                            @()
                        }
                    }
                    
                    # Tab completion for filter names
                    Register-ArgumentCompleter -CommandName Edit-ProUFilter -ParameterName Name -ScriptBlock {
                        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
                        try {
                            Get-ProUFilters | Where-Object { $_.name -like "*$wordToComplete*" } | 
                                ForEach-Object { "'$($_.name)'" }
                        } catch {
                            @()
                        }
                    }
                }
                
                'Paths' {
                    Write-Verbose "Enabling path completion"
                    # Path completion for export/import functions
                    $pathCommands = @('Export-ProUConfig', 'Export-ProUConfigAll', 'Import-ProUConfig', 'Import-ProUConfigAll')
                    foreach ($cmd in $pathCommands) {
                        Register-ArgumentCompleter -CommandName $cmd -ParameterName SavePath -ScriptBlock {
                            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
                            $paths = Get-ChildItem -Path "$wordToComplete*" -Directory -ErrorAction SilentlyContinue
                            $paths | ForEach-Object { "'$($_.FullName)'" }
                        }
                    }
                }
                
                'Parameters' {
                    Write-Verbose "Enabling parameter completion"
                    # Additional parameter completions can be added here
                }
            }
        }
        
        Write-Host "Auto-completion features enabled: $($Features -join ', ')" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to enable auto-completion: $_"
    }
}

function Update-ProUAutoCompleteCache {
    <#
    .SYNOPSIS
        Updates the auto-completion cache with current ProfileUnity data.
    
    .DESCRIPTION
        Refreshes cached data used for auto-completion to ensure current information.
    
    .EXAMPLE
        Update-ProUAutoCompleteCache
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-Host "Updating auto-completion cache..." -ForegroundColor Yellow
        
        # Cache configuration names
        $script:CachedConfigurations = try {
            Get-ProUConfig | Select-Object -ExpandProperty name
        } catch {
            @()
        }
        
        # Cache filter names
        $script:CachedFilters = try {
            Get-ProUFilters | Select-Object -ExpandProperty name
        } catch {
            @()
        }
        
        Write-Host "Auto-completion cache updated" -ForegroundColor Green
        Write-Host "  Configurations: $($script:CachedConfigurations.Count)" -ForegroundColor Gray
        Write-Host "  Filters: $($script:CachedFilters.Count)" -ForegroundColor Gray
    }
    catch {
        Write-Warning "Failed to update auto-completion cache: $_"
    }
}

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
    try {
        Enable-ProUAutoComplete -Features @('ObjectNames', 'Paths') -ErrorAction SilentlyContinue
    }
    catch {
        Write-Verbose "Auto-completion initialization failed: $_"
    }
}

# Export functions
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
Export-ModuleMember -Function @(
    'Get-ProUIntelliSenseData',
    'Show-ProUObjectPreview',
    'Get-ProUSmartSuggestions',
    'Enable-ProUAutoComplete',
    'Update-ProUAutoCompleteCache',
    'Save-ProURecentServer'
)
#>
