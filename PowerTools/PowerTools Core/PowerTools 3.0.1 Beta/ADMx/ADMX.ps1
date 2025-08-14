# ADMX/ADMX.ps1 - ProfileUnity ADMX Template Management Functions with Name Resolution

function Add-ProUAdmx {
    <#
    .SYNOPSIS
        Adds ADMX/ADML templates to the current ProfileUnity configuration.
    
    .DESCRIPTION
        Queries the ProfileUnity server for ADMX policy settings and adds them
        to the currently loaded configuration. Supports name resolution for filter parameters.
    
    .PARAMETER AdmxFile
        The ADMX file name (e.g., "chrome.admx")
    
    .PARAMETER AdmlFile
        The ADML file name (e.g., "chrome.adml")
    
    .PARAMETER GpoId
        The GPO ID to use for the ADMX settings
    
    .PARAMETER FilterName
        Filter name to apply to the ADMX settings (supports name resolution)
    
    .PARAMETER FilterId
        Filter ID to apply to the ADMX settings (supports name resolution)
    
    .PARAMETER Description
        Description for the ADMX settings
    
    .PARAMETER Sequence
        The sequence number for the ADMX settings (default: 1)
    
    .PARAMETER Disabled
        Add the ADMX template in disabled state
    
    .EXAMPLE
        Add-ProUAdmx -AdmxFile "chrome.admx" -AdmlFile "chrome.adml" -GpoId "12345"
        
    .EXAMPLE
        Add-ProUAdmx -AdmxFile "firefox.admx" -AdmlFile "firefox.adml" -GpoId "67890" -FilterName "Domain Computers"
        
    .EXAMPLE
        Add-ProUAdmx -AdmxFile "edge.admx" -AdmlFile "edge.adml" -GpoId "11111" -FilterId "123"
    #>
    [CmdletBinding(DefaultParameterSetName = 'NoFilter')]
    param(
        [Parameter(Mandatory)]
        [string]$AdmxFile,
        
        [Parameter(Mandatory)]
        [string]$AdmlFile,
        
        [Parameter(Mandatory)]
        [string]$GpoId,
        
        [Parameter(ParameterSetName = 'WithFilterName')]
        [string]$FilterName,
        
        [Parameter(ParameterSetName = 'WithFilterId')]
        [string]$FilterId,
        
        [string]$Description = "Added via PowerTools",
        
        [int]$Sequence = 1,
        
        [switch]$Disabled
    )
    
    Begin {
        # Check if configuration is loaded
        $currentConfig = $script:ModuleConfig.CurrentItems.Config
        if (-not $currentConfig -and $global:CurrentConfig) {
            $currentConfig = $global:CurrentConfig
        }
        
        if (-not $currentConfig) {
            throw "No configuration loaded for editing. Use Edit-ProUConfig first."
        }
    }
    
    Process {
        try {
            Write-Host "Querying ProfileUnity server for ADMX settings..." -ForegroundColor Yellow
            
            # Build the query URL
            $queryUrl = "server/admxadmlfiles?admx=$AdmxFile&adml=$AdmlFile&gpoid=$GpoId"
            
            # Query the server
            $response = Invoke-ProfileUnityApi -Endpoint $queryUrl
            
            if (-not $response -or -not $response.tag) {
                throw "No ADMX data returned from server"
            }
            
            $admxRule = $response.tag
            
            # Resolve filter if specified
            $resolvedFilterId = $null
            $resolvedFilterName = $null
            
            if ($FilterName) {
                Write-Verbose "Resolving filter name: $FilterName"
                $resolvedFilterId = Resolve-ProUFilterId -InputValue $FilterName
                if ($resolvedFilterId) {
                    $filter = Get-ProUFilters | Where-Object { $_.ID -eq $resolvedFilterId }
                    if ($filter) {
                        Write-Host "Resolved '$FilterName' to Filter ID: $resolvedFilterId" -ForegroundColor Green
                        $resolvedFilterName = $filter.Name
                        $admxRule.FilterId = $resolvedFilterId
                        $admxRule.Filter = $resolvedFilterName
                    } else {
                        # Try direct name lookup
                        $filters = Get-ProUFilters -Name $FilterName -ErrorAction SilentlyContinue
                        if ($filters) {
                            $filter = $filters | Select-Object -First 1
                            $resolvedFilterId = $filter.ID
                            $resolvedFilterName = $filter.Name
                            $admxRule.FilterId = $resolvedFilterId
                            $admxRule.Filter = $resolvedFilterName
                            Write-Host "Found filter: $resolvedFilterName (ID: $resolvedFilterId)" -ForegroundColor Green
                        } else {
                            Write-Warning "Filter '$FilterName' not found - proceeding without filter"
                        }
                    }
                } else {
                    # Try direct name lookup
                    try {
                        $filters = Get-ProUFilters -Name $FilterName -ErrorAction SilentlyContinue
                        if ($filters) {
                            $filter = $filters | Select-Object -First 1
                            $resolvedFilterId = $filter.ID
                            $resolvedFilterName = $filter.Name
                            $admxRule.FilterId = $resolvedFilterId
                            $admxRule.Filter = $resolvedFilterName
                            Write-Host "Found filter: $resolvedFilterName (ID: $resolvedFilterId)" -ForegroundColor Green
                        } else {
                            Write-Warning "Filter '$FilterName' not found - proceeding without filter"
                        }
                    }
                    catch {
                        Write-Warning "Could not resolve filter '$FilterName' - proceeding without filter"
                    }
                }
            } elseif ($FilterId) {
                Write-Verbose "Resolving filter ID: $FilterId"
                $resolvedFilterId = Resolve-ProUFilterId -InputValue $FilterId
                if ($resolvedFilterId -and $resolvedFilterId -ne $FilterId) {
                    Write-Host "Resolved '$FilterId' to Filter ID: $resolvedFilterId" -ForegroundColor Green
                }
                $targetFilterId = $resolvedFilterId -or $FilterId
                
                $filter = Get-ProUFilters | Where-Object { $_.ID -eq $targetFilterId }
                if ($filter) {
                    $resolvedFilterId = $filter.ID
                    $resolvedFilterName = $filter.Name
                    $admxRule.FilterId = $resolvedFilterId
                    $admxRule.Filter = $resolvedFilterName
                    Write-Host "Using filter: $resolvedFilterName (ID: $resolvedFilterId)" -ForegroundColor Green
                } else {
                    Write-Warning "Filter with ID '$targetFilterId' not found - proceeding without filter"
                }
            }
            
            # Update the ADMX rule with our settings
            if ($Description) {
                $admxRule.Description = $Description
            }
            
            if ($Sequence) {
                $admxRule.Sequence = $Sequence
            }
            
            # Set disabled state
            $admxRule.Disabled = $Disabled.ToString().ToLower()
            
            # Initialize AdministrativeTemplates array if it doesn't exist
            if ($null -eq $currentConfig.AdministrativeTemplates) {
                $currentConfig | Add-Member -NotePropertyName AdministrativeTemplates -NotePropertyValue @() -Force
            }
            
            # Add the new rule
            $currentConfig.AdministrativeTemplates += $admxRule
            
            # Update both storage locations
            $script:ModuleConfig.CurrentItems.Config = $currentConfig
            $global:CurrentConfig = $currentConfig
            
            Write-Host "ADMX template added to configuration" -ForegroundColor Green
            Write-Host "  ADMX File: $AdmxFile" -ForegroundColor Cyan
            Write-Host "  ADML File: $AdmlFile" -ForegroundColor Cyan
            Write-Host "  GPO ID: $GpoId" -ForegroundColor Cyan
            if ($resolvedFilterName) {
                Write-Host "  Filter: $resolvedFilterName" -ForegroundColor Cyan
            }
            Write-Host "  Sequence: $Sequence" -ForegroundColor Cyan
            Write-Host "  Disabled: $Disabled" -ForegroundColor Cyan
            Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
            
            return $admxRule
        }
        catch {
            Write-Error "Failed to add ADMX template: $_"
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