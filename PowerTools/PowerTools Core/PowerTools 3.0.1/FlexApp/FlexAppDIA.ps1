# FlexApp/FlexAppDIA.ps1 - ProfileUnity FlexApp DIA Management Functions with Name Resolution

function Add-ProUFlexAppDia {
    <#
    .SYNOPSIS
        Adds a FlexApp DIA package to the current ProfileUnity configuration.
    
    .DESCRIPTION
        Creates a new FlexApp DIA package in the configuration being edited.
        Supports name resolution for FlexApp and Filter parameters.
    
    .PARAMETER DIAName
        Name of the FlexApp package to use for DIA (supports name resolution)
    
    .PARAMETER DIAId
        ID of the FlexApp package to use for DIA (supports name resolution)
    
    .PARAMETER DIAUUID
        UUID of the FlexApp package to use for DIA (supports name resolution)
    
    .PARAMETER FilterName
        Name of the filter to apply (supports name resolution)
    
    .PARAMETER FilterId
        ID of the filter to apply (supports name resolution)
    
    .PARAMETER DifferencingPath
        Path where differences will be stored
    
    .PARAMETER UseJit
        Enable Just-In-Time provisioning
    
    .PARAMETER CacheLocal
        Enable local caching
    
    .PARAMETER Sequence
        Sequence number for the DIA package (default: 1)
    
    .PARAMETER Description
        Description for the DIA package
    
    .EXAMPLE
        Add-ProUFlexAppDia -DIAName "Chrome" -FilterName "All Users" -DifferencingPath "C:\DIA\Chrome"
        
    .EXAMPLE
        Add-ProUFlexAppDia -DIAId "12345" -FilterId "67890" -DifferencingPath "C:\DIA" -UseJit -CacheLocal
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$DIAName,
        
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$DIAId,
        
        [Parameter(Mandatory, ParameterSetName = 'ByUUID')]
        [string]$DIAUUID,
        
        [Parameter(ParameterSetName = 'ByName')]
        [Parameter(ParameterSetName = 'ById')]
        [Parameter(ParameterSetName = 'ByUUID')]
        [string]$FilterName,
        
        [Parameter(ParameterSetName = 'ByName')]
        [Parameter(ParameterSetName = 'ById')]
        [Parameter(ParameterSetName = 'ByUUID')]
        [string]$FilterId,
        
        [Parameter(Mandatory)]
        [string]$DifferencingPath,
        
        [switch]$UseJit,
        [switch]$CacheLocal,
        
        [int]$Sequence = 1,
        
        [string]$Description = "FlexApp DIA added via PowerTools"
    )
    
    # Get current configuration
    $currentConfig = $script:ModuleConfig.CurrentItems.Config
    if (-not $currentConfig -and $global:CurrentConfig) {
        $currentConfig = $global:CurrentConfig
    }
    
    if (-not $currentConfig) {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    try {
        # Resolve FlexApp package
        $flexApp = $null
        switch ($PSCmdlet.ParameterSetName) {
            'ByName' {
                Write-Verbose "Resolving FlexApp name: $DIAName"
                $resolvedId = Resolve-ProUFlexAppId -InputValue $DIAName
                if ($resolvedId) {
                    $flexApp = Get-ProUFlexapps | Where-Object { $_.ID -eq $resolvedId }
                    if ($flexApp) {
                        Write-Host "Resolved '$DIAName' to FlexApp ID: $resolvedId" -ForegroundColor Green
                    }
                }
                
                if (-not $flexApp) {
                    $flexApps = Get-ProUFlexapps -Name $DIAName
                    if ($flexApps) {
                        $flexApp = $flexApps | Select-Object -First 1
                    }
                }
                
                if (-not $flexApp) {
                    throw "FlexApp package '$DIAName' not found"
                }
            }
            'ById' {
                $resolvedId = Resolve-ProUFlexAppId -InputValue $DIAId
                if ($resolvedId -and $resolvedId -ne $DIAId) {
                    Write-Host "Resolved '$DIAId' to FlexApp ID: $resolvedId" -ForegroundColor Green
                }
                $targetId = $resolvedId -or $DIAId
                
                $flexApp = Get-ProUFlexapps | Where-Object { $_.ID -eq $targetId }
                if (-not $flexApp) {
                    throw "FlexApp package with ID '$targetId' not found"
                }
            }
            'ByUUID' {
                $resolvedUUID = Resolve-ProUFlexAppUUID -InputValue $DIAUUID
                if ($resolvedUUID -and $resolvedUUID -ne $DIAUUID) {
                    Write-Host "Resolved '$DIAUUID' to FlexApp UUID: $resolvedUUID" -ForegroundColor Green
                }
                $targetUUID = $resolvedUUID -or $DIAUUID
                
                $flexApp = Get-ProUFlexapps | Where-Object { $_.UUID -eq $targetUUID }
                if (-not $flexApp) {
                    throw "FlexApp package with UUID '$targetUUID' not found"
                }
            }
        }
        
        # Resolve filter
        $filter = $null
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
                } else {
                    # Try direct name lookup
                    $filters = Get-ProUFilters -Name $FilterName
                    if ($filters) {
                        $filter = $filters | Select-Object -First 1
                        $resolvedFilterId = $filter.ID
                        $resolvedFilterName = $filter.Name
                    }
                }
            } else {
                # Try direct name lookup
                $filters = Get-ProUFilters -Name $FilterName
                if ($filters) {
                    $filter = $filters | Select-Object -First 1
                    $resolvedFilterId = $filter.ID
                    $resolvedFilterName = $filter.Name
                }
            }
            
            if (-not $filter) {
                throw "Filter '$FilterName' not found"
            }
        } elseif ($FilterId) {
            $resolvedFilterId = Resolve-ProUFilterId -InputValue $FilterId
            if ($resolvedFilterId -and $resolvedFilterId -ne $FilterId) {
                Write-Host "Resolved '$FilterId' to Filter ID: $resolvedFilterId" -ForegroundColor Green
            }
            $targetFilterId = $resolvedFilterId -or $FilterId
            
            $filter = Get-ProUFilters | Where-Object { $_.ID -eq $targetFilterId }
            if ($filter) {
                $resolvedFilterId = $filter.ID
                $resolvedFilterName = $filter.Name
            } else {
                throw "Filter with ID '$targetFilterId' not found"
            }
        }
        
        Write-Verbose "Adding FlexApp DIA: $($flexApp.Name) with filter: $resolvedFilterName"
        
        # Create DIA package object
        $diaPackage = @{
            DifferencingPath = $DifferencingPath
            UseJit = $UseJit.ToString().ToLower()
            CacheLocal = $CacheLocal.ToString().ToLower()
            PredictiveBlockCaching = "false"
            FlexAppPackageId = $flexApp.ID
            FlexAppPackageUuid = $flexApp.UUID
            Sequence = $Sequence.ToString()
        }
        
        # Create module item
        $moduleItem = @{
            FlexAppPackages = @($diaPackage)
            Playback = "0"
            ReversePlay = "false"
            FilterId = $resolvedFilterId
            Filter = $resolvedFilterName
            Description = $Description
            Disabled = "false"
        }
        
        # Initialize FlexAppDias array if needed
        if (-not $currentConfig.FlexAppDias) {
            $currentConfig | Add-Member -NotePropertyName FlexAppDias -NotePropertyValue @() -Force
        }
        
        # Add to configuration
        $currentConfig.FlexAppDias += $moduleItem
        
        # Update both storage locations
        $script:ModuleConfig.CurrentItems.Config = $currentConfig
        $global:CurrentConfig = $currentConfig
        
        Write-Host "FlexApp DIA added to configuration" -ForegroundColor Green
        Write-Host "  Package: $($flexApp.Name)" -ForegroundColor Cyan
        Write-Host "  Filter: $resolvedFilterName" -ForegroundColor Cyan
        Write-Host "  Differencing Path: $DifferencingPath" -ForegroundColor Cyan
        Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
        
        return $moduleItem
    }
    catch {
        Write-Error "Failed to add FlexApp DIA: $_"
        throw
    }
}

function Get-ProUFlexAppDia {
    <#
    .SYNOPSIS
        Gets FlexApp DIA packages from the current configuration.
    
    .DESCRIPTION
        Retrieves all FlexApp DIA packages from the configuration being edited.
        Provides enhanced display with resolved names.
    
    .PARAMETER Name
        Filter by FlexApp package name (supports wildcards)
    
    .PARAMETER FilterName
        Filter by assigned filter name (supports wildcards)
    
    .PARAMETER Index
        Get specific DIA by index
    
    .PARAMETER Detailed
        Show detailed information including settings
    
    .EXAMPLE
        Get-ProUFlexAppDia
        
    .EXAMPLE
        Get-ProUFlexAppDia -Name "Chrome*" -Detailed
        
    .EXAMPLE
        Get-ProUFlexAppDia -Index 1
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$FilterName,
        [int]$Index,
        [switch]$Detailed
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
    
    if (-not $currentConfig.FlexAppDias -or $currentConfig.FlexAppDias.Count -eq 0) {
        Write-Host "No FlexApp DIA packages found in current configuration" -ForegroundColor Yellow
        return
    }
    
    # Get all FlexApp packages for name lookup
    try {
        $allFlexApps = Get-ProUFlexapps -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "Could not retrieve FlexApp packages for name resolution: $_"
        $allFlexApps = @()
    }
    
    $diaIndex = 0
    $results = @()
    
    $currentConfig.FlexAppDias | ForEach-Object {
        $dia = $_
        $diaIndex++
        
        # Skip if specific index requested and doesn't match
        if ($Index -and $diaIndex -ne $Index) {
            return
        }
        
        foreach ($package in $dia.FlexAppPackages) {
            # Find FlexApp name
            $flexApp = $allFlexApps | Where-Object { $_.ID -eq $package.FlexAppPackageId }
            $flexAppName = if ($flexApp) { $flexApp.Name } else { "Unknown (ID: $($package.FlexAppPackageId))" }
            
            # Apply name filter if specified
            if ($Name -and $flexAppName -notlike $Name) {
                return
            }
            
            # Apply filter name filter if specified
            if ($FilterName -and $dia.Filter -notlike $FilterName) {
                return
            }
            
            $result = [PSCustomObject]@{
                Index = $diaIndex
                FlexAppName = $flexAppName
                FlexAppId = $package.FlexAppPackageId
                FlexAppUUID = $package.FlexAppPackageUuid
                Filter = $dia.Filter
                FilterId = $dia.FilterId
                DifferencingPath = $package.DifferencingPath
                UseJit = [System.Convert]::ToBoolean($package.UseJit)
                CacheLocal = [System.Convert]::ToBoolean($package.CacheLocal)
                Sequence = [int]$package.Sequence
                Disabled = [System.Convert]::ToBoolean($dia.Disabled)
                Description = $dia.Description
            }
            
            if ($Detailed) {
                # Add additional details if available
                $result | Add-Member -NotePropertyName FlexAppDetails -NotePropertyValue $flexApp
                $result | Add-Member -NotePropertyName RawDiaData -NotePropertyValue $dia
                $result | Add-Member -NotePropertyName RawPackageData -NotePropertyValue $package
            }
            
            $results += $result
        }
    }
    
    if ($results.Count -eq 0) {
        Write-Host "No FlexApp DIA packages match the specified criteria" -ForegroundColor Yellow
        return
    }
    
    return $results
}

function Remove-ProUFlexAppDia {
    <#
    .SYNOPSIS
        Removes a FlexApp DIA package from the current configuration.
    
    .DESCRIPTION
        Removes a FlexApp DIA by index, name, or ID from the configuration being edited.
    
    .PARAMETER Index
        Index of the DIA to remove (use Get-ProUFlexAppDia to see indices)
    
    .PARAMETER DIAName
        Name of the FlexApp DIA package to remove (supports name resolution)
    
    .PARAMETER DIAId
        ID of the FlexApp DIA package to remove (supports name resolution)
    
    .EXAMPLE
        Remove-ProUFlexAppDia -Index 1
        
    .EXAMPLE
        Remove-ProUFlexAppDia -DIAName "Chrome"
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'ByIndex')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByIndex')]
        [int]$Index,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$DIAName,
        
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$DIAId
    )
    
    # Get current configuration
    $currentConfig = $script:ModuleConfig.CurrentItems.Config
    if (-not $currentConfig -and $global:CurrentConfig) {
        $currentConfig = $global:CurrentConfig
    }
    
    if (-not $currentConfig) {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    if (-not $currentConfig.FlexAppDias -or $currentConfig.FlexAppDias.Count -eq 0) {
        throw "No FlexApp DIA packages found in current configuration"
    }
    
    try {
        switch ($PSCmdlet.ParameterSetName) {
            'ByIndex' {
                if ($Index -lt 1 -or $Index -gt $currentConfig.FlexAppDias.Count) {
                    throw "Invalid index. Valid range: 1-$($currentConfig.FlexAppDias.Count)"
                }
                
                $targetIndex = $Index - 1
                $diaToRemove = $currentConfig.FlexAppDias[$targetIndex]
                
                # Get FlexApp name for confirmation
                $flexAppName = "Unknown"
                if ($diaToRemove.FlexAppPackages -and $diaToRemove.FlexAppPackages[0].FlexAppPackageId) {
                    try {
                        $flexApp = Get-ProUFlexapps | Where-Object { $_.ID -eq $diaToRemove.FlexAppPackages[0].FlexAppPackageId }
                        if ($flexApp) {
                            $flexAppName = $flexApp.Name
                        }
                    }
                    catch {
                        # Continue with unknown name
                    }
                }
            }
            
            'ByName' {
                # Resolve name to find the DIA
                $resolvedId = Resolve-ProUFlexAppId -InputValue $DIAName
                $targetDias = @()
                
                foreach ($i in 0..($currentConfig.FlexAppDias.Count - 1)) {
                    $dia = $currentConfig.FlexAppDias[$i]
                    if ($dia.FlexAppPackages) {
                        foreach ($package in $dia.FlexAppPackages) {
                            # Try to match by resolved ID or direct name lookup
                            $flexApp = Get-ProUFlexapps | Where-Object { $_.ID -eq $package.FlexAppPackageId }
                            if ($flexApp -and ($flexApp.Name -eq $DIAName -or $flexApp.ID -eq $resolvedId)) {
                                $targetDias += @{ Index = $i; DIA = $dia; FlexAppName = $flexApp.Name }
                                break
                            }
                        }
                    }
                }
                
                if ($targetDias.Count -eq 0) {
                    throw "FlexApp DIA package '$DIAName' not found"
                }
                
                if ($targetDias.Count -gt 1) {
                    Write-Warning "Multiple DIA packages found for '$DIAName'. Removing first match."
                }
                
                $targetIndex = $targetDias[0].Index
                $diaToRemove = $targetDias[0].DIA
                $flexAppName = $targetDias[0].FlexAppName
            }
            
            'ById' {
                $resolvedId = Resolve-ProUFlexAppId -InputValue $DIAId
                $targetId = $resolvedId -or $DIAId
                
                $targetIndex = -1
                $flexAppName = "Unknown"
                
                for ($i = 0; $i -lt $currentConfig.FlexAppDias.Count; $i++) {
                    $dia = $currentConfig.FlexAppDias[$i]
                    if ($dia.FlexAppPackages) {
                        foreach ($package in $dia.FlexAppPackages) {
                            if ($package.FlexAppPackageId -eq $targetId) {
                                $targetIndex = $i
                                $diaToRemove = $dia
                                
                                # Get FlexApp name
                                try {
                                    $flexApp = Get-ProUFlexapps | Where-Object { $_.ID -eq $targetId }
                                    if ($flexApp) {
                                        $flexAppName = $flexApp.Name
                                    }
                                }
                                catch {
                                    # Continue with unknown name
                                }
                                break
                            }
                        }
                        if ($targetIndex -ge 0) { break }
                    }
                }
                
                if ($targetIndex -lt 0) {
                    throw "FlexApp DIA package with ID '$targetId' not found"
                }
            }
        }
        
        # Confirm removal
        $confirmMessage = "Remove FlexApp DIA: $flexAppName (Filter: $($diaToRemove.Filter))"
        if ($PSCmdlet.ShouldProcess($confirmMessage, "Remove FlexApp DIA")) {
            
            # Remove the DIA
            $newDias = @()
            for ($i = 0; $i -lt $currentConfig.FlexAppDias.Count; $i++) {
                if ($i -ne $targetIndex) {
                    $newDias += $currentConfig.FlexAppDias[$i]
                }
            }
            
            $currentConfig.FlexAppDias = $newDias
            
            # Update both storage locations
            $script:ModuleConfig.CurrentItems.Config = $currentConfig
            $global:CurrentConfig = $currentConfig
            
            Write-Host "FlexApp DIA removed: $flexAppName" -ForegroundColor Green
            Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "Failed to remove FlexApp DIA: $_"
        throw
    }
}

function Set-ProUFlexAppDiaSequence {
    <#
    .SYNOPSIS
        Sets the sequence number for FlexApp DIA packages.
    
    .DESCRIPTION
        Updates the sequence numbers for FlexApp DIA packages in the current configuration.
    
    .PARAMETER Index
        Index of the DIA to update
    
    .PARAMETER Sequence
        New sequence number
    
    .PARAMETER ResequenceAll
        Resequence all DIAs starting from specified number
    
    .PARAMETER StartAt
        Starting sequence number for resequencing (default: 1)
    
    .EXAMPLE
        Set-ProUFlexAppDiaSequence -Index 1 -Sequence 5
        
    .EXAMPLE
        Set-ProUFlexAppDiaSequence -ResequenceAll -StartAt 1
    #>
    [CmdletBinding(DefaultParameterSetName = 'Single')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Single')]
        [int]$Index,
        
        [Parameter(Mandatory, ParameterSetName = 'Single')]
        [int]$Sequence,
        
        [Parameter(Mandatory, ParameterSetName = 'All')]
        [switch]$ResequenceAll,
        
        [Parameter(ParameterSetName = 'All')]
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
    
    if (-not $currentConfig.FlexAppDias -or $currentConfig.FlexAppDias.Count -eq 0) {
        throw "No FlexApp DIA packages found in current configuration"
    }
    
    try {
        if ($PSCmdlet.ParameterSetName -eq 'Single') {
            if ($Index -lt 1 -or $Index -gt $currentConfig.FlexAppDias.Count) {
                throw "Invalid index. Valid range: 1-$($currentConfig.FlexAppDias.Count)"
            }
            
            $dia = $currentConfig.FlexAppDias[$Index - 1]
            
            # Update sequence for all packages in this DIA
            foreach ($package in $dia.FlexAppPackages) {
                $package.Sequence = $Sequence.ToString()
            }
            
            Write-Host "Updated FlexApp DIA #$Index sequence to: $Sequence" -ForegroundColor Green
        }
        else {
            # Resequence all DIAs
            $sequenceNumber = $StartAt
            foreach ($dia in $currentConfig.FlexAppDias) {
                foreach ($package in $dia.FlexAppPackages) {
                    $package.Sequence = $sequenceNumber.ToString()
                }
                $sequenceNumber++
            }
            
            Write-Host "Resequenced all FlexApp DIAs ($StartAt to $($sequenceNumber - 1))" -ForegroundColor Green
        }
        
        # Update both storage locations
        $script:ModuleConfig.CurrentItems.Config = $currentConfig
        $global:CurrentConfig = $currentConfig
        
        Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
    }
    catch {
        Write-Error "Failed to update FlexApp DIA sequence: $_"
        throw
    }
}

function Enable-ProUFlexAppDia {
    <#
    .SYNOPSIS
        Enables a FlexApp DIA package in the current configuration.
    
    .DESCRIPTION
        Enables a disabled FlexApp DIA package by index or name.
    
    .PARAMETER Index
        Index of the DIA to enable
    
    .PARAMETER DIAName
        Name of the FlexApp DIA package to enable (supports name resolution)
    
    .EXAMPLE
        Enable-ProUFlexAppDia -Index 1
        
    .EXAMPLE
        Enable-ProUFlexAppDia -DIAName "Chrome"
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByIndex')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByIndex')]
        [int]$Index,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$DIAName
    )
    
    # Get current configuration
    $currentConfig = $script:ModuleConfig.CurrentItems.Config
    if (-not $currentConfig -and $global:CurrentConfig) {
        $currentConfig = $global:CurrentConfig
    }
    
    if (-not $currentConfig) {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    if (-not $currentConfig.FlexAppDias -or $currentConfig.FlexAppDias.Count -eq 0) {
        throw "No FlexApp DIA packages found in current configuration"
    }
    
    try {
        $diaToUpdate = $null
        $displayName = ""
        
        switch ($PSCmdlet.ParameterSetName) {
            'ByIndex' {
                if ($Index -lt 1 -or $Index -gt $currentConfig.FlexAppDias.Count) {
                    throw "Invalid index. Valid range: 1-$($currentConfig.FlexAppDias.Count)"
                }
                
                $diaToUpdate = $currentConfig.FlexAppDias[$Index - 1]
                $displayName = "FlexApp DIA #$Index"
                
                # Try to get actual FlexApp name
                if ($diaToUpdate.FlexAppPackages -and $diaToUpdate.FlexAppPackages[0].FlexAppPackageId) {
                    try {
                        $flexApp = Get-ProUFlexapps | Where-Object { $_.ID -eq $diaToUpdate.FlexAppPackages[0].FlexAppPackageId }
                        if ($flexApp) {
                            $displayName = $flexApp.Name
                        }
                    }
                    catch {
                        # Continue with index-based name
                    }
                }
            }
            
            'ByName' {
                $resolvedId = Resolve-ProUFlexAppId -InputValue $DIAName
                
                foreach ($dia in $currentConfig.FlexAppDias) {
                    if ($dia.FlexAppPackages) {
                        foreach ($package in $dia.FlexAppPackages) {
                            $flexApp = Get-ProUFlexapps | Where-Object { $_.ID -eq $package.FlexAppPackageId }
                            if ($flexApp -and ($flexApp.Name -eq $DIAName -or $flexApp.ID -eq $resolvedId)) {
                                $diaToUpdate = $dia
                                $displayName = $flexApp.Name
                                break
                            }
                        }
                        if ($diaToUpdate) { break }
                    }
                }
                
                if (-not $diaToUpdate) {
                    throw "FlexApp DIA package '$DIAName' not found"
                }
            }
        }
        
        # Enable the DIA
        $diaToUpdate.Disabled = "false"
        
        # Update both storage locations
        $script:ModuleConfig.CurrentItems.Config = $currentConfig
        $global:CurrentConfig = $currentConfig
        
        Write-Host "Enabled FlexApp DIA: $displayName" -ForegroundColor Green
        Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
    }
    catch {
        Write-Error "Failed to enable FlexApp DIA: $_"
        throw
    }
}

function Disable-ProUFlexAppDia {
    <#
    .SYNOPSIS
        Disables a FlexApp DIA package in the current configuration.
    
    .DESCRIPTION
        Disables an enabled FlexApp DIA package by index or name.
    
    .PARAMETER Index
        Index of the DIA to disable
    
    .PARAMETER DIAName
        Name of the FlexApp DIA package to disable (supports name resolution)
    
    .EXAMPLE
        Disable-ProUFlexAppDia -Index 1
        
    .EXAMPLE
        Disable-ProUFlexAppDia -DIAName "Chrome"
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByIndex')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByIndex')]
        [int]$Index,
        
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$DIAName
    )
    
    # Get current configuration
    $currentConfig = $script:ModuleConfig.CurrentItems.Config
    if (-not $currentConfig -and $global:CurrentConfig) {
        $currentConfig = $global:CurrentConfig
    }
    
    if (-not $currentConfig) {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    if (-not $currentConfig.FlexAppDias -or $currentConfig.FlexAppDias.Count -eq 0) {
        throw "No FlexApp DIA packages found in current configuration"
    }
    
    try {
        $diaToUpdate = $null
        $displayName = ""
        
        switch ($PSCmdlet.ParameterSetName) {
            'ByIndex' {
                if ($Index -lt 1 -or $Index -gt $currentConfig.FlexAppDias.Count) {
                    throw "Invalid index. Valid range: 1-$($currentConfig.FlexAppDias.Count)"
                }
                
                $diaToUpdate = $currentConfig.FlexAppDias[$Index - 1]
                $displayName = "FlexApp DIA #$Index"
                
                # Try to get actual FlexApp name
                if ($diaToUpdate.FlexAppPackages -and $diaToUpdate.FlexAppPackages[0].FlexAppPackageId) {
                    try {
                        $flexApp = Get-ProUFlexapps | Where-Object { $_.ID -eq $diaToUpdate.FlexAppPackages[0].FlexAppPackageId }
                        if ($flexApp) {
                            $displayName = $flexApp.Name
                        }
                    }
                    catch {
                        # Continue with index-based name
                    }
                }
            }
            
            'ByName' {
                $resolvedId = Resolve-ProUFlexAppId -InputValue $DIAName
                
                foreach ($dia in $currentConfig.FlexAppDias) {
                    if ($dia.FlexAppPackages) {
                        foreach ($package in $dia.FlexAppPackages) {
                            $flexApp = Get-ProUFlexapps | Where-Object { $_.ID -eq $package.FlexAppPackageId }
                            if ($flexApp -and ($flexApp.Name -eq $DIAName -or $flexApp.ID -eq $resolvedId)) {
                                $diaToUpdate = $dia
                                $displayName = $flexApp.Name
                                break
                            }
                        }
                        if ($diaToUpdate) { break }
                    }
                }
                
                if (-not $diaToUpdate) {
                    throw "FlexApp DIA package '$DIAName' not found"
                }
            }
        }
        
        # Disable the DIA
        $diaToUpdate.Disabled = "true"
        
        # Update both storage locations
        $script:ModuleConfig.CurrentItems.Config = $currentConfig
        $global:CurrentConfig = $currentConfig
        
        Write-Host "Disabled FlexApp DIA: $displayName" -ForegroundColor Green
        Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
    }
    catch {
        Write-Error "Failed to disable FlexApp DIA: $_"
        throw
    }
}

function Resolve-ProUFlexAppId {
    <#
    .SYNOPSIS
        Resolves a FlexApp package name to its ID.
    
    .DESCRIPTION
        Internal helper function that resolves a FlexApp package name to its ID.
        If the input is already an ID format, returns it unchanged.
    
    .PARAMETER InputValue
        The name or ID to resolve
    
    .EXAMPLE
        Resolve-ProUFlexAppId -InputValue "Chrome"
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
        
        # Search for the FlexApp by name
        Write-Verbose "Resolving FlexApp name '$InputValue' to ID..."
        
        try {
            $flexApps = Get-ProUFlexapps -ErrorAction SilentlyContinue
        }
        catch {
            Write-Verbose "Could not retrieve FlexApps for name resolution: $_"
            return $null
        }
        
        # Find exact name match
        $exactMatch = $flexApps | Where-Object { $_.Name -eq $InputValue }
        if ($exactMatch) {
            if ($exactMatch.Count -gt 1) {
                Write-Warning "Multiple FlexApps found with name '$InputValue'. Using first match."
            }
            return $exactMatch[0].ID
        }
        
        # Look for partial matches
        $partialMatches = $flexApps | Where-Object { $_.Name -like "*$InputValue*" }
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
        Write-Verbose "No FlexApp found with name: $InputValue"
        return $null
    }
    catch {
        Write-Verbose "Error resolving FlexApp ID: $_"
        return $null
    }
}

function Resolve-ProUFlexAppUUID {
    <#
    .SYNOPSIS
        Resolves a FlexApp package name to its UUID.
    
    .DESCRIPTION
        Internal helper function that resolves a FlexApp package name to its UUID.
        If the input is already a UUID format, returns it unchanged.
    
    .PARAMETER InputValue
        The name or UUID to resolve
    
    .EXAMPLE
        Resolve-ProUFlexAppUUID -InputValue "Chrome"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputValue
    )
    
    try {
        # Check if input looks like a UUID (contains hyphens and letters)
        if ($InputValue -match '^[\da-f\-]+$' -and $InputValue.Length -gt 8) {
            return $InputValue
        }
        
        # Search for the FlexApp by name
        Write-Verbose "Resolving FlexApp name '$InputValue' to UUID..."
        
        try {
            $flexApps = Get-ProUFlexapps -ErrorAction SilentlyContinue
        }
        catch {
            Write-Verbose "Could not retrieve FlexApps for name resolution: $_"
            return $null
        }
        
        # Find exact name match
        $exactMatch = $flexApps | Where-Object { $_.Name -eq $InputValue }
        if ($exactMatch) {
            if ($exactMatch.Count -gt 1) {
                Write-Warning "Multiple FlexApps found with name '$InputValue'. Using first match."
            }
            return $exactMatch[0].UUID
        }
        
        # Look for partial matches
        $partialMatches = $flexApps | Where-Object { $_.Name -like "*$InputValue*" }
        if ($partialMatches) {
            if ($partialMatches.Count -eq 1) {
                Write-Host "Found partial match: '$($partialMatches[0].Name)'" -ForegroundColor Yellow
                return $partialMatches[0].UUID
            } else {
                Write-Warning "Multiple partial matches found for '$InputValue':"
                $partialMatches | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
                return $partialMatches[0].UUID
            }
        }
        
        # No match found
        Write-Verbose "No FlexApp found with name: $InputValue"
        return $null
    }
    catch {
        Write-Verbose "Error resolving FlexApp UUID: $_"
        return $null
    }
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
    'Add-ProUFlexAppDia',
    'Get-ProUFlexAppDia',
    'Remove-ProUFlexAppDia',
    'Set-ProUFlexAppDiaSequence',
    'Enable-ProUFlexAppDia',
    'Disable-ProUFlexAppDia',
    'Resolve-ProUFlexAppId',
    'Resolve-ProUFlexAppUUID',
    'Resolve-ProUFilterId'
)