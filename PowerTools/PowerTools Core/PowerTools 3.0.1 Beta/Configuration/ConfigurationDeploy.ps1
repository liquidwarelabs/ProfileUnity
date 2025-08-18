# ConfigurationDeploy.ps1 - Configuration Deployment and Management Functions

function Update-ProUConfig {
    <#
    .SYNOPSIS
        Deploys a ProfileUnity configuration.
    
    .DESCRIPTION
        Deploys a configuration to generate and push the configuration script.
    
    .PARAMETER Name
        Name of the configuration to deploy
    
    .PARAMETER Force
        Skip confirmation prompt
    
    .PARAMETER Encoding
        Script encoding (default: ascii)
    
    .EXAMPLE
        Update-ProUConfig -Name "Production Config"
        
    .EXAMPLE
        Update-ProUConfig -Name "Test Config" -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [switch]$Force,
        
        [ValidateSet('ascii', 'unicode', 'utf8')]
        [string]$Encoding = 'ascii'
    )
    
    try {
        # Find configuration
        $configs = Get-ProUConfig
        $config = $configs | Where-Object { $_.Name -eq $Name }
        
        if (-not $config) {
            throw "Configuration '$Name' not found"
        }
        
        if ($config.Enabled -eq $false) {
            Write-Warning "Configuration '$Name' is disabled. Deploy anyway?"
            if (-not $Force -and -not (Confirm-Action -Title "Deploy Disabled Configuration" -Message "Configuration is disabled. Continue with deployment?")) {
                Write-Host "Deploy cancelled" -ForegroundColor Yellow
                return
            }
        }
        
        if ($Force -or $PSCmdlet.ShouldProcess($Name, "Deploy configuration")) {
            Write-Host "Deploying configuration: $Name" -ForegroundColor Yellow
            Write-Verbose "Configuration ID: $($config.ID)"
            
            # Call the deployment endpoint
            $endpoint = "configuration/$($config.ID)/script?encoding=$Encoding&deploy=true"
            $response = Invoke-ProfileUnityApi -Endpoint $endpoint -Method POST
            
            if ($response) {
                Write-Host "Configuration '$Name' deployed successfully" -ForegroundColor Green
                Write-LogMessage -Message "Configuration '$Name' deployed by $env:USERNAME" -Level Info
                
                # Return deployment info
                return [PSCustomObject]@{
                    ConfigurationName = $Name
                    ConfigurationID = $config.ID
                    DeploymentTime = Get-Date
                    Status = "Success"
                }
            }
        }
        else {
            Write-Host "Deploy cancelled" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "Failed to deploy configuration: $_"
        Write-LogMessage -Message "Failed to deploy configuration '$Name': $_" -Level Error
        throw
    }
}

function Get-ProUConfigScript {
    <#
    .SYNOPSIS
        Gets the deployment script for a configuration.
    
    .DESCRIPTION
        Retrieves the generated script without deploying it.
    
    .PARAMETER Name
        Name of the configuration
    
    .PARAMETER Encoding
        Script encoding (default: ascii)
    
    .PARAMETER OutFile
        Path to save the script
    
    .EXAMPLE
        Get-ProUConfigScript -Name "Test Config"
        
    .EXAMPLE
        Get-ProUConfigScript -Name "Test Config" -OutFile "C:\Scripts\config.cmd"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [ValidateSet('ascii', 'unicode', 'utf8')]
        [string]$Encoding = 'ascii',
        
        [string]$OutFile
    )
    
    try {
        # Find configuration
        $configs = Get-ProUConfig
        $config = $configs | Where-Object { $_.Name -eq $Name }
        
        if (-not $config) {
            throw "Configuration '$Name' not found"
        }
        
        Write-Verbose "Getting script for configuration ID: $($config.ID)"
        
        # Get the script without deploying
        $endpoint = "configuration/$($config.ID)/script?encoding=$Encoding&deploy=false"
        
        if ($OutFile) {
            # Download directly to file
            $null = Invoke-ProfileUnityApi -Endpoint $endpoint -Method POST -OutFile $OutFile
            Write-Host "Configuration script saved to: $OutFile" -ForegroundColor Green
            
            return Get-Item $OutFile
        }
        else {
            # Return script content
            $response = Invoke-ProfileUnityApi -Endpoint $endpoint -Method POST
            return $response
        }
    }
    catch {
        Write-Error "Failed to get configuration script: $_"
        throw
    }
}

function Export-ProUConfig {
    <#
    .SYNOPSIS
        Exports a ProfileUnity configuration to JSON.
    
    .DESCRIPTION
        Exports configuration settings to a JSON file.
    
    .PARAMETER Name
        Name of the configuration to export
    
    .PARAMETER SavePath
        Directory to save the export
    
    .PARAMETER IncludeMetadata
        Include additional metadata in export
    
    .EXAMPLE
        Export-ProUConfig -Name "Production" -SavePath "C:\Backups"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [string]$SavePath,
        
        [switch]$IncludeMetadata
    )
    
    try {
        if (-not (Test-Path $SavePath)) {
            throw "Save path does not exist: $SavePath"
        }
        
        # Find configuration
        $configs = Get-ProUConfig
        $config = $configs | Where-Object { $_.Name -eq $Name }
        
        if (-not $config) {
            throw "Configuration '$Name' not found"
        }
        
        Write-Verbose "Exporting configuration ID: $($config.ID)"
        
        # Build output filename
        $safeFileName = ConvertTo-SafeFileName -FileName $Name
        $outputFile = Join-Path $SavePath "$safeFileName.json"
        
        # Download the configuration
        $endpoint = "configuration/$($config.ID)/download?encoding=default"
        Invoke-ProfileUnityApi -Endpoint $endpoint -OutFile $outputFile
        
        # Add metadata if requested
        if ($IncludeMetadata) {
            $content = Get-Content $outputFile -Raw | ConvertFrom-Json
            
            # Add export metadata
            $content | Add-Member -NotePropertyName "_exportMetadata" -NotePropertyValue @{
                ExportDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                ExportedBy = $env:USERNAME
                ExportedFrom = $script:ModuleConfig.ServerName
                OriginalId = $config.ID
                Version = $script:ModuleConfig.ModuleVersion
            }
            
            $content | ConvertTo-Json -Depth 20 | Set-Content $outputFile
        }
        
        Write-Host "Configuration exported: $outputFile" -ForegroundColor Green
        return Get-Item $outputFile
    }
    catch {
        Write-Error "Failed to export configuration: $_"
        throw
    }
}

function Export-ProUConfigAll {
    <#
    .SYNOPSIS
        Exports all ProfileUnity configurations.
    
    .DESCRIPTION
        Exports all configurations to JSON files in the specified directory.
    
    .PARAMETER SavePath
        Directory to save the exports
    
    .PARAMETER IncludeDisabled
        Include disabled configurations
    
    .EXAMPLE
        Export-ProUConfigAll -SavePath "C:\Backups\Configurations"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SavePath,
        
        [switch]$IncludeDisabled
    )
    
    try {
        if (-not (Test-Path $SavePath)) {
            New-Item -ItemType Directory -Path $SavePath -Force | Out-Null
        }
        
        $configs = Get-ProUConfig
        
        if (-not $IncludeDisabled) {
            $configs = $configs | Where-Object { $_.Enabled }
        }
        
        if (-not $configs) {
            Write-Warning "No configurations found to export"
            return
        }
        
        Write-Host "Exporting $($configs.Count) configurations..." -ForegroundColor Cyan
        
        $exported = 0
        $failed = 0
        
        foreach ($config in $configs) {
            try {
                Export-ProUConfig -Name $config.Name -SavePath $SavePath
                $exported++
            }
            catch {
                Write-Warning "Failed to export '$($config.Name)': $_"
                $failed++
            }
        }
        
        Write-Host "`nExport Summary:" -ForegroundColor Cyan
        Write-Host "  Exported: $exported" -ForegroundColor Green
        if ($failed -gt 0) {
            Write-Host "  Failed: $failed" -ForegroundColor Red
        }
        
        return [PSCustomObject]@{
            ExportPath = $SavePath
            TotalConfigurations = $configs.Count
            Exported = $exported
            Failed = $failed
        }
    }
    catch {
        Write-Error "Failed to export configurations: $_"
        throw
    }
}

function Import-ProUConfig {
    <#
    .SYNOPSIS
        Imports a ProfileUnity configuration from JSON.
    
    .DESCRIPTION
        Imports a configuration from a JSON file.
    
    .PARAMETER JsonFile
        Path to the JSON file to import
    
    .PARAMETER NewName
        Optional new name for the imported configuration
    
    .EXAMPLE
        Import-ProUConfig -JsonFile "C:\Backups\config.json"
        
    .EXAMPLE
        Import-ProUConfig -JsonFile "C:\Backups\config.json" -NewName "Imported Config"
    #>
    [CmdletBinding()]
    param(
        [string]$JsonFile,
        
        [string]$NewName
    )
    
    try {
        # Get file path if not provided
        if (-not $JsonFile) {
            $JsonFile = Get-FileName -Filter $script:FileFilters.Json -Title "Select Configuration JSON"
            if (-not $JsonFile) {
                Write-Host "No file selected" -ForegroundColor Yellow
                return
            }
        }
        
        if (-not (Test-Path $JsonFile)) {
            throw "File not found: $JsonFile"
        }
        
        Write-Verbose "Importing configuration from: $JsonFile"
        
        # Read and parse JSON
        $jsonContent = Get-Content $JsonFile -Raw | ConvertFrom-Json
        
        # Extract configuration object
        $configObject = if ($jsonContent.configurations) { 
            $jsonContent.configurations 
        } else { 
            $jsonContent 
        }
        
        # Update name if specified
        if ($NewName) {
            $configObject.name = $NewName
        }
        else {
            # Add import suffix to avoid conflicts
            $configObject.name = "$($configObject.name) - Imported $(Get-Date -Format 'yyyyMMdd-HHmm')"
        }
        
        # Clear ID to create new
        $configObject.ID = $null
        
        # Remove export metadata if present
        if ($configObject._exportMetadata) {
            $configObject.PSObject.Properties.Remove('_exportMetadata')
        }
        
        # Import the configuration
        $response = Invoke-ProfileUnityApi -Endpoint "configuration/import" -Method POST -Body @($configObject)
        
        if ($response) {
            Write-Host "Configuration imported successfully: $($configObject.name)" -ForegroundColor Green
            return $response
        }
    }
    catch {
        Write-Error "Failed to import configuration: $_"
        throw
    }
}

function Import-ProUConfigAll {
    <#
    .SYNOPSIS
        Imports multiple ProfileUnity configurations from a directory.
    
    .DESCRIPTION
        Imports all JSON configuration files from a directory.
    
    .PARAMETER SourceDir
        Directory containing JSON files to import
    
    .PARAMETER AddPrefix
        Prefix to add to imported configuration names
    
    .EXAMPLE
        Import-ProUConfigAll -SourceDir "C:\Backups\Configurations"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceDir,
        
        [string]$AddPrefix = ""
    )
    
    try {
        if (-not (Test-Path $SourceDir)) {
            throw "Source directory not found: $SourceDir"
        }
        
        $jsonFiles = Get-ChildItem -Path $SourceDir -Filter "*.json"
        
        if (-not $jsonFiles) {
            Write-Warning "No JSON files found in: $SourceDir"
            return
        }
        
        Write-Host "Importing $($jsonFiles.Count) configuration files..." -ForegroundColor Cyan
        
        $imported = 0
        $failed = 0
        
        foreach ($file in $jsonFiles) {
            try {
                Write-Host "  Processing: $($file.Name)" -NoNewline
                
                # Determine new name
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
                $newName = if ($AddPrefix) { "$AddPrefix$baseName" } else { $null }
                
                Import-ProUConfig -JsonFile $file.FullName -NewName $newName
                
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
        if ($failed -gt 0) {
            Write-Host "  Failed: $failed" -ForegroundColor Red
        }
        
        return [PSCustomObject]@{
            SourceDirectory = $SourceDir
            TotalFiles = $jsonFiles.Count
            Imported = $imported
            Failed = $failed
        }
    }
    catch {
        Write-Error "Failed to import configurations: $_"
        throw
    }
}

function Compare-ProUConfig {
    <#
    .SYNOPSIS
        Compares two ProfileUnity configurations.
    
    .DESCRIPTION
        Shows differences between two configurations.
    
    .PARAMETER Config1
        Name of the first configuration
    
    .PARAMETER Config2
        Name of the second configuration
    
    .EXAMPLE
        Compare-ProUConfig -Config1 "Production" -Config2 "Test"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Config1,
        
        [Parameter(Mandatory)]
        [string]$Config2
    )
    
    try {
        Write-Host "Loading configurations for comparison..." -ForegroundColor Yellow
        
        # Load both configurations
        Edit-ProUConfig -Name $Config1 -Quiet
        $configData1 = $script:ModuleConfig.CurrentItems.Config
        
        Edit-ProUConfig -Name $Config2 -Quiet
        $configData2 = $script:ModuleConfig.CurrentItems.Config
        
        if (-not $configData1 -or -not $configData2) {
            throw "Failed to load configurations for comparison"
        }
        
        Write-Host "`nConfiguration Comparison:" -ForegroundColor Cyan
        Write-Host "  Config 1: $Config1" -ForegroundColor Gray
        Write-Host "  Config 2: $Config2" -ForegroundColor Gray
        Write-Host ""
        
        # Compare basic properties
        Write-Host "Basic Properties:" -ForegroundColor Yellow
        if ($configData1.disabled -ne $configData2.disabled) {
            Write-Host "  Enabled: $(-not $configData1.disabled) vs $(-not $configData2.disabled)" -ForegroundColor White
        }
        
        # Compare module counts
        $modules1 = if ($configData1.modules) { $configData1.modules.Count } else { 0 }
        $modules2 = if ($configData2.modules) { $configData2.modules.Count } else { 0 }
        
        if ($modules1 -ne $modules2) {
            Write-Host "  Module Count: $modules1 vs $modules2" -ForegroundColor White
        }
        
        # Compare module types
        if ($configData1.modules -and $configData2.modules) {
            $types1 = $configData1.modules | Group-Object moduleType | Sort-Object Name
            $types2 = $configData2.modules | Group-Object moduleType | Sort-Object Name
            
            Write-Host "`nModule Types:" -ForegroundColor Yellow
            
            $allTypes = ($types1.Name + $types2.Name) | Select-Object -Unique | Sort-Object
            
            foreach ($type in $allTypes) {
                $count1 = ($types1 | Where-Object { $_.Name -eq $type }).Count
                $count2 = ($types2 | Where-Object { $_.Name -eq $type }).Count
                
                if ($count1 -ne $count2) {
                    Write-Host "  $type : $count1 vs $count2" -ForegroundColor White
                }
            }
        }
        
        # Clear loaded configs
        $script:ModuleConfig.CurrentItems.Config = $null
        $global:CurrentConfig = $null
        
        return [PSCustomObject]@{
            Configuration1 = $Config1
            Configuration2 = $Config2
            ModuleCount1 = $modules1
            ModuleCount2 = $modules2
            Differences = "See console output for details"
        }
    }
    catch {
        Write-Error "Failed to compare configurations: $_"
        throw
    }
}

# Export functions
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
Export-ModuleMember -Function @(
    'Export-ProUConfig',
    'Export-ProUConfigAll',
    'Import-ProUConfig',
    'Import-ProUConfigAll',
    'Compare-ProUConfig'
)
#>



