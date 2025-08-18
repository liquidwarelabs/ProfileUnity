# Core\Helpers.ps1 - Updated with Correct Assert Function
# Relative Path: \Core\Helpers.ps1

# =============================================================================
# CORE HELPER FUNCTIONS - MATCHING WORKING MODULE
# =============================================================================

# Assert-ProfileUnityConnection moved to Core/Connection.ps1 to avoid duplication

# Invoke-ProfileUnityApi moved to Core/Connection.ps1 to avoid duplication

function Confirm-Action {
    <#
    .SYNOPSIS
        Prompts user for confirmation of an action.
    
    .DESCRIPTION
        Shows a confirmation dialog with Yes/No choices.
    
    .PARAMETER Title
        Title of the confirmation dialog
    
    .PARAMETER Message
        Message to display to the user
    
    .EXAMPLE
        Confirm-Action -Title "Delete Item" -Message "Are you sure?"
    #>
    [CmdletBinding()]
    param(
        [string]$Title = "Confirm Action",
        [string]$Message = "Do you want to continue?"
    )
    
    $choices = @(
        [System.Management.Automation.Host.ChoiceDescription]::new("&Yes", "Proceed with the action")
        [System.Management.Automation.Host.ChoiceDescription]::new("&No", "Cancel the action")
    )
    
    $result = $host.UI.PromptForChoice($Title, $Message, $choices, 1)
    return $result -eq 0
}

function Get-FileName {
    <#
    .SYNOPSIS
        Shows a file selection dialog.
    
    .DESCRIPTION
        Opens a Windows file dialog for file selection.
    
    .PARAMETER Filter
        File filter string
    
    .PARAMETER InitialDirectory
        Initial directory to show
    
    .EXAMPLE
        Get-FileName -Filter "JSON files (*.json)|*.json"
    #>
    [CmdletBinding()]
    param(
        [string]$Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*",
        [string]$InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    )
    
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.OpenFileDialog -Property @{
            InitialDirectory = $InitialDirectory
            Filter = $Filter
        }
        
        if ($dialog.ShowDialog() -eq 'OK') {
            return $dialog.FileName
        }
        return $null
    }
    catch {
        Write-Warning "File dialog not available: $_"
        return $null
    }
}

function ConvertTo-SafeFileName {
    <#
    .SYNOPSIS
        Converts a string to a safe filename.
    
    .DESCRIPTION
        Removes or replaces invalid characters from a string to create a valid filename.
    
    .PARAMETER FileName
        The original filename string
    
    .PARAMETER Replacement
        Character to use as replacement for invalid characters (default: '_')
    
    .EXAMPLE
        ConvertTo-SafeFileName -FileName "My Config: Test/Data"
        # Returns: "My Config_ Test_Data"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FileName,
        
        [string]$Replacement = '_'
    )
    
    # Get invalid characters for filenames
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
    
    # Replace invalid characters
    $safeName = $FileName
    foreach ($char in $invalidChars) {
        $safeName = $safeName.Replace($char, $Replacement)
    }
    
    # Remove multiple consecutive replacement characters
    while ($safeName.Contains($Replacement + $Replacement)) {
        $safeName = $safeName.Replace($Replacement + $Replacement, $Replacement)
    }
    
    # Trim replacement characters from start/end
    $safeName = $safeName.Trim($Replacement)
    
    # Ensure the filename isn't empty
    if ([string]::IsNullOrWhiteSpace($safeName)) {
        $safeName = "unnamed"
    }
    
    # Truncate if too long (Windows max filename is 255 chars)
    if ($safeName.Length -gt 200) {
        $safeName = $safeName.Substring(0, 200).TrimEnd($Replacement)
    }
    
    return $safeName
}

function Write-LogMessage {
    <#
    .SYNOPSIS
        Writes a message to the module log file.
    
    .DESCRIPTION
        Centralized logging function for the ProfileUnity PowerTools module.
    
    .PARAMETER Message
        The message to log
    
    .PARAMETER Level
        Log level (Info, Warning, Error)
    
    .PARAMETER Category
        Optional category for the log entry
    
    .EXAMPLE
        Write-LogMessage -Message "Configuration saved" -Level Info
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('Info', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Info',
        
        [string]$Category = 'General'
    )
    
    try {
        # Create log entry
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $logEntry = "$timestamp [$Level] [$Category] $Message"
        
        # Write to verbose stream
        Write-Verbose $logEntry
        
        # Optionally write to file if path exists
        $logDir = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ProfileUnity-PowerTools\Logs'
        if (Test-Path $logDir) {
            $logFile = Join-Path $logDir "ProfileUnity-PowerTools_$(Get-Date -Format 'yyyyMMdd').log"
            Add-Content -Path $logFile -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    }
    catch {
        # Ignore logging errors
    }
}

function Format-ProfileUnityData {
    <#
    .SYNOPSIS
        Formats ProfileUnity data for display.
    
    .DESCRIPTION
        Standardizes the display format for ProfileUnity objects.
    
    .PARAMETER Data
        The data to format
    
    .PARAMETER Type
        The type of data being formatted
    
    .EXAMPLE
        Format-ProfileUnityData -Data $configurations -Type "Configuration"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Data,
        
        [ValidateSet('Configuration', 'Filter', 'FlexApp', 'User', 'Computer')]
        [string]$Type
    )
    
    try {
        switch ($Type) {
            'Configuration' {
                $Data | Select-Object @(
                    @{Name='Name'; Expression={$_.Name}},
                    @{Name='ID'; Expression={$_.ID}},
                    @{Name='Enabled'; Expression={-not $_.Disabled}},
                    @{Name='Modules'; Expression={if ($_.modules) {$_.modules.Count} else {0}}},
                    @{Name='Description'; Expression={$_.Description}}
                )
            }
            
            'Filter' {
                $Data | Select-Object @(
                    @{Name='Name'; Expression={$_.name}},
                    @{Name='ID'; Expression={$_.id}},
                    @{Name='Type'; Expression={$_.filterType}},
                    @{Name='Rules'; Expression={if ($_.rules) {$_.rules.Count} else {0}}}
                )
            }
            
            default {
                return $Data
            }
        }
    }
    catch {
        Write-Warning "Failed to format data: $_"
        return $Data
    }
}

function Convert-ProfileUnityGuid {
    <#
    .SYNOPSIS
        Converts between different GUID formats used by ProfileUnity.
    
    .DESCRIPTION
        Handles GUID format conversions for ProfileUnity API compatibility.
    
    .PARAMETER Guid
        The GUID to convert
    
    .PARAMETER Format
        The target format
    
    .EXAMPLE
        Convert-ProfileUnityGuid -Guid "12345678-1234-1234-1234-123456789012" -Format Bracketed
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Guid,
        
        [ValidateSet('Plain', 'Bracketed', 'Upper', 'Lower')]
        [string]$Format = 'Plain'
    )
    
    try {
        # Parse GUID to ensure it's valid
        $guidObj = [System.Guid]::Parse($Guid)
        
        switch ($Format) {
            'Plain' { return $guidObj.ToString() }
            'Bracketed' { return "{$($guidObj.ToString())}" }
            'Upper' { return $guidObj.ToString().ToUpper() }
            'Lower' { return $guidObj.ToString().ToLower() }
        }
    }
    catch {
        Write-Warning "Invalid GUID format: $Guid"
        return $Guid
    }
}

function Get-ProfileUnityErrorDetails {
    <#
    .SYNOPSIS
        Extracts detailed error information from ProfileUnity API responses.
    
    .DESCRIPTION
        Parses error responses to provide meaningful error messages.
    
    .PARAMETER ErrorRecord
        The error record to parse
    
    .EXAMPLE
        Get-ProfileUnityErrorDetails -ErrorRecord $_
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )
    
    try {
        $errorDetails = @{
            Message = $ErrorRecord.Exception.Message
            Category = $ErrorRecord.CategoryInfo.Category
            TargetName = $ErrorRecord.CategoryInfo.TargetName
        }
        
        # Try to extract API error details
        if ($ErrorRecord.Exception -is [System.Net.WebException]) {
            $response = $ErrorRecord.Exception.Response
            if ($response) {
                $errorDetails.StatusCode = $response.StatusCode
                $errorDetails.StatusDescription = $response.StatusDescription
                
                # Try to read response content
                try {
                    $stream = $response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $content = $reader.ReadToEnd()
                    
                    if ($content) {
                        $apiError = $content | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if ($apiError) {
                            $errorDetails.ApiError = $apiError
                        }
                    }
                }
                catch {
                    # Ignore errors reading response content
                }
            }
        }
        
        return $errorDetails
    }
    catch {
        return @{
            Message = "Failed to parse error details"
            Category = "Unknown"
        }
    }
}

function Validate-ProfileUnityObject {
    <#
    .SYNOPSIS
        Validates ProfileUnity object structure.
    
    .DESCRIPTION
        Checks if an object has the required properties for ProfileUnity operations.
    
    .PARAMETER Object
        The object to validate
    
    .PARAMETER Type
        The expected object type
    
    .PARAMETER RequiredProperties
        Array of required property names
    
    .EXAMPLE
        Validate-ProfileUnityObject -Object $config -Type "Configuration" -RequiredProperties @('name', 'id')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Object,
        
        [string]$Type = "Unknown",
        
        [string[]]$RequiredProperties = @()
    )
    
    try {
        if (-not $Object) {
            throw "Object is null"
        }
        
        $missingProperties = @()
        
        foreach ($property in $RequiredProperties) {
            if (-not ($Object.PSObject.Properties.Name -contains $property)) {
                $missingProperties += $property
            }
        }
        
        if ($missingProperties.Count -gt 0) {
            throw "$Type object is missing required properties: $($missingProperties -join ', ')"
        }
        
        return $true
    }
    catch {
        Write-Error "Validation failed for $Type object: $_"
        return $false
    }
}

function New-ProfileUnityGuid {
    <#
    .SYNOPSIS
        Generates a new GUID for ProfileUnity objects.
    
    .DESCRIPTION
        Creates a new GUID in the format expected by ProfileUnity.
    
    .EXAMPLE
        New-ProfileUnityGuid
    #>
    [CmdletBinding()]
    param()
    
    return [System.Guid]::NewGuid().ToString()
}

# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
# Export-ModuleMember removed to prevent conflicts when dot-sourcing