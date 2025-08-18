# ADMX/ADMX.ps1 - ProfileUnity ADMX Template Management Functions with Name Resolution

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



function Clean-ProUConfiguration {
    <#
    .SYNOPSIS
        Cleans problematic Unicode characters from the current ProfileUnity configuration.
    
    .DESCRIPTION
        Directly cleans all HelpText and other text fields in AdministrativeTemplates to prevent JSON parsing errors.
        This function should be called before saving configurations that contain ADMX templates.
    
    .EXAMPLE
        Clean-ProUConfiguration
        Save-ProUConfig -Force
    #>
    [CmdletBinding()]
    param()
    
    # Check if configuration is loaded
    $currentConfig = if ($global:CurrentConfig) { 
        $global:CurrentConfig 
    } elseif ($script:ModuleConfig.CurrentItems.Config) { 
        $script:ModuleConfig.CurrentItems.Config 
    } else {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    Write-Verbose "Cleaning problematic Unicode characters from configuration..."
    
    $cleanedCount = 0
    
    if ($currentConfig.AdministrativeTemplates) {
        for ($i = 0; $i -lt $currentConfig.AdministrativeTemplates.Count; $i++) {
            $template = $currentConfig.AdministrativeTemplates[$i]
            
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
                                                $setting.HelpText = Clean-AdmxText -Text $setting.HelpText
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
    }
    
    Write-Verbose "Cleaned $cleanedCount HelpText fields"
    Write-Host "Configuration is now ready for saving" -ForegroundColor Green
}

function Add-ProUAdmx {
    <#
    .SYNOPSIS
        Adds ADMx/ADMl templates to the current ProfileUnity configuration.
    .DESCRIPTION
        This function queries the ProfileUnity server for ADMX policy settings and adds them
        to the currently loaded configuration.
    .PARAMETER AdmxFile
        The ADMX file name (e.g., "chrome.admx")
    .PARAMETER AdmlFile
        The ADML file name (e.g., "chrome.adml")
    .PARAMETER GpoId
        The GPO ID to use for the ADMX settings
    .PARAMETER FilterName
        Optional filter name to apply to the ADMX settings
    .PARAMETER Description
        Optional description for the ADMX settings
    .PARAMETER Sequence
        The sequence number for the ADMX settings (default: 1)
    .EXAMPLE
        Add-ProUAdmx -AdmxFile "chrome.admx" -AdmlFile "chrome.adml" -GpoId "12345"
    .EXAMPLE
        Add-ProUAdmx -AdmxFile "firefox.admx" -AdmlFile "firefox.adml" -GpoId "67890" -FilterName "Domain Computers"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AdmxFile,
        
        [Parameter(Mandatory)]
        [string]$AdmlFile,
        
        [Parameter(Mandatory)]
        [string]$GpoId,
        
        [string]$FilterName,
        
        [string]$Description = "Added via PowerTools",
        
        [int]$Sequence = 1
    )
    
    Begin {
        Assert-ProfileUnityConnection
        
        # Check if configuration is loaded
        $currentConfig = if ($script:ModuleConfig.CurrentItems.Config) { 
            $script:ModuleConfig.CurrentItems.Config 
        } elseif ($global:CurrentConfig) { 
            $global:CurrentConfig 
        } else {
            throw "No configuration loaded for editing. Use Edit-ProUConfig first."
        }
    }
    
    Process {
        try {
            Write-Host "Querying ProfileUnity server for ADMX settings..." -ForegroundColor Yellow
            Write-Verbose "Parameters: AdmxFile=$AdmxFile, AdmlFile=$AdmlFile, GpoId=$GpoId, Description=$Description, Sequence=$Sequence"
            
            # Build the query URL
            $queryUrl = "server/admxadmlfiles?admx=$AdmxFile&adml=$AdmlFile&gpoid=$GpoId"
            Write-Verbose "API URL: $queryUrl"
            
            # Query the server
            Write-Verbose "Calling Invoke-ProfileUnityApi..."
            $response = Invoke-ProfileUnityApi -Endpoint $queryUrl
            Write-Verbose "API Response Type: $($response.GetType().Name)"
            Write-Verbose "API Response Keys: $($response.PSObject.Properties.Name -join ', ')"
            
            if (-not $response -or -not $response.tag) {
                Write-Verbose "Full API Response: $($response | ConvertTo-Json -Depth 3)"
                throw "No ADMX data returned from server"
            }
            
            $admxRule = $response.tag
            
            if (-not $admxRule) {
                throw "No ADMX data returned from server"
            }
            
            # Clean the ADMX rule to prevent JSON parsing errors
            Write-Verbose "Cleaning ADMX rule to prevent JSON parsing errors..."
            
            # Directly clean all HelpText fields in the ADMX rule
            if ($admxRule.Categories) {
                foreach ($category in $admxRule.Categories) {
                    if ($category.Children) {
                        foreach ($child in $category.Children) {
                            if ($child.Children) {
                                foreach ($grandchild in $child.Children) {
                                    if ($grandchild.Settings) {
                                        foreach ($setting in $grandchild.Settings) {
                                            # Clean HelpText - this is the main culprit
                                            if ($setting.HelpText -and $setting.HelpText -is [string]) {
                                                $originalLength = $setting.HelpText.Length
                                                $setting.HelpText = Clean-AdmxText -Text $setting.HelpText
                                                $newLength = $setting.HelpText.Length
                                                if ($originalLength -ne $newLength) {
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
                Write-Verbose "ADMX Categories cleaned successfully"
            }
            
            # Clean other text fields
            if ($admxRule.Description -and $admxRule.Description -is [string]) {
                $admxRule.Description = Clean-AdmxText -Text $admxRule.Description
            }
            
            # Also clean the DisplayName if it exists
            if ($admxRule.DisplayName -and $admxRule.DisplayName -is [string]) {
                $admxRule.DisplayName = Clean-AdmxText -Text $admxRule.DisplayName
            }
            
            Write-Verbose "ADMX rule cleaned using direct approach"
            
            # Ensure the rule is properly structured for the array
            Write-Verbose "Verifying ADMX rule structure..."
            if ($admxRule -is [array]) {
                Write-Verbose "ADMX rule is already an array"
            } else {
                Write-Verbose "ADMX rule is a single object - this is correct"
            }
            
            # Get filter ID if filter name provided
            $filterId = $null
            if ($FilterName) {
                $filter = Get-ProUFilters | Where-Object { $_.name -eq $FilterName }
                if ($filter) {
                    $filterId = $filter.id
                    Write-Host "Using filter: $FilterName (ID: $filterId)" -ForegroundColor Green
                } else {
                    Write-Warning "Filter '$FilterName' not found - proceeding without filter"
                }
            }
            
            # Update the ADMX rule with our settings
            if ($filterId) {
                $admxRule.FilterId = $filterId
                $admxRule.Filter = $FilterName
            }
            
            if ($Description) {
                $admxRule.Description = $Description
            }
            
            if ($Sequence) {
                $admxRule.Sequence = $Sequence
            }
            
            # Initialize AdministrativeTemplates array if it doesn't exist
            if ($null -eq $currentConfig.AdministrativeTemplates) {
                Write-Verbose "Initializing AdministrativeTemplates array"
                $currentConfig | Add-Member -NotePropertyName AdministrativeTemplates -NotePropertyValue @() -Force
            }
            
            Write-Verbose "Current AdministrativeTemplates count: $($currentConfig.AdministrativeTemplates.Count)"
            
            # Add the new rule
            Write-Verbose "Adding ADMX rule to configuration..."
            $currentConfig.AdministrativeTemplates += $admxRule
            Write-Verbose "New AdministrativeTemplates count: $($currentConfig.AdministrativeTemplates.Count)"
            
            # Update both storage locations (matching working script)
            Write-Verbose "Updating storage locations..."
            $script:ModuleConfig.CurrentItems.Config = $currentConfig
            $global:CurrentConfig = $currentConfig
            Write-Verbose "Storage locations updated successfully"
            
            Write-Host "Successfully added ADMX rule:" -ForegroundColor Green
            Write-Host "  ADMX: $AdmxFile" -ForegroundColor Cyan
            Write-Host "  ADML: $AdmlFile" -ForegroundColor Cyan
            Write-Host "  GPO ID: $GpoId" -ForegroundColor Cyan
            if ($filterId) {
                Write-Host "  Filter: $FilterName" -ForegroundColor Cyan
            }
            
            # Count settings
            $settingCount = 0
            if ($admxRule.TemplateSettingStates) {
                $settingCount = @($admxRule.TemplateSettingStates).Count
            }
            
            Write-Host "  Settings: $settingCount" -ForegroundColor Cyan
            Write-Host "`nUse Save-ProUConfig to save changes" -ForegroundColor Yellow
            
            return $admxRule
        }
        catch {
            Write-Error "Failed to add ADMX configuration: $_"
            throw
        }
    }
}

function Get-ProUAdmx {
    <#
    .SYNOPSIS
        Gets ADMX templates from the current ProfileUnity configuration.
    
    .DESCRIPTION
        Retrieves ADMX templates from the configuration being edited with enhanced filtering and display.
    
    .PARAMETER Name
        Filter by ADMX file name (supports wildcards)
    
    .PARAMETER FilterName
        Filter by assigned filter name (supports wildcards)
    
    .PARAMETER Index
        Get specific ADMX template by index
    
    .PARAMETER Sequence
        Get ADMX template by sequence number
    
    .PARAMETER Detailed
        Show detailed information including all settings
    
    .PARAMETER IncludeDisabled
        Include disabled templates in results
    
    .EXAMPLE
        Get-ProUAdmx
        
    .EXAMPLE
        Get-ProUAdmx -Name "chrome*" -Detailed
        
    .EXAMPLE
        Get-ProUAdmx -FilterName "Domain*" -IncludeDisabled
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$FilterName,
        [int]$Index,
        [int]$Sequence,
        [switch]$Detailed,
        [switch]$IncludeDisabled
    )
    
    # Get current configuration
    $currentConfig = $script:ModuleConfig.CurrentItems.Config
    if (-not $currentConfig -and $global:CurrentConfig) {
        $currentConfig = $global:CurrentConfig
    }
    
    if (-not $currentConfig) {
        Write-Warning "No configuration loaded. Use Edit-ProUConfig first."
        return
    }
    
    if (-not $currentConfig.AdministrativeTemplates) {
        Write-Host "No ADMX templates found in current configuration" -ForegroundColor Yellow
        return
    }
    
    $templates = $currentConfig.AdministrativeTemplates
    $results = @()
    $currentIndex = 0
    
    # Apply filters
    $templates | ForEach-Object {
        $template = $_
        $currentIndex++
        
        # Skip if specific index requested and doesn't match
        if ($Index -and $currentIndex -ne $Index) {
            return
        }
        
        # Skip if specific sequence requested and doesn't match
        if ($Sequence -and $template.Sequence -ne $Sequence) {
            return
        }
        
        # Apply name filter
        if ($Name) {
            $admxFileName = if ($template.AdmxFile) { Split-Path $template.AdmxFile -Leaf } else { "" }
            if ($admxFileName -notlike $Name) {
                return
            }
        }
        
        # Apply filter name filter
        if ($FilterName -and $template.Filter -notlike $FilterName) {
            return
        }
        
        # Skip disabled templates unless explicitly included
        if (-not $IncludeDisabled -and $template.Disabled -eq "true") {
            return
        }
        
        # Create result object
        $result = [PSCustomObject]@{
            Index = $currentIndex
            Sequence = [int]$template.Sequence
            AdmxFile = if ($template.AdmxFile) { Split-Path $template.AdmxFile -Leaf } else { "" }
            AdmxFullPath = $template.AdmxFile
            AdmlFile = if ($template.AdmlFile) { Split-Path $template.AdmlFile -Leaf } else { "" }
            AdmlFullPath = $template.AdmlFile
            Filter = $template.Filter
            FilterId = $template.FilterId
            Description = $template.Description
            Disabled = [System.Convert]::ToBoolean($template.Disabled)
            SettingsCount = if ($template.TemplateSettingStates) { @($template.TemplateSettingStates).Count } else { 0 }
            ControlsCount = if ($template.SettingControlStates) { @($template.SettingControlStates).Count } else { 0 }
        }
        
        if ($Detailed) {
            # Add detailed information
            $result | Add-Member -NotePropertyName RawTemplateData -NotePropertyValue $template
            
            if ($template.TemplateSettingStates) {
                $result | Add-Member -NotePropertyName Settings -NotePropertyValue @(
                    $template.TemplateSettingStates | ForEach-Object {
                        [PSCustomObject]@{
                            Key = $_.key
                            State = $_.state
                            Value = $_.value
                            DisplayName = $_.displayName
                            Type = $_.type
                        }
                    }
                )
            }
            
            if ($template.SettingControlStates) {
                $result | Add-Member -NotePropertyName Controls -NotePropertyValue @(
                    $template.SettingControlStates | ForEach-Object {
                        [PSCustomObject]@{
                            Key = $_.key
                            State = $_.state
                            Value = $_.value
                            ControlType = $_.controlType
                        }
                    }
                )
            }
        }
        
        $results += $result
    }
    
    if ($results.Count -eq 0) {
        Write-Host "No ADMX templates match the specified criteria" -ForegroundColor Yellow
        return
    }
    
    return $results
}

function Remove-ProUAdmx {
    <#
    .SYNOPSIS
        Removes an ADMX template from the current ProfileUnity configuration.
    
    .DESCRIPTION
        Removes an ADMX template by index, sequence number, or name from the currently loaded configuration.
    
    .PARAMETER Index
        The index of the ADMX template to remove (from Get-ProUAdmx)
    
    .PARAMETER Sequence
        The sequence number of the ADMX template to remove
    
    .PARAMETER Name
        The ADMX file name to remove (supports name resolution and wildcards)
    
    .EXAMPLE
        Remove-ProUAdmx -Index 1
        
    .EXAMPLE
        Remove-ProUAdmx -Sequence 5
        
    .EXAMPLE
        Remove-ProUAdmx -Name "chrome.admx"
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Index')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Index')]
        [int]$Index,
        
        [Parameter(Mandatory, ParameterSetName = 'Sequence')]
        [int]$Sequence,
        
        [Parameter(Mandatory, ParameterSetName = 'Name')]
        [string]$Name
    )
    
    # Get current configuration
    $currentConfig = $script:ModuleConfig.CurrentItems.Config
    if (-not $currentConfig -and $global:CurrentConfig) {
        $currentConfig = $global:CurrentConfig
    }
    
    if (-not $currentConfig) {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    if (-not $currentConfig.AdministrativeTemplates -or $currentConfig.AdministrativeTemplates.Count -eq 0) {
        throw "No ADMX templates found in current configuration"
    }
    
    try {
        $templatesToRemove = @()
        
        switch ($PSCmdlet.ParameterSetName) {
            'Index' {
                if ($Index -lt 1 -or $Index -gt $currentConfig.AdministrativeTemplates.Count) {
                    throw "Invalid index. Valid range: 1-$($currentConfig.AdministrativeTemplates.Count)"
                }
                
                $templatesToRemove += @{
                    Index = $Index - 1
                    Template = $currentConfig.AdministrativeTemplates[$Index - 1]
                }
            }
            
            'Sequence' {
                for ($i = 0; $i -lt $currentConfig.AdministrativeTemplates.Count; $i++) {
                    if ($currentConfig.AdministrativeTemplates[$i].Sequence -eq $Sequence) {
                        $templatesToRemove += @{
                            Index = $i
                            Template = $currentConfig.AdministrativeTemplates[$i]
                        }
                    }
                }
                
                if ($templatesToRemove.Count -eq 0) {
                    throw "No ADMX template found with sequence: $Sequence"
                }
            }
            
            'Name' {
                for ($i = 0; $i -lt $currentConfig.AdministrativeTemplates.Count; $i++) {
                    $template = $currentConfig.AdministrativeTemplates[$i]
                    $admxFileName = if ($template.AdmxFile) { Split-Path $template.AdmxFile -Leaf } else { "" }
                    
                    # Support both exact match and wildcard matching
                    if ($admxFileName -eq $Name -or $admxFileName -like $Name -or $template.AdmxFile -like "*$Name*") {
                        $templatesToRemove += @{
                            Index = $i
                            Template = $template
                        }
                    }
                }
                
                if ($templatesToRemove.Count -eq 0) {
                    throw "No ADMX template found matching name: $Name"
                }
            }
        }
        
        # Sort by index descending to remove from end first (maintains indices)
        $templatesToRemove = $templatesToRemove | Sort-Object Index -Descending
        
        # Confirm removal
        foreach ($item in $templatesToRemove) {
            $template = $item.Template
            $admxName = if ($template.AdmxFile) { Split-Path $template.AdmxFile -Leaf } else { "ADMX Template" }
            $confirmMessage = "Remove ADMX template: $admxName (Sequence: $($template.Sequence))"
            
            if ($PSCmdlet.ShouldProcess($confirmMessage, "Remove ADMX Template")) {
                # Create new array without this template
                $newTemplates = @()
                for ($i = 0; $i -lt $currentConfig.AdministrativeTemplates.Count; $i++) {
                    if ($i -ne $item.Index) {
                        $newTemplates += $currentConfig.AdministrativeTemplates[$i]
                    }
                }
                
                $currentConfig.AdministrativeTemplates = $newTemplates
                
                Write-Host "Removed ADMX template: $admxName" -ForegroundColor Green
            }
        }
        
        # Update both storage locations
        $script:ModuleConfig.CurrentItems.Config = $currentConfig
        $global:CurrentConfig = $currentConfig
        
        if ($templatesToRemove.Count -gt 0) {
            Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "Failed to remove ADMX template: $_"
        throw
    }
}

function Set-ProUAdmxSequence {
    <#
    .SYNOPSIS
        Sets the sequence number for ADMX templates.
    
    .DESCRIPTION
        Updates the sequence numbers for ADMX templates in the current configuration.
    
    .PARAMETER Index
        Index of the ADMX template to update
    
    .PARAMETER Sequence
        New sequence number
    
    .PARAMETER Name
        Name of the ADMX template to update (supports name resolution)
    
    .PARAMETER ResequenceAll
        Resequence all ADMX templates starting from specified number
    
    .PARAMETER StartAt
        Starting sequence number for resequencing (default: 1)
    
    .EXAMPLE
        Set-ProUAdmxSequence -Index 1 -Sequence 5
        
    .EXAMPLE
        Set-ProUAdmxSequence -Name "chrome.admx" -Sequence 3
        
    .EXAMPLE
        Set-ProUAdmxSequence -ResequenceAll -StartAt 1
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByIndex')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByIndex')]
        [int]$Index,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,
        
        [Parameter(Mandatory, ParameterSetName = 'ByIndex')]
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [int]$Sequence,
        
        [Parameter(Mandatory, ParameterSetName = 'ResequenceAll')]
        [switch]$ResequenceAll,
        
        [Parameter(ParameterSetName = 'ResequenceAll')]
        [int]$StartAt = 1
    )
    
    # Get current configuration
    $currentConfig = $script:ModuleConfig.CurrentItems.Config
    if (-not $currentConfig -and $global:CurrentConfig) {
        $currentConfig = $global:CurrentConfig
    }
    
    if (-not $currentConfig) {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    if (-not $currentConfig.AdministrativeTemplates -or $currentConfig.AdministrativeTemplates.Count -eq 0) {
        Write-Warning "No ADMX templates found in current configuration"
        return
    }
    
    try {
        switch ($PSCmdlet.ParameterSetName) {
            'ByIndex' {
                if ($Index -lt 1 -or $Index -gt $currentConfig.AdministrativeTemplates.Count) {
                    throw "Invalid index. Valid range: 1-$($currentConfig.AdministrativeTemplates.Count)"
                }
                
                $template = $currentConfig.AdministrativeTemplates[$Index - 1]
                $template.Sequence = $Sequence
                
                $admxName = if ($template.AdmxFile) { Split-Path $template.AdmxFile -Leaf } else { "ADMX Template #$Index" }
                Write-Host "Updated sequence for $admxName to: $Sequence" -ForegroundColor Green
            }
            
            'ByName' {
                $templatesUpdated = 0
                
                for ($i = 0; $i -lt $currentConfig.AdministrativeTemplates.Count; $i++) {
                    $template = $currentConfig.AdministrativeTemplates[$i]
                    $admxFileName = if ($template.AdmxFile) { Split-Path $template.AdmxFile -Leaf } else { "" }
                    
                    if ($admxFileName -eq $Name -or $admxFileName -like $Name -or $template.AdmxFile -like "*$Name*") {
                        $template.Sequence = $Sequence
                        $templatesUpdated++
                        Write-Host "Updated sequence for $admxFileName to: $Sequence" -ForegroundColor Green
                    }
                }
                
                if ($templatesUpdated -eq 0) {
                    throw "No ADMX template found matching name: $Name"
                }
                
                if ($templatesUpdated -gt 1) {
                    Write-Warning "Updated sequence for $templatesUpdated templates matching '$Name'"
                }
            }
            
            'ResequenceAll' {
                Write-Host "Resequencing ADMX templates..." -ForegroundColor Yellow
                
                $sequenceNumber = $StartAt
                foreach ($template in $currentConfig.AdministrativeTemplates) {
                    $template.Sequence = $sequenceNumber
                    $sequenceNumber++
                }
                
                Write-Host "ADMX templates resequenced ($StartAt to $($sequenceNumber - 1))" -ForegroundColor Green
            }
        }
        
        # Update both storage locations
        $script:ModuleConfig.CurrentItems.Config = $currentConfig
        $global:CurrentConfig = $currentConfig
        
        Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
    }
    catch {
        Write-Error "Failed to update ADMX sequence: $_"
        throw
    }
}

function Enable-ProUAdmx {
    <#
    .SYNOPSIS
        Enables an ADMX template in the current configuration.
    
    .DESCRIPTION
        Enables a disabled ADMX template by index, name, or sequence number.
    
    .PARAMETER Index
        Index of the ADMX template to enable
    
    .PARAMETER Name
        Name of the ADMX template to enable (supports name resolution)
    
    .PARAMETER Sequence
        Sequence number of the ADMX template to enable
    
    .EXAMPLE
        Enable-ProUAdmx -Index 1
        
    .EXAMPLE
        Enable-ProUAdmx -Name "chrome.admx"
        
    .EXAMPLE
        Enable-ProUAdmx -Sequence 5
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByIndex')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByIndex')]
        [int]$Index,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,
        
        [Parameter(Mandatory, ParameterSetName = 'BySequence')]
        [int]$Sequence
    )
    
    # Get current configuration
    $currentConfig = $script:ModuleConfig.CurrentItems.Config
    if (-not $currentConfig -and $global:CurrentConfig) {
        $currentConfig = $global:CurrentConfig
    }
    
    if (-not $currentConfig) {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    if (-not $currentConfig.AdministrativeTemplates -or $currentConfig.AdministrativeTemplates.Count -eq 0) {
        throw "No ADMX templates found in current configuration"
    }
    
    try {
        $templatesEnabled = 0
        
        switch ($PSCmdlet.ParameterSetName) {
            'ByIndex' {
                if ($Index -lt 1 -or $Index -gt $currentConfig.AdministrativeTemplates.Count) {
                    throw "Invalid index. Valid range: 1-$($currentConfig.AdministrativeTemplates.Count)"
                }
                
                $template = $currentConfig.AdministrativeTemplates[$Index - 1]
                $template.Disabled = "false"
                $templatesEnabled = 1
                
                $admxName = if ($template.AdmxFile) { Split-Path $template.AdmxFile -Leaf } else { "ADMX Template #$Index" }
                Write-Host "Enabled ADMX template: $admxName" -ForegroundColor Green
            }
            
            'ByName' {
                for ($i = 0; $i -lt $currentConfig.AdministrativeTemplates.Count; $i++) {
                    $template = $currentConfig.AdministrativeTemplates[$i]
                    $admxFileName = if ($template.AdmxFile) { Split-Path $template.AdmxFile -Leaf } else { "" }
                    
                    if ($admxFileName -eq $Name -or $admxFileName -like $Name -or $template.AdmxFile -like "*$Name*") {
                        $template.Disabled = "false"
                        $templatesEnabled++
                        Write-Host "Enabled ADMX template: $admxFileName" -ForegroundColor Green
                    }
                }
                
                if ($templatesEnabled -eq 0) {
                    throw "No ADMX template found matching name: $Name"
                }
                
                if ($templatesEnabled -gt 1) {
                    Write-Host "Enabled $templatesEnabled templates matching '$Name'" -ForegroundColor Yellow
                }
            }
            
            'BySequence' {
                foreach ($template in $currentConfig.AdministrativeTemplates) {
                    if ($template.Sequence -eq $Sequence) {
                        $template.Disabled = "false"
                        $templatesEnabled++
                        
                        $admxName = if ($template.AdmxFile) { Split-Path $template.AdmxFile -Leaf } else { "ADMX Template" }
                        Write-Host "Enabled ADMX template: $admxName (Sequence: $Sequence)" -ForegroundColor Green
                    }
                }
                
                if ($templatesEnabled -eq 0) {
                    throw "No ADMX template found with sequence: $Sequence"
                }
            }
        }
        
        # Update both storage locations
        $script:ModuleConfig.CurrentItems.Config = $currentConfig
        $global:CurrentConfig = $currentConfig
        
        Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
    }
    catch {
        Write-Error "Failed to enable ADMX template: $_"
        throw
    }
}

function Disable-ProUAdmx {
    <#
    .SYNOPSIS
        Disables an ADMX template in the current configuration.
    
    .DESCRIPTION
        Disables an enabled ADMX template by index, name, or sequence number.
    
    .PARAMETER Index
        Index of the ADMX template to disable
    
    .PARAMETER Name
        Name of the ADMX template to disable (supports name resolution)
    
    .PARAMETER Sequence
        Sequence number of the ADMX template to disable
    
    .EXAMPLE
        Disable-ProUAdmx -Index 1
        
    .EXAMPLE
        Disable-ProUAdmx -Name "chrome.admx"
        
    .EXAMPLE
        Disable-ProUAdmx -Sequence 5
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByIndex')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByIndex')]
        [int]$Index,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,
        
        [Parameter(Mandatory, ParameterSetName = 'BySequence')]
        [int]$Sequence
    )
    
    # Get current configuration
    $currentConfig = $script:ModuleConfig.CurrentItems.Config
    if (-not $currentConfig -and $global:CurrentConfig) {
        $currentConfig = $global:CurrentConfig
    }
    
    if (-not $currentConfig) {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    if (-not $currentConfig.AdministrativeTemplates -or $currentConfig.AdministrativeTemplates.Count -eq 0) {
        throw "No ADMX templates found in current configuration"
    }
    
    try {
        $templatesDisabled = 0
        
        switch ($PSCmdlet.ParameterSetName) {
            'ByIndex' {
                if ($Index -lt 1 -or $Index -gt $currentConfig.AdministrativeTemplates.Count) {
                    throw "Invalid index. Valid range: 1-$($currentConfig.AdministrativeTemplates.Count)"
                }
                
                $template = $currentConfig.AdministrativeTemplates[$Index - 1]
                $template.Disabled = "true"
                $templatesDisabled = 1
                
                $admxName = if ($template.AdmxFile) { Split-Path $template.AdmxFile -Leaf } else { "ADMX Template #$Index" }
                Write-Host "Disabled ADMX template: $admxName" -ForegroundColor Green
            }
            
            'ByName' {
                for ($i = 0; $i -lt $currentConfig.AdministrativeTemplates.Count; $i++) {
                    $template = $currentConfig.AdministrativeTemplates[$i]
                    $admxFileName = if ($template.AdmxFile) { Split-Path $template.AdmxFile -Leaf } else { "" }
                    
                    if ($admxFileName -eq $Name -or $admxFileName -like $Name -or $template.AdmxFile -like "*$Name*") {
                        $template.Disabled = "true"
                        $templatesDisabled++
                        Write-Host "Disabled ADMX template: $admxFileName" -ForegroundColor Green
                    }
                }
                
                if ($templatesDisabled -eq 0) {
                    throw "No ADMX template found matching name: $Name"
                }
                
                if ($templatesDisabled -gt 1) {
                    Write-Host "Disabled $templatesDisabled templates matching '$Name'" -ForegroundColor Yellow
                }
            }
            
            'BySequence' {
                foreach ($template in $currentConfig.AdministrativeTemplates) {
                    if ($template.Sequence -eq $Sequence) {
                        $template.Disabled = "true"
                        $templatesDisabled++
                        
                        $admxName = if ($template.AdmxFile) { Split-Path $template.AdmxFile -Leaf } else { "ADMX Template" }
                        Write-Host "Disabled ADMX template: $admxName (Sequence: $Sequence)" -ForegroundColor Green
                    }
                }
                
                if ($templatesDisabled -eq 0) {
                    throw "No ADMX template found with sequence: $Sequence"
                }
            }
        }
        
        # Update both storage locations
        $script:ModuleConfig.CurrentItems.Config = $currentConfig
        $global:CurrentConfig = $currentConfig
        
        Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
    }
    catch {
        Write-Error "Failed to disable ADMX template: $_"
        throw
    }
}

function Copy-ProUAdmx {
    <#
    .SYNOPSIS
        Copies an ADMX template within the current configuration.
    
    .DESCRIPTION
        Creates a copy of an existing ADMX template with optional modifications.
    
    .PARAMETER SourceIndex
        Index of the source ADMX template to copy
    
    .PARAMETER SourceName
        Name of the source ADMX template to copy (supports name resolution)
    
    .PARAMETER NewSequence
        Sequence number for the copied template (default: auto-increment)
    
    .PARAMETER NewDescription
        Description for the copied template
    
    .PARAMETER NewFilterName
        Filter name for the copied template (supports name resolution)
    
    .PARAMETER NewFilterId
        Filter ID for the copied template (supports name resolution)
    
    .PARAMETER Disabled
        Create the copy in disabled state
    
    .EXAMPLE
        Copy-ProUAdmx -SourceIndex 1 -NewSequence 10
        
    .EXAMPLE
        Copy-ProUAdmx -SourceName "chrome.admx" -NewFilterName "Executives" -NewDescription "Chrome for Executives"
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByIndex')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByIndex')]
        [int]$SourceIndex,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$SourceName,
        
        [int]$NewSequence,
        
        [string]$NewDescription,
        
        [Parameter(ParameterSetName = 'ByIndex')]
        [Parameter(ParameterSetName = 'ByName')]
        [string]$NewFilterName,
        
        [Parameter(ParameterSetName = 'ByIndex')]
        [Parameter(ParameterSetName = 'ByName')]
        [string]$NewFilterId,
        
        [switch]$Disabled
    )
    
    # Get current configuration
    $currentConfig = $script:ModuleConfig.CurrentItems.Config
    if (-not $currentConfig -and $global:CurrentConfig) {
        $currentConfig = $global:CurrentConfig
    }
    
    if (-not $currentConfig) {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    if (-not $currentConfig.AdministrativeTemplates -or $currentConfig.AdministrativeTemplates.Count -eq 0) {
        throw "No ADMX templates found in current configuration"
    }
    
    try {
        # Find source template
        $sourceTemplate = $null
        
        switch ($PSCmdlet.ParameterSetName) {
            'ByIndex' {
                if ($SourceIndex -lt 1 -or $SourceIndex -gt $currentConfig.AdministrativeTemplates.Count) {
                    throw "Invalid source index. Valid range: 1-$($currentConfig.AdministrativeTemplates.Count)"
                }
                
                $sourceTemplate = $currentConfig.AdministrativeTemplates[$SourceIndex - 1]
            }
            
            'ByName' {
                foreach ($template in $currentConfig.AdministrativeTemplates) {
                    $admxFileName = if ($template.AdmxFile) { Split-Path $template.AdmxFile -Leaf } else { "" }
                    
                    if ($admxFileName -eq $SourceName -or $admxFileName -like $SourceName -or $template.AdmxFile -like "*$SourceName*") {
                        $sourceTemplate = $template
                        break
                    }
                }
                
                if (-not $sourceTemplate) {
                    throw "No ADMX template found matching name: $SourceName"
                }
            }
        }
        
        # Create deep copy of the source template
        $copiedTemplate = $sourceTemplate | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        
        # Apply modifications
        if ($NewSequence) {
            $copiedTemplate.Sequence = $NewSequence
        } else {
            # Auto-increment sequence
            $maxSequence = ($currentConfig.AdministrativeTemplates | ForEach-Object { [int]$_.Sequence } | Measure-Object -Maximum).Maximum
            $copiedTemplate.Sequence = $maxSequence + 1
        }
        
        if ($NewDescription) {
            $copiedTemplate.Description = $NewDescription
        } else {
            $copiedTemplate.Description = "$($copiedTemplate.Description) (Copy)"
        }
        
        # Resolve new filter if specified
        if ($NewFilterName -or $NewFilterId) {
            $resolvedFilterId = $null
            $resolvedFilterName = $null
            
            if ($NewFilterName) {
                $resolvedFilterId = Resolve-ProUFilterId -InputValue $NewFilterName
                if ($resolvedFilterId) {
                    $filter = Get-ProUFilters | Where-Object { $_.ID -eq $resolvedFilterId }
                    if ($filter) {
                        $resolvedFilterName = $filter.Name
                        Write-Host "Resolved '$NewFilterName' to Filter ID: $resolvedFilterId" -ForegroundColor Green
                    }
                }
            } elseif ($NewFilterId) {
                $resolvedFilterId = Resolve-ProUFilterId -InputValue $NewFilterId
                if ($resolvedFilterId) {
                    $filter = Get-ProUFilters | Where-Object { $_.ID -eq $resolvedFilterId }
                    if ($filter) {
                        $resolvedFilterName = $filter.Name
                    }
                }
            }
            
            if ($resolvedFilterId -and $resolvedFilterName) {
                $copiedTemplate.FilterId = $resolvedFilterId
                $copiedTemplate.Filter = $resolvedFilterName
            } else {
                Write-Warning "Could not resolve new filter - keeping original filter"
            }
        }
        
        # Set disabled state
        $copiedTemplate.Disabled = $Disabled.ToString().ToLower()
        
        # Add the copied template to configuration
        $currentConfig.AdministrativeTemplates += $copiedTemplate
        
        # Update both storage locations
        $script:ModuleConfig.CurrentItems.Config = $currentConfig
        $global:CurrentConfig = $currentConfig
        
        $sourceAdmxName = if ($sourceTemplate.AdmxFile) { Split-Path $sourceTemplate.AdmxFile -Leaf } else { "ADMX Template" }
        Write-Host "Copied ADMX template: $sourceAdmxName" -ForegroundColor Green
        Write-Host "  New Sequence: $($copiedTemplate.Sequence)" -ForegroundColor Cyan
        if ($resolvedFilterName) {
            Write-Host "  New Filter: $resolvedFilterName" -ForegroundColor Cyan
        }
        Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
        
        return $copiedTemplate
    }
    catch {
        Write-Error "Failed to copy ADMX template: $_"
        throw
    }
}

function Test-ProUAdmx {
    <#
    .SYNOPSIS
        Tests and validates ADMX templates in the current configuration.
    
    .DESCRIPTION
        Validates ADMX template settings and reports issues with enhanced validation.
    
    .PARAMETER Index
        Test specific ADMX template by index
    
    .PARAMETER Name
        Test specific ADMX template by name (supports name resolution)
    
    .PARAMETER Detailed
        Show detailed validation results
    
    .EXAMPLE
        Test-ProUAdmx
        
    .EXAMPLE
        Test-ProUAdmx -Index 1 -Detailed
        
    .EXAMPLE
        Test-ProUAdmx -Name "chrome*" -Detailed
    #>
    [CmdletBinding()]
    param(
        [int]$Index,
        [string]$Name,
        [switch]$Detailed
    )
    
    # Check if configuration is loaded
    $currentConfig = $script:ModuleConfig.CurrentItems.Config
    if (-not $currentConfig -and $global:CurrentConfig) {
        $currentConfig = $global:CurrentConfig
    }
    
    if (-not $currentConfig) {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    Write-Host "Testing ADMX templates in configuration..." -ForegroundColor Yellow
    
    if (-not $currentConfig.AdministrativeTemplates -or $currentConfig.AdministrativeTemplates.Count -eq 0) {
        Write-Host "No ADMX templates found" -ForegroundColor Yellow
        return [PSCustomObject]@{
            TemplateCount = 0
            Issues = @()
            Warnings = @()
            IsValid = $true
        }
    }
    
    $templatesToTest = $currentConfig.AdministrativeTemplates
    
    # Filter templates if specific criteria provided
    if ($Index) {
        if ($Index -lt 1 -or $Index -gt $templatesToTest.Count) {
            throw "Invalid index. Valid range: 1-$($templatesToTest.Count)"
        }
        $templatesToTest = @($templatesToTest[$Index - 1])
    } elseif ($Name) {
        $templatesToTest = $templatesToTest | Where-Object {
            $admxFileName = if ($_.AdmxFile) { Split-Path $_.AdmxFile -Leaf } else { "" }
            $admxFileName -like $Name -or $_.AdmxFile -like "*$Name*"
        }
        
        if ($templatesToTest.Count -eq 0) {
            Write-Warning "No ADMX templates found matching name: $Name"
            return
        }
    }
    
    $issues = @()
    $warnings = @()
    $templateResults = @()
    
    # Check for duplicate sequences across all templates
    $sequences = $currentConfig.AdministrativeTemplates | Group-Object -Property Sequence
    $duplicates = $sequences | Where-Object { $_.Count -gt 1 }
    if ($duplicates) {
        $issues += "Duplicate sequence numbers found: $($duplicates.Name -join ', ')"
    }
    
    # Check each template
    $currentIndex = 0
    foreach ($template in $currentConfig.AdministrativeTemplates) {
        $currentIndex++
        
        # Skip if not in our test set
        if ($templatesToTest -notcontains $template) {
            continue
        }
        
        $templateName = if ($template.AdmxFile) { 
            Split-Path $template.AdmxFile -Leaf 
        } else { 
            "Template #$currentIndex" 
        }
        
        $templateIssues = @()
        $templateWarnings = @()
        
        # Check for missing files
        if ([string]::IsNullOrWhiteSpace($template.AdmxFile)) {
            $templateIssues += "Missing ADMX file"
            $issues += "$templateName : Missing ADMX file"
        }
        
        if ([string]::IsNullOrWhiteSpace($template.AdmlFile)) {
            $templateWarnings += "Missing ADML file"
            $warnings += "$templateName : Missing ADML file"
        }
        
        # Check for settings
        if (-not $template.TemplateSettingStates -or $template.TemplateSettingStates.Count -eq 0) {
            $templateWarnings += "No settings configured"
            $warnings += "$templateName : No settings configured"
        }
        
        # Check filter consistency
        if ($template.FilterId -and -not $template.Filter) {
            $templateWarnings += "Filter ID set but filter name missing"
            $warnings += "$templateName : Filter ID set but filter name missing"
        } elseif ($template.Filter -and -not $template.FilterId) {
            $templateWarnings += "Filter name set but filter ID missing"
            $warnings += "$templateName : Filter name set but filter ID missing"
        }
        
        # Validate filter exists (if both ID and name are set)
        if ($template.FilterId -and $template.Filter) {
            try {
                $filter = Get-ProUFilters | Where-Object { $_.ID -eq $template.FilterId }
                if (-not $filter) {
                    $templateIssues += "Referenced filter ID does not exist"
                    $issues += "$templateName : Referenced filter ID '$($template.FilterId)' does not exist"
                } elseif ($filter.Name -ne $template.Filter) {
                    $templateWarnings += "Filter name mismatch (expected: '$($filter.Name)', found: '$($template.Filter)')"
                    $warnings += "$templateName : Filter name mismatch"
                }
            }
            catch {
                $templateWarnings += "Could not validate filter reference"
                $warnings += "$templateName : Could not validate filter reference"
            }
        }
        
        # Check sequence number
        if ([int]$template.Sequence -lt 1) {
            $templateIssues += "Invalid sequence number (must be >= 1)"
            $issues += "$templateName : Invalid sequence number"
        }
        
        # Validate settings structure
        if ($template.TemplateSettingStates) {
            foreach ($setting in $template.TemplateSettingStates) {
                if (-not $setting.key) {
                    $templateWarnings += "Setting with missing key found"
                    $warnings += "$templateName : Setting with missing key found"
                }
                if (-not $setting.state) {
                    $templateWarnings += "Setting '$($setting.key)' has no state defined"
                    $warnings += "$templateName : Setting '$($setting.key)' has no state"
                }
            }
        }
        
        # Create template result if detailed output requested
        if ($Detailed) {
            $templateResults += [PSCustomObject]@{
                Index = $currentIndex
                Name = $templateName
                AdmxFile = $template.AdmxFile
                AdmlFile = $template.AdmlFile
                Sequence = [int]$template.Sequence
                Filter = $template.Filter
                FilterId = $template.FilterId
                Disabled = [System.Convert]::ToBoolean($template.Disabled)
                SettingsCount = if ($template.TemplateSettingStates) { @($template.TemplateSettingStates).Count } else { 0 }
                Issues = $templateIssues
                Warnings = $templateWarnings
                IsValid = $templateIssues.Count -eq 0
            }
        }
    }
    
    # Display results
    Write-Host "`nTest Results:" -ForegroundColor Cyan
    Write-Host "  Templates Tested: $($templatesToTest.Count)" -ForegroundColor Gray
    Write-Host "  Total Templates: $($currentConfig.AdministrativeTemplates.Count)" -ForegroundColor Gray
    
    if ($issues.Count -eq 0 -and $warnings.Count -eq 0) {
        Write-Host "  No issues found" -ForegroundColor Green
    }
    else {
        if ($issues.Count -gt 0) {
            Write-Host "  Issues ($($issues.Count)):" -ForegroundColor Red
            $issues | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
        }
        
        if ($warnings.Count -gt 0) {
            Write-Host "  Warnings ($($warnings.Count)):" -ForegroundColor Yellow
            $warnings | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
        }
    }
    
    $result = [PSCustomObject]@{
        TemplateCount = $templatesToTest.Count
        TotalTemplates = $currentConfig.AdministrativeTemplates.Count
        Issues = $issues
        Warnings = $warnings
        IsValid = $issues.Count -eq 0
    }
    
    if ($Detailed) {
        $result | Add-Member -NotePropertyName TemplateDetails -NotePropertyValue $templateResults
    }
    
    return $result
}

function Resolve-ProUFilterId {
    <#
    .SYNOPSIS
        Resolves a filter name to its ID.
    
    .DESCRIPTION
        Internal helper function that resolves a filter name to its ID.
        If the input is already an ID format, returns it unchanged.
    
    .PARAMETER InputValue
        The name or ID to resolve
    
    .EXAMPLE
        Resolve-ProUFilterId -InputValue "All Users"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputValue
    )
    
    try {
        # Check if input looks like an ID (numeric or UUID-like)
        if ($InputValue -match '^[\da-f\-]+$' -or $InputValue -match '^\d+$') {
            return $InputValue
        }
        
        # Search for the filter by name
        Write-Verbose "Resolving filter name '$InputValue' to ID..."
        
        try {
            $filters = Get-ProUFilters -ErrorAction SilentlyContinue
        }
        catch {
            Write-Verbose "Could not retrieve filters for name resolution: $_"
            return $null
        }
        
        # Find exact name match
        $exactMatch = $filters | Where-Object { $_.Name -eq $InputValue }
        if ($exactMatch) {
            if ($exactMatch.Count -gt 1) {
                Write-Warning "Multiple filters found with name '$InputValue'. Using first match."
            }
            return $exactMatch[0].ID
        }
        
        # Look for partial matches
        $partialMatches = $filters | Where-Object { $_.Name -like "*$InputValue*" }
        if ($partialMatches) {
            if ($partialMatches.Count -eq 1) {
                Write-Host "Found partial match: '$($partialMatches[0].Name)'" -ForegroundColor Yellow
                return $partialMatches[0].ID
            } else {
                Write-Warning "Multiple partial matches found for '$InputValue':"
                $partialMatches | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
                return $partialMatches[0].ID
            }
        }
        
        # No match found
        Write-Verbose "No filter found with name: $InputValue"
        return $null
    }
    catch {
        Write-Verbose "Error resolving filter ID: $_"
        return $null
    }
}

# Export functions
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
Export-ModuleMember -Function @(
    'Add-ProUAdmx',
    'Get-ProUAdmx',
    'Remove-ProUAdmx',
    'Set-ProUAdmxSequence',
    'Enable-ProUAdmx',
    'Disable-ProUAdmx',
    'Copy-ProUAdmx',
    'Test-ProUAdmx',
    'Resolve-ProUFilterId'
)
#>
