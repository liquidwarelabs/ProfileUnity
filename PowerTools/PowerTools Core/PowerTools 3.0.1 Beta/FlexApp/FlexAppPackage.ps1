# FlexAppPackage.ps1 - ProfileUnity FlexApp Package Management Functions

function Get-ProUFlexapps {
    <#
    .SYNOPSIS
        Gets ProfileUnity FlexApp packages.
    
    .DESCRIPTION
        Retrieves all FlexApp packages or filters by name.
    
    .PARAMETER Name
        Optional name filter (supports wildcards)
    
    .PARAMETER Enabled
        Filter by enabled/disabled status
    
    .PARAMETER Type
        Filter by package type (VHD, VMDK)
    
    .EXAMPLE
        Get-ProUFlexapps
        
    .EXAMPLE
        Get-ProUFlexapps -Name "*Office*" -Enabled $true
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        
        [bool]$Enabled,
        
        [ValidateSet('VHD', 'VMDK')]
        [string]$Type
    )
    
    try {
        Write-Verbose "Retrieving FlexApp packages..."
        $response = Invoke-ProfileUnityApi -Endpoint "flexapppackage"
        
        if (-not $response -or -not $response.Tag) {
            Write-Warning "No FlexApp packages found"
            return
        }
        
        $packages = $response.Tag.Rows
        
        # Apply filters
        if ($Name) {
            $packages = $packages | Where-Object { $_.name -like $Name }
        }
        
        if ($PSBoundParameters.ContainsKey('Enabled')) {
            $packages = $packages | Where-Object { -not $_.disabled -eq $Enabled }
        }
        
        if ($Type) {
            $packages = $packages | Where-Object { $_.packageType -eq $Type }
        }
        
        # Format output
        $packages | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.name
                ID = $_.id
                UUID = $_.uuid
                Version = $_.version
                Enabled = -not $_.disabled
                Type = $_.packageType
                Size = $_.size
                SizeMB = [math]::Round($_.size / 1MB, 2)
                Created = $_.created
                Modified = $_.modified
                ModifiedBy = $_.modifiedBy
                Path = $_.path
                CloudPath = $_.cloudPath
                Description = $_.description
            }
        }
    }
    catch {
        Write-Error "Failed to retrieve FlexApp packages: $_"
        throw
    }
}

function Edit-ProUFlexapp {
    <#
    .SYNOPSIS
        Loads a ProfileUnity FlexApp package for editing.
    
    .DESCRIPTION
        Retrieves a FlexApp package and stores it in memory for editing.
    
    .PARAMETER Name
        The exact name of the FlexApp package to edit
    
    .PARAMETER Quiet
        Suppress confirmation messages
    
    .EXAMPLE
        Edit-ProUFlexapp -Name "Microsoft Office 2019"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [switch]$Quiet
    )
    
    try {
        # Get all FlexApp packages
        $packages = Get-ProUFlexapps
        $package = $packages | Where-Object { $_.Name -eq $Name }
        
        if (-not $package) {
            throw "FlexApp package '$Name' not found"
        }
        
        Write-Verbose "Loading FlexApp package ID: $($package.ID)"
        
        # Get full package details
        $response = Invoke-ProfileUnityApi -Endpoint "flexapppackage/$($package.ID)"
        
        if (-not $response -or -not $response.tag) {
            throw "Failed to load FlexApp package details"
        }
        
        $packageData = $response.tag
        
        # Store in module config
        $script:ModuleConfig.CurrentItems.FlexApp = $packageData
        
        # Also set global variable for backward compatibility
        $global:CurrentFlexapp = $packageData
        
        if (-not $Quiet) {
            Write-Host "FlexApp package '$Name' loaded for editing" -ForegroundColor Green
            Write-Host "Version: $($packageData.Version)" -ForegroundColor Cyan
            Write-Host "Type: $($packageData.Type)" -ForegroundColor Cyan
            Write-Host "Size: $([math]::Round($packageData.Size / 1MB, 2)) MB" -ForegroundColor Cyan
            
            # Show history if available
            if ($packageData.History) {
                $historyLines = $packageData.History -split "`n"
                Write-Host "History entries: $($historyLines.Count)" -ForegroundColor Cyan
            }
        }
        
        return $packageData
    }
    catch {
        Write-Error "Failed to edit FlexApp package: $_"
        throw
    }
}

function Save-ProUFlexapp {
    <#
    .SYNOPSIS
        Saves the currently edited ProfileUnity FlexApp package.
    
    .DESCRIPTION
        Saves changes made to the current FlexApp package back to the server.
    
    .PARAMETER Force
        Skip confirmation prompt
    
    .EXAMPLE
        Save-ProUFlexapp
        
    .EXAMPLE
        Save-ProUFlexapp -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [switch]$Force
    )
    
    # Get current FlexApp package
    $currentPackage = $script:ModuleConfig.CurrentItems.FlexApp
    if (-not $currentPackage -and $global:CurrentFlexapp) {
        $currentPackage = $global:CurrentFlexapp
    }
    
    if (-not $currentPackage) {
        throw "No FlexApp package loaded for editing. Use Edit-ProUFlexapp first."
    }
    
    $packageName = $currentPackage.name
    
    if ($Force -or $PSCmdlet.ShouldProcess($packageName, "Save FlexApp package")) {
        try {
            Write-Verbose "Saving FlexApp package: $packageName"
            
            # Prepare the package object
            $packageToSave = @{
                flexapppackages = $currentPackage
            }
            
            $response = Invoke-ProfileUnityApi -Endpoint "flexapppackage" -Method POST -Body $packageToSave
            
            if ($response) {
                Write-Host "FlexApp package '$packageName' saved successfully" -ForegroundColor Green
                Write-LogMessage -Message "FlexApp package '$packageName' saved by $env:USERNAME" -Level Info
                
                # Clear current package after successful save
                $script:ModuleConfig.CurrentItems.FlexApp = $null
                $global:CurrentFlexapp = $null
                
                return $response
            }
        }
        catch {
            Write-Error "Failed to save FlexApp package: $_"
            throw
        }
    }
    else {
        Write-Host "Save cancelled" -ForegroundColor Yellow
    }
}

function Remove-ProUFlexapp {
    <#
    .SYNOPSIS
        Removes a ProfileUnity FlexApp package.
    
    .DESCRIPTION
        Deletes a FlexApp package from the ProfileUnity server.
    
    .PARAMETER Name
        Name of the FlexApp package to remove
    
    .PARAMETER Force
        Skip confirmation prompt
    
    .EXAMPLE
        Remove-ProUFlexapp -Name "Old Application"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [switch]$Force
    )
    
    try {
        # Find FlexApp package
        $packages = Get-ProUFlexapps
        $package = $packages | Where-Object { $_.Name -eq $Name }
        
        if (-not $package) {
            throw "FlexApp package '$Name' not found"
        }
        
        if ($Force -or $PSCmdlet.ShouldProcess($Name, "Remove FlexApp package")) {
            Write-Verbose "Deleting FlexApp package ID: $($package.ID)"
            
            $response = Invoke-ProfileUnityApi -Endpoint "flexapppackage/remove" -Method DELETE -Body @{
                ids = @($package.ID)
            }
            
            Write-Host "FlexApp package '$Name' deleted successfully" -ForegroundColor Green
            Write-LogMessage -Message "FlexApp package '$Name' deleted by $env:USERNAME" -Level Info
            
            return $response
        }
        else {
            Write-Host "Delete cancelled" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "Failed to delete FlexApp package: $_"
        throw
    }
}

function Enable-ProUFlexapp {
    <#
    .SYNOPSIS
        Enables a ProfileUnity FlexApp package.
    
    .DESCRIPTION
        Enables a disabled FlexApp package.
    
    .PARAMETER Name
        Name of the FlexApp package to enable
    
    .EXAMPLE
        Enable-ProUFlexapp -Name "Microsoft Office"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    try {
        # Find FlexApp package
        $packages = Get-ProUFlexapps
        $package = $packages | Where-Object { $_.Name -eq $Name }
        
        if (-not $package) {
            throw "FlexApp package '$Name' not found"
        }
        
        if ($package.Enabled) {
            Write-Host "FlexApp package '$Name' is already enabled" -ForegroundColor Yellow
            return
        }
        
        Write-Verbose "Enabling FlexApp package ID: $($package.ID)"
        
        $response = Invoke-ProfileUnityApi -Endpoint "flexapppackage/$($package.ID)/enable" -Method POST
        
        Write-Host "FlexApp package '$Name' enabled successfully" -ForegroundColor Green
        return $response
    }
    catch {
        Write-Error "Failed to enable FlexApp package: $_"
        throw
    }
}

function Disable-ProUFlexapp {
    <#
    .SYNOPSIS
        Disables a ProfileUnity FlexApp package.
    
    .DESCRIPTION
        Disables an enabled FlexApp package.
    
    .PARAMETER Name
        Name of the FlexApp package to disable
    
    .EXAMPLE
        Disable-ProUFlexapp -Name "Microsoft Office"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    try {
        # Find FlexApp package
        $packages = Get-ProUFlexapps
        $package = $packages | Where-Object { $_.Name -eq $Name }
        
        if (-not $package) {
            throw "FlexApp package '$Name' not found"
        }
        
        if (-not $package.Enabled) {
            Write-Host "FlexApp package '$Name' is already disabled" -ForegroundColor Yellow
            return
        }
        
        Write-Verbose "Disabling FlexApp package ID: $($package.ID)"
        
        $response = Invoke-ProfileUnityApi -Endpoint "flexapppackage/$($package.ID)/disable" -Method POST
        
        Write-Host "FlexApp package '$Name' disabled successfully" -ForegroundColor Green
        return $response
    }
    catch {
        Write-Error "Failed to disable FlexApp package: $_"
        throw
    }
}

function Add-ProUFlexappNote {
    <#
    .SYNOPSIS
        Adds a note to the currently edited FlexApp package history.
    
    .DESCRIPTION
        Adds a timestamped note to the FlexApp package history.
    
    .PARAMETER Note
        The note text to add
    
    .EXAMPLE
        Add-ProUFlexappNote -Note "Updated application to version 2.0"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Note
    )
    
    # Get current FlexApp package
    $currentPackage = $script:ModuleConfig.CurrentItems.FlexApp
    if (-not $currentPackage -and $global:CurrentFlexapp) {
        $currentPackage = $global:CurrentFlexapp
    }
    
    if (-not $currentPackage) {
        throw "No FlexApp package loaded for editing. Use Edit-ProUFlexapp first."
    }
    
    try {
        # Initialize history if needed
        if (-not $currentPackage.History) {
            $currentPackage | Add-Member -NotePropertyName History -NotePropertyValue "" -Force
        }
        
        # Create timestamped note
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $noteEntry = "[$timestamp] Note: $Note"
        
        # Add to history (prepend for newest first)
        if ($currentPackage.History) {
            $currentPackage.History = "$noteEntry`n$($currentPackage.History)"
        }
        else {
            $currentPackage.History = $noteEntry
        }
        
        # Update both storage locations
        $script:ModuleConfig.CurrentItems.FlexApp = $currentPackage
        $global:CurrentFlexapp = $currentPackage
        
        Write-Host "Note added to FlexApp package history" -ForegroundColor Green
        Write-Host "Use Save-ProUFlexapp to save changes" -ForegroundColor Yellow
    }
    catch {
        Write-Error "Failed to add note: $_"
        throw
    }
}

function Get-ProUFlexappWorkingState {
    <#
    .SYNOPSIS
        Gets the working state of a FlexApp package.
    
    .DESCRIPTION
        Retrieves the current working state and deployment status.
    
    .PARAMETER Name
        Name of the FlexApp package
    
    .EXAMPLE
        Get-ProUFlexappWorkingState -Name "Microsoft Office"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    try {
        # Find FlexApp package
        $packages = Get-ProUFlexapps
        $package = $packages | Where-Object { $_.Name -eq $Name }
        
        if (-not $package) {
            throw "FlexApp package '$Name' not found"
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "flexapppackage/$($package.ID)/workingstate"
        
        if ($response) {
            return [PSCustomObject]@{
                PackageName = $Name
                State = $response.state
                LastUpdated = $response.lastUpdated
                DeploymentStatus = $response.deploymentStatus
                ActiveSessions = $response.activeSessions
            }
        }
    }
    catch {
        Write-Error "Failed to get FlexApp working state: $_"
        throw
    }
}

function Get-ProUFlexappReport {
    <#
    .SYNOPSIS
        Gets a report of FlexApp packages.
    
    .DESCRIPTION
        Generates a report of VHD or VMDK FlexApp packages.
    
    .PARAMETER Type
        Type of packages to report on
    
    .EXAMPLE
        Get-ProUFlexappReport -Type VHD
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('VHD', 'VMDK')]
        [string]$Type
    )
    
    try {
        $endpoint = if ($Type -eq 'VHD') { 
            "flexapppackage/vhd/report" 
        } else { 
            "flexapppackage/vmdk/report" 
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint $endpoint
        
        if ($response) {
            return $response | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.name
                    Version = $_.version
                    Size = $_.size
                    SizeMB = [math]::Round($_.size / 1MB, 2)
                    Created = $_.created
                    Modified = $_.modified
                    Enabled = -not $_.disabled
                    InUse = $_.inUse
                    AssignmentCount = $_.assignmentCount
                }
            }
        }
    }
    catch {
        Write-Error "Failed to get FlexApp report: $_"
        throw
    }
}

function Update-ProUFlexappCloud {
    <#
    .SYNOPSIS
        Updates FlexApp packages from cloud storage.
    
    .DESCRIPTION
        Synchronizes FlexApp packages with cloud storage.
    
    .EXAMPLE
        Update-ProUFlexappCloud
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    
    if ($PSCmdlet.ShouldProcess("FlexApp packages", "Update from cloud")) {
        try {
            Write-Host "Updating FlexApp packages from cloud storage..." -ForegroundColor Yellow
            
            $response = Invoke-ProfileUnityApi -Endpoint "flexapppackage/cloud/update" -Method POST
            
            if ($response) {
                Write-Host "FlexApp cloud update completed" -ForegroundColor Green
                
                if ($response.updated) {
                    Write-Host "  Updated: $($response.updated.Count)" -ForegroundColor Cyan
                }
                if ($response.added) {
                    Write-Host "  Added: $($response.added.Count)" -ForegroundColor Cyan
                }
                if ($response.removed) {
                    Write-Host "  Removed: $($response.removed.Count)" -ForegroundColor Cyan
                }
                
                return $response
            }
        }
        catch {
            Write-Error "Failed to update FlexApp packages from cloud: $_"
            throw
        }
    }
}

function Test-ProUFlexapp {
    <#
    .SYNOPSIS
        Tests a FlexApp package configuration.
    
    .DESCRIPTION
        Validates FlexApp package settings and availability.
    
    .PARAMETER Name
        Name of the FlexApp package to test
    
    .EXAMPLE
        Test-ProUFlexapp -Name "Microsoft Office"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    try {
        Write-Host "Testing FlexApp package: $Name" -ForegroundColor Yellow
        
        # Get package details
        $packages = Get-ProUFlexapps
        $package = $packages | Where-Object { $_.Name -eq $Name }
        
        if (-not $package) {
            throw "FlexApp package '$Name' not found"
        }
        
        $issues = @()
        $warnings = @()
        
        # Check if package is disabled
        if (-not $package.Enabled) {
            $warnings += "FlexApp package is disabled"
        }
        
        # Check package path
        if ([string]::IsNullOrWhiteSpace($package.Path) -and [string]::IsNullOrWhiteSpace($package.CloudPath)) {
            $issues += "No package path specified"
        }
        
        # Check size
        if ($package.Size -eq 0) {
            $warnings += "Package size is 0 bytes"
        }
        
        # Get working state
        try {
            $workingState = Get-ProUFlexappWorkingState -Name $Name
            if ($workingState.State -ne "Ready") {
                $warnings += "Package state: $($workingState.State)"
            }
        }
        catch {
            $warnings += "Could not retrieve working state"
        }
        
        # Display results
        Write-Host "`nTest Results:" -ForegroundColor Cyan
        Write-Host "  Package Type: $($package.Type)" -ForegroundColor Gray
        Write-Host "  Version: $($package.Version)" -ForegroundColor Gray
        Write-Host "  Size: $($package.SizeMB) MB" -ForegroundColor Gray
        
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
        
        return [PSCustomObject]@{
            PackageName = $Name
            PackageType = $package.Type
            Version = $package.Version
            SizeMB = $package.SizeMB
            Issues = $issues
            Warnings = $warnings
            IsValid = $issues.Count -eq 0
        }
    }
    catch {
        Write-Error "Failed to test FlexApp package: $_"
        throw
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-ProUFlexapps',
    'Edit-ProUFlexapp',
    'Save-ProUFlexapp',
    'Remove-ProUFlexapp',
    'Enable-ProUFlexapp',
    'Disable-ProUFlexapp',
    'Add-ProUFlexappNote',
    'Get-ProUFlexappWorkingState',
    'Get-ProUFlexappReport',
    'Update-ProUFlexappCloud',
    'Test-ProUFlexapp'
)