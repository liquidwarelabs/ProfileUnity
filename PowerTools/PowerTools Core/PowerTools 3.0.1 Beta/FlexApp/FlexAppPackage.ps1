# FlexAppPackage.ps1 - ProfileUnity FlexApp Package Management Functions
# Location: \FlexApp\FlexAppPackage.ps1
# Compatible with: ProfileUnity PowerTools v3.0 / PowerShell 5.1+

function Get-ProUFlexapps {
    <#
    .SYNOPSIS
        Gets ProfileUnity FlexApp packages.
    
    .DESCRIPTION
        Retrieves all FlexApp packages or packages by name.
    
    .PARAMETER Name
        Optional name filter (supports wildcards)
    
    .EXAMPLE
        Get-ProUFlexapps
        
    .EXAMPLE
        Get-ProUFlexapps -Name "*Chrome*"
    #>
    [CmdletBinding()]
    param(
        [string]$Name
    )
    
    try {
        Write-Verbose "Retrieving FlexApp packages..."
        $response = Invoke-ProfileUnityApi -Endpoint "flexapppackage"
        
        if (-not $response -or -not $response.Tag) {
            Write-Warning "No FlexApp packages found"
            return
        }
        
        $packages = $response.Tag.Rows
        
        # Filter by name if specified
        if ($Name) {
            $packages = $packages | Where-Object { $_.name -like $Name }
        }
        
        return $packages | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.name
                ID = $_.id
                Version = $_.version
                Description = $_.description
                Enabled = -not $_.disabled
                Size = $_.size
                Created = $_.created
                LastModified = $_.lastModified
                ModifiedBy = $_.modifiedBy
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
        Edit-ProUFlexapp -Name "Google Chrome"
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
        
        # Store in module config with null checking
        if (-not $script:ModuleConfig) {
            $script:ModuleConfig = @{ CurrentItems = @{} }
        }
        if (-not $script:ModuleConfig.CurrentItems) {
            $script:ModuleConfig.CurrentItems = @{}
        }
        $script:ModuleConfig.CurrentItems.FlexApp = $packageData
        
        # Also set global variable for backward compatibility
        $global:CurrentFlexapp = $packageData
        
        if (-not $Quiet) {
            Write-Host "FlexApp package '$Name' loaded for editing" -ForegroundColor Green
            Write-Host "Version: $($packageData.version)" -ForegroundColor Cyan
            Write-Host "Size: $($packageData.size)" -ForegroundColor Cyan
            
            # Show package summary if available
            if ($packageData.applications) {
                Write-Host "Applications: $($packageData.applications.Count)" -ForegroundColor Gray
            }
        }
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
    [CmdletBinding(SupportsShouldProcess)]
    param([switch]$Force) 
    
    if ($Force) {
        Save-ProfileUnityItem -ItemType 'flexapppackage' -Force -Confirm:$false
    } else {
        Save-ProfileUnityItem -ItemType 'flexapppackage'
    }
}

function New-ProUFlexapp {
    <#
    .SYNOPSIS
        Creates a new ProfileUnity FlexApp package.
    
    .DESCRIPTION
        Creates a new FlexApp package with basic settings.
    
    .PARAMETER Name
        Name of the new FlexApp package
    
    .PARAMETER Version
        Version of the FlexApp package
    
    .PARAMETER Description
        Optional description
    
    .EXAMPLE
        New-ProUFlexapp -Name "Google Chrome" -Version "1.0" -Description "Chrome browser package"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [string]$Version,
        
        [string]$Description = ""
    )
    
    try {
        # Check if package already exists
        $existingPackages = Get-ProUFlexapps
        if ($existingPackages | Where-Object { $_.Name -eq $Name }) {
            throw "FlexApp package '$Name' already exists"
        }
        
        Write-Verbose "Creating new FlexApp package: $Name"
        
        # Create basic package object
        $newPackage = @{
            name = $Name
            description = $Description
            version = $Version
            disabled = $false
            applications = @()
        }
        
        # Create the package
        $response = Invoke-ProfileUnityApi -Endpoint "flexapppackage" -Method POST -Body @{
            flexapppackage = $newPackage
        }
        
        if ($response) {
            Write-Host "FlexApp package '$Name' created successfully" -ForegroundColor Green
            return $response
        }
    }
    catch {
        Write-Error "Failed to create FlexApp package: $_"
        throw
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
        Remove-ProUFlexapp -Name "Old Package"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [switch]$Force
    )
    
    try {
        $packages = Get-ProUFlexapps
        $package = $packages | Where-Object { $_.Name -eq $Name }
        
        if (-not $package) {
            throw "FlexApp package '$Name' not found"
        }
        
        if ($Force -or $PSCmdlet.ShouldProcess($Name, "Remove FlexApp package")) {
            $response = Invoke-ProfileUnityApi -Endpoint "flexapppackage/$($package.ID)" -Method DELETE
            Write-Host "FlexApp package '$Name' removed successfully" -ForegroundColor Green
            return $response
        }
        else {
            Write-Host "Remove cancelled" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "Failed to remove FlexApp package: $_"
        throw
    }
}

function Copy-ProUFlexapp {
    <#
    .SYNOPSIS
        Copies an existing ProfileUnity FlexApp package.
    
    .DESCRIPTION
        Copies an existing FlexApp package with a new name.
    
    .PARAMETER SourceName
        Name of the FlexApp package to copy
    
    .PARAMETER NewName
        Name for the new FlexApp package
    
    .PARAMETER Description
        Optional new description
    
    .EXAMPLE
        Copy-ProUFlexapp -SourceName "Chrome v1.0" -NewName "Chrome v1.1"
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
        # Find source package
        $packages = Get-ProUFlexapps
        $sourcePackage = $packages | Where-Object { $_.Name -eq $SourceName }
        
        if (-not $sourcePackage) {
            throw "Source FlexApp package '$SourceName' not found"
        }
        
        Write-Verbose "Copying FlexApp package ID: $($sourcePackage.ID)"
        
        # Get full package details
        $response = Invoke-ProfileUnityApi -Endpoint "flexapppackage/$($sourcePackage.ID)"
        
        if ($response -and $response.tag) {
            # Update the copy with new name
            $copiedPackage = $response.tag
            $copiedPackage.name = $NewName
            
            if ($Description) {
                $copiedPackage.description = $Description
            }
            else {
                $copiedPackage.description = "Copy of $SourceName - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            }
            
            # Remove ID so it creates a new package
            $copiedPackage.PSObject.Properties.Remove('id')
            
            # Save the new package
            $saveResponse = Invoke-ProfileUnityApi -Endpoint "flexapppackage" -Method POST -Body @{
                flexapppackage = $copiedPackage
            }
            
            Write-Host "FlexApp package copied successfully" -ForegroundColor Green
            Write-Host "  Source: $SourceName" -ForegroundColor Cyan
            Write-Host "  New: $NewName" -ForegroundColor Cyan
            
            return $saveResponse
        }
    }
    catch {
        Write-Error "Failed to copy FlexApp package: $_"
        throw
    }
}

function Test-ProUFlexapp {
    <#
    .SYNOPSIS
        Tests a ProfileUnity FlexApp package for issues.
    
    .DESCRIPTION
        Validates FlexApp package settings and checks for common problems.
    
    .PARAMETER Name
        Name of the FlexApp package to test
    
    .EXAMPLE
        Test-ProUFlexapp -Name "Google Chrome"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    try {
        $packages = Get-ProUFlexapps
        $package = $packages | Where-Object { $_.Name -eq $Name }
        
        if (-not $package) {
            throw "FlexApp package '$Name' not found"
        }
        
        Write-Verbose "Testing FlexApp package: $Name"
        
        # Get detailed package
        $response = Invoke-ProfileUnityApi -Endpoint "flexapppackage/$($package.ID)"
        $packageData = $response.tag
        
        $issues = @()
        $warnings = @()
        
        # Basic validation
        if (-not $packageData.name) {
            $issues += "Missing package name"
        }
        
        if (-not $packageData.version) {
            $warnings += "Missing version information"
        }
        
        if (-not $packageData.applications -or $packageData.applications.Count -eq 0) {
            $warnings += "Package has no applications defined"
        }
        
        # Size validation
        if ($packageData.size -and $packageData.size -gt 1073741824) { # 1GB
            $warnings += "Package size is larger than 1GB, consider splitting into smaller packages"
        }
        
        $isValid = $issues.Count -eq 0
        
        $result = [PSCustomObject]@{
            PackageName = $Name
            IsValid = $isValid
            Issues = $issues
            Warnings = $warnings
            ApplicationCount = if ($packageData.applications) { $packageData.applications.Count } else { 0 }
            TestDate = Get-Date
        }
        
        # Display results
        if ($isValid) {
            Write-Host "FlexApp package '$Name' validation: PASSED" -ForegroundColor Green
        }
        else {
            Write-Host "FlexApp package '$Name' validation: FAILED" -ForegroundColor Red
            $issues | ForEach-Object { Write-Host "  ERROR: $_" -ForegroundColor Red }
        }
        
        if ($warnings.Count -gt 0) {
            $warnings | ForEach-Object { Write-Host "  WARNING: $_" -ForegroundColor Yellow }
        }
        
        return $result
    }
    catch {
        Write-Error "Failed to test FlexApp package: $_"
        throw
    }
}

function Add-ProUFlexappNote {
    <#
    .SYNOPSIS
        Adds a note to the currently loaded FlexApp package.
    
    .DESCRIPTION
        Adds a note or comment to the FlexApp package that's currently being edited.
    
    .PARAMETER Note
        The note to add to the package
    
    .EXAMPLE
        Add-ProUFlexappNote -Note "Updated for Windows 11 compatibility"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Note
    )
    
    # Check if FlexApp package is loaded for editing
    $currentPackage = $null
    if ($script:ModuleConfig -and $script:ModuleConfig.CurrentItems -and $script:ModuleConfig.CurrentItems.FlexApp) {
        $currentPackage = $script:ModuleConfig.CurrentItems.FlexApp
    }
    elseif ($global:CurrentFlexapp) {
        $currentPackage = $global:CurrentFlexapp
    }
    
    if (-not $currentPackage) {
        throw "No FlexApp package loaded for editing. Use Edit-ProUFlexapp first."
    }
    
    # Add the note
    if (-not $currentPackage.notes) {
        $currentPackage | Add-Member -NotePropertyName 'notes' -NotePropertyValue @()
    }
    
    $noteEntry = @{
        text = $Note
        author = $env:USERNAME
        date = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }
    
    $currentPackage.notes += $noteEntry
    
    # Update both storage locations
    if ($script:ModuleConfig -and $script:ModuleConfig.CurrentItems) {
        $script:ModuleConfig.CurrentItems.FlexApp = $currentPackage
    }
    if ($global:CurrentFlexapp) {
        $global:CurrentFlexapp = $currentPackage
    }
    
    Write-Host "Note added to FlexApp package" -ForegroundColor Green
    Write-Host "Use Save-ProUFlexapp to save changes" -ForegroundColor Yellow
}

# Export functions
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
Export-ModuleMember -Function @(
    'Get-ProUFlexapps',
    'Edit-ProUFlexapp',
    'Save-ProUFlexapp',
    'New-ProUFlexapp',
    'Remove-ProUFlexapp',
    'Copy-ProUFlexapp',
    'Test-ProUFlexapp',
    'Add-ProUFlexappNote'
)
#>
