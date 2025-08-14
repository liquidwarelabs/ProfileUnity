# Get-GPOAdmxDependencies.ps1
# Location: \Scripts\GPO-Analysis\
# Compatible with ProfileUnity PowerTools v3.0
# PowerShell 5.1+ Compatible

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

    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$AdmxStorePath,

    [ValidatePattern('^[a-z]{2}-[A-Z]{2}$')]
    [string]$Language = "en-US",

    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$OutputFolder = $PSScriptRoot,

    [switch]$ExportSettingsReport
)

# Initialize error handling
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

# Import required modules
try {
    Import-Module GroupPolicy -ErrorAction Stop
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Verbose "Required modules imported successfully"
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
        throw "Could not determine domain central store path. Please specify -AdmxStorePath"
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

# Function to extract Administrative Template settings from GPO XML report
function Get-AdministrativeTemplateSettings {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [xml]$Report
    )
    
    Write-Verbose "Extracting Administrative Template settings from GPO report"
    $settings = @()
    
    # Process Computer Configuration
    if ($Report.GPO.Computer.ExtensionData) {
        foreach ($extension in $Report.GPO.Computer.ExtensionData) {
            # Look for Administrative Templates extension
            if ($extension.Extension.Policy) {
                foreach ($policy in $extension.Extension.Policy) {
                    if ($policy.Name -and $policy.State -and $policy.State -ne "Not Configured") {
                        $settings += [PSCustomObject]@{
                            Name = $policy.Name
                            State = $policy.State
                            Category = if ($policy.Category) { $policy.Category } else { "Unknown" }
                            Scope = "Computer"
                            RegistryKey = ""
                            ValueName = ""
                            Supported = if ($policy.Supported) { $policy.Supported } else { "" }
                        }
                    }
                }
            }
            
            # Check for Registry-based policies
            if ($extension.Extension.RegistrySettings.Policy) {
                foreach ($regPolicy in $extension.Extension.RegistrySettings.Policy) {
                    if ($regPolicy.Name -and $regPolicy.State -and $regPolicy.State -ne "Not Configured") {
                        $regKey = ""
                        $regValue = ""
                        
                        if ($regPolicy.Properties) {
                            $regKey = $regPolicy.Properties.Key
                            $regValue = $regPolicy.Properties.Value
                        }
                        
                        $settings += [PSCustomObject]@{
                            Name = $regPolicy.Name
                            State = $regPolicy.State
                            Category = if ($regPolicy.Category) { $regPolicy.Category } else { "Registry" }
                            Scope = "Computer"
                            RegistryKey = $regKey
                            ValueName = $regValue
                            Supported = if ($regPolicy.Supported) { $regPolicy.Supported } else { "" }
                        }
                    }
                }
            }
        }
    }
    
    # Process User Configuration
    if ($Report.GPO.User.ExtensionData) {
        foreach ($extension in $Report.GPO.User.ExtensionData) {
            # Look for Administrative Templates extension
            if ($extension.Extension.Policy) {
                foreach ($policy in $extension.Extension.Policy) {
                    if ($policy.Name -and $policy.State -and $policy.State -ne "Not Configured") {
                        $settings += [PSCustomObject]@{
                            Name = $policy.Name
                            State = $policy.State
                            Category = if ($policy.Category) { $policy.Category } else { "Unknown" }
                            Scope = "User"
                            RegistryKey = ""
                            ValueName = ""
                            Supported = if ($policy.Supported) { $policy.Supported } else { "" }
                        }
                    }
                }
            }
            
            # Check for Registry-based policies
            if ($extension.Extension.RegistrySettings.Policy) {
                foreach ($regPolicy in $extension.Extension.RegistrySettings.Policy) {
                    if ($regPolicy.Name -and $regPolicy.State -and $regPolicy.State -ne "Not Configured") {
                        $regKey = ""
                        $regValue = ""
                        
                        if ($regPolicy.Properties) {
                            $regKey = $regPolicy.Properties.Key
                            $regValue = $regPolicy.Properties.Value
                        }
                        
                        $settings += [PSCustomObject]@{
                            Name = $regPolicy.Name
                            State = $regPolicy.State
                            Category = if ($regPolicy.Category) { $regPolicy.Category } else { "Registry" }
                            Scope = "User"
                            RegistryKey = $regKey
                            ValueName = $regValue
                            Supported = if ($regPolicy.Supported) { $regPolicy.Supported } else { "" }
                        }
                    }
                }
            }
        }
    }
    
    # Remove duplicates and return configured settings only
    $uniqueSettings = $settings | Sort-Object -Property Name, Scope -Unique
    Write-Verbose "Found $($uniqueSettings.Count) configured Administrative Template settings"
    
    return $uniqueSettings
}

# Function to parse registry.pol for validation
function Get-RegistryPolEntries {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$FilePath,
        
        [Parameter(Mandatory)]
        [string]$Scope
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-Verbose "Registry.pol file not found: $FilePath"
        return @()
    }
    
    Write-Verbose "Parsing registry.pol file: $FilePath"
    
    try {
        $data = [System.IO.File]::ReadAllBytes($FilePath)
        if ($data.Length -lt 16) {
            Write-Verbose "Registry.pol file too small: $FilePath"
            return @()
        }
        
        # Verify PReg signature
        $signature = [System.Text.Encoding]::ASCII.GetString($data, 0, 4)
        if ($signature -ne "PReg") {
            Write-Warning "Invalid registry.pol signature in: $FilePath"
            return @()
        }
        
        $pointer = 8  # Skip PReg header and version
        $results = @()

        while ($pointer -lt ($data.Length - 8)) {
            try {
                # Read opening bracket [
                if ($data[$pointer] -ne 0x5B -or $data[$pointer + 1] -ne 0x00) {
                    $pointer += 2
                    continue
                }
                $pointer += 2
                
                # Read registry key
                $keyEnd = $pointer
                while ($keyEnd -lt ($data.Length - 1) -and 
                       -not ($data[$keyEnd] -eq 0x00 -and $data[$keyEnd + 1] -eq 0x00)) {
                    $keyEnd += 2
                }
                
                $keyLength = $keyEnd - $pointer
                $registryKey = if ($keyLength -gt 0) {
                    [System.Text.Encoding]::Unicode.GetString($data, $pointer, $keyLength)
                } else {
                    ""
                }
                $pointer = $keyEnd + 2
                
                # Skip semicolon separator
                if ($pointer -lt ($data.Length - 1) -and $data[$pointer] -eq 0x3B) {
                    $pointer += 2
                }
                
                # Read value name
                $valueEnd = $pointer
                while ($valueEnd -lt ($data.Length - 1) -and 
                       -not ($data[$valueEnd] -eq 0x00 -and $data[$valueEnd + 1] -eq 0x00)) {
                    $valueEnd += 2
                }
                
                $valueLength = $valueEnd - $pointer
                $valueName = if ($valueLength -gt 0) {
                    [System.Text.Encoding]::Unicode.GetString($data, $pointer, $valueLength)
                } else {
                    ""
                }
                $pointer = $valueEnd + 2
                
                # Skip semicolon separator
                if ($pointer -lt ($data.Length - 1) -and $data[$pointer] -eq 0x3B) {
                    $pointer += 2
                }
                
                # Read value type (4 bytes)
                $valueType = 0
                if ($pointer + 4 -le $data.Length) {
                    $valueType = [BitConverter]::ToUInt32($data, $pointer)
                    $pointer += 4
                } else {
                    break
                }
                
                # Skip semicolon separator
                if ($pointer -lt ($data.Length - 1) -and $data[$pointer] -eq 0x3B) {
                    $pointer += 2
                }
                
                # Read data size (4 bytes)
                $dataSize = 0
                if ($pointer + 4 -le $data.Length) {
                    $dataSize = [BitConverter]::ToUInt32($data, $pointer)
                    $pointer += 4
                } else {
                    break
                }
                
                # Skip semicolon separator
                if ($pointer -lt ($data.Length - 1) -and $data[$pointer] -eq 0x3B) {
                    $pointer += 2
                }
                
                # Read value data
                $valueData = $null
                if ($dataSize -gt 0 -and ($pointer + $dataSize) -le $data.Length) {
                    switch ($valueType) {
                        1 { # REG_SZ
                            $maxLen = [Math]::Min($dataSize, 1000)
                            $valueData = [System.Text.Encoding]::Unicode.GetString($data, $pointer, $maxLen)
                            $valueData = $valueData.TrimEnd([char]0)
                        }
                        4 { # REG_DWORD
                            if ($dataSize -ge 4) {
                                $valueData = [BitConverter]::ToUInt32($data, $pointer)
                            }
                        }
                        default {
                            $valueData = "<binary data>"
                        }
                    }
                }
                $pointer += $dataSize
                
                # Skip to closing bracket ]
                while ($pointer -lt ($data.Length - 1) -and 
                       -not ($data[$pointer] -eq 0x5D -and $data[$pointer + 1] -eq 0x00)) {
                    $pointer += 2
                }
                if ($pointer -lt ($data.Length - 1)) {
                    $pointer += 2
                }

                if ($registryKey -and $valueName) {
                    $results += [PSCustomObject]@{
                        RegistryKey = $registryKey
                        ValueName = $valueName
                        ValueType = $valueType
                        ValueData = $valueData
                        FullPath = "$registryKey\$valueName"
                        Scope = $Scope
                    }
                }
            } catch {
                Write-Verbose "Error parsing registry entry at position $pointer`: $($_.Exception.Message)"
                break
            }
        }

        Write-Verbose "Successfully parsed $($results.Count) registry entries from $FilePath"
        return $results
        
    } catch {
        Write-Warning "Failed to parse registry.pol file '$FilePath': $($_.Exception.Message)"
        return @()
    }
}

# Function to match settings to ADMX files
function Find-AdmxMatches {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [array]$Settings,
        
        [Parameter(Mandatory)]
        [array]$RegistryEntries,
        
        [Parameter(Mandatory)]
        [string]$AdmxPath
    )
    
    Write-Verbose "Finding ADMX matches for $($Settings.Count) settings"
    
    try {
        $admxFiles = Get-ChildItem -Path $AdmxPath -Filter "*.admx" -ErrorAction Stop
        Write-Host "Scanning $($admxFiles.Count) ADMX files for policy matches..." -ForegroundColor Yellow
        
        $matches = @()
        $processedCount = 0
        
        # Create lookup tables for faster matching
        $settingsLookup = @{}
        foreach ($setting in $Settings) {
            $key = $setting.Name.ToLower()
            if (-not $settingsLookup.ContainsKey($key)) {
                $settingsLookup[$key] = @()
            }
            $settingsLookup[$key] += $setting
        }
        
        foreach ($admxFile in $admxFiles) {
            $processedCount++
            Write-Progress -Activity "Scanning ADMX Files" -Status $admxFile.Name -PercentComplete (($processedCount / $admxFiles.Count) * 100)
            
            try {
                [xml]$xml = Get-Content -Path $admxFile.FullName -Raw -ErrorAction Stop
                $namespaceManager = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
                $namespaceManager.AddNamespace("ns", $xml.DocumentElement.NamespaceURI)
                
                # Get all policies in this ADMX
                $policies = $xml.SelectNodes("//ns:policy", $namespaceManager)
                
                foreach ($policy in $policies) {
                    $policyName = $policy.name
                    $policyDisplayName = $policy.displayName
                    
                    # Try multiple matching strategies
                    $matchedSettings = @()
                    
                    # Strategy 1: Direct name match
                    if ($settingsLookup.ContainsKey($policyName.ToLower())) {
                        $matchedSettings += $settingsLookup[$policyName.ToLower()]
                    }
                    
                    # Strategy 2: Match without namespace prefix
                    $nameWithoutPrefix = $policyName -replace '^[^:]+:', ''
                    if ($settingsLookup.ContainsKey($nameWithoutPrefix.ToLower())) {
                        $matchedSettings += $settingsLookup[$nameWithoutPrefix.ToLower()]
                    }
                    
                    # Strategy 3: Display name matching (if available)
                    if (-not $matchedSettings -and $policyDisplayName) {
                        $displayNameClean = $policyDisplayName -replace '^\$\(string\.', '' -replace '\)$', ''
                        
                        foreach ($setting in $Settings) {
                            if ($setting.Name -ieq $displayNameClean -or 
                                $setting.Name -ieq $policyDisplayName -or
                                $setting.Name -like "*$displayNameClean*" -or
                                $displayNameClean -like "*$($setting.Name)*") {
                                $matchedSettings += $setting
                            }
                        }
                    }
                    
                    # Strategy 4: Registry-based matching
                    if (-not $matchedSettings) {
                        $policyKey = $policy.key
                        $policyValueName = $policy.valueName
                        
                        if ($policyKey -and $policyValueName) {
                            foreach ($regEntry in $RegistryEntries) {
                                if ($regEntry.RegistryKey -ieq $policyKey -and $regEntry.ValueName -ieq $policyValueName) {
                                    # Found registry match, look for corresponding setting
                                    foreach ($setting in $Settings) {
                                        if (($setting.RegistryKey -ieq $policyKey) -or 
                                            ($setting.Scope -eq $regEntry.Scope)) {
                                            $matchedSettings += $setting
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    # Add unique matches
                    foreach ($matchedSetting in ($matchedSettings | Sort-Object -Property Name -Unique)) {
                        $matches += [PSCustomObject]@{
                            AdmxFile = $admxFile.Name
                            PolicyName = $policyName
                            PolicyDisplayName = $policyDisplayName
                            SettingName = $matchedSetting.Name
                            State = $matchedSetting.State
                            Category = $matchedSetting.Category
                            Scope = $matchedSetting.Scope
                            MatchMethod = "Name/Registry"
                        }
                        
                        Write-Verbose "Match found: $($admxFile.Name) -> $($matchedSetting.Name)"
                    }
                }
            } catch {
                Write-Verbose "Error processing ADMX file '$($admxFile.Name)': $($_.Exception.Message)"
                continue
            }
        }
        
        Write-Progress -Activity "Scanning ADMX Files" -Completed
        Write-Verbose "Found $($matches.Count) policy matches across ADMX files"
        
        return $matches
        
    } catch {
        throw "Failed to scan ADMX files: $($_.Exception.Message)"
    }
}

# Main processing
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "GPO ADMX DEPENDENCY ANALYSIS" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "GPO: $GpoDisplayName" -ForegroundColor Yellow
Write-Host "ADMX Store: $AdmxStorePath" -ForegroundColor Yellow
Write-Host "Language: $Language" -ForegroundColor Yellow

# Generate GPO XML report
Write-Host "`nGenerating GPO report..." -ForegroundColor Yellow
try {
    [xml]$gpoReport = Get-GPOReport -Name $GpoDisplayName -ReportType Xml -ErrorAction Stop
    Write-Host "GPO report generated successfully" -ForegroundColor Green
} catch {
    throw "Failed to generate GPO report: $($_.Exception.Message)"
}

# Extract Administrative Template settings
Write-Host "`nExtracting Administrative Template settings..." -ForegroundColor Yellow
$adminTemplateSettings = Get-AdministrativeTemplateSettings -Report $gpoReport
Write-Host "Found $($adminTemplateSettings.Count) configured Administrative Template settings" -ForegroundColor Green

if ($adminTemplateSettings.Count -eq 0) {
    Write-Warning "No configured Administrative Template settings found in GPO"
    Write-Host "This GPO might not use Administrative Templates or all settings are 'Not Configured'" -ForegroundColor Yellow
    exit 0
}

# Parse registry.pol files for additional validation
$domain = (Get-ADDomain).DNSRoot
$gpoPath = "\\$domain\SYSVOL\$domain\Policies\{$($gpo.Id)}"
$computerPolPath = Join-Path $gpoPath "Machine\registry.pol"
$userPolPath = Join-Path $gpoPath "User\registry.pol"

Write-Host "`nAnalyzing registry.pol files..." -ForegroundColor Yellow
$allRegistryEntries = @()

if (Test-Path $computerPolPath) {
    $computerEntries = Get-RegistryPolEntries -FilePath $computerPolPath -Scope "Computer"
    $allRegistryEntries += $computerEntries
    Write-Host "Computer registry entries: $($computerEntries.Count)" -ForegroundColor Green
}

if (Test-Path $userPolPath) {
    $userEntries = Get-RegistryPolEntries -FilePath $userPolPath -Scope "User"
    $allRegistryEntries += $userEntries
    Write-Host "User registry entries: $($userEntries.Count)" -ForegroundColor Green
}

Write-Host "Total registry entries: $($allRegistryEntries.Count)" -ForegroundColor Cyan

# Find ADMX matches
Write-Host "`nMatching settings to ADMX templates..." -ForegroundColor Yellow
$admxMatches = Find-AdmxMatches -Settings $adminTemplateSettings -RegistryEntries $allRegistryEntries -AdmxPath $AdmxStorePath

# Generate required file lists
$requiredAdmxFiles = @()
$requiredAdmlFiles = @()

if ($admxMatches.Count -gt 0) {
    $uniqueAdmxFiles = $admxMatches | Select-Object -ExpandProperty AdmxFile -Unique | Sort-Object
    
    foreach ($admxFile in $uniqueAdmxFiles) {
        $requiredAdmxFiles += $admxFile
        
        # Check for corresponding ADML file
        $admlFile = $admxFile -replace '\.admx$', '.adml'
        $admlPath = Join-Path (Join-Path $AdmxStorePath $Language) $admlFile
        
        if (Test-Path $admlPath) {
            $requiredAdmlFiles += $admlFile
        } else {
            $requiredAdmlFiles += "$admlFile [MISSING]"
        }
    }
}

# Display results
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "ANALYSIS RESULTS" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan

Write-Host "`nRequired ADMX Files ($($requiredAdmxFiles.Count)):" -ForegroundColor Green
if ($requiredAdmxFiles.Count -gt 0) {
    foreach ($file in $requiredAdmxFiles) {
        Write-Host "  - $file" -ForegroundColor White
    }
} else {
    Write-Host "  None identified" -ForegroundColor Yellow
}

Write-Host "`nRequired ADML Files ($Language) ($($requiredAdmlFiles.Count)):" -ForegroundColor Green
if ($requiredAdmlFiles.Count -gt 0) {
    foreach ($file in $requiredAdmlFiles) {
        if ($file -like "*[MISSING]") {
            Write-Host "  - $file" -ForegroundColor Red
        } else {
            Write-Host "  - $file" -ForegroundColor White
        }
    }
} else {
    Write-Host "  None identified" -ForegroundColor Yellow
}

# Show matched settings summary
if ($admxMatches.Count -gt 0) {
    Write-Host "`nMatched Settings by ADMX File:" -ForegroundColor Yellow
    $matchedGroups = $admxMatches | Group-Object -Property AdmxFile
    
    foreach ($group in $matchedGroups) {
        Write-Host "  $($group.Name):" -ForegroundColor Cyan
        foreach ($match in $group.Group) {
            Write-Host "    - $($match.SettingName) [$($match.State)] ($($match.Scope))" -ForegroundColor Gray
        }
    }
}

# Identify unmatched settings
$unmatchedSettings = $adminTemplateSettings | Where-Object {
    $setting = $_
    -not ($admxMatches | Where-Object { $_.SettingName -eq $setting.Name })
}

if ($unmatchedSettings.Count -gt 0) {
    Write-Host "`nUnmatched Settings ($($unmatchedSettings.Count)):" -ForegroundColor Red
    foreach ($setting in ($unmatchedSettings | Select-Object -First 10)) {
        Write-Host "  - $($setting.Name) [$($setting.State)] ($($setting.Scope))" -ForegroundColor Yellow
        if ($setting.Category) {
            Write-Host "    Category: $($setting.Category)" -ForegroundColor Gray
        }
    }
    if ($unmatchedSettings.Count -gt 10) {
        Write-Host "  ... and $($unmatchedSettings.Count - 10) more" -ForegroundColor Yellow
    }
}

# Export results to files
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$safeGpoName = $GpoDisplayName -replace '[^\w\s-]', '' -replace '\s+', '_'

# Export required ADMX files
$admxCsvPath = Join-Path $OutputFolder "Required_ADMX_${safeGpoName}_$timestamp.csv"
$requiredAdmxFiles | ForEach-Object { 
    [PSCustomObject]@{
        FileName = $_
        FileType = "ADMX"
        Status = if ($_ -like "*[MISSING]") { "Missing" } else { "Available" }
    }
} | Export-Csv -Path $admxCsvPath -NoTypeInformation -ErrorAction SilentlyContinue

# Export required ADML files
$admlCsvPath = Join-Path $OutputFolder "Required_ADML_${safeGpoName}_$timestamp.csv"
$requiredAdmlFiles | ForEach-Object { 
    [PSCustomObject]@{
        FileName = $_
        FileType = "ADML"
        Language = $Language
        Status = if ($_ -like "*[MISSING]") { "Missing" } else { "Available" }
    }
} | Export-Csv -Path $admlCsvPath -NoTypeInformation -ErrorAction SilentlyContinue

Write-Host "`nFiles exported:" -ForegroundColor Cyan
Write-Host "  ADMX list: $admxCsvPath" -ForegroundColor White
Write-Host "  ADML list: $admlCsvPath" -ForegroundColor White

# Export detailed settings report if requested
if ($ExportSettingsReport -and $admxMatches.Count -gt 0) {
    $detailsCsvPath = Join-Path $OutputFolder "ADMX_Settings_Details_${safeGpoName}_$timestamp.csv"
    $admxMatches | Select-Object AdmxFile, PolicyName, SettingName, State, Category, Scope, MatchMethod | 
        Export-Csv -Path $detailsCsvPath -NoTypeInformation -ErrorAction SilentlyContinue
    Write-Host "  Settings details: $detailsCsvPath" -ForegroundColor White
}

# Export unmatched settings if any
if ($unmatchedSettings.Count -gt 0) {
    $unmatchedCsvPath = Join-Path $OutputFolder "Unmatched_Settings_${safeGpoName}_$timestamp.csv"
    $unmatchedSettings | Select-Object Name, State, Category, Scope, RegistryKey, ValueName | 
        Export-Csv -Path $unmatchedCsvPath -NoTypeInformation -ErrorAction SilentlyContinue
    Write-Host "  Unmatched settings: $unmatchedCsvPath" -ForegroundColor White
}

# Final summary
Write-Host "`n" + ("=" * 70) -ForegroundColor Green
Write-Host "ANALYSIS COMPLETE" -ForegroundColor Green
Write-Host ("=" * 70) -ForegroundColor Green
Write-Host "Administrative Template settings: $($adminTemplateSettings.Count)" -ForegroundColor White
Write-Host "Registry entries found: $($allRegistryEntries.Count)" -ForegroundColor White
Write-Host "Settings matched to ADMX: $($admxMatches.Count)" -ForegroundColor White
Write-Host "Unmatched settings: $($unmatchedSettings.Count)" -ForegroundColor White
Write-Host "Required ADMX files: $($requiredAdmxFiles.Count)" -ForegroundColor White
Write-Host "Required ADML files: $($requiredAdmlFiles.Count)" -ForegroundColor White

if ($requiredAdmxFiles.Count -eq 0 -and $adminTemplateSettings.Count -gt 0) {
    Write-Host "`nNote: Settings found but no ADMX matches identified." -ForegroundColor Yellow
    Write-Host "This may indicate custom templates or complex policy configurations." -ForegroundColor Yellow
}

# Script reference
Write-Verbose "Script: Get-GPOAdmxDependencies.ps1"
Write-Verbose "Location: \Scripts\GPO-Analysis\"
Write-Verbose "Compatible with: ProfileUnity PowerTools v3.0"