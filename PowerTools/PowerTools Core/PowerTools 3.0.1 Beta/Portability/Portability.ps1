# Portability.ps1 - ProfileUnity Portability Rule Management Functions
# Location: \Portability\Portability.ps1
# Compatible with: ProfileUnity PowerTools v3.0 / PowerShell 5.1+

function Get-ProUPortRule {
    <#
    .SYNOPSIS
        Gets ProfileUnity portability rules.
    
    .DESCRIPTION
        Retrieves all portability rules or rules by name.
    
    .PARAMETER Name
        Optional name filter (supports wildcards)
    
    .EXAMPLE
        Get-ProUPortRule
        
    .EXAMPLE
        Get-ProUPortRule -Name "*User*"
    #>
    [CmdletBinding()]
    param(
        [string]$Name
    )
    
    try {
        Write-Verbose "Retrieving portability rules..."
        $response = Invoke-ProfileUnityApi -Endpoint "portability"
        
        # Handle different response formats consistently
        $rules = if ($response.Tag.Rows) { 
            $response.Tag.Rows 
        } elseif ($response.tag) { 
            $response.tag 
        } elseif ($response) { 
            $response 
        } else { 
            @() 
        }
        
        if (-not $rules) {
            Write-Warning "No portability rules found"
            return
        }
        
        # Filter by name if specified
        if ($Name) {
            $rules = $rules | Where-Object { $_.name -like $Name }
        }
        
        return $rules | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.name
                ID = $_.id
                Type = $_.portabilityType
                Description = $_.description
                Enabled = -not $_.disabled
                Path = $_.path
                LastModified = $_.lastModified
                ModifiedBy = $_.modifiedBy
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
        Edit-ProUPortRule -Name "User Profile Rule"
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
        
        # Store in module config with null checking
        if (-not $script:ModuleConfig) {
            $script:ModuleConfig = @{ CurrentItems = @{} }
        }
        if (-not $script:ModuleConfig.CurrentItems) {
            $script:ModuleConfig.CurrentItems = @{}
        }
        $script:ModuleConfig.CurrentItems.PortRule = $ruleData
        
        # Also set global variable for backward compatibility
        $global:CurrentPortRule = $ruleData
        
        if (-not $Quiet) {
            Write-Host "Portability rule '$Name' loaded for editing" -ForegroundColor Green
            Write-Host "Type: $($ruleData.portabilityType)" -ForegroundColor Cyan
            Write-Host "Path: $($ruleData.path)" -ForegroundColor Cyan
            
            # Show rule criteria summary if available
            if ($ruleData.criteria) {
                Write-Host "Criteria: $($ruleData.criteria.Count) rules" -ForegroundColor Gray
            }
        }
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
    param([switch]$Force) 
    
    if ($Force -or $PSCmdlet.ShouldProcess("portability rule on ProfileUnity server", "Save")) {
        Save-ProfileUnityItem -ItemType 'portability' -Force:$Force -Confirm:$false
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
        Creates a new portability rule with basic settings.
    
    .PARAMETER Name
        Name of the new portability rule
    
    .PARAMETER Type
        Portability rule type (User, Computer, etc.)
    
    .PARAMETER Path
        Target path for the rule
    
    .PARAMETER Description
        Optional description
    
    .EXAMPLE
        New-ProUPortRule -Name "User Profile Rule" -Type "User" -Path "%USERPROFILE%" -Description "User profile portability"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [ValidateSet('User', 'Computer', 'Application')]
        [string]$Type,
        
        [Parameter(Mandatory)]
        [string]$Path,
        
        [string]$Description = ""
    )
    
    try {
        # Check if rule already exists
        $existingRules = Get-ProUPortRule
        if ($existingRules | Where-Object { $_.Name -eq $Name }) {
            throw "Portability rule '$Name' already exists"
        }
        
        Write-Verbose "Creating new portability rule: $Name"
        
        # Create complete rule object with all required fields
        $newRule = @{
            Name = $Name
            Description = $Description
            PortabilityType = $Type
            Path = $Path
            Disabled = $false
            Comments = ""
            # Rule criteria and settings
            FilterRules = @()
            Connections = 0
            MachineClasses = 0
            OperatingSystems = 0
            SystemEvents = 0
            RuleAggregate = 0
            Priority = 100
            ClientId = $null
            ClientSecret = $null
            # Portability specific fields
            IncludeSubfolders = $true
            CopyPermissions = $false
            BackupExisting = $false
        }
        
        # Create the rule - use direct object, not wrapped
        $response = Invoke-ProfileUnityApi -Endpoint "portability" -Method POST -Body $newRule
        
        # Validate response
        if ($response -and $response.type -eq "success") {
            Write-Host "Portability rule '$Name' created successfully" -ForegroundColor Green
            Write-Verbose "Rule ID: $($response.tag.id)"
            return $response.tag
        }
        elseif ($response -and $response.type -eq "error") {
            throw "Server error: $($response.message)"
        }
        else {
            throw "Unexpected response from server: $($response | ConvertTo-Json -Depth 2)"
        }
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
        $rules = Get-ProUPortRule
        $rule = $rules | Where-Object { $_.Name -eq $Name }
        
        if (-not $rule) {
            throw "Portability rule '$Name' not found"
        }
        
        if ($Force -or $PSCmdlet.ShouldProcess($Name, "Remove portability rule")) {
            $response = Invoke-ProfileUnityApi -Endpoint "portability/$($rule.ID)" -Method DELETE
            Write-Host "Portability rule '$Name' removed successfully" -ForegroundColor Green
            return $response
        }
        else {
            Write-Host "Remove cancelled" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "Failed to remove portability rule: $_"
        throw
    }
}

function Copy-ProUPortRule {
    <#
    .SYNOPSIS
        Copies an existing ProfileUnity portability rule.
    
    .DESCRIPTION
        Copies an existing portability rule with a new name.
    
    .PARAMETER SourceName
        Name of the portability rule to copy
    
    .PARAMETER NewName
        Name for the new portability rule
    
    .PARAMETER Description
        Optional new description
    
    .EXAMPLE
        Copy-ProUPortRule -SourceName "Production Rule" -NewName "Test Rule"
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
        # Find source rule
        $rules = Get-ProUPortRule
        $sourceRule = $rules | Where-Object { $_.Name -eq $SourceName }
        
        if (-not $sourceRule) {
            throw "Source portability rule '$SourceName' not found"
        }
        
        Write-Verbose "Copying portability rule ID: $($sourceRule.ID)"
        
        # Get full rule details
        $response = Invoke-ProfileUnityApi -Endpoint "portability/$($sourceRule.ID)"
        
        if ($response -and $response.tag) {
            # Update the copy with new name
            $copiedRule = $response.tag
            $copiedRule.name = $NewName
            
            if ($Description) {
                $copiedRule.description = $Description
            }
            else {
                $copiedRule.description = "Copy of $SourceName - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            }
            
            # Remove ID so it creates a new rule
            $copiedRule.PSObject.Properties.Remove('id')
            
            # Save the new rule
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

function Test-ProUPortRule {
    <#
    .SYNOPSIS
        Tests a ProfileUnity portability rule for issues.
    
    .DESCRIPTION
        Validates portability rule settings and checks for common problems.
    
    .PARAMETER Name
        Name of the portability rule to test
    
    .EXAMPLE
        Test-ProUPortRule -Name "User Profile Rule"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    
    try {
        $rules = Get-ProUPortRule
        $rule = $rules | Where-Object { $_.Name -eq $Name }
        
        if (-not $rule) {
            throw "Portability rule '$Name' not found"
        }
        
        Write-Verbose "Testing portability rule: $Name"
        
        # Get detailed rule
        $response = Invoke-ProfileUnityApi -Endpoint "portability/$($rule.ID)"
        $ruleData = $response.tag
        
        $issues = @()
        $warnings = @()
        
        # Basic validation
        if (-not $ruleData.name) {
            $issues += "Missing rule name"
        }
        
        if (-not $ruleData.portabilityType) {
            $issues += "Missing portability type"
        }
        
        if (-not $ruleData.path) {
            $issues += "Missing path specification"
        }
        
        # Path validation
        if ($ruleData.path -and $ruleData.path -notmatch '%|\\\\|\$env:') {
            $warnings += "Path appears to be hardcoded rather than using environment variables"
        }
        
        $isValid = $issues.Count -eq 0
        
        $result = [PSCustomObject]@{
            RuleName = $Name
            IsValid = $isValid
            Issues = $issues
            Warnings = $warnings
            PathType = $ruleData.portabilityType
            TestDate = Get-Date
        }
        
        # Display results
        if ($isValid) {
            Write-Host "Portability rule '$Name' validation: PASSED" -ForegroundColor Green
        }
        else {
            Write-Host "Portability rule '$Name' validation: FAILED" -ForegroundColor Red
            $issues | ForEach-Object { Write-Host "  ERROR: $_" -ForegroundColor Red }
        }
        
        if ($warnings.Count -gt 0) {
            $warnings | ForEach-Object { Write-Host "  WARNING: $_" -ForegroundColor Yellow }
        }
        
        return $result
    }
    catch {
        Write-Error "Failed to test portability rule: $_"
        throw
    }
}

function Get-ProUPortRuleTypes {
    <#
    .SYNOPSIS
        Gets available portability rule types.
    
    .DESCRIPTION
        Retrieves the list of available portability rule types.
    
    .EXAMPLE
        Get-ProUPortRuleTypes
    #>
    [CmdletBinding()]
    param()
    
    try {
        $response = Invoke-ProfileUnityApi -Endpoint "portability/types"
        
        if ($response) {
            return $response | ForEach-Object {
                [PSCustomObject]@{
                    RuleType = $_.type
                    DisplayName = $_.displayName
                    Description = $_.description
                }
            }
        }
        else {
            # Return common rule types if API doesn't provide them
            return @(
                [PSCustomObject]@{ RuleType = 'User'; DisplayName = 'User'; Description = 'User-based portability rule' }
                [PSCustomObject]@{ RuleType = 'Computer'; DisplayName = 'Computer'; Description = 'Computer-based portability rule' }
                [PSCustomObject]@{ RuleType = 'Application'; DisplayName = 'Application'; Description = 'Application-based portability rule' }
            )
        }
    }
    catch {
        Write-Error "Failed to retrieve portability rule types: $_"
        throw
    }
}

# Export functions
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
Export-ModuleMember -Function @(
    'Get-ProUPortRule',
    'Edit-ProUPortRule',
    'Save-ProUPortRule',
    'New-ProUPortRule',
    'Remove-ProUPortRule',
    'Copy-ProUPortRule',
    'Test-ProUPortRule',
    'Get-ProUPortRuleTypes'
)
#>