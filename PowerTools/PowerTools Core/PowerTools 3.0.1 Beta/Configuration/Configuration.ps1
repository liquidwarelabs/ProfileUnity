# Configuration.ps1 - ProfileUnity Configuration Management Functions
# Location: \Configuration\Configuration.ps1
# Compatible with: ProfileUnity PowerTools v3.0 / PowerShell 5.1+

function Clean-AdmxText {
    <#
    .SYNOPSIS
        Cleans problematic characters from ADMX text data to prevent JSON parsing errors.
    
    .DESCRIPTION
        Removes or replaces characters that cause JSON parsing errors during Save-ProUConfig.
        This includes control characters, invalid Unicode sequences, and other problematic characters.
    
    .PARAMETER Text
        The text to clean
    
    .RETURNS
        Cleaned text safe for JSON serialization
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )
    
    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }
    
    # More aggressive cleaning - only allow safe ASCII characters and basic punctuation
    # This is more restrictive but should prevent all JSON parsing issues
    $cleaned = $Text -replace '[^\x20-\x7E]', ' '
    
    # Replace multiple spaces with single space
    $cleaned = $cleaned -replace '\s+', ' '
    
    # Trim whitespace
    $cleaned = $cleaned.Trim()
    
    # Ensure the text is not too long (JSON has limits)
    if ($cleaned.Length -gt 10000) {
        $cleaned = $cleaned.Substring(0, 10000) + "..."
    }
    
    return $cleaned
}

function Clean-AdmxObject {
    <#
    .SYNOPSIS
        Recursively cleans all text properties in an ADMX object.
    
    .DESCRIPTION
        Traverses through all properties of an ADMX object and cleans any string values
        to prevent JSON parsing errors during Save-ProUConfig.
    
    .PARAMETER Object
        The object to clean
    
    .RETURNS
        The cleaned object
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Object
    )
    
    if ($null -eq $Object) {
        return $Object
    }
    
    # Handle arrays
    if ($Object -is [array]) {
        for ($i = 0; $i -lt $Object.Count; $i++) {
            $Object[$i] = Clean-AdmxObject -Object $Object[$i]
        }
        return $Object
    }
    
    # Handle PSCustomObject and other objects with properties
    if ($Object -is [PSCustomObject] -or $Object.GetType().GetProperties()) {
        $properties = $Object.PSObject.Properties
        foreach ($prop in $properties) {
            if ($prop.Value -is [string]) {
                $prop.Value = Clean-AdmxText -Text $prop.Value
            }
            elseif ($prop.Value -is [array] -or $prop.Value -is [PSCustomObject]) {
                $prop.Value = Clean-AdmxObject -Object $prop.Value
            }
        }
        return $Object
    }
    
    # Handle simple types
    if ($Object -is [string]) {
        return Clean-AdmxText -Text $Object
    }
    
    return $Object
}



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
        
        # Handle different response formats consistently
        $configs = if ($response.Tag.Rows) { 
            $response.Tag.Rows 
        } elseif ($response.tag) { 
            $response.tag 
        } elseif ($response) { 
            $response 
        } else { 
            @() 
        }
        
        if (-not $configs) {
            Write-Warning "No configurations found"
            return
        }
        
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
        
        # Store in module config with null checking
        if (-not $script:ModuleConfig) {
            $script:ModuleConfig = @{ CurrentItems = @{} }
        }
        if (-not $script:ModuleConfig.CurrentItems) {
            $script:ModuleConfig.CurrentItems = @{}
        }
        $script:ModuleConfig.CurrentItems.Config = $configData
        
        # Also set global variable for backward compatibility
        $global:CurrentConfig = $configData
        
        if (-not $Quiet) {
            Write-Host "Configuration '$Name' loaded for editing" -ForegroundColor Green
            
            # Count actual configuration components
            $componentCount = 0
            $components = @()
            
            if ($configData.FlexAppDias -and $configData.FlexAppDias.Count -gt 0) {
                $componentCount += $configData.FlexAppDias.Count
                $components += "FlexApp DIAs: $($configData.FlexAppDias.Count)"
            }
            if ($configData.Registries -and $configData.Registries.Count -gt 0) {
                $componentCount += $configData.Registries.Count
                $components += "Registry: $($configData.Registries.Count)"
            }
            if ($configData.AdministrativeTemplates -and $configData.AdministrativeTemplates.Count -gt 0) {
                $componentCount += $configData.AdministrativeTemplates.Count
                $components += "ADMX: $($configData.AdministrativeTemplates.Count)"
            }
            if ($configData.EnvironmentVariables -and $configData.EnvironmentVariables.Count -gt 0) {
                $componentCount += $configData.EnvironmentVariables.Count
                $components += "Environment: $($configData.EnvironmentVariables.Count)"
            }
            if ($configData.Shortcuts -and $configData.Shortcuts.Count -gt 0) {
                $componentCount += $configData.Shortcuts.Count
                $components += "Shortcuts: $($configData.Shortcuts.Count)"
            }
            
            Write-Host "Components: $componentCount" -ForegroundColor Cyan
            if ($components.Count -gt 0) {
                $components | ForEach-Object {
                    Write-Host "  $_" -ForegroundColor Gray
                }
            }
        }
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
    [CmdletBinding(SupportsShouldProcess)]
    param([switch]$Force) 
    
    if ($Force) {
        Save-ProfileUnityItem -ItemType 'configuration' -Force -Confirm:$false
    } else {
        Save-ProfileUnityItem -ItemType 'configuration'
    }
}

function Save-ProfileUnityItem {
    <#
    .SYNOPSIS
        Universal save function for ProfileUnity items.
    
    .DESCRIPTION
        Saves any ProfileUnity item type with proper error handling.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('configuration', 'filter', 'portability', 'flexapppackage')]
        [string]$ItemType,
        
        [switch]$Force
    )
    
    $currentKey = switch ($ItemType) {
        'configuration' { 'Config' }
        'filter' { 'Filter' }
        'portability' { 'PortRule' }
        'flexapppackage' { 'FlexApp' }
    }
    
    $currentItem = $script:ModuleConfig.CurrentItems[$currentKey]
    
    # Also check global variables for backward compatibility
    if (-not $currentItem) {
        $currentItem = switch ($ItemType) {
            'configuration' { $global:CurrentConfig }
            'filter' { $global:CurrentFilter }
            'portability' { $global:CurrentPortRule }
            'flexapppackage' { $global:CurrentFlexapp }
        }
    }
    
    if (-not $currentItem) {
        throw "No $ItemType loaded for editing. Use Edit-ProU$currentKey first."
    }
    
    # Use standard PowerShell confirmation pattern
    # -Force bypasses confirmation, or user can use -Confirm:$false
    if ($Force -or $PSCmdlet.ShouldProcess("$ItemType on ProfileUnity server", "Save")) {
        try {
            Write-Verbose "Saving $ItemType to ProfileUnity server..."
            Write-Verbose "Item type: $ItemType"
            Write-Verbose "Current item exists: $($null -ne $currentItem)"
            
            if ($ItemType -eq 'configuration' -and $currentItem.AdministrativeTemplates) {
                Write-Verbose "Configuration contains $($currentItem.AdministrativeTemplates.Count) AdministrativeTemplates"
                foreach ($template in $currentItem.AdministrativeTemplates) {
                    Write-Verbose "  - $($template.DisplayName) (Sequence: $($template.Sequence))"
                }
                
                # Clean AdministrativeTemplates to prevent JSON parsing errors
                Write-Verbose "Cleaning AdministrativeTemplates to prevent JSON parsing errors..."
                Write-Verbose "AdministrativeTemplates type before cleaning: $($currentItem.AdministrativeTemplates.GetType().Name)"
                Write-Verbose "AdministrativeTemplates count before cleaning: $($currentItem.AdministrativeTemplates.Count)"
                
                # Clean specific problematic text fields in AdministrativeTemplates
                Write-Verbose "Cleaning problematic text fields in AdministrativeTemplates..."
                $cleanedCount = 0
                
                for ($i = 0; $i -lt $currentItem.AdministrativeTemplates.Count; $i++) {
                    $template = $currentItem.AdministrativeTemplates[$i]
                    
                    # Clean template-level text fields
                    if ($template.DisplayName -and $template.DisplayName -is [string]) {
                        $template.DisplayName = Clean-AdmxText -Text $template.DisplayName
                    }
                    if ($template.Description -and $template.Description -is [string]) {
                        $template.Description = Clean-AdmxText -Text $template.Description
                    }
                    
                    # Directly clean all HelpText fields in the template
                    if ($template.Categories) {
                        foreach ($category in $template.Categories) {
                            if ($category.Children) {
                                foreach ($child in $category.Children) {
                                    if ($child.Children) {
                                        foreach ($grandchild in $child.Children) {
                                            if ($grandchild.Settings) {
                                                foreach ($setting in $grandchild.Settings) {
                                                    # Clean HelpText - this is the main culprit
                                                    if ($setting.HelpText -and $setting.HelpText -is [string]) {
                                                        $originalLength = $setting.HelpText.Length
                                                        $cleanedText = Clean-AdmxText -Text $setting.HelpText
                                                        $setting.HelpText = $cleanedText
                                                        $newLength = $setting.HelpText.Length
                                                        if ($originalLength -ne $newLength) {
                                                            $cleanedCount++
                                                            Write-Verbose "Cleaned HelpText: $($setting.Name) - $originalLength -> $newLength chars"
                                                        }
                                                    }
                                                    
                                                    # Clean other text fields
                                                    if ($setting.Name -and $setting.Name -is [string]) {
                                                        $setting.Name = Clean-AdmxText -Text $setting.Name
                                                    }
                                                    if ($setting.Description -and $setting.Description -is [string]) {
                                                        $setting.Description = Clean-AdmxText -Text $setting.Description
                                                    }
                                                    if ($setting.DisplayName -and $setting.DisplayName -is [string]) {
                                                        $setting.DisplayName = Clean-AdmxText -Text $setting.DisplayName
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                Write-Verbose "Cleaned $cleanedCount HelpText fields"
                
                Write-Verbose "AdministrativeTemplates type after cleaning: $($currentItem.AdministrativeTemplates.GetType().Name)"
                Write-Verbose "AdministrativeTemplates count after cleaning: $($currentItem.AdministrativeTemplates.Count)"
                Write-Verbose "AdministrativeTemplates cleaned using targeted approach"
                
                # Log the full configuration being sent
                Write-Verbose "Full configuration being sent to API:"
                Write-Verbose ($currentItem | ConvertTo-Json -Depth 5)
            }
            
            $response = Invoke-ProfileUnityApi -Endpoint $ItemType -Method POST -Body $currentItem
            Write-Verbose "Save API response received"
            Write-Verbose "Save API Response Type: $($response.GetType().Name)"
            Write-Verbose "Save API Response Keys: $($response.PSObject.Properties.Name -join ', ')"
            Write-Verbose "Full Save API Response: $($response | ConvertTo-Json -Depth 5)"
            Write-Host "$ItemType saved successfully" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to save ${ItemType}: $_"
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
        Name of the new configuration
    
    .PARAMETER Description
        Optional description
    
    .PARAMETER Template
        Optional template to base the configuration on
    
    .EXAMPLE
        New-ProUConfig -Name "Test Configuration" -Description "Test config"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [string]$Description = "",
        
        [string]$Template
    )
    
    try {
        # Check if configuration already exists
        $existingConfigs = Get-ProUConfig
        if ($existingConfigs | Where-Object { $_.Name -eq $Name }) {
            throw "Configuration '$Name' already exists"
        }
        
        Write-Verbose "Creating new configuration: $Name"
        
        # Create complete configuration object with all required fields
        $newConfig = @{
            Name = $Name
            Description = $Description
            Disabled = $false
            Comments = ""
            CompressionType = 0
            EnableFilter = $false
            EnableLogFilter = $false
            LogLevel = 1
            LogPath = ""
            GroupName = ""
            RequireGroupMembership = $false
            OverrideDeploymentPath = ""
            OverrideCloudCreds = ""
            PortabilityRetention = 0
            FlexAppDiaAndPortabilitySecondaryPaths = ""
            EnableCloaking = $false
            ApplicationPreservationMode = $false
            EnableFlexAppSystrayUtility = $false
            EnableCacheThrottle = $false
            FlexappCacheThrottleFilterId = ""
            FlexappCacheThrottleFilter = $null
            FlexappCacheThrottleTarget = 0.0
            Filter = $null
            FilterId = ""
            LogFilter = $null
            LogFilterId = ""
            # Initialize all module arrays
            AdministrativeTemplates = @()
            ApplicationLaunchers = @()
            ApplicationRestrictions = @()
            AppstreamApps = @()
            FlexAppOnes = @()
            AppVApps = @()
            DesktopStartMenus = @()
            DriveMappings = @()
            EnvironmentVariables = @()
            FileAssociations = @()
            FlexAppDias = @()
            FlexAppUias = @()
            FolderRedirections = @()
            IniFiles = @()
            InternetExplorers = @()
            InternetProxies = @()
            Inventories = @()
            MapiProfiles = @()
            MessageBoxes = @()
            MsixApps = @()
            OfficeFileLocations = @()
            OfficeOptions = @()
            Outlooks = @()
            Paths = @()
            PortabilitySettings = @()
            Printers = @()
            PrinterInstalls = @()
            PrivilegeElevations = @()
            ProfileCleanups = @()
            RdpClients = @()
            Registries = @()
            RegistryRedirections = @()
            Shortcuts = @()
            ThinApps = @()
            TimeSyncs = @()
            TriggerPoints = @()
            UserDefinedAliases = @()
            UserDefinedScripts = @()
            VirtualDisks = @()
            WindowsOptions = @()
        }
        
        # If template specified, copy from template
        if ($Template) {
            $templateConfig = $existingConfigs | Where-Object { $_.Name -eq $Template }
            if ($templateConfig) {
                Write-Verbose "Using template: $Template"
                # Get full template details
                $templateResponse = Invoke-ProfileUnityApi -Endpoint "configuration/$($templateConfig.ID)"
                if ($templateResponse.tag) {
                    # Copy all module arrays from template
                    $templateData = $templateResponse.tag
                    foreach ($property in $templateData.PSObject.Properties) {
                        if ($newConfig.ContainsKey($property.Name) -and $property.Name -notin @('Name', 'Description', 'ID', 'CreatedBy', 'DateCreated', 'DateLastModified', 'LastModifiedBy')) {
                            $newConfig[$property.Name] = $property.Value
                        }
                    }
                    Write-Verbose "Copied template structure from: $Template"
                }
            }
            else {
                Write-Warning "Template '$Template' not found, creating empty configuration"
            }
        }
        
        # Create the configuration - use direct object, not wrapped
        $response = Invoke-ProfileUnityApi -Endpoint "configuration" -Method POST -Body $newConfig
        
        # Validate response
        if ($response -and $response.type -eq "success") {
            Write-Host "Configuration '$Name' created successfully" -ForegroundColor Green
            Write-Verbose "Configuration ID: $($response.tag.id)"
            return $response.tag
        }
        elseif ($response -and $response.type -eq "error") {
            throw "Server error: $($response.message)"
        }
        else {
            throw "Unexpected response from server: $($response | ConvertTo-Json -Depth 2)"
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
        Remove-ProUConfig -Name "Old Configuration"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [switch]$Force
    )
    
    try {
        $configs = Get-ProUConfig
        $config = $configs | Where-Object { $_.Name -eq $Name }
        
        if (-not $config) {
            throw "Configuration '$Name' not found"
        }
        
        if ($Force -or $PSCmdlet.ShouldProcess($Name, "Remove configuration")) {
            $response = Invoke-ProfileUnityApi -Endpoint "configuration/$($config.ID)" -Method DELETE
            Write-Host "Configuration '$Name' removed successfully" -ForegroundColor Green
            return $response
        }
        else {
            Write-Host "Remove cancelled" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "Failed to remove configuration: $_"
        throw
    }
}

function Copy-ProUConfig {
    <#
    .SYNOPSIS
        Copies an existing ProfileUnity configuration.
    
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
                configuration = $copiedConfig
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
        Test-ProUConfig -Name "Production Configuration"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    try {
        $configs = Get-ProUConfig
        $config = $configs | Where-Object { $_.Name -eq $Name }
        
        if (-not $config) {
            throw "Configuration '$Name' not found"
        }
        
        Write-Verbose "Testing configuration: $Name"
        
        # Get detailed configuration
        $response = Invoke-ProfileUnityApi -Endpoint "configuration/$($config.ID)"
        $configData = $response.tag
        
        $issues = @()
        $warnings = @()
        
        # Basic validation
        if (-not $configData.name) {
            $issues += "Missing configuration name"
        }
        
        if (-not $configData.modules -or $configData.modules.Count -eq 0) {
            $warnings += "Configuration has no modules"
        }
        
        # Module validation
        if ($configData.modules) {
            $duplicateSequences = $configData.modules | Group-Object Sequence | Where-Object { $_.Count -gt 1 }
            if ($duplicateSequences) {
                $issues += "Duplicate module sequences found"
            }
        }
        
        $isValid = $issues.Count -eq 0
        
        $result = [PSCustomObject]@{
            ConfigurationName = $Name
            IsValid = $isValid
            Issues = $issues
            Warnings = $warnings
            ModuleCount = if ($configData.modules) { $configData.modules.Count } else { 0 }
            TestDate = Get-Date
        }
        
        # Display results
        if ($isValid) {
            Write-Host "Configuration '$Name' validation: PASSED" -ForegroundColor Green
        }
        else {
            Write-Host "Configuration '$Name' validation: FAILED" -ForegroundColor Red
            $issues | ForEach-Object { Write-Host "  ERROR: $_" -ForegroundColor Red }
        }
        
        if ($warnings.Count -gt 0) {
            $warnings | ForEach-Object { Write-Host "  WARNING: $_" -ForegroundColor Yellow }
        }
        
        return $result
    }
    catch {
        Write-Error "Failed to test configuration: $_"
        throw
    }
}

function Get-ProUConfigModules {
    <#
    .SYNOPSIS
        Gets available module types for configurations.
    
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
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
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
#>