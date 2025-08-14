# TemplateManagement.ps1 - ProfileUnity Template Management Functions

function Get-ProUTemplate {
    <#
    .SYNOPSIS
        Gets ProfileUnity configuration templates.
    
    .DESCRIPTION
        Retrieves available configuration templates.
    
    .PARAMETER Id
        Specific template ID to retrieve
    
    .EXAMPLE
        Get-ProUTemplate
        
    .EXAMPLE
        Get-ProUTemplate -Id "12345"
    #>
    [CmdletBinding()]
    param(
        [string]$Id
    )
    
    try {
        $endpoint = if ($Id) {
            "template/$Id"
        } else {
            "template"
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint $endpoint
        
        if ($response) {
            if ($Id) {
                return [PSCustomObject]@{
                    Id = $response.id
                    Name = $response.name
                    Description = $response.description
                    Category = $response.category
                    Version = $response.version
                    Author = $response.author
                    Created = $response.created
                    Modified = $response.modified
                    ConfigurationCount = if ($response.configurations) { $response.configurations.Count } else { 0 }
                    Configurations = $response.configurations
                }
            } else {
                return $response | ForEach-Object {
                    [PSCustomObject]@{
                        Id = $_.id
                        Name = $_.name
                        Description = $_.description
                        Category = $_.category
                        Version = $_.version
                        Author = $_.author
                        Created = $_.created
                        Modified = $_.modified
                        ConfigurationCount = if ($_.configurations) { $_.configurations.Count } else { 0 }
                    }
                }
            }
        }
    }
    catch {
        Write-Error "Failed to get templates: $_"
        throw
    }
}

function Export-ProUTemplate {
    <#
    .SYNOPSIS
        Downloads a ProfileUnity template.
    
    .DESCRIPTION
        Exports a template to a file for backup or sharing.
    
    .PARAMETER Id
        Template ID to download
    
    .PARAMETER SavePath
        Path where template file will be saved
    
    .EXAMPLE
        Export-ProUTemplate -Id "12345" -SavePath "C:\Templates\MyTemplate.json"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,
        
        [Parameter(Mandatory)]
        [string]$SavePath
    )
    
    try {
        # Get template info first
        $template = Get-ProUTemplate -Id $Id
        if (-not $template) {
            throw "Template with ID '$Id' not found"
        }
        
        Write-Verbose "Downloading template: $($template.Name)"
        
        # Ensure directory exists
        $directory = Split-Path $SavePath -Parent
        if (-not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        
        # Download the template
        $null = Invoke-ProfileUnityApi -Endpoint "template/$Id/download" -Method POST -OutFile $SavePath
        
        Write-Host "Template exported: $SavePath" -ForegroundColor Green
        Write-Host "  Name: $($template.Name)" -ForegroundColor Cyan
        Write-Host "  Configurations: $($template.ConfigurationCount)" -ForegroundColor Cyan
        
        return Get-Item $SavePath
    }
    catch {
        Write-Error "Failed to export template: $_"
        throw
    }
}

function Test-ProUTemplate {
    <#
    .SYNOPSIS
        Validates a ProfileUnity template file.
    
    .DESCRIPTION
        Tests a template file for validity and compatibility.
    
    .PARAMETER FilePath
        Path to template file to validate
    
    .EXAMPLE
        Test-ProUTemplate -FilePath "C:\Templates\MyTemplate.json"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    
    try {
        if (-not (Test-Path $FilePath)) {
            throw "Template file not found: $FilePath"
        }
        
        Write-Host "Validating template file: $FilePath" -ForegroundColor Yellow
        
        # Read file content
        $templateData = Get-Content $FilePath -Raw
        
        $body = @{
            templateData = $templateData
            fileName = Split-Path $FilePath -Leaf
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "template/validate" -Method POST -Body $body
        
        if ($response) {
            $issues = @()
            $warnings = @()
            
            # Parse validation results
            if ($response.isValid -eq $false) {
                if ($response.errors) {
                    $issues += $response.errors
                }
            }
            
            if ($response.warnings) {
                $warnings += $response.warnings
            }
            
            # Display results
            Write-Host "`nTemplate Validation Results:" -ForegroundColor Cyan
            
            if ($response.templateInfo) {
                Write-Host "Template Information:" -ForegroundColor Gray
                Write-Host "  Name: $($response.templateInfo.name)" -ForegroundColor Gray
                Write-Host "  Version: $($response.templateInfo.version)" -ForegroundColor Gray
                Write-Host "  Author: $($response.templateInfo.author)" -ForegroundColor Gray
                Write-Host "  Configurations: $($response.templateInfo.configurationCount)" -ForegroundColor Gray
            }
            
            if ($issues.Count -eq 0 -and $warnings.Count -eq 0) {
                Write-Host "  Validation: PASSED" -ForegroundColor Green
            } else {
                if ($issues.Count -gt 0) {
                    Write-Host "  Errors:" -ForegroundColor Red
                    $issues | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
                }
                
                if ($warnings.Count -gt 0) {
                    Write-Host "  Warnings:" -ForegroundColor Yellow
                    $warnings | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
                }
            }
            
            return [PSCustomObject]@{
                IsValid = $response.isValid
                TemplateInfo = $response.templateInfo
                Issues = $issues
                Warnings = $warnings
                CanDeploy = $response.isValid -and $issues.Count -eq 0
            }
        }
    }
    catch {
        Write-Error "Failed to validate template: $_"
        throw
    }
}

function Deploy-ProUTemplate {
    <#
    .SYNOPSIS
        Deploys a ProfileUnity template.
    
    .DESCRIPTION
        Imports and applies a template to create configurations.
    
    .PARAMETER FilePath
        Path to template file to deploy
    
    .PARAMETER TargetName
        Name for the deployed configuration(s)
    
    .PARAMETER Validate
        Validate template before deployment
    
    .EXAMPLE
        Deploy-ProUTemplate -FilePath "C:\Templates\Windows10.json" -TargetName "Win10-Prod"
        
    .EXAMPLE
        Deploy-ProUTemplate -FilePath "C:\Templates\Office365.json" -Validate
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [string]$TargetName,
        
        [switch]$Validate
    )
    
    try {
        if (-not (Test-Path $FilePath)) {
            throw "Template file not found: $FilePath"
        }
        
        # Validate first if requested
        if ($Validate) {
            $validationResult = Test-ProUTemplate -FilePath $FilePath
            if (-not $validationResult.CanDeploy) {
                throw "Template validation failed. Cannot deploy."
            }
            Write-Host "Template validation passed" -ForegroundColor Green
        }
        
        # Read template content
        $templateData = Get-Content $FilePath -Raw
        
        $templateFileName = Split-Path $FilePath -Leaf
        $deployName = if ($TargetName) { $TargetName } else { "Deployed from $templateFileName" }
        
        if ($PSCmdlet.ShouldProcess($deployName, "Deploy template")) {
            $body = @{
                templateData = $templateData
                fileName = $templateFileName
                targetName = $deployName
            }
            
            $response = Invoke-ProfileUnityApi -Endpoint "template/deploy" -Method POST -Body $body
            
            if ($response) {
                Write-Host "Template deployed successfully" -ForegroundColor Green
                Write-Host "  Template: $templateFileName" -ForegroundColor Cyan
                Write-Host "  Target: $deployName" -ForegroundColor Cyan
                
                if ($response.configurations) {
                    Write-Host "  Configurations created: $($response.configurations.Count)" -ForegroundColor Cyan
                    $response.configurations | ForEach-Object {
                        Write-Host "    - $($_.name)" -ForegroundColor Gray
                    }
                }
                
                return $response
            }
        }
    }
    catch {
        Write-Error "Failed to deploy template: $_"
        throw
    }
}

function New-ProUTemplateFromConfig {
    <#
    .SYNOPSIS
        Creates a template from existing configurations.
    
    .DESCRIPTION
        Extracts configurations into a reusable template.
    
    .PARAMETER ConfigurationNames
        Names of configurations to include in template
    
    .PARAMETER TemplateName
        Name for the new template
    
    .PARAMETER Description
        Template description
    
    .PARAMETER Author
        Template author name
    
    .PARAMETER Category
        Template category
    
    .PARAMETER SavePath
        Path to save the template file
    
    .EXAMPLE
        New-ProUTemplateFromConfig -ConfigurationNames @("Win10 Base", "Office 2019") -TemplateName "Standard Workstation" -SavePath "C:\Templates"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ConfigurationNames,
        
        [Parameter(Mandatory)]
        [string]$TemplateName,
        
        [string]$Description = "Created by PowerTools",
        
        [string]$Author = $env:USERNAME,
        
        [string]$Category = "Custom",
        
        [Parameter(Mandatory)]
        [string]$SavePath
    )
    
    try {
        Write-Host "Creating template from configurations..." -ForegroundColor Yellow
        
        # Get all configurations
        $allConfigs = Get-ProUConfig
        $selectedConfigs = @()
        
        foreach ($configName in $ConfigurationNames) {
            $config = $allConfigs | Where-Object { $_.Name -eq $configName }
            if (-not $config) {
                Write-Warning "Configuration '$configName' not found - skipping"
                continue
            }
            
            # Get detailed configuration
            $detailedConfig = Get-ProUConfig -Name $configName -Detailed
            if ($detailedConfig) {
                $selectedConfigs += $detailedConfig
                Write-Host "  Added: $configName" -ForegroundColor Green
            }
        }
        
        if ($selectedConfigs.Count -eq 0) {
            throw "No valid configurations found to include in template"
        }
        
        $body = @{
            templateName = $TemplateName
            description = $Description
            author = $Author
            category = $Category
            configurations = $selectedConfigs
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "template/extractconfiguration" -Method POST -Body $body
        
        if ($response) {
            # Build file path
            $safeFileName = ConvertTo-SafeFileName -FileName $TemplateName
            $filePath = Join-Path $SavePath "$safeFileName.json"
            
            # Ensure directory exists
            if (-not (Test-Path $SavePath)) {
                New-Item -ItemType Directory -Path $SavePath -Force | Out-Null
            }
            
            # Save template to file
            $response | ConvertTo-Json -Depth 20 | Set-Content -Path $filePath -Encoding UTF8
            
            Write-Host "Template created successfully" -ForegroundColor Green
            Write-Host "  Name: $TemplateName" -ForegroundColor Cyan
            Write-Host "  Configurations: $($selectedConfigs.Count)" -ForegroundColor Cyan
            Write-Host "  File: $filePath" -ForegroundColor Cyan
            
            return [PSCustomObject]@{
                TemplateName = $TemplateName
                ConfigurationCount = $selectedConfigs.Count
                FilePath = $filePath
                TemplateData = $response
            }
        }
    }
    catch {
        Write-Error "Failed to create template from configurations: $_"
        throw
    }
}

function Import-ProUTemplate {
    <#
    .SYNOPSIS
        Imports a ProfileUnity template file.
    
    .DESCRIPTION
        Imports a template file into the ProfileUnity server.
    
    .PARAMETER FilePath
        Path to template file to import
    
    .PARAMETER NewName
        Optional new name for the imported template
    
    .PARAMETER Validate
        Validate template before import
    
    .EXAMPLE
        Import-ProUTemplate -FilePath "C:\Templates\Standard.json"
        
    .EXAMPLE
        Import-ProUTemplate -FilePath "C:\Templates\Custom.json" -NewName "Custom Template v2" -Validate
    #>
    [CmdletBinding()]
    param(
        [string]$FilePath,
        
        [string]$NewName,
        
        [switch]$Validate
    )
    
    try {
        # Get file path if not provided
        if (-not $FilePath) {
            $FilePath = Get-FileName -Filter "Template files (*.json)|*.json|All files (*.*)|*.*" -Title "Select Template File"
            if (-not $FilePath) {
                Write-Host "No file selected" -ForegroundColor Yellow
                return
            }
        }
        
        if (-not (Test-Path $FilePath)) {
            throw "Template file not found: $FilePath"
        }
        
        # Validate if requested
        if ($Validate) {
            $validationResult = Test-ProUTemplate -FilePath $FilePath
            if (-not $validationResult.CanDeploy) {
                throw "Template validation failed. Cannot import."
            }
            Write-Host "Template validation passed" -ForegroundColor Green
        }
        
        # Read template content
        $templateData = Get-Content $FilePath -Raw
        
        $body = @{
            templateData = $templateData
            fileName = Split-Path $FilePath -Leaf
        }
        
        if ($NewName) {
            $body.templateName = $NewName
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "template/import" -Method POST -Body $body
        
        if ($response) {
            $templateName = if ($NewName) { $NewName } else { $response.name }
            
            Write-Host "Template imported successfully" -ForegroundColor Green
            Write-Host "  Name: $templateName" -ForegroundColor Cyan
            Write-Host "  ID: $($response.id)" -ForegroundColor Cyan
            
            if ($response.configurationCount) {
                Write-Host "  Configurations: $($response.configurationCount)" -ForegroundColor Cyan
            }
            
            return $response
        }
    }
    catch {
        Write-Error "Failed to import template: $_"
        throw
    }
}

function Compare-ProUTemplate {
    <#
    .SYNOPSIS
        Compares two ProfileUnity templates.
    
    .DESCRIPTION
        Compares template files or server templates to identify differences.
    
    .PARAMETER Template1
        First template (ID or file path)
    
    .PARAMETER Template2
        Second template (ID or file path)
    
    .EXAMPLE
        Compare-ProUTemplate -Template1 "12345" -Template2 "67890"
        
    .EXAMPLE
        Compare-ProUTemplate -Template1 "C:\Templates\Old.json" -Template2 "C:\Templates\New.json"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Template1,
        
        [Parameter(Mandatory)]
        [string]$Template2
    )
    
    try {
        Write-Host "Comparing templates..." -ForegroundColor Yellow
        
        # Load template data
        $templateData1 = if (Test-Path $Template1) {
            # File path
            Get-Content $Template1 -Raw | ConvertFrom-Json
        } else {
            # Template ID
            (Get-ProUTemplate -Id $Template1).Configurations
        }
        
        $templateData2 = if (Test-Path $Template2) {
            # File path
            Get-Content $Template2 -Raw | ConvertFrom-Json
        } else {
            # Template ID
            (Get-ProUTemplate -Id $Template2).Configurations
        }
        
        if (-not $templateData1 -or -not $templateData2) {
            throw "Could not load one or both templates for comparison"
        }
        
        $differences = @()
        
        # Compare basic properties
        $name1 = if ($templateData1.name) { $templateData1.name } else { Split-Path $Template1 -Leaf }
        $name2 = if ($templateData2.name) { $templateData2.name } else { Split-Path $Template2 -Leaf }
        
        Write-Host "`nTemplate Comparison:" -ForegroundColor Cyan
        Write-Host "  Template 1: $name1" -ForegroundColor Gray
        Write-Host "  Template 2: $name2" -ForegroundColor Gray
        
        # Compare configuration counts
        $config1Count = if ($templateData1.configurations) { $templateData1.configurations.Count } else { 0 }
        $config2Count = if ($templateData2.configurations) { $templateData2.configurations.Count } else { 0 }
        
        Write-Host "`nConfiguration Count:" -ForegroundColor Yellow
        Write-Host "  Template 1: $config1Count" -ForegroundColor Gray
        Write-Host "  Template 2: $config2Count" -ForegroundColor Gray
        
        if ($config1Count -ne $config2Count) {
            $differences += "Different number of configurations: $config1Count vs $config2Count"
        }
        
        # Compare version info if available
        if ($templateData1.version -and $templateData2.version) {
            Write-Host "`nVersions:" -ForegroundColor Yellow
            Write-Host "  Template 1: $($templateData1.version)" -ForegroundColor Gray
            Write-Host "  Template 2: $($templateData2.version)" -ForegroundColor Gray
            
            if ($templateData1.version -ne $templateData2.version) {
                $differences += "Different versions: $($templateData1.version) vs $($templateData2.version)"
            }
        }
        
        # Display differences summary
        if ($differences.Count -eq 0) {
            Write-Host "`nResult: Templates appear similar" -ForegroundColor Green
        } else {
            Write-Host "`nDifferences found:" -ForegroundColor Yellow
            $differences | ForEach-Object {
                Write-Host "  - $_" -ForegroundColor White
            }
        }
        
        return [PSCustomObject]@{
            Template1 = $name1
            Template2 = $name2
            Differences = $differences
            AreSimilar = $differences.Count -eq 0
        }
    }
    catch {
        Write-Error "Failed to compare templates: $_"
        throw
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-ProUTemplate',
    'Export-ProUTemplate',
    'Test-ProUTemplate',
    'Deploy-ProUTemplate',
    'New-ProUTemplateFromConfig',
    'Import-ProUTemplate',
    'Compare-ProUTemplate'
)