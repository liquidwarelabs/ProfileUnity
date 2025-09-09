# Scripts\GPO-Analysis\Get-GPOAdmxDependencies.ps1
# Location: \Scripts\GPO-Analysis\Get-GPOAdmxDependencies.ps1
# PowerShell 5.x Compatible

<#
.SYNOPSIS
    Determines required ADMX and ADML files for Administrative Template settings in a GPO
.DESCRIPTION
    Analyzes a GPO to identify which ADMX/ADML files are needed for Administrative Templates.
    Creates reports showing dependencies and unmatched settings.
.PARAMETER GpoDisplayName
    Display name of the target GPO
.PARAMETER AdmxStorePath
    Path to the PolicyDefinitions store (default: Central Store)
.PARAMETER Language
    Language-specific folder for ADML files (default: en-US)
.PARAMETER OutputFolder
    Folder where CSV output is saved (default: script directory)
.PARAMETER ExportSettingsReport
    Creates detailed report of all matched settings
.EXAMPLE
    .\Get-GPOAdmxDependencies.ps1 -GpoDisplayName "Security Baseline" -ExportSettingsReport
.EXAMPLE
    .\Get-GPOAdmxDependencies.ps1 -GpoDisplayName "Chrome Policy" -AdmxStorePath "C:\PolicyDefinitions"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$GpoDisplayName,

    [string]$AdmxStorePath,

    [ValidatePattern('^[a-z]{2}-[A-Z]{2}$')]
    [string]$Language = "en-US",

    [string]$OutputFolder = $PSScriptRoot,

    [switch]$ExportSettingsReport
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$ProgressPreference = 'SilentlyContinue'

# Import required modules
try {
    Import-Module GroupPolicy -ErrorAction Stop
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "Required modules imported successfully" -ForegroundColor Green
} catch {
    throw "Failed to import required modules: $($_.Exception.Message)"
}

# Set default ADMX store path if not provided
if (-not $PSBoundParameters.ContainsKey('AdmxStorePath')) {
    try {
        $domain = (Get-ADDomain -ErrorAction Stop).DNSRoot
        $AdmxStorePath = "\\$domain\SYSVOL\$domain\Policies\PolicyDefinitions"
        Write-Host "Using domain central store: $AdmxStorePath" -ForegroundColor Cyan
        
        if (-not (Test-Path $AdmxStorePath)) {
            throw "Central store not found at: $AdmxStorePath"
        }
    } catch {
        throw "Could not determine domain central store path: $($_.Exception.Message)"
    }
}

# Get and validate GPO
Write-Host "Retrieving GPO information..." -ForegroundColor Yellow
try {
    $gpo = Get-GPO -Name $GpoDisplayName -ErrorAction Stop
    Write-Host "GPO found: $GpoDisplayName (ID: $($gpo.Id))" -ForegroundColor Green
} catch {
    throw "GPO '$GpoDisplayName' not found: $($_.Exception.Message)"
}

# Helper to get XML attribute values regardless of namespaces
function Get-XmlAttributeValue {
    param(
        [System.Xml.XmlNode]$Node,
        [string]$AttributeName
    )
    
    # Try multiple approaches to get the attribute
    $attr = $Node.SelectSingleNode("@*[local-name()='$AttributeName']")
    if ($attr) { return $attr.Value }
    
    # Try direct attribute access
    $attr = $Node.GetAttribute($AttributeName)
    if ($attr) { return $attr }
    
    # Try with namespace prefix
    $attr = $Node.GetAttribute("$AttributeName")
    if ($attr) { return $attr }
    
    return $null
}

# Function to extract policy settings from GPO XML report (namespace-agnostic)
function Get-GpoPolicySettings {
    param([xml]$GpoXml, [string]$GpoName)
    
    $policySettings = @()
    
    try {
        # Process Computer Configuration
        # Match any Extension nodes under Computer, regardless of parent wrapper name
        $computerExtensionNodes = $GpoXml.SelectNodes("//*[local-name()='GPO']/*[local-name()='Computer']//*[local-name()='Extension']")
        if ($computerExtensionNodes -and $computerExtensionNodes.Count -gt 0) {
            foreach ($extension in $computerExtensionNodes) {
                $extensionType = Get-XmlAttributeValue -Node $extension -AttributeName 'type'
                if ($extensionType -like "*:RegistrySettings" -or $extensionType -like "*Administrative Templates*" -or $extensionType -like "*RegistrySettings*") {
                    $policyNodes = $extension.SelectNodes("*[local-name()='Policy']")
                    if ($policyNodes -and $policyNodes.Count -gt 0) {
                        foreach ($policy in $policyNodes) {
                            $policyName = Get-XmlAttributeValue -Node $policy -AttributeName 'Name'
                            if ($policyName) {
                                $state = Get-XmlAttributeValue -Node $policy -AttributeName 'State'
                                $category = Get-XmlAttributeValue -Node $policy -AttributeName 'Category'
                                $supported = Get-XmlAttributeValue -Node $policy -AttributeName 'Supported'
                                $explain = Get-XmlAttributeValue -Node $policy -AttributeName 'Explain'
                                $policySettings += [PSCustomObject]@{
                                    GpoName = $GpoName
                                    SettingScope = "Computer"
                                    SettingName = $policyName
                                    State = if ($state) { $state } else { "Unknown" }
                                    Category = if ($category) { $category } else { "Unknown" }
                                    Supported = if ($supported) { $supported } else { "Unknown" }
                                    ExplainText = if ($explain) { $explain } else { "" }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        # Process User Configuration
        # Match any Extension nodes under User, regardless of parent wrapper name
        $userExtensionNodes = $GpoXml.SelectNodes("//*[local-name()='GPO']/*[local-name()='User']//*[local-name()='Extension']")
        if ($userExtensionNodes -and $userExtensionNodes.Count -gt 0) {
            foreach ($extension in $userExtensionNodes) {
                $extensionType = Get-XmlAttributeValue -Node $extension -AttributeName 'type'
                if ($extensionType -like "*:RegistrySettings" -or $extensionType -like "*Administrative Templates*" -or $extensionType -like "*RegistrySettings*") {
                    $policyNodes = $extension.SelectNodes("*[local-name()='Policy']")
                    if ($policyNodes -and $policyNodes.Count -gt 0) {
                        foreach ($policy in $policyNodes) {
                            $policyName = Get-XmlAttributeValue -Node $policy -AttributeName 'Name'
                            if ($policyName) {
                                $state = Get-XmlAttributeValue -Node $policy -AttributeName 'State'
                                $category = Get-XmlAttributeValue -Node $policy -AttributeName 'Category'
                                $supported = Get-XmlAttributeValue -Node $policy -AttributeName 'Supported'
                                $explain = Get-XmlAttributeValue -Node $policy -AttributeName 'Explain'
                                $policySettings += [PSCustomObject]@{
                                    GpoName = $GpoName
                                    SettingScope = "User"
                                    SettingName = $policyName
                                    State = if ($state) { $state } else { "Unknown" }
                                    Category = if ($category) { $category } else { "Unknown" }
                                    Supported = if ($supported) { $supported } else { "Unknown" }
                                    ExplainText = if ($explain) { $explain } else { "" }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        # If no settings found, try a simpler approach - just look for any Policy nodes
        if ($policySettings.Count -eq 0) {
            Write-Host "No settings found with standard approach, trying alternative method..." -ForegroundColor Yellow
            
            # Look for any Policy nodes in the XML
            $allPolicies = $GpoXml.SelectNodes("//*[local-name()='Policy']")
            if ($allPolicies -and $allPolicies.Count -gt 0) {
                Write-Host "Found $($allPolicies.Count) Policy nodes using XPath" -ForegroundColor Green
                Write-Host "Debug: Examining first few Policy nodes..." -ForegroundColor Yellow
                $sampleCount = [Math]::Min(3, $allPolicies.Count)
                for ($i = 0; $i -lt $sampleCount; $i++) {
                    $policy = $allPolicies[$i]
                    Write-Host "  Policy $($i+1):" -ForegroundColor Gray
                    Write-Host "    Node name: $($policy.Name)" -ForegroundColor Gray
                    Write-Host "    Local name: $($policy.LocalName)" -ForegroundColor Gray
                    Write-Host "    Attributes count: $($policy.Attributes.Count)" -ForegroundColor Gray
                    if ($policy.Attributes.Count -gt 0) {
                        foreach ($attr in $policy.Attributes) {
                            Write-Host "      Attribute: $($attr.Name) = $($attr.Value)" -ForegroundColor Gray
                        }
                    }
                    
                    $policyName = $policy.InnerText.Trim()
                    $cleanPolicyName = $policyName
                    
                    # Split by newlines and take only the first line (the actual policy name)
                    $lines = $cleanPolicyName -split "`n|`r`n"
                    if ($lines.Count -gt 0) {
                        $cleanPolicyName = $lines[0].Trim()
                    }
                    
                    # Remove common suffixes and everything after them
                    $cleanPolicyName = $cleanPolicyName -replace '\s+(Enabled|Disabled|Not Configured).*$', ''
                    
                    # Remove any text that starts with "This policy setting" or similar
                    $cleanPolicyName = $cleanPolicyName -replace '\s+This policy setting.*$', ''
                    
                    # Remove any text that starts with "The policy" or similar
                    $cleanPolicyName = $cleanPolicyName -replace '\s+The policy.*$', ''
                    
                    # Remove any text that starts with "At least" (system requirements)
                    $cleanPolicyName = $cleanPolicyName -replace '\s+At least.*$', ''
                    
                    $cleanPolicyName = $cleanPolicyName.Trim()
                    Write-Host "    Extracted Name: $cleanPolicyName" -ForegroundColor Gray
                }
                
                foreach ($policy in $allPolicies) {
                    # Get policy name from node text content since attributes are empty
                    $policyName = $policy.InnerText.Trim()
                    if ($policyName -and $policyName -ne "") {
                        # Extract just the policy name (first line before any description)
                        # The policy name is typically the first part before "Enabled", "Disabled", etc.
                        $cleanPolicyName = $policyName
                        
                        # Split by newlines and take only the first line (the actual policy name)
                        $lines = $cleanPolicyName -split "`n|`r`n"
                        if ($lines.Count -gt 0) {
                            $cleanPolicyName = $lines[0].Trim()
                        }
                        
                        # Remove common suffixes and everything after them (with or without space)
                        $cleanPolicyName = $cleanPolicyName -replace '(Enabled|Disabled|Not Configured).*$', ''
                        
                        # Remove any text that starts with "This policy setting" or similar
                        $cleanPolicyName = $cleanPolicyName -replace '\s+This policy setting.*$', ''
                        
                        # Remove any text that starts with "The policy" or similar
                        $cleanPolicyName = $cleanPolicyName -replace '\s+The policy.*$', ''
                        
                        # Remove any text that starts with "At least" (system requirements)
                        $cleanPolicyName = $cleanPolicyName -replace '\s+At least.*$', ''
                        
                        # Remove any text that starts with "System/" (category paths)
                        $cleanPolicyName = $cleanPolicyName -replace '\s+System/.*$', ''
                        
                        # Remove any text that starts with "Windows Components/" (category paths)
                        $cleanPolicyName = $cleanPolicyName -replace '\s+Windows Components/.*$', ''
                        
                        # Remove any text that starts with "Administrative Templates/" (category paths)
                        $cleanPolicyName = $cleanPolicyName -replace '\s+Administrative Templates/.*$', ''
                        
                        # Clean up any remaining whitespace
                        $cleanPolicyName = $cleanPolicyName.Trim()
                        
                        # Debug: Show the cleaning process for first few policies
                        if ($VerbosePreference -eq 'Continue' -and $policySettings.Count -lt 3) {
                            Write-Host "Debug: Policy cleaning - Original: '$policyName'" -ForegroundColor Magenta
                            Write-Host "Debug: Policy cleaning - Cleaned: '$cleanPolicyName'" -ForegroundColor Magenta
                        }
                        
                        # Additional cleaning: Remove any remaining text that looks like descriptions
                        # This is a more aggressive approach to get just the policy name
                        if ($cleanPolicyName -like "*This policy setting*") {
                            $cleanPolicyName = $cleanPolicyName -replace 'This policy setting.*$', ''
                        }
                        if ($cleanPolicyName -like "*The policy*") {
                            $cleanPolicyName = $cleanPolicyName -replace 'The policy.*$', ''
                        }
                        if ($cleanPolicyName -like "*If you*") {
                            $cleanPolicyName = $cleanPolicyName -replace 'If you.*$', ''
                        }
                        
                        # Final cleanup
                        $cleanPolicyName = $cleanPolicyName.Trim()
                        
                        $policySettings += [PSCustomObject]@{
                            GpoName = $GpoName
                            SettingScope = "Unknown"
                            SettingName = $cleanPolicyName
                            State = "Unknown"
                            Category = "Unknown"
                            Supported = "Unknown"
                            ExplainText = ""
                        }
                    }
                }
            }
            
            # If still no settings, try looking for any nodes with "Name" attribute
            if ($policySettings.Count -eq 0) {
                Write-Host "Trying to find any nodes with Name attribute..." -ForegroundColor Yellow
                $allNamedNodes = $GpoXml.SelectNodes("//*[@*[local-name()='Name']]")
                if ($allNamedNodes -and $allNamedNodes.Count -gt 0) {
                    Write-Host "Found $($allNamedNodes.Count) nodes with Name attribute" -ForegroundColor Green
                    foreach ($node in $allNamedNodes) {
                        $nodeName = Get-XmlAttributeValue -Node $node -AttributeName 'Name'
                        if ($nodeName -and $nodeName -ne "") {
                            $policySettings += [PSCustomObject]@{
                                GpoName = $GpoName
                                SettingScope = "Unknown"
                                SettingName = $nodeName
                                State = "Unknown"
                                Category = "Unknown"
                                Supported = "Unknown"
                                ExplainText = ""
                            }
                        }
                    }
                }
            }
        }
        
    } catch {
        Write-Warning "Error processing GPO XML for $GpoName : $_"
    }
    
    return $policySettings
}

# Generate GPO report and extract policy settings
Write-Host "Generating GPO report and extracting policy settings..." -ForegroundColor Yellow

try {
    $gpoReport = Get-GPOReport -Name $GpoDisplayName -ReportType Xml -ErrorAction Stop
    $gpoXml = [xml]$gpoReport
    Write-Host "GPO report generated successfully" -ForegroundColor Green
    
    # Debug: Let's see what's actually in the XML
    if ($VerbosePreference -eq 'Continue') {
        Write-Host "`nDebug: Checking XML structure..." -ForegroundColor Yellow
        Write-Host "  GPO.Computer exists: $($gpoXml.GPO.Computer -ne $null)" -ForegroundColor Gray
        Write-Host "  GPO.User exists: $($gpoXml.GPO.User -ne $null)" -ForegroundColor Gray
        
        # Check Computer ExtensionData using namespace-agnostic XPath
        $computerExtensionDataNodes = $gpoXml.SelectNodes("//*[local-name()='GPO']/*[local-name()='Computer']/*[local-name()='ExtensionData']")
        if ($computerExtensionDataNodes -and $computerExtensionDataNodes.Count -gt 0) {
            Write-Host "  Computer.ExtensionData count: $($computerExtensionDataNodes.Count)" -ForegroundColor Gray
            foreach ($extData in $computerExtensionDataNodes) {
                $extensionNodes = $extData.SelectNodes("*[local-name()='Extension']")
                if ($extensionNodes -and $extensionNodes.Count -gt 0) {
                    foreach ($ext in $extensionNodes) {
                        $extensionType = Get-XmlAttributeValue -Node $ext -AttributeName 'type'
                        Write-Host "    Extension type: $extensionType" -ForegroundColor Gray
                    }
                }
            }
        } else {
            Write-Host "  Computer.ExtensionData: Not found" -ForegroundColor Gray
        }
        
        # Check User ExtensionData using namespace-agnostic XPath
        $userExtensionDataNodes = $gpoXml.SelectNodes("//*[local-name()='GPO']/*[local-name()='User']/*[local-name()='ExtensionData']")
        if ($userExtensionDataNodes -and $userExtensionDataNodes.Count -gt 0) {
            Write-Host "  User.ExtensionData count: $($userExtensionDataNodes.Count)" -ForegroundColor Gray
            foreach ($extData in $userExtensionDataNodes) {
                $extensionNodes = $extData.SelectNodes("*[local-name()='Extension']")
                if ($extensionNodes -and $extensionNodes.Count -gt 0) {
                    foreach ($ext in $extensionNodes) {
                        $extensionType = Get-XmlAttributeValue -Node $ext -AttributeName 'type'
                        Write-Host "    Extension type: $extensionType" -ForegroundColor Gray
                    }
                }
            }
        } else {
            Write-Host "  User.ExtensionData: Not found" -ForegroundColor Gray
        }
    }
    
    $policySettings = Get-GpoPolicySettings -GpoXml $gpoXml -GpoName $GpoDisplayName
    
    if ($policySettings -and $policySettings.Count -gt 0) {
        Write-Host "Found $($policySettings.Count) policy settings" -ForegroundColor Green
        
        if ($VerbosePreference -eq 'Continue') {
            Write-Host "`nSample policy settings:" -ForegroundColor Yellow
            $policySettings | Select-Object -First 5 | ForEach-Object {
                Write-Host "  Scope: $($_.SettingScope), Name: $($_.SettingName)" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "Found 0 policy settings" -ForegroundColor Yellow
    }
    
} catch {
    Write-Error "Failed to generate GPO report: $($_.Exception.Message)"
    return
}

if (-not $policySettings -or $policySettings.Count -eq 0) {
    Write-Warning "No policy settings found in GPO. The GPO might not have any Administrative Template settings."
    return
}

# Initialize collections
$requiredAdmxFiles = @()
$requiredAdmlFiles = @()
$admlFileUsage = @()
$unmatchedSettings = @()

# Debug: Check what type admlFileUsage is
if ($VerbosePreference -eq 'Continue') {
    Write-Host "Debug: admlFileUsage type: $($admlFileUsage.GetType().Name)" -ForegroundColor Yellow
    Write-Host "Debug: admlFileUsage is array: $($admlFileUsage -is [array])" -ForegroundColor Yellow
    Write-Host "Debug: admlFileUsage count: $(if ($admlFileUsage -is [array]) { $admlFileUsage.Count } else { 'N/A' })" -ForegroundColor Yellow
}

# Get available ADML files (based on Microsoft approach)
Write-Host "Scanning ADML files..." -ForegroundColor Yellow

# Validate ADMX store path
if (-not (Test-Path $AdmxStorePath -PathType Container)) {
    throw "ADMX store path not found or not accessible: $AdmxStorePath"
}

$admlPath = Join-Path $AdmxStorePath $Language
if (-not (Test-Path $admlPath -PathType Container)) {
    throw "ADML language path not found: $admlPath"
}

$admlFiles = Get-ChildItem -Path $admlPath -Filter "*.adml" -ErrorAction SilentlyContinue

if ($admlFiles.Count -eq 0) {
    throw "No ADML files found in $admlPath"
}

Write-Host "Found $($admlFiles.Count) ADML files to analyze" -ForegroundColor Cyan

# Search ADML files for policy settings (based on Microsoft approach)
Write-Host "Searching ADML files for policy settings..." -ForegroundColor Yellow
if ($VerbosePreference -eq 'Continue') {
    Write-Host "Debug: Sample policy names to search for:" -ForegroundColor Yellow
    $policySettings | Select-Object -First 3 | ForEach-Object {
        Write-Host "  '$($_.SettingName)'" -ForegroundColor Gray
    }
}

$processedCount = 0

foreach ($admlFile in $admlFiles) {
    $processedCount++
    Write-Progress -Activity "Analyzing ADML Files" -Status "Processing $($admlFile.Name)" -PercentComplete (($processedCount / $admlFiles.Count) * 100)
    
    try {
        # Load ADML file as XML
        $admlXml = [xml](Get-Content -Path $admlFile.FullName -Raw -ErrorAction Stop)
        
        foreach ($policySetting in $policySettings) {
            $settingName = $policySetting.SettingName
            
            # Search for policy name in various ADML XML locations
            $found = $false
            
            # Look for policy names in stringTable elements
            $stringNodes = $admlXml.SelectNodes("//*[local-name()='stringTable']/*[local-name()='string']")
            if ($stringNodes -and $stringNodes.Count -gt 0) {
                foreach ($stringNode in $stringNodes) {
                    $stringId = $stringNode.GetAttribute("id")
                    $stringValue = $stringNode.InnerText
                    
                    # Check if the string value contains our policy name
                    if ($stringValue -and $stringValue -like "*$settingName*") {
                        $found = $true
                        break
                    }
                }
            }
            
            # Also check for direct text content in the XML
            if (-not $found) {
                $allTextNodes = $admlXml.SelectNodes("//text()")
                if ($allTextNodes -and $allTextNodes.Count -gt 0) {
                    foreach ($textNode in $allTextNodes) {
                        if ($textNode.Value -and $textNode.Value -like "*$settingName*") {
                            $found = $true
                            break
                        }
                    }
                }
            }
            
            # Fallback to simple text search if XML parsing fails
            if (-not $found) {
                $admlContent = Get-Content -Path $admlFile.FullName -Raw -ErrorAction Stop
                if ($admlContent -like "*$settingName*") {
                    $found = $true
                }
            }
            
            if ($found) {
                if ($VerbosePreference -eq 'Continue') {
                    Write-Host "  Found match: '$settingName' in $($admlFile.Name)" -ForegroundColor Green
                }
                $admlFileUsage += [PSCustomObject]@{
                    GpoName = $policySetting.GpoName
                    SettingScope = $policySetting.SettingScope
                    SettingName = $policySetting.SettingName
                    State = $policySetting.State
                    Category = $policySetting.Category
                    AdmlFile = $admlFile.Name
                    AdmxFile = $admlFile.Name -replace '\.adml$', '.admx'
                }
            }
        }
    } catch {
        Write-Warning "Error processing ADML file $($admlFile.Name): $_"
    }
}

Write-Progress -Activity "Analyzing ADML Files" -Completed

# Debug: Check admlFileUsage after search
if ($VerbosePreference -eq 'Continue') {
    Write-Host "Debug: After ADML search - admlFileUsage type: $($admlFileUsage.GetType().Name)" -ForegroundColor Yellow
    Write-Host "Debug: After ADML search - admlFileUsage is array: $($admlFileUsage -is [array])" -ForegroundColor Yellow
    Write-Host "Debug: After ADML search - admlFileUsage count: $(if ($admlFileUsage -is [array]) { $admlFileUsage.Count } else { 'N/A' })" -ForegroundColor Yellow
}

# Get unique ADMX files from ADML matches
$requiredAdmxFiles = @()
$requiredAdmlFiles = @()

# Ensure admlFileUsage is always an array
if (-not ($admlFileUsage -is [array])) {
    $admlFileUsage = @()
}

if ($admlFileUsage -and $admlFileUsage.Count -gt 0) {
    $requiredAdmxFiles = @($admlFileUsage | Select-Object -ExpandProperty AdmxFile -Unique | Sort-Object)
    $requiredAdmlFiles = @($admlFileUsage | Select-Object -ExpandProperty AdmlFile -Unique | Sort-Object)
    
    # Debug: Check the arrays we created
    if ($VerbosePreference -eq 'Continue') {
        Write-Host "Debug: requiredAdmxFiles type: $($requiredAdmxFiles.GetType().Name)" -ForegroundColor Yellow
        Write-Host "Debug: requiredAdmxFiles count: $(if ($requiredAdmxFiles -is [array]) { $requiredAdmxFiles.Count } else { 'N/A' })" -ForegroundColor Yellow
        Write-Host "Debug: requiredAdmlFiles type: $($requiredAdmlFiles.GetType().Name)" -ForegroundColor Yellow
        Write-Host "Debug: requiredAdmlFiles count: $(if ($requiredAdmlFiles -is [array]) { $requiredAdmlFiles.Count } else { 'N/A' })" -ForegroundColor Yellow
    }
}

# Find unmatched settings
$unmatchedSettings = @()
if ($admlFileUsage -and $admlFileUsage.Count -gt 0) {
    foreach ($setting in $policySettings) {
        $isMatched = $admlFileUsage | Where-Object { $_.SettingName -eq $setting.SettingName -and $_.SettingScope -eq $setting.SettingScope }
        if (-not $isMatched) {
            $unmatchedSettings += $setting
        }
    }
} else {
    $unmatchedSettings = $policySettings
}

# Display results
Write-Host "`n" + ("=" * 70) -ForegroundColor Green
Write-Host "ADMX DEPENDENCY ANALYSIS RESULTS" -ForegroundColor Green
Write-Host ("=" * 70) -ForegroundColor Green
Write-Host "GPO: $GpoDisplayName" -ForegroundColor White
Write-Host "ADMX Store: $AdmxStorePath" -ForegroundColor White
Write-Host "Language: $Language" -ForegroundColor White

Write-Host "`nSummary:" -ForegroundColor Cyan
Write-Host "  Policy Settings Found: $($policySettings.Count)" -ForegroundColor White
Write-Host "  ADML Files Analyzed: $($admlFiles.Count)" -ForegroundColor White
Write-Host "  Settings Matched to ADML: $(if ($admlFileUsage) { $admlFileUsage.Count } else { 0 })" -ForegroundColor Green
Write-Host "  Required ADMX Files: $($requiredAdmxFiles.Count)" -ForegroundColor Green
Write-Host "  Required ADML Files: $($requiredAdmlFiles.Count)" -ForegroundColor Green
Write-Host "  Unmatched Settings: $($unmatchedSettings.Count)" -ForegroundColor Yellow

# Show required files
if ($requiredAdmxFiles -and $requiredAdmxFiles.Count -gt 0) {
    Write-Host "`nRequired ADMX Files:" -ForegroundColor Cyan
    $requiredAdmxFiles | Sort-Object | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
    
    Write-Host "`nRequired ADML Files:" -ForegroundColor Cyan
    $requiredAdmlFiles | Sort-Object | ForEach-Object { 
        if ($_ -like "*[MISSING]") {
            Write-Host "  $_" -ForegroundColor Red
        } else {
            Write-Host "  $_" -ForegroundColor White
        }
    }
}

# Export results to CSV
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$safeGpoName = $GpoDisplayName -replace '[^\w\-_\.]', '_'

$admxCsvPath = Join-Path $OutputFolder "Required_ADMX_${safeGpoName}_$timestamp.csv"
$admlCsvPath = Join-Path $OutputFolder "Required_ADML_${safeGpoName}_$timestamp.csv"

if ($requiredAdmxFiles -and $requiredAdmxFiles.Count -gt 0) {
    $requiredAdmxFiles | ForEach-Object { 
        [PSCustomObject]@{
            FileName = $_
            FileType = "ADMX"
            Status = "Required"
        }
    } | Export-Csv -Path $admxCsvPath -NoTypeInformation -ErrorAction SilentlyContinue
}

if ($requiredAdmlFiles -and $requiredAdmlFiles.Count -gt 0) {
    $requiredAdmlFiles | ForEach-Object { 
        [PSCustomObject]@{
            FileName = $_
            FileType = "ADML"
            Language = $Language
            Status = if ($_ -like "*[MISSING]") { "Missing" } else { "Available" }
        }
    } | Export-Csv -Path $admlCsvPath -NoTypeInformation -ErrorAction SilentlyContinue
}

Write-Host "`nFiles exported:" -ForegroundColor Cyan
Write-Host "  ADMX list: $admxCsvPath" -ForegroundColor White
Write-Host "  ADML list: $admlCsvPath" -ForegroundColor White

# Export detailed policy matches report if requested
if ($ExportSettingsReport -and $admlFileUsage -and $admlFileUsage.Count -gt 0) {
    $detailsCsvPath = Join-Path $OutputFolder "ADML_Policy_Matches_${safeGpoName}_$timestamp.csv"
    $admlFileUsage | Select-Object GpoName, SettingScope, SettingName, State, Category, AdmlFile, AdmxFile | 
        Export-Csv -Path $detailsCsvPath -NoTypeInformation -ErrorAction SilentlyContinue
    Write-Host "  Policy matches details: $detailsCsvPath" -ForegroundColor White
}

# Export unmatched settings if any
if ($unmatchedSettings -and $unmatchedSettings.Count -gt 0) {
    $unmatchedCsvPath = Join-Path $OutputFolder "Unmatched_Settings_${safeGpoName}_$timestamp.csv"
    $unmatchedSettings | Select-Object GpoName, SettingScope, SettingName, State, Category | 
        Export-Csv -Path $unmatchedCsvPath -NoTypeInformation -ErrorAction SilentlyContinue
    Write-Host "  Unmatched settings: $unmatchedCsvPath" -ForegroundColor White
}

Write-Host "`nAnalysis complete!" -ForegroundColor Green
