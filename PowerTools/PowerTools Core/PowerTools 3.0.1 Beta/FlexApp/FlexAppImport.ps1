# FlexAppImport.ps1 - ProfileUnity FlexApp Import Functions

function Import-ProUFlexapp {
    <#
    .SYNOPSIS
        Imports a FlexApp package from XML.
    
    .DESCRIPTION
        Imports a FlexApp package from an XML file on the ProfileUnity server.
    
    .PARAMETER Path
        Path to the XML file on the ProfileUnity server
    
    .PARAMETER LocalFile
        Path to a local XML file to upload and import
    
    .EXAMPLE
        Import-ProUFlexapp -Path "\\server\share\flexapps\Office.xml"
        
    .EXAMPLE
        Import-ProUFlexapp -LocalFile "C:\FlexApps\Office.xml"
    #>
    [CmdletBinding(DefaultParameterSetName = 'ServerPath')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ServerPath')]
        [string]$Path,
        
        [Parameter(Mandatory, ParameterSetName = 'LocalFile')]
        [string]$LocalFile
    )
    
    try {
        if ($PSCmdlet.ParameterSetName -eq 'LocalFile') {
            if (-not (Test-Path $LocalFile)) {
                throw "Local file not found: $LocalFile"
            }
            
            # For local files, we need to upload first
            # This would require additional implementation
            throw "Local file upload not yet implemented. Please copy file to ProfileUnity server first."
        }
        
        Write-Host "Importing FlexApp package from: $Path" -ForegroundColor Yellow
        
        # Get package XML from server path
        $response = Invoke-ProfileUnityApi -Endpoint "server/flexapppackagexml?path=$Path"
        
        if (-not $response -or -not $response.Tag) {
            throw "Failed to read FlexApp package XML"
        }
        
        $package = $response.Tag
        
        Write-Verbose "Package found: $($package.name) v$($package.version)"
        
        # Import the package
        $importResponse = Invoke-ProfileUnityApi -Endpoint "flexapppackage/import" -Method POST -Body @($package)
        
        if ($importResponse) {
            Write-Host "FlexApp package imported successfully" -ForegroundColor Green
            Write-Host "  Name: $($package.name)" -ForegroundColor Cyan
            Write-Host "  Version: $($package.version)" -ForegroundColor Cyan
            Write-Host "  Type: $($package.type)" -ForegroundColor Cyan
            
            return $importResponse
        }
    }
    catch {
        Write-Error "Failed to import FlexApp package: $_"
        throw
    }
}

function Import-ProUFlexappsAll {
    <#
    .SYNOPSIS
        Imports all FlexApp packages from a directory.
    
    .DESCRIPTION
        Imports all XML FlexApp package files from a specified directory on the ProfileUnity server.
    
    .PARAMETER SourceDir
        Directory path on the ProfileUnity server containing XML files
    
    .PARAMETER Filter
        File filter pattern (default: *.xml)
    
    .PARAMETER Recurse
        Search subdirectories
    
    .EXAMPLE
        Import-ProUFlexappsAll -SourceDir "\\server\share\flexapps"
        
    .EXAMPLE
        Import-ProUFlexappsAll -SourceDir "C:\FlexApps" -Recurse
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceDir,
        
        [string]$Filter = "*.xml",
        
        [switch]$Recurse
    )
    
    try {
        Write-Host "Scanning for FlexApp packages in: $SourceDir" -ForegroundColor Yellow
        
        # Get file list from server
        # Note: This would need server-side directory browsing support
        $files = @()
        
        # For now, we'll need to get the file list another way
        # This is a limitation that would need server API support
        Write-Warning "Batch import requires manual file listing. Please import files individually."
        
        # Placeholder for when API supports directory listing
        <#
        $files = Get-ProfileUnityServerFiles -Path $SourceDir -Filter $Filter -Recurse:$Recurse
        
        if (-not $files) {
            Write-Warning "No XML files found in: $SourceDir"
            return
        }
        
        Write-Host "Found $($files.Count) XML files to import" -ForegroundColor Cyan
        
        $imported = 0
        $failed = 0
        $skipped = 0
        
        foreach ($file in $files) {
            try {
                Write-Host "  Processing: $($file.Name)" -NoNewline
                
                # Check if already exists
                $packageInfo = Get-FlexAppPackageInfo -Path $file.FullName
                $existing = Get-ProUFlexapps -Name $packageInfo.Name
                
                if ($existing) {
                    Write-Host " [SKIPPED - Already exists]" -ForegroundColor Yellow
                    $skipped++
                    continue
                }
                
                Import-ProUFlexapp -Path $file.FullName
                $imported++
                Write-Host " [OK]" -ForegroundColor Green
            }
            catch {
                $failed++
                Write-Host " [FAILED]" -ForegroundColor Red
                Write-Warning "    Error: $_"
            }
        }
        
        Write-Host "`nImport Summary:" -ForegroundColor Cyan
        Write-Host "  Imported: $imported" -ForegroundColor Green
        Write-Host "  Skipped: $skipped" -ForegroundColor Yellow
        if ($failed -gt 0) {
            Write-Host "  Failed: $failed" -ForegroundColor Red
        }
        #>
        
        Write-Host @"

To import multiple FlexApp packages:
1. Copy all XML files to a location accessible by the ProfileUnity server
2. Run Import-ProUFlexapp for each file:
   
   Get-ChildItem -Path "$SourceDir" -Filter $Filter $(if ($Recurse) { "-Recurse" }) | ForEach-Object {
       Import-ProUFlexapp -Path `$_.FullName
   }
"@ -ForegroundColor Cyan
    }
    catch {
        Write-Error "Failed to import FlexApp packages: $_"
        throw
    }
}

function Export-ProUFlexapp {
    <#
    .SYNOPSIS
        Exports a FlexApp package configuration.
    
    .DESCRIPTION
        Exports FlexApp package metadata to XML format.
    
    .PARAMETER Name
        Name of the FlexApp package to export
    
    .PARAMETER OutputPath
        Path to save the exported XML
    
    .EXAMPLE
        Export-ProUFlexapp -Name "Microsoft Office" -OutputPath "C:\Exports\Office.xml"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [string]$OutputPath
    )
    
    try {
        # Find FlexApp package
        $packages = Get-ProUFlexapps
        $package = $packages | Where-Object { $_.Name -eq $Name }
        
        if (-not $package) {
            throw "FlexApp package '$Name' not found"
        }
        
        Write-Verbose "Exporting FlexApp package ID: $($package.ID)"
        
        # Get full package details
        $response = Invoke-ProfileUnityApi -Endpoint "flexapppackage/$($package.ID)"
        
        if (-not $response -or -not $response.tag) {
            throw "Failed to load FlexApp package details"
        }
        
        $packageData = $response.tag
        
        # Create XML structure
        $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<FlexAppPackage>
    <Name>$($packageData.name)</Name>
    <Version>$($packageData.version)</Version>
    <Type>$($packageData.type)</Type>
    <Description>$([System.Security.SecurityElement]::Escape($packageData.description))</Description>
    <Path>$($packageData.path)</Path>
    <CloudPath>$($packageData.cloudPath)</CloudPath>
    <Size>$($packageData.size)</Size>
    <Created>$($packageData.created)</Created>
    <Modified>$($packageData.modified)</Modified>
    <History>$([System.Security.SecurityElement]::Escape($packageData.History))</History>
    <Metadata>
        <ExportDate>$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</ExportDate>
        <ExportedBy>$env:USERNAME</ExportedBy>
        <ExportedFrom>$($script:ModuleConfig.ServerName)</ExportedFrom>
    </Metadata>
</FlexAppPackage>
"@
        
        # Save to file
        $xml | Set-Content -Path $OutputPath -Encoding UTF8
        
        Write-Host "FlexApp package exported to: $OutputPath" -ForegroundColor Green
        return Get-Item $OutputPath
    }
    catch {
        Write-Error "Failed to export FlexApp package: $_"
        throw
    }
}

function Test-ProUFlexappImport {
    <#
    .SYNOPSIS
        Tests if a FlexApp XML file can be imported.
    
    .DESCRIPTION
        Validates a FlexApp XML file before importing.
    
    .PARAMETER Path
        Path to the XML file to test
    
    .EXAMPLE
        Test-ProUFlexappImport -Path "\\server\share\flexapps\Office.xml"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    try {
        Write-Host "Testing FlexApp package: $Path" -ForegroundColor Yellow
        
        # Try to read the XML
        $response = Invoke-ProfileUnityApi -Endpoint "server/flexapppackagexml?path=$Path"
        
        if (-not $response -or -not $response.Tag) {
            throw "Failed to read FlexApp package XML"
        }
        
        $package = $response.Tag
        
        $issues = @()
        $warnings = @()
        
        # Validate required fields
        if ([string]::IsNullOrWhiteSpace($package.name)) {
            $issues += "Package name is missing"
        }
        
        if ([string]::IsNullOrWhiteSpace($package.version)) {
            $warnings += "Package version is missing"
        }
        
        if ([string]::IsNullOrWhiteSpace($package.path) -and [string]::IsNullOrWhiteSpace($package.cloudPath)) {
            $issues += "No package path specified"
        }
        
        # Check if already exists
        if ($package.name) {
            $existing = Get-ProUFlexapps -Name $package.name
            if ($existing) {
                $warnings += "Package with name '$($package.name)' already exists"
            }
        }
        
        # Display results
        Write-Host "`nValidation Results:" -ForegroundColor Cyan
        Write-Host "  Package: $($package.name)" -ForegroundColor Gray
        Write-Host "  Version: $($package.version)" -ForegroundColor Gray
        Write-Host "  Type: $($package.type)" -ForegroundColor Gray
        
        if ($issues.Count -eq 0 -and $warnings.Count -eq 0) {
            Write-Host "  Status: Ready to import" -ForegroundColor Green
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
            Path = $Path
            PackageName = $package.name
            Version = $package.version
            Type = $package.type
            Issues = $issues
            Warnings = $warnings
            CanImport = $issues.Count -eq 0
        }
    }
    catch {
        Write-Error "Failed to test FlexApp package: $_"
        throw
    }
}

function Update-ProUFlexappMetadata {
    <#
    .SYNOPSIS
        Updates metadata for a FlexApp package.
    
    .DESCRIPTION
        Updates version, description, or other metadata for an existing FlexApp package.
    
    .PARAMETER Name
        Name of the FlexApp package
    
    .PARAMETER NewVersion
        New version number
    
    .PARAMETER Description
        New description
    
    .PARAMETER AddNote
        Note to add to history
    
    .EXAMPLE
        Update-ProUFlexappMetadata -Name "Office" -NewVersion "2.0" -AddNote "Updated to Office 2021"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [string]$NewVersion,
        
        [string]$Description,
        
        [string]$AddNote
    )
    
    if ($PSCmdlet.ShouldProcess($Name, "Update FlexApp metadata")) {
        try {
            # Load the package
            Edit-ProUFlexapp -Name $Name -Quiet
            
            $package = $script:ModuleConfig.CurrentItems.FlexApp
            if (-not $package) {
                throw "Failed to load FlexApp package"
            }
            
            $changes = @()
            
            # Update version
            if ($NewVersion) {
                $package.version = $NewVersion
                $changes += "Version updated to: $NewVersion"
            }
            
            # Update description
            if ($Description) {
                $package.description = $Description
                $changes += "Description updated"
            }
            
            # Add note
            if ($AddNote) {
                Add-ProUFlexappNote -Note $AddNote
                $changes += "Note added to history"
            }
            
            if ($changes.Count -gt 0) {
                # Save changes
                Save-ProUFlexapp -Force
                
                Write-Host "FlexApp package '$Name' updated:" -ForegroundColor Green
                $changes | ForEach-Object {
                    Write-Host "  - $_" -ForegroundColor Cyan
                }
            }
            else {
                Write-Host "No changes specified" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Error "Failed to update FlexApp metadata: $_"
            throw
        }
    }
}

function Compare-ProUFlexappVersions {
    <#
    .SYNOPSIS
        Compares versions of FlexApp packages.
    
    .DESCRIPTION
        Compares FlexApp packages with the same name to identify version differences.
    
    .PARAMETER Name
        Name pattern to match packages
    
    .EXAMPLE
        Compare-ProUFlexappVersions -Name "*Office*"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    try {
        $packages = Get-ProUFlexapps -Name $Name
        
        if (-not $packages) {
            Write-Warning "No FlexApp packages found matching: $Name"
            return
        }
        
        if ($packages.Count -eq 1) {
            Write-Host "Only one package found matching: $Name" -ForegroundColor Yellow
            return $packages
        }
        
        Write-Host "FlexApp Version Comparison:" -ForegroundColor Cyan
        Write-Host "Found $($packages.Count) packages matching: $Name" -ForegroundColor Gray
        Write-Host ""
        
        # Group by base name (without version)
        $grouped = $packages | Group-Object { $_.Name -replace '\s*v?\d+(\.\d+)*\s*$', '' }
        
        foreach ($group in $grouped) {
            Write-Host "Package: $($group.Name)" -ForegroundColor Yellow
            
            $group.Group | Sort-Object Version -Descending | ForEach-Object {
                $status = if ($_.Enabled) { "Enabled" } else { "Disabled" }
                $sizeInfo = "$([math]::Round($_.SizeMB, 2)) MB"
                
                Write-Host ("  v{0,-10} {1,-10} {2,-12} Modified: {3}" -f 
                    $_.Version, 
                    $status, 
                    $sizeInfo,
                    $_.Modified) -ForegroundColor $(if ($_.Enabled) { "Green" } else { "Gray" })
            }
            Write-Host ""
        }
        
        return $packages | Sort-Object Name, Version
    }
    catch {
        Write-Error "Failed to compare FlexApp versions: $_"
        throw
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Import-ProUFlexapp',
    'Import-ProUFlexappsAll',
    'Export-ProUFlexapp',
    'Test-ProUFlexappImport',
    'Update-ProUFlexappMetadata',
    'Compare-ProUFlexappVersions'
)