# Portability.ps1 - ProfileUnity Portability Rule Management Functions

function Get-ProUPortRule {
    <#
    .SYNOPSIS
        Gets ProfileUnity portability rules.
    
    .DESCRIPTION
        Retrieves all portability rules or filters by name.
    
    .PARAMETER Name
        Optional name filter (supports wildcards)
    
    .PARAMETER Type
        Filter by portability type
    
    .PARAMETER Enabled
        Filter by enabled/disabled status
    
    .EXAMPLE
        Get-ProUPortRule
        
    .EXAMPLE
        Get-ProUPortRule -Name "*Desktop*" -Enabled $true
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        
        [ValidateSet('File', 'Folder', 'Registry', 'Printer', 'NetworkDrive')]
        [string]$Type,
        
        [bool]$Enabled
    )
    
    try {
        Write-Verbose "Retrieving portability rules..."
        $response = Invoke-ProfileUnityApi -Endpoint "portability"
        
        if (-not $response -or -not $response.Tag) {
            Write-Warning "No portability rules found"
            return
        }
        
        $rules = $response.Tag.Rows
        
        # Apply filters
        if ($Name) {
            $rules = $rules | Where-Object { $_.name -like $Name }
        }
        
        if ($Type) {
            $rules = $rules | Where-Object { $_.portabilityType -eq $Type }
        }
        
        if ($PSBoundParameters.ContainsKey('Enabled')) {
            $rules = $rules | Where-Object { -not $_.disabled -eq $Enabled }
        }
        
        # Format output
        $rules | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.name
                ID = $_.id
                Type = $_.portabilityType
                Path = $_.path
                Enabled = -not $_.disabled
                Description = $_.description
                CreatedBy = $_.createdBy
                ModifiedBy = $_.modifiedBy
                LastModified = $_.lastModified
                RuleCount = $_.ruleCount
            }
        }
    }
    catch {
        Write-Error "Failed to retrieve portability rules: $_"
        throw
    }
}

function Edit-ProUPortRule {
    <#
    .SYNOPSIS
        Loads a ProfileUnity portability rule for editing.
    
    .DESCRIPTION
        Retrieves a portability rule and stores it in memory for editing.
    
    .PARAMETER Name
        The exact name of the portability rule to edit
    
    .PARAMETER Quiet
        Suppress confirmation messages
    
    .EXAMPLE
        Edit-ProUPortRule -Name "User Desktop Files"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [switch]$Quiet
    )
    
    try {
        # Get all portability rules
        $rules = Get-ProUPortRule
        $rule = $rules | Where-Object { $_.Name -eq $Name }
        
        if (-not $rule) {
            throw "Portability rule '$Name' not found"
        }
        
        Write-Verbose "Loading portability rule ID: $($rule.ID)"
        
        # Get full rule details
        $response = Invoke-ProfileUnityApi -Endpoint "portability/$($rule.ID)"
        
        if (-not $response -or -not $response.tag) {
            throw "Failed to load portability rule details"
        }
        
        $ruleData = $response.tag
        
        # Store in module config
        $script:ModuleConfig.CurrentItems.PortRule = $ruleData
        
        # Also set global variable for backward compatibility
        $global:CurrentPortRule = $ruleData
        
        if (-not $Quiet) {
            Write-Host "Portability rule '$Name' loaded for editing" -ForegroundColor Green
            Write-Host "Type: $($ruleData.portabilityType)" -ForegroundColor Cyan
            
            # Show rule summary
            if ($ruleData.PortabilityRules) {
                Write-Host "Rules: $($ruleData.PortabilityRules.Count)" -ForegroundColor Cyan
                
                # Show breakdown by action
                $actionGroups = $ruleData.PortabilityRules | Group-Object -Property action
                $actionGroups | ForEach-Object {
                    Write-Host "  $($_.Name): $($_.Count)" -ForegroundColor Gray
                }
            }
        }
        
        return $ruleData
    }
    catch {
        Write-Error "Failed to edit portability rule: $_"
        throw
    }
}

function Save-ProUPortRule {
    <#
    .SYNOPSIS
        Saves the currently edited ProfileUnity portability rule.
    
    .DESCRIPTION
        Saves changes made to the current portability rule back to the server.
    
    .PARAMETER Force
        Skip confirmation prompt
    
    .EXAMPLE
        Save-ProUPortRule
        
    .EXAMPLE
        Save-ProUPortRule -Force
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [switch]$Force
    )
    
    # Get current portability rule
    $currentRule = $script:ModuleConfig.CurrentItems.PortRule
    if (-not $currentRule -and $global:CurrentPortRule) {
        $currentRule = $global:CurrentPortRule
    }
    
    if (-not $currentRule) {
        throw "No portability rule loaded for editing. Use Edit-ProUPortRule first."
    }
    
    $ruleName = $currentRule.name
    
    if ($Force -or $PSCmdlet.ShouldProcess($ruleName, "Save portability rule")) {
        try {
            Write-Verbose "Saving portability rule: $ruleName"
            
            # Prepare the rule object
            $ruleToSave = @{
                portability = $currentRule
            }
            
            $response = Invoke-ProfileUnityApi -Endpoint "portability" -Method POST -Body $ruleToSave
            
            if ($response) {
                Write-Host "Portability rule '$ruleName' saved successfully" -ForegroundColor Green
                Write-LogMessage -Message "Portability rule '$ruleName' saved by $env:USERNAME" -Level Info
                
                # Clear current rule after successful save
                $script:ModuleConfig.CurrentItems.PortRule = $null
                $global:CurrentPortRule = $null
                
                return $response
            }
        }
        catch {
            Write-Error "Failed to save portability rule: $_"
            throw
        }
    }
    else {
        Write-Host "Save cancelled" -ForegroundColor Yellow
    }
}

function New-ProUPortRule {
    <#
    .SYNOPSIS
        Creates a new ProfileUnity portability rule.
    
    .DESCRIPTION
        Creates a new portability rule with specified settings.
    
    .PARAMETER Name
        Name for the new portability rule
    
    .PARAMETER Type
        Type of portability rule
    
    .PARAMETER Description
        Description of the rule
    
    .PARAMETER BasePath
        Base path for the rule
    
    .EXAMPLE
        New-ProUPortRule -Name "Custom Files" -Type File -BasePath "%USERPROFILE%\Documents"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [ValidateSet('File', 'Folder', 'Registry', 'Printer', 'NetworkDrive')]
        [string]$Type,
        
        [string]$Description = "Created by PowerTools",
        
        [string]$BasePath = ""
    )
    
    try {
        # Create new portability rule object
        $newRule = @{
            name = $Name
            description = $Description
            portabilityType = $Type
            disabled = $false
            PortabilityRules = @()
        }
        
        # Add default rule based on type
        switch ($Type) {
            'File' {
                if ($BasePath) {
                    $newRule.PortabilityRules += @{
                        path = $BasePath
                        action = "IncludeFile"
                        recursive = $false
                    }
                }
            }
            'Folder' {
                if ($BasePath) {
                    $newRule.PortabilityRules += @{
                        path = $BasePath
                        action = "IncludeFolder"
                        recursive = $true
                    }
                }
            }
            'Registry' {
                $newRule.PortabilityRules += @{
                    path = "HKCU\Software"
                    action = "IncludeRegistry"
                    recursive = $false
                }
            }
            'Printer' {
                $newRule.PortabilityRules += @{
                    action = "IncludePrinter"
                    printerName = ""
                }
            }
            'NetworkDrive' {
                $newRule.PortabilityRules += @{
                    action = "MapNetworkDrive"
                    driveLetter = ""
                    uncPath = ""
                }
            }
        }
        
        $response = Invoke-ProfileUnityApi -Endpoint "portability" -Method POST -Body @{
            portability = $newRule
        }
        
        Write-Host "Portability rule '$Name' created successfully" -ForegroundColor Green
        Write-Host "Edit the rule to add specific paths and settings" -ForegroundColor Yellow
        
        return $response
    }
    catch {
        Write-Error "Failed to create portability rule: $_"
        throw
    }
}

function Remove-ProUPortRule {
    <#
    .SYNOPSIS
        Removes a ProfileUnity portability rule.
    
    .DESCRIPTION
        Deletes a portability rule from the ProfileUnity server.
    
    .PARAMETER Name
        Name of the portability rule to remove
    
    .PARAMETER Force
        Skip confirmation prompt
    
    .EXAMPLE
        Remove-ProUPortRule -Name "Old Rule"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [switch]$Force
    )
    
    try {
        # Find portability rule
        $rules = Get-ProUPortRule
        $rule = $rules | Where-Object { $_.Name -eq $Name }
        
        if (-not $rule) {
            throw "Portability rule '$Name' not found"
        }
        
        if ($Force -or $PSCmdlet.ShouldProcess($Name, "Remove portability rule")) {
            Write-Verbose "Deleting portability rule ID: $($rule.ID)"
            
            $response = Invoke-ProfileUnityApi -Endpoint "portability/remove" -Method DELETE -Body @{
                ids = @($rule.ID)
            }
            
            Write-Host "Portability rule '$Name' deleted successfully" -ForegroundColor Green
            Write-LogMessage -Message "Portability rule '$Name' deleted by $env:USERNAME" -Level Info
            
            return $response
        }
        else {
            Write-Host "Delete cancelled" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "Failed to delete portability rule: $_"
        throw
    }
}

function Copy-ProUPortRule {
    <#
    .SYNOPSIS
        Creates a copy of a ProfileUnity portability rule.
    
    .DESCRIPTION
        Copies an existing portability rule with a new name.
    
    .PARAMETER SourceName
        Name of the portability rule to copy
    
    .PARAMETER NewName
        Name for the new rule
    
    .EXAMPLE
        Copy-ProUPortRule -SourceName "Desktop Files" -NewName "Desktop Files - Copy"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceName,
        
        [Parameter(Mandatory)]
        [string]$NewName
    )
    
    try {
        # Find source rule
        $rules = Get-ProUPortRule
        $sourceRule = $rules | Where-Object { $_.Name -eq $SourceName }
        
        if (-not $sourceRule) {
            throw "Source portability rule '$SourceName' not found"
        }
        
        Write-Verbose "Copying portability rule ID: $($sourceRule.ID)"
        
        # Copy the rule
        $response = Invoke-ProfileUnityApi -Endpoint "portability/$($sourceRule.ID)/copy" -Method POST
        
        if ($response -and $response.tag) {
            # Update the copy with new name
            $copiedRule = $response.tag
            $copiedRule.name = $NewName
            $copiedRule.description = "Copy of $SourceName - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            
            # Save the updated rule
            $saveResponse = Invoke-ProfileUnityApi -Endpoint "portability" -Method POST -Body @{
                portability = $copiedRule
            }
            
            Write-Host "Portability rule copied successfully" -ForegroundColor Green
            Write-Host "  Source: $SourceName" -ForegroundColor Cyan
            Write-Host "  New: $NewName" -ForegroundColor Cyan
            
            return $saveResponse
        }
    }
    catch {
        Write-Error "Failed to copy portability rule: $_"
        throw
    }
}

function Export-ProUPortRule {
    <#
    .SYNOPSIS
        Exports a ProfileUnity portability rule to JSON.
    
    .DESCRIPTION
        Exports portability rule settings to a JSON file.
    
    .PARAMETER Name
        Name of the portability rule to export
    
    .PARAMETER SavePath
        Directory to save the export
    
    .EXAMPLE
        Export-ProUPortRule -Name "User Files" -SavePath "C:\Backups"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [string]$SavePath
    )
    
    try {
        if (-not (Test-Path $SavePath)) {
            throw "Save path does not exist: $SavePath"
        }
        
        # Find rule
        $rules = Get-ProUPortRule
        $rule = $rules | Where-Object { $_.Name -eq $Name }
        
        if (-not $rule) {
            throw "Portability rule '$Name' not found"
        }
        
        Write-Verbose "Exporting portability rule ID: $($rule.ID)"
        
        # Build output filename
        $safeFileName = ConvertTo-SafeFileName -FileName $Name
        $outputFile = Join-Path $SavePath "$safeFileName.json"
        
        # Download the rule
        $endpoint = "portability/download?ids=$($rule.ID)"
        Invoke-ProfileUnityApi -Endpoint $endpoint -Method POST -OutFile $outputFile
        
        Write-Host "Portability rule exported: $outputFile" -ForegroundColor Green
        return Get-Item $outputFile
    }
    catch {
        Write-Error "Failed to export portability rule: $_"
        throw
    }
}

function Export-ProUPortRuleAll {
    <#
    .SYNOPSIS
        Exports all ProfileUnity portability rules.
    
    .DESCRIPTION
        Exports all portability rules to JSON files in the specified directory.
    
    .PARAMETER SavePath
        Directory to save the exports
    
    .PARAMETER IncludeDisabled
        Include disabled rules
    
    .EXAMPLE
        Export-ProUPortRuleAll -SavePath "C:\Backups\PortabilityRules"
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
        
        $rules = Get-ProUPortRule
        
        if (-not $IncludeDisabled) {
            $rules = $rules | Where-Object { $_.Enabled }
        }
        
        if (-not $rules) {
            Write-Warning "No portability rules found to export"
            return
        }
        
        Write-Host "Exporting $($rules.Count) portability rules..." -ForegroundColor Cyan
        
        $exported = 0
        $failed = 0
        
        foreach ($rule in $rules) {
            try {
                Export-ProUPortRule -Name $rule.Name -SavePath $SavePath
                $exported++
            }
            catch {
                Write-Warning "Failed to export '$($rule.Name)': $_"
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
            TotalRules = $rules.Count
            Exported = $exported
            Failed = $failed
        }
    }
    catch {
        Write-Error "Failed to export portability rules: $_"
        throw
    }
}

function Import-ProUPortRule {
    <#
    .SYNOPSIS
        Imports a ProfileUnity portability rule from JSON.
    
    .DESCRIPTION
        Imports a portability rule from a JSON file.
    
    .PARAMETER JsonFile
        Path to the JSON file to import
    
    .PARAMETER NewName
        Optional new name for the imported rule
    
    .EXAMPLE
        Import-ProUPortRule -JsonFile "C:\Backups\rule.json"
    #>
    [CmdletBinding()]
    param(
        [string]$JsonFile,
        
        [string]$NewName
    )
    
    try {
        # Get file path if not provided
        if (-not $JsonFile) {
            $JsonFile = Get-FileName -Filter $script:FileFilters.Json -Title "Select Portability Rule JSON"
            if (-not $JsonFile) {
                Write-Host "No file selected" -ForegroundColor Yellow
                return
            }
        }
        
        if (-not (Test-Path $JsonFile)) {
            throw "File not found: $JsonFile"
        }
        
        Write-Verbose "Importing portability rule from: $JsonFile"
        
        # Read and parse JSON
        $jsonContent = Get-Content $JsonFile -Raw | ConvertFrom-Json
        
        # Extract rule object
        $ruleObject = if ($jsonContent.portability) { 
            $jsonContent.portability 
        } else { 
            $jsonContent 
        }
        
        # Update name if specified
        if ($NewName) {
            $ruleObject.name = $NewName
        }
        else {
            # Add import suffix to avoid conflicts
            $ruleObject.name = "$($ruleObject.name) - Imported $(Get-Date -Format 'yyyyMMdd-HHmm')"
        }
        
        # Clear ID to create new
        $ruleObject.ID = $null
        
        # Import the rule
        $response = Invoke-ProfileUnityApi -Endpoint "portability/import" -Method POST -Body @($ruleObject)
        
        if ($response) {
            Write-Host "Portability rule imported successfully: $($ruleObject.name)" -ForegroundColor Green
            return $response
        }
    }
    catch {
        Write-Error "Failed to import portability rule: $_"
        throw
    }
}

function Import-ProUPortRuleAll {
    <#
    .SYNOPSIS
        Imports multiple ProfileUnity portability rules from a directory.
    
    .DESCRIPTION
        Imports all JSON portability rule files from a directory.
    
    .PARAMETER SourceDir
        Directory containing JSON files to import
    
    .EXAMPLE
        Import-ProUPortRuleAll -SourceDir "C:\Backups\PortabilityRules"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceDir
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
        
        Write-Host "Importing $($jsonFiles.Count) portability rule files..." -ForegroundColor Cyan
        
        $imported = 0
        $failed = 0
        
        foreach ($file in $jsonFiles) {
            try {
                Write-Host "  Processing: $($file.Name)" -NoNewline
                Import-ProUPortRule -JsonFile $file.FullName
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
        Write-Error "Failed to import portability rules: $_"
        throw
    }
}

function Add-ProUPortRulePath {
    <#
    .SYNOPSIS
        Adds a path to the currently edited portability rule.
    
    .DESCRIPTION
        Adds a new path rule to the portability rule being edited.
    
    .PARAMETER Path
        Path to add
    
    .PARAMETER Action
        Action for the path
    
    .PARAMETER Recursive
        Apply recursively to subfolders
    
    .PARAMETER Exclude
        Exclusion pattern
    
    .EXAMPLE
        Add-ProUPortRulePath -Path "%APPDATA%\MyApp" -Action IncludeFolder -Recursive
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [Parameter(Mandatory)]
        [ValidateSet('IncludeFile', 'IncludeFolder', 'ExcludeFile', 'ExcludeFolder', 
                     'IncludeRegistry', 'ExcludeRegistry')]
        [string]$Action,
        
        [switch]$Recursive,
        
        [string]$Exclude = ""
    )
    
    # Get current rule
    $currentRule = $script:ModuleConfig.CurrentItems.PortRule
    if (-not $currentRule -and $global:CurrentPortRule) {
        $currentRule = $global:CurrentPortRule
    }
    
    if (-not $currentRule) {
        throw "No portability rule loaded for editing. Use Edit-ProUPortRule first."
    }
    
    try {
        # Initialize rules array if needed
        if (-not $currentRule.PortabilityRules) {
            $currentRule | Add-Member -NotePropertyName PortabilityRules -NotePropertyValue @() -Force
        }
        
        # Create new rule
        $newPathRule = @{
            path = $Path
            action = $Action
            recursive = $Recursive.IsPresent
        }
        
        if ($Exclude) {
            $newPathRule.exclude = $Exclude
        }
        
        # Add to rule
        $currentRule.PortabilityRules += $newPathRule
        
        # Update both storage locations
        $script:ModuleConfig.CurrentItems.PortRule = $currentRule
        $global:CurrentPortRule = $currentRule
        
        Write-Host "Path rule added" -ForegroundColor Green
        Write-Host "  Path: $Path" -ForegroundColor Cyan
        Write-Host "  Action: $Action" -ForegroundColor Cyan
        if ($Recursive) {
            Write-Host "  Recursive: Yes" -ForegroundColor Cyan
        }
        if ($Exclude) {
            Write-Host "  Exclude: $Exclude" -ForegroundColor Cyan
        }
        Write-Host "Use Save-ProUPortRule to save changes" -ForegroundColor Yellow
    }
    catch {
        Write-Error "Failed to add path rule: $_"
        throw
    }
}

function Test-ProUPortRule {
    <#
    .SYNOPSIS
        Tests a ProfileUnity portability rule.
    
    .DESCRIPTION
        Validates portability rule settings and paths.
    
    .PARAMETER Name
        Name of the portability rule to test
    
    .EXAMPLE
        Test-ProUPortRule -Name "User Documents"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    try {
        Write-Host "Testing portability rule: $Name" -ForegroundColor Yellow
        
        # Load the rule
        Edit-ProUPortRule -Name $Name -Quiet
        
        $rule = $script:ModuleConfig.CurrentItems.PortRule
        if (-not $rule) {
            throw "Failed to load portability rule"
        }
        
        $issues = @()
        $warnings = @()
        
        # Check if rule is disabled
        if ($rule.disabled) {
            $warnings += "Portability rule is disabled"
        }
        
        # Check for rules
        if (-not $rule.PortabilityRules -or $rule.PortabilityRules.Count -eq 0) {
            $issues += "Portability rule has no paths defined"
        }
        else {
            # Validate each rule
            foreach ($pathRule in $rule.PortabilityRules) {
                # Check for empty paths
                if ([string]::IsNullOrWhiteSpace($pathRule.path) -and 
                    $pathRule.action -ne 'IncludePrinter' -and 
                    $pathRule.action -ne 'MapNetworkDrive') {
                    $issues += "Rule has empty path for action: $($pathRule.action)"
                }
                
                # Check for invalid environment variables
                if ($pathRule.path -match '%([^%]+)%') {
                    $envVar = $matches[1]
                    $commonVars = @('USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'PROGRAMDATA', 
                                   'SYSTEMDRIVE', 'TEMP', 'USERNAME', 'USERDOMAIN')
                    
                    if ($envVar -notin $commonVars) {
                        $warnings += "Uncommon environment variable used: %$envVar%"
                    }
                }
                
                # Check for absolute paths
                if ($pathRule.path -match '^[A-Z]:\\') {
                    $warnings += "Absolute path used: $($pathRule.path) - Consider using environment variables"
                }
            }
        }
        
        # Display results
        Write-Host "`nTest Results:" -ForegroundColor Cyan
        Write-Host "  Rule Type: $($rule.portabilityType)" -ForegroundColor Gray
        Write-Host "  Path Rules: $(if ($rule.PortabilityRules) { $rule.PortabilityRules.Count } else { 0 })" -ForegroundColor Gray
        
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
        
        # Clear the loaded rule
        $script:ModuleConfig.CurrentItems.PortRule = $null
        $global:CurrentPortRule = $null
        
        return [PSCustomObject]@{
            RuleName = $Name
            RuleType = $rule.portabilityType
            PathCount = if ($rule.PortabilityRules) { $rule.PortabilityRules.Count } else { 0 }
            Issues = $issues
            Warnings = $warnings
            IsValid = $issues.Count -eq 0
        }
    }
    catch {
        Write-Error "Failed to test portability rule: $_"
        throw
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-ProUPortRule',
    'Edit-ProUPortRule',
    'Save-ProUPortRule',
    'New-ProUPortRule',
    'Remove-ProUPortRule',
    'Copy-ProUPortRule',
    'Export-ProUPortRule',
    'Export-ProUPortRuleAll',
    'Import-ProUPortRule',
    'Import-ProUPortRuleAll',
    'Add-ProUPortRulePath',
    'Test-ProUPortRule'
)