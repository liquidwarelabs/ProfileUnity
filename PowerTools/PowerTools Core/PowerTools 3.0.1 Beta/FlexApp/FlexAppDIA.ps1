# FlexAppDIA.ps1
# Location: \FlexApp\FlexAppDIA.ps1
# Compatible with ProfileUnity PowerTools v3.0
# PowerShell 5.1+ Compatible

<#
.SYNOPSIS
    ProfileUnity FlexApp DIA Management Functions with hardcoded DifferencingPath
.DESCRIPTION
    Provides FlexApp DIA package management for ProfileUnity configurations.
    DifferencingPath is hardcoded to %systemdrive%\FADIA-T\VHDW\%username% for consistency.
    Based on the actual ProfileUnity-PowerToolsv3.psm1 implementation.
.NOTES
    Version: 3.0 Optimized
    Author: ProfileUnity PowerTools
    PowerShell: 5.1+ Compatible
    Size: Under 1000 lines for better AI handling
#>

#Requires -Version 5.1

function Add-ProUFlexAppDia {
    <#
    .SYNOPSIS
        Adds a FlexApp DIA package to the current ProfileUnity configuration with hardcoded DifferencingPath.
    
    .DESCRIPTION
        Creates a new FlexApp DIA package in the configuration being edited.
        DifferencingPath is automatically set to %systemdrive%\FADIA-T\VHDW\%username%.
        Uses the same pattern as the actual ProfileUnity-PowerToolsv3.psm1 module.
    
    .PARAMETER DIAName
        Name of the FlexApp package to use for DIA
    
    .PARAMETER FilterName
        Name of the filter to apply
    
    .PARAMETER UseJit
        Enable Just-In-Time provisioning (default: False)
    
    .PARAMETER CacheLocal
        Enable local caching (Cache Blocks Locally) (default: False)
    
    .PARAMETER PredictiveBlockCaching
        Enable Predictive Block Caching (default: False)
    
    .PARAMETER CacheAllBlocks
        Enable Cache All Blocks Locally (default: False)
    
    .PARAMETER EnableClickToLayer
        Enable Click to Layer functionality (default: False)
    
    .PARAMETER Sequence
        Sequence number for the DIA package (default: 0)
    
    .PARAMETER Description
        Description for the DIA package
    
    .EXAMPLE
        Add-ProUFlexAppDia -DIAName "7zip" -FilterName "Test"
        
    .EXAMPLE
        Add-ProUFlexAppDia -DIAName "Chrome" -FilterName "All Users" -UseJit -CacheLocal -PredictiveBlockCaching
        
    .EXAMPLE
        Add-ProUFlexAppDia -DIAName "Office" -FilterName "Users" -CacheAllBlocks -EnableClickToLayer
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DIAName,
        
        [Parameter(Mandatory)]
        [string]$FilterName,
        
        [switch]$UseJit,
        [switch]$CacheLocal,
        [switch]$PredictiveBlockCaching,
        [switch]$CacheAllBlocks,
        [switch]$EnableClickToLayer,
        
        [string]$Sequence = "0",
        
        [string]$Description = "DIA package added with PowerTools"
    )
    
    # Ensure ProfileUnity connection
    Assert-ProfileUnityConnection
    
    # Check if configuration is loaded for editing
    if (-not $script:ModuleConfig.CurrentItems.Config -and -not $global:CurrentConfig) {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    # Use whichever is available (following v3 pattern)
    $currentConfig = if ($script:ModuleConfig.CurrentItems.Config) { 
        $script:ModuleConfig.CurrentItems.Config 
    } else { 
        $global:CurrentConfig 
    }
    
    try {
        Write-Verbose "Looking up FlexApp package: $DIAName"
        
        # Get FlexApp and Filter details using the core function (matching working implementation)
        $flexApp = Get-ProfileUnityItem -ItemType 'flexapppackage' -Name $DIAName
        $filter = Get-ProfileUnityItem -ItemType 'filter' -Name $FilterName
        
        if (-not $flexApp) { throw "FlexApp package '$DIAName' not found" }
        if (-not $filter) { throw "Filter '$FilterName' not found" }
        
        Write-Verbose "Found FlexApp: $($flexApp[0].name) (ID: $($flexApp[0].id))"
        Write-Verbose "Found Filter: $($filter[0].name) (ID: $($filter[0].id))"
        
        # Hardcoded DifferencingPath - no longer configurable
        $DifferencingPath = "%systemdrive%\FADIA-T\VHDW\%username%"
        Write-Verbose "Using hardcoded DifferencingPath: $DifferencingPath"
        
        # Create DIA package object (matching working v3 structure)
        $diaPackage = @{
            DifferencingPath = $DifferencingPath
            UseJit = if ($UseJit) { "True" } else { "False" }
            CacheLocal = if ($CacheLocal) { "True" } else { "False" }
            PredictiveBlockCaching = if ($PredictiveBlockCaching) { "True" } else { "False" }
            FlexAppPackageId = $flexApp[0].id
            FlexAppPackageUuid = $flexApp[0].uuid
            Sequence = $Sequence
        }
        
        # Create module item (matching working v3 structure)
        $moduleItem = @{
            FlexAppPackages = @($diaPackage)
            Playback = "0"
            ReversePlay = "False"
            FilterId = $filter[0].id
            Description = $Description
            Disabled = "False"
        }
        
        # Add to current configuration (matching v3 pattern)
        if (-not $currentConfig.FlexAppDias) {
            $currentConfig | Add-Member -NotePropertyName FlexAppDias -NotePropertyValue @() -Force
        }
        
        $currentConfig.FlexAppDias += $moduleItem
        
        # Update both storage locations (matching v3 pattern)
        $script:ModuleConfig.CurrentItems.Config = $currentConfig
        $global:CurrentConfig = $currentConfig
        
        Write-Host "FlexApp DIA '$DIAName' with filter '$FilterName' added to configuration" -ForegroundColor Green
        Write-Host "  Differencing Path: $DifferencingPath" -ForegroundColor Cyan
        Write-Host "  Use JIT: $UseJit" -ForegroundColor Cyan  
        Write-Host "  Cache Local: $CacheLocal" -ForegroundColor Cyan
        Write-Host "  Predictive Block Caching: $PredictiveBlockCaching" -ForegroundColor Cyan
        Write-Host "  Cache All Blocks: $CacheAllBlocks" -ForegroundColor Cyan
        Write-Host "  Enable Click to Layer: $EnableClickToLayer" -ForegroundColor Cyan
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
        Shows resolved names where possible.
    
    .PARAMETER Index
        Get specific DIA by index
    
    .PARAMETER Detailed
        Show detailed information
    
    .EXAMPLE
        Get-ProUFlexAppDia
        
    .EXAMPLE
        Get-ProUFlexAppDia -Index 1 -Detailed
    #>
    [CmdletBinding()]
    param(
        [int]$Index,
        [switch]$Detailed
    )
    
    # Check if configuration is loaded
    $currentConfig = if ($script:ModuleConfig.CurrentItems.Config) { 
        $script:ModuleConfig.CurrentItems.Config 
    } elseif ($global:CurrentConfig) { 
        $global:CurrentConfig 
    } else {
        Write-Warning "No configuration loaded. Use Edit-ProUConfig first."
        return
    }
    
    if (-not $currentConfig.FlexAppDias -or $currentConfig.FlexAppDias.Count -eq 0) {
        Write-Host "No FlexApp DIA packages found in current configuration" -ForegroundColor Yellow
        return
    }
    
    # Get FlexApp and Filter data for name resolution
    $allFlexApps = @()
    $allFilters = @()
    
    try {
        $allFlexApps = Get-ProUFlexapps -ErrorAction SilentlyContinue
        $allFilters = Get-ProUFilters -ErrorAction SilentlyContinue
    }
    catch {
        Write-Verbose "Could not retrieve FlexApp/Filter data for name resolution: $_"
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
            # Resolve FlexApp name
            $flexAppName = "Unknown"
            $flexApp = $allFlexApps | Where-Object { $_.id -eq $package.FlexAppPackageId } | Select-Object -First 1
            if ($flexApp) {
                $flexAppName = $flexApp.name
            }
            
            # Resolve Filter name
            $filterName = "Unknown"
            $filter = $allFilters | Where-Object { $_.id -eq $dia.FilterId } | Select-Object -First 1
            if ($filter) {
                $filterName = $filter.name
            }
            
            $result = [PSCustomObject]@{
                Index = $diaIndex
                FlexAppName = $flexAppName
                FlexAppId = $package.FlexAppPackageId
                FlexAppUUID = $package.FlexAppPackageUuid
                FilterName = $filterName
                FilterId = $dia.FilterId
                DifferencingPath = $package.DifferencingPath
                UseJit = [System.Convert]::ToBoolean($package.UseJit)
                CacheLocal = [System.Convert]::ToBoolean($package.CacheLocal)
                PredictiveBlockCaching = if ($package.PredictiveBlockCaching) { [System.Convert]::ToBoolean($package.PredictiveBlockCaching) } else { $false }
                CacheAllBlocks = if ($package.CacheAllBlocks) { [System.Convert]::ToBoolean($package.CacheAllBlocks) } else { $false }
                EnableClickToLayer = if ($package.EnableClickToLayer) { [System.Convert]::ToBoolean($package.EnableClickToLayer) } else { $false }
                Sequence = $package.Sequence
                Disabled = [System.Convert]::ToBoolean($dia.Disabled)
                Description = $dia.Description
            }
            
            if ($Detailed) {
                $result | Add-Member -NotePropertyName FlexAppDetails -NotePropertyValue $flexApp
                $result | Add-Member -NotePropertyName FilterDetails -NotePropertyValue $filter
                $result | Add-Member -NotePropertyName RawDiaData -NotePropertyValue $dia
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
        Removes a FlexApp DIA package by index.
    
    .PARAMETER Index
        Index of the DIA to remove (use Get-ProUFlexAppDia to see indices)
    
    .PARAMETER Force
        Skip confirmation prompt
    
    .EXAMPLE
        Remove-ProUFlexAppDia -Index 1
        
    .EXAMPLE
        Remove-ProUFlexAppDia -Index 2 -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Index,
        
        [switch]$Force
    )
    
    # Check if configuration is loaded
    $currentConfig = if ($script:ModuleConfig.CurrentItems.Config) { 
        $script:ModuleConfig.CurrentItems.Config 
    } elseif ($global:CurrentConfig) { 
        $global:CurrentConfig 
    } else {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    if (-not $currentConfig.FlexAppDias -or $currentConfig.FlexAppDias.Count -eq 0) {
        throw "No FlexApp DIA packages found in current configuration"
    }
    
    if ($Index -lt 1 -or $Index -gt $currentConfig.FlexAppDias.Count) {
        throw "Invalid index. Valid range: 1-$($currentConfig.FlexAppDias.Count)"
    }
    
    try {
        $indexToRemove = $Index - 1
        $dia = $currentConfig.FlexAppDias[$indexToRemove]
        
        # Try to get FlexApp name for display
        $displayName = "FlexApp DIA #$Index"
        try {
            if ($dia.FlexAppPackages -and $dia.FlexAppPackages[0].FlexAppPackageId) {
                $flexApp = Get-ProUFlexapps | Where-Object { 
                    $_.id -eq $dia.FlexAppPackages[0].FlexAppPackageId 
                } | Select-Object -First 1
                
                if ($flexApp) {
                    $displayName = $flexApp.name
                }
            }
        }
        catch {
            Write-Verbose "Could not resolve FlexApp name for display"
        }
        
        # Confirmation
        if (-not $Force -and -not $PSCmdlet.ShouldProcess($displayName, "Remove FlexApp DIA")) {
            Write-Host "Operation cancelled" -ForegroundColor Yellow
            return
        }
        
        # Remove the DIA by creating new array without the specified index
        $newDias = @()
        for ($i = 0; $i -lt $currentConfig.FlexAppDias.Count; $i++) {
            if ($i -ne $indexToRemove) {
                $newDias += $currentConfig.FlexAppDias[$i]
            }
        }
        $currentConfig.FlexAppDias = $newDias
        
        # Update both storage locations
        $script:ModuleConfig.CurrentItems.Config = $currentConfig
        $global:CurrentConfig = $currentConfig
        
        Write-Host "Removed FlexApp DIA: $displayName" -ForegroundColor Green
        Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
    }
    catch {
        Write-Error "Failed to remove FlexApp DIA: $_"
        throw
    }
}

function Set-ProUFlexAppDiaSequence {
    <#
    .SYNOPSIS
        Updates sequence numbers for FlexApp DIA packages.
    
    .DESCRIPTION
        Resequences all FlexApp DIA packages in the current configuration.
    
    .PARAMETER StartAt
        Starting sequence number (default: 0)
    
    .EXAMPLE
        Set-ProUFlexAppDiaSequence
        
    .EXAMPLE
        Set-ProUFlexAppDiaSequence -StartAt 1
    #>
    [CmdletBinding()]
    param(
        [string]$StartAt = "0"
    )
    
    # Check if configuration is loaded
    $currentConfig = if ($script:ModuleConfig.CurrentItems.Config) { 
        $script:ModuleConfig.CurrentItems.Config 
    } elseif ($global:CurrentConfig) { 
        $global:CurrentConfig 
    } else {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    if (-not $currentConfig.FlexAppDias -or $currentConfig.FlexAppDias.Count -eq 0) {
        Write-Warning "No FlexApp DIA packages found in current configuration"
        return
    }
    
    Write-Host "Resequencing FlexApp DIA packages..." -ForegroundColor Yellow
    
    $sequence = [int]$StartAt
    foreach ($dia in $currentConfig.FlexAppDias) {
        foreach ($package in $dia.FlexAppPackages) {
            $package.Sequence = $sequence.ToString()
        }
        $sequence++
    }
    
    # Update both storage locations
    $script:ModuleConfig.CurrentItems.Config = $currentConfig
    $global:CurrentConfig = $currentConfig
    
    Write-Host "FlexApp DIA packages resequenced ($StartAt to $($sequence - 1))" -ForegroundColor Green
    Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
}

function Enable-ProUFlexAppDia {
    <#
    .SYNOPSIS
        Enables a FlexApp DIA package.
    
    .DESCRIPTION
        Enables a disabled FlexApp DIA package by index.
    
    .PARAMETER Index
        Index of the DIA to enable
    
    .EXAMPLE
        Enable-ProUFlexAppDia -Index 1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Index
    )
    
    # Check if configuration is loaded
    $currentConfig = if ($script:ModuleConfig.CurrentItems.Config) { 
        $script:ModuleConfig.CurrentItems.Config 
    } elseif ($global:CurrentConfig) { 
        $global:CurrentConfig 
    } else {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    if (-not $currentConfig.FlexAppDias -or $currentConfig.FlexAppDias.Count -eq 0) {
        throw "No FlexApp DIA packages found in current configuration"
    }
    
    if ($Index -lt 1 -or $Index -gt $currentConfig.FlexAppDias.Count) {
        throw "Invalid index. Valid range: 1-$($currentConfig.FlexAppDias.Count)"
    }
    
    $dia = $currentConfig.FlexAppDias[$Index - 1]
    $dia.Disabled = "False"
    
    # Update both storage locations
    $script:ModuleConfig.CurrentItems.Config = $currentConfig
    $global:CurrentConfig = $currentConfig
    
    Write-Host "Enabled FlexApp DIA #$Index" -ForegroundColor Green
    Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
}

function Disable-ProUFlexAppDia {
    <#
    .SYNOPSIS
        Disables a FlexApp DIA package.
    
    .DESCRIPTION
        Disables a FlexApp DIA package by index.
    
    .PARAMETER Index
        Index of the DIA to disable
    
    .EXAMPLE
        Disable-ProUFlexAppDia -Index 1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Index
    )
    
    # Check if configuration is loaded
    $currentConfig = if ($script:ModuleConfig.CurrentItems.Config) { 
        $script:ModuleConfig.CurrentItems.Config 
    } elseif ($global:CurrentConfig) { 
        $global:CurrentConfig 
    } else {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    if (-not $currentConfig.FlexAppDias -or $currentConfig.FlexAppDias.Count -eq 0) {
        throw "No FlexApp DIA packages found in current configuration"
    }
    
    if ($Index -lt 1 -or $Index -gt $currentConfig.FlexAppDias.Count) {
        throw "Invalid index. Valid range: 1-$($currentConfig.FlexAppDias.Count)"
    }
    
    $dia = $currentConfig.FlexAppDias[$Index - 1]
    $dia.Disabled = "True"
    
    # Update both storage locations
    $script:ModuleConfig.CurrentItems.Config = $currentConfig
    $global:CurrentConfig = $currentConfig
    
    Write-Host "Disabled FlexApp DIA #$Index" -ForegroundColor Green
    Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
}

# Export functions
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
Export-ModuleMember -Function @(
    'Add-ProUFlexAppDia',
    'Get-ProUFlexAppDia',
    'Remove-ProUFlexAppDia',
    'Set-ProUFlexAppDiaSequence',
    'Enable-ProUFlexAppDia',
    'Disable-ProUFlexAppDia'
)
#>
