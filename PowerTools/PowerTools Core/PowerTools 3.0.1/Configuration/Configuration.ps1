# Configuration.ps1 - ProfileUnity Configuration Management Functions

function Get-ProUConfig {
    <#
    .SYNOPSIS
        Gets ProfileUnity configurations.
    
    .DESCRIPTION
        Retrieves all configurations or filters by name.
    
    .PARAMETER Name
        Optional name filter (supports wildcards)
    
    .PARAMETER Detailed
        Include detailed configuration information
    
    .EXAMPLE
        Get-ProUConfig
        
    .EXAMPLE
        Get-ProUConfig -Name "*Production*"
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [switch]$Detailed
    )
    
    try {
        Write-Verbose "Retrieving configurations..."
        $response = Invoke-ProfileUnityApi -Endpoint "configuration"
        
        if (-not $response -or -not $response.Tag) {
            Write-Warning "No configurations found"
            return
        }
        
        $configs = $response.Tag.Rows
        
        # Filter by name if specified
        if ($Name) {
            $configs = $configs | Where-Object { $_.name -like $Name }
        }
        
        # Return detailed or summary view
        if ($Detailed) {
            foreach ($config in $configs) {
                $detailResponse = Invoke-ProfileUnityApi -Endpoint "configuration/$($config.id)"
                if ($detailResponse.tag) {
                    $detailResponse.tag
                }
            }
        }
        else {
            $configs | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.name
                    ID = $_.id
                    Description = $_.description
                    Enabled = -not $_.disabled
                    DeployCount = $_.deployCount
                    LastModified = $_.lastModified
                    ModifiedBy = $_.modifiedBy
                }
            }
        }
    }
    catch {
        Write-Error "Failed to retrieve configurations: $_"
        throw
    }
}

function Edit-ProUConfig {
    <#
    .SYNOPSIS
        Loads a ProfileUnity configuration for editing.
    
    .DESCRIPTION
        Retrieves a configuration and stores it in memory for editing.
    
    .PARAMETER Name
        The exact name of the configuration to edit
    
    .PARAMETER Quiet
        Suppress confirmation messages
    
    .EXAMPLE
        Edit-ProUConfig -Name "Windows 10 Configuration"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [switch]$Quiet
    )
    
    try {
        # Get all configurations
        $configs = Get-ProUConfig
        $config = $configs | Where-Object { $_.Name -eq $Name }
        
        if (-not $config) {
            throw "Configuration '$Name' not found"
        }
        
        Write-Verbose "Loading configuration ID: $($config.ID)"
        
        # Get full configuration details
        $response = Invoke-ProfileUnityApi -Endpoint "configuration/$($config.ID)"
        
        if (-not $response -or -not $response.tag) {
            throw "Failed to load configuration details"
        }
        
        $configData = $response.tag
        
        # Store in module config
        $script:ModuleConfig.CurrentItems.Config = $configData
        
        # Also set global variable for backward compatibility
        $global:CurrentConfig = $configData
        
        if (-not $Quiet) {
            Write-Host "Configuration '$Name' loaded for editing" -ForegroundColor Green
            Write-Host "Modules: $(if ($configData.modules) { $configData.modules.Count } else { 0 })" -ForegroundColor Cyan
            
            # Show module summary
            if ($configData.modules) {
                $moduleSummary = $configData.modules | Group-Object -Property moduleType | 
                    Select-Object Name, Count
                $moduleSummary | ForEach-Object {
                    Write-Host "  $($_.Name): $($_.Count)" -ForegroundColor Gray
                }
            }
        }
        
        return $configData
    }
    catch {
        Write-Error "Failed to edit configuration: $_"
        throw
    }
}

function Save-ProUConfig {
    <#
    .SYNOPSIS
        Saves the currently edited ProfileUnity configuration.
    
    .DESCRIPTION
        Saves changes made to the current configuration back to the server.
    
    .PARAMETER Force
        Skip confirmation prompt
    
    .EXAMPLE
        Save-ProUConfig
        
    .EXAMPLE
        Save-ProUConfig -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [switch]$Force
    )
    
    # Get current configuration
    $currentConfig = $script:ModuleConfig.CurrentItems.Config
    if (-not $currentConfig -and $global:CurrentConfig) {
        $currentConfig = $global:CurrentConfig
    }
    
    if (-not $currentConfig) {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    $configName = $currentConfig.name
    
    if ($Force -or $PSCmdlet.ShouldProcess($configName, "Save configuration")) {
        try {
            Write-Verbose "Saving configuration: $configName"
            
            # Prepare the configuration object
            $configToSave = @{
                configurations = $currentConfig
            }
            
            $response = Invoke-ProfileUnityApi -Endpoint "configuration" -Method POST -Body $configToSave
            
            if ($response) {
                Write-Host "Configuration '$configName' saved successfully" -ForegroundColor Green
                Write-LogMessage -Message "Configuration '$configName' saved by $env:USERNAME" -Level Info
                
                # Clear current config after successful save
                $script:ModuleConfig.CurrentItems.Config = $null
                $global:CurrentConfig = $null
                
                return $response
            }
        }
        catch {
            Write-Error "Failed to save configuration: $_"
            throw
        }
    }
    else {
        Write-Host "Save cancelled" -ForegroundColor Yellow
    }
}

function New-ProUConfig {
    <#
    .SYNOPSIS
        Creates a new ProfileUnity configuration.
    
    .DESCRIPTION
        Creates a new configuration with basic settings.
    
    .PARAMETER Name
        Name for the new configuration
    
    .PARAMETER Description
        Description of the configuration
    
    .PARAMETER CopyFrom
        Name of existing configuration to copy from
    
    .EXAMPLE
        New-ProUConfig -Name "Test Config" -Description "Testing configuration"
        
    .EXAMPLE
        New-ProUConfig -Name "New Config" -CopyFrom "Template Config"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [string]$Description = "Created by PowerTools",
        
        [string]$CopyFrom
    )
    
    try {
        if ($CopyFrom) {
            # Find source configuration
            $sourceConfigs = Get-ProUConfig
            $sourceConfig = $sourceConfigs | Where-Object { $_.Name -eq $CopyFrom }
            
            if (-not $sourceConfig) {
                throw "Source configuration '$CopyFrom' not found"
            }
            
            Write-Verbose "Copying from configuration: $CopyFrom"
            
            # Use the copy endpoint
            $response = Invoke-ProfileUnityApi -Endpoint "configuration/$($sourceConfig.ID)/copy" -Method POST
            
            if ($response -and $response.tag) {
                # Update the name and description
                $newConfig = $response.tag
                $newConfig.name = $Name
                $newConfig.description = $Description
                
                # Save the updated configuration
                $saveResponse = Invoke-ProfileUnityApi -Endpoint "configuration" -Method POST -Body @{
                    configurations = $newConfig
                }
                
                Write-Host "Configuration '$Name' created successfully (copied from '$CopyFrom')" -ForegroundColor Green
                return $saveResponse
            }
        }
        else {
            # Create new empty configuration
            $newConfig = @{
                name = $Name
                description = $Description
                disabled = $false
                modules = @()
                AdministrativeTemplates = @()
                FlexAppDias = @()
                UserEnvironmentConfigs = @()
            }
            
            $response = Invoke-ProfileUnityApi -Endpoint "configuration" -Method POST -Body @{
                configurations = $newConfig
            }
            
            Write-Host "Configuration '$Name' created successfully" -ForegroundColor Green
            return $response
        }
    }
    catch {
        Write-Error "Failed to create configuration: $_"
        throw
    }
}

function Remove-ProUConfig {
    <#
    .SYNOPSIS
        Removes a ProfileUnity configuration.
    
    .DESCRIPTION
        Deletes a configuration from the ProfileUnity server.
    
    .PARAMETER Name
        Name of the configuration to remove
    
    .PARAMETER Force
        Skip confirmation prompt
    
    .EXAMPLE
        Remove-ProUConfig -Name "Old Config"
        
    .EXAMPLE
        Remove-ProUConfig -Name "Test Config" -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [switch]$Force
    )
    
    try {
        # Find configuration
        $configs = Get-ProUConfig
        $config = $configs | Where-Object { $_.Name -eq $Name }
        
        if (-not $config) {
            throw "Configuration '$Name' not found"
        }
        
        if ($Force -or $PSCmdlet.ShouldProcess($Name, "Remove configuration")) {
            Write-Verbose "Deleting configuration ID: $($config.ID)"
            
            $response = Invoke-ProfileUnityApi -Endpoint "configuration/$($config.ID)?force=false" -Method DELETE
            
            Write-Host "Configuration '$Name' deleted successfully" -ForegroundColor Green
            Write-LogMessage -Message "Configuration '$Name' deleted by $env:USERNAME" -Level Info
            
            return $response
        }
        else {
            Write-Host "Delete cancelled" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "Failed to delete configuration: $_"
        throw
    }
}

function Copy-ProUConfig {
    <#
    .SYNOPSIS
        Creates a copy of a ProfileUnity configuration.
    
    .DESCRIPTION
        Copies an existing configuration with a new name.
    
    .PARAMETER SourceName
        Name of the configuration to copy
    
    .PARAMETER NewName
        Name for the new configuration
    
    .PARAMETER Description
        Optional new description
    
    .EXAMPLE
        Copy-ProUConfig -SourceName "Production" -NewName "Production-Copy"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceName,
        
        [Parameter(Mandatory)]
        [string]$NewName,
        
        [string]$Description
    )
    
    try {
        # Find source configuration
        $configs = Get-ProUConfig
        $sourceConfig = $configs | Where-Object { $_.Name -eq $SourceName }
        
        if (-not $sourceConfig) {
            throw "Source configuration '$SourceName' not found"
        }
        
        Write-Verbose "Copying configuration ID: $($sourceConfig.ID)"
        
        # Copy the configuration
        $response = Invoke-ProfileUnityApi -Endpoint "configuration/$($sourceConfig.ID)/copy" -Method POST
        
        if ($response -and $response.tag) {
            # Update the copy with new name
            $copiedConfig = $response.tag
            $copiedConfig.name = $NewName
            
            if ($Description) {
                $copiedConfig.description = $Description
            }
            else {
                $copiedConfig.description = "Copy of $SourceName - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            }
            
            # Save the updated configuration
            $saveResponse = Invoke-ProfileUnityApi -Endpoint "configuration" -Method POST -Body @{
                configurations = $copiedConfig
            }
            
            Write-Host "Configuration copied successfully" -ForegroundColor Green
            Write-Host "  Source: $SourceName" -ForegroundColor Cyan
            Write-Host "  New: $NewName" -ForegroundColor Cyan
            
            return $saveResponse
        }
    }
    catch {
        Write-Error "Failed to copy configuration: $_"
        throw
    }
}

function Test-ProUConfig {
    <#
    .SYNOPSIS
        Tests a ProfileUnity configuration for issues.
    
    .DESCRIPTION
        Validates configuration settings and checks for common problems.
    
    .PARAMETER Name
        Name of the configuration to test
    
    .EXAMPLE
        Test-ProUConfig -Name "Production Config"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    try {
        Write-Host "Testing configuration: $Name" -ForegroundColor Yellow
        
        # Load the configuration
        Edit-ProUConfig -Name $Name -Quiet
        
        $config = $script:ModuleConfig.CurrentItems.Config
        if (-not $config) {
            throw "Failed to load configuration"
        }
        
        $issues = @()
        $warnings = @()
        
        # Check if configuration is disabled
        if ($config.disabled) {
            $warnings += "Configuration is disabled"
        }
        
        # Check for modules
        if (-not $config.modules -or $config.modules.Count -eq 0) {
            $warnings += "Configuration has no modules defined"
        }
        
        # Check for filters
        $hasFilters = $false
        if ($config.modules) {
            foreach ($module in $config.modules) {
                if ($module.FilterId -and $module.FilterId -ne [guid]::Empty) {
                    $hasFilters = $true
                    break
                }
            }
        }
        
        if (-not $hasFilters) {
            $warnings += "No filters assigned to any modules"
        }
        
        # Check for administrative templates
        if ($config.AdministrativeTemplates -and $config.AdministrativeTemplates.Count -gt 0) {
            Write-Host "  Administrative Templates: $($config.AdministrativeTemplates.Count)" -ForegroundColor Gray
        }
        
        # Display results
        Write-Host "`nTest Results:" -ForegroundColor Cyan
        
        if ($issues.Count -eq 0 -and $warnings.Count -eq 0) {
            Write-Host "  No issues found" -ForegroundColor Green
        }
        else {
            if ($issues.Count -gt 0) {
                Write-Host "  Issues:" -ForegroundColor Red
                $issues | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
            }
            
            if ($warnings.Count -gt 0) {
                Write-Host "  Warnings:" -ForegroundColor Yellow
                $warnings | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
            }
        }
        
        # Clear the loaded config
        $script:ModuleConfig.CurrentItems.Config = $null
        $global:CurrentConfig = $null
        
        return [PSCustomObject]@{
            ConfigurationName = $Name
            Issues = $issues
            Warnings = $warnings
            IsValid = $issues.Count -eq 0
        }
    }
    catch {
        Write-Error "Failed to test configuration: $_"
        throw
    }
}

function Get-ProUConfigModules {
    <#
    .SYNOPSIS
        Gets available configuration modules.
    
    .DESCRIPTION
        Retrieves the list of available module types for configurations.
    
    .EXAMPLE
        Get-ProUConfigModules
    #>
    [CmdletBinding()]
    param()
    
    try {
        $response = Invoke-ProfileUnityApi -Endpoint "configuration/modules"
        
        if ($response) {
            return $response | ForEach-Object {
                [PSCustomObject]@{
                    ModuleType = $_.moduleType
                    DisplayName = $_.displayName
                    Category = $_.category
                    Description = $_.description
                }
            }
        }
    }
    catch {
        Write-Error "Failed to retrieve configuration modules: $_"
        throw
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-ProUConfig',
    'Edit-ProUConfig',
    'Save-ProUConfig',
    'New-ProUConfig',
    'Remove-ProUConfig',
    'Copy-ProUConfig',
    'Test-ProUConfig',
    'Get-ProUConfigModules'
)