<#
.SYNOPSIS
    Determines required ADMX and ADML files for Administrative Template settings in a GPO.
.PARAMETER GpoDisplayName
    Display name of the target GPO.
.PARAMETER AdmxStorePath
    Path to the PolicyDefinitions store (default: Central Store).
.PARAMETER Language
    Language-specific folder for ADML files (default: en-US).
.PARAMETER OutputFolder
    Folder where CSV output is saved (default: script directory).
.PARAMETER VerboseOutput
    Enables detailed match output for debugging.
.PARAMETER ExportSettingsReport
    Creates detailed report of all matched settings.
#>

param (
    [Parameter(Mandatory)]
    [string]$GpoDisplayName,

    [string]$AdmxStorePath = "\\$((Get-ADDomain).DNSRoot)\SYSVOL\$((Get-ADDomain).DNSRoot)\Policies\PolicyDefinitions",

    [string]$Language = "en-US",

    [string]$OutputFolder = "$PSScriptRoot",

    [switch]$VerboseOutput,

    [switch]$ExportSettingsReport
)

Import-Module GroupPolicy -ErrorAction Stop

# Get GPO info
try {
    $Gpo = Get-GPO -Name $GpoDisplayName -ErrorAction Stop
} catch {
    Write-Error "GPO '$GpoDisplayName' not found."
    exit 1
}

Write-Host "Analyzing GPO: $GpoDisplayName" -ForegroundColor Cyan
Write-Host "GPO ID: $($Gpo.Id)" -ForegroundColor Cyan

# Get GPO Report to identify configured settings
Write-Host "`nGenerating GPO report..." -ForegroundColor Yellow
try {
    [xml]$GpoReport = Get-GPOReport -Name $GpoDisplayName -ReportType Xml
} catch {
    Write-Error "Failed to generate GPO report."
    exit 1
}

# Function to extract Administrative Template settings from GPO XML report
function Get-AdministrativeTemplateSettings {
    param ([xml]$Report)
    
    $settings = @()
    
    # Navigate the GPO report structure directly without namespaces first
    # Computer Configuration
    if ($Report.GPO.Computer.ExtensionData) {
        foreach ($extension in $Report.GPO.Computer.ExtensionData) {
            if ($extension.Extension.Policy) {
                foreach ($policy in $extension.Extension.Policy) {
                    if ($policy.Name -and $policy.State) {
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
            
            # Check for RegistrySettings type extensions
            if ($extension.Extension.RegistrySettings) {
                foreach ($regSetting in $extension.Extension.RegistrySettings.Policy) {
                    if ($regSetting.Name -and $regSetting.State) {
                        $regKey = ""
                        $regValue = ""
                        
                        if ($regSetting.Properties) {
                            $regKey = $regSetting.Properties.Key
                            $regValue = $regSetting.Properties.Value
                        }
                        
                        $settings += [PSCustomObject]@{
                            Name = $regSetting.Name
                            State = $regSetting.State
                            Category = if ($regSetting.Category) { $regSetting.Category } else { "Unknown" }
                            Scope = "Computer"
                            RegistryKey = $regKey
                            ValueName = $regValue
                            Supported = if ($regSetting.Supported) { $regSetting.Supported } else { "" }
                        }
                    }
                }
            }
        }
    }
    
    # User Configuration
    if ($Report.GPO.User.ExtensionData) {
        foreach ($extension in $Report.GPO.User.ExtensionData) {
            if ($extension.Extension.Policy) {
                foreach ($policy in $extension.Extension.Policy) {
                    if ($policy.Name -and $policy.State) {
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
            
            # Check for RegistrySettings type extensions
            if ($extension.Extension.RegistrySettings) {
                foreach ($regSetting in $extension.Extension.RegistrySettings.Policy) {
                    if ($regSetting.Name -and $regSetting.State) {
                        $regKey = ""
                        $regValue = ""
                        
                        if ($regSetting.Properties) {
                            $regKey = $regSetting.Properties.Key
                            $regValue = $regSetting.Properties.Value
                        }
                        
                        $settings += [PSCustomObject]@{
                            Name = $regSetting.Name
                            State = $regSetting.State
                            Category = if ($regSetting.Category) { $regSetting.Category } else { "Unknown" }
                            Scope = "User"
                            RegistryKey = $regKey
                            ValueName = $regValue
                            Supported = if ($regSetting.Supported) { $regSetting.Supported } else { "" }
                        }
                    }
                }
            }
        }
    }
    
    # Remove duplicates and return
    return $settings | Sort-Object -Unique -Property Name, Scope | Where-Object { $_.State -ne "Not Configured" }
}

# Get Administrative Template settings from GPO report
$adminTemplateSettings = Get-AdministrativeTemplateSettings -Report $GpoReport
Write-Host "`nFound $($adminTemplateSettings.Count) Administrative Template settings in GPO report" -ForegroundColor Green

if ($VerboseOutput -and $adminTemplateSettings.Count -gt 0) {
    Write-Host "`nSample settings from GPO report:" -ForegroundColor Yellow
    $adminTemplateSettings | Select-Object -First 5 | ForEach-Object {
        Write-Host "  $($_.Scope): $($_.Name) = $($_.State)" -ForegroundColor Gray
        if ($_.Category) {
            Write-Host "    Category: $($_.Category)" -ForegroundColor DarkGray
        }
        if ($_.RegistryKey) {
            Write-Host "    Registry: $($_.RegistryKey)\$($_.ValueName)" -ForegroundColor DarkGray
        }
    }
}

# Parse registry.pol for additional validation
$Domain = (Get-ADDomain).DNSRoot
$GpoPath = "\\$Domain\SYSVOL\$Domain\Policies\{$($Gpo.Id)}"

function Parse-RegistryPol {
    param ([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        return @()
    }
    
    $data = [System.IO.File]::ReadAllBytes($FilePath)
    if ($data.Length -lt 0x10) { return @() }
    
    # Check for PReg signature
    $signature = [System.Text.Encoding]::ASCII.GetString($data, 0, 4)
    if ($signature -ne "PReg") {
        Write-Warning "Invalid registry.pol signature"
        return @()
    }
    
    $pointer = 8  # Skip PReg header and version
    $results = @()

    while ($pointer -lt $data.Length - 8) {
        try {
            # Read bracket [
            if ($data[$pointer] -ne 0x5B -or $data[$pointer + 1] -ne 0x00) {
                $pointer += 2
                continue
            }
            $pointer += 2
            
            # Read key
            $keyEnd = $pointer
            while ($keyEnd -lt $data.Length - 1 -and -not ($data[$keyEnd] -eq 0x00 -and $data[$keyEnd + 1] -eq 0x00)) {
                $keyEnd += 2
            }
            $keyLen = $keyEnd - $pointer
            if ($keyLen -gt 0) {
                $key = [System.Text.Encoding]::Unicode.GetString($data, $pointer, $keyLen)
            } else {
                $key = ""
            }
            $pointer = $keyEnd + 2
            
            # Skip semicolon
            if ($pointer -lt $data.Length - 1 -and $data[$pointer] -eq 0x3B) {
                $pointer += 2
            }
            
            # Read value name
            $valEnd = $pointer
            while ($valEnd -lt $data.Length - 1 -and -not ($data[$valEnd] -eq 0x00 -and $data[$valEnd + 1] -eq 0x00)) {
                $valEnd += 2
            }
            $valLen = $valEnd - $pointer
            if ($valLen -gt 0) {
                $val = [System.Text.Encoding]::Unicode.GetString($data, $pointer, $valLen)
            } else {
                $val = ""
            }
            $pointer = $valEnd + 2
            
            # Skip semicolon
            if ($pointer -lt $data.Length - 1 -and $data[$pointer] -eq 0x3B) {
                $pointer += 2
            }
            
            # Read type (4 bytes)
            if ($pointer + 4 -le $data.Length) {
                $type = [BitConverter]::ToUInt32($data, $pointer)
                $pointer += 4
            } else {
                break
            }
            
            # Skip semicolon
            if ($pointer -lt $data.Length - 1 -and $data[$pointer] -eq 0x3B) {
                $pointer += 2
            }
            
            # Read data size (4 bytes)
            if ($pointer + 4 -le $data.Length) {
                $dataSize = [BitConverter]::ToUInt32($data, $pointer)
                $pointer += 4
            } else {
                break
            }
            
            # Skip semicolon
            if ($pointer -lt $data.Length - 1 -and $data[$pointer] -eq 0x3B) {
                $pointer += 2
            }
            
            # Read data
            $dataValue = $null
            if ($dataSize -gt 0 -and ($pointer + $dataSize) -le $data.Length) {
                if ($type -eq 1) { # REG_SZ
                    $dataValue = [System.Text.Encoding]::Unicode.GetString($data, $pointer, [Math]::Min($dataSize, 1000))
                    $dataValue = $dataValue.TrimEnd([char]0)
                } elseif ($type -eq 4 -and $dataSize -ge 4) { # REG_DWORD
                    $dataValue = [BitConverter]::ToUInt32($data, $pointer)
                }
            }
            $pointer += $dataSize
            
            # Skip closing bracket ]
            while ($pointer -lt $data.Length - 1 -and -not ($data[$pointer] -eq 0x5D -and $data[$pointer + 1] -eq 0x00)) {
                $pointer += 2
            }
            if ($pointer -lt $data.Length - 1) {
                $pointer += 2
            }

            if ($key -and $val) {
                $results += [PSCustomObject]@{
                    RegistryKey = $key
                    ValueName = $val
                    ValueType = $type
                    ValueData = $dataValue
                    FullPath = "$key\$val"
                }
            }
        } catch {
            if ($VerboseOutput) {
                Write-Warning "Error parsing at position $pointer"
            }
            break
        }
    }

    return $results
}

# Get all registry entries from both computer and user policies
$allRegistryEntries = @()
$computerPolPath = Join-Path $GpoPath "Machine\registry.pol"
$userPolPath = Join-Path $GpoPath "User\registry.pol"

Write-Host "`nParsing registry.pol files..." -ForegroundColor Yellow
if (Test-Path $computerPolPath) {
    $compEntries = Parse-RegistryPol -FilePath $computerPolPath
    $allRegistryEntries += $compEntries | Add-Member -NotePropertyName "Scope" -NotePropertyValue "Computer" -PassThru
    Write-Host "  Found $($compEntries.Count) computer configuration entries"
}

if (Test-Path $userPolPath) {
    $userEntries = Parse-RegistryPol -FilePath $userPolPath
    $allRegistryEntries += $userEntries | Add-Member -NotePropertyName "Scope" -NotePropertyValue "User" -PassThru
    Write-Host "  Found $($userEntries.Count) user configuration entries"
}

Write-Host "  Total registry entries: $($allRegistryEntries.Count)"

if ($VerboseOutput -and $allRegistryEntries.Count -gt 0) {
    Write-Host "`nSample registry.pol entries:" -ForegroundColor Yellow
    $allRegistryEntries | Select-Object -First 5 | ForEach-Object {
        Write-Host "  $($_.RegistryKey)\$($_.ValueName) = $($_.ValueData)" -ForegroundColor Gray
    }
}

# If we found settings but no registry entries, provide additional diagnostics
if ($adminTemplateSettings.Count -gt 0 -and $allRegistryEntries.Count -eq 0) {
    Write-Host "`nNote: GPO has configured settings but no registry.pol entries found." -ForegroundColor Yellow
    Write-Host "This might indicate:" -ForegroundColor Yellow
    Write-Host "  - Settings are configured but not yet applied" -ForegroundColor Yellow
    Write-Host "  - Settings are preference items rather than policies" -ForegroundColor Yellow
    Write-Host "  - GPO might need to be refreshed" -ForegroundColor Yellow
}

# Function to match settings to ADMX files
function Find-AdmxMatches {
    param (
        [array]$Settings,
        [array]$RegistryEntries,
        [string]$AdmxPath
    )
    
    $matches = @()
    $admxFiles = Get-ChildItem -Path $AdmxPath -Filter *.admx -ErrorAction Stop
    
    Write-Host "`nScanning $($admxFiles.Count) ADMX files for matches..." -ForegroundColor Yellow
    $progress = 0
    
    # Create lookup table for faster matching
    $settingsLookup = @{}
    foreach ($setting in $Settings) {
        $settingsLookup[$setting.Name.ToLower()] = $setting
    }
    
    foreach ($admx in $admxFiles) {
        $progress++
        Write-Progress -Activity "Scanning ADMX files" -Status "$($admx.Name)" -PercentComplete (($progress / $admxFiles.Count) * 100)
        
        try {
            [xml]$xml = Get-Content -Path $admx.FullName -Raw -ErrorAction Stop
        } catch {
            continue
        }

        $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $ns.AddNamespace("ns", $xml.DocumentElement.NamespaceURI)
        
        # Get all policies in this ADMX
        $policies = $xml.SelectNodes("//ns:policy", $ns)
        
        foreach ($policy in $policies) {
            $policyName = $policy.name
            $policyDisplayName = $policy.displayName
            
            # Try to match by policy name first
            $matchedSetting = $null
            
            # Clean up policy names for matching
            $policyNameClean = $policyName.Trim()
            
            # Direct name match
            if ($settingsLookup.ContainsKey($policyNameClean.ToLower())) {
                $matchedSetting = $settingsLookup[$policyNameClean.ToLower()]
            }
            
            # Try without namespace prefix (some GPO reports include namespace)
            if (-not $matchedSetting) {
                $nameWithoutPrefix = $policyNameClean -replace '^[^:]+:', ''
                if ($settingsLookup.ContainsKey($nameWithoutPrefix.ToLower())) {
                    $matchedSetting = $settingsLookup[$nameWithoutPrefix.ToLower()]
                }
            }
            
            # Try matching by display name
            if (-not $matchedSetting -and $policyDisplayName) {
                # Remove string resource references
                $displayNameClean = $policyDisplayName -replace '^\$\(string\.', '' -replace '\)$', ''
                
                foreach ($setting in $Settings) {
                    # Various matching attempts
                    if ($setting.Name -ieq $displayNameClean -or 
                        $setting.Name -ieq $policyDisplayName -or
                        $setting.Name -ieq $policyNameClean -or
                        $setting.Name -like "*$policyNameClean*" -or
                        $policyNameClean -like "*$($setting.Name)*") {
                        $matchedSetting = $setting
                        break
                    }
                }
            }
            
            # Also check by registry path if available
            if (-not $matchedSetting) {
                # Get registry info from policy
                $policyKey = $null
                $policyValueName = $null
                
                # Check for key attribute on policy
                if ($policy.key) {
                    $policyKey = $policy.key
                }
                
                # Check enabledValue/disabledValue
                $enabledValue = $policy.SelectSingleNode(".//ns:enabledValue", $ns)
                $disabledValue = $policy.SelectSingleNode(".//ns:disabledValue", $ns)
                
                if ($enabledValue -and $enabledValue.ParentNode.key) {
                    $policyKey = $enabledValue.ParentNode.key
                    $policyValueName = $enabledValue.ParentNode.valueName
                } elseif ($disabledValue -and $disabledValue.ParentNode.key) {
                    $policyKey = $disabledValue.ParentNode.key
                    $policyValueName = $disabledValue.ParentNode.valueName
                }
                
                # Match against registry entries
                if ($policyKey -and $policyValueName) {
                    foreach ($regEntry in $RegistryEntries) {
                        if ($regEntry.RegistryKey -ieq $policyKey -and $regEntry.ValueName -ieq $policyValueName) {
                            # Found a match via registry
                            foreach ($setting in $Settings) {
                                if ($setting.RegistryKey -ieq $policyKey -or 
                                    ($setting.Scope -eq $regEntry.Scope -and $setting.State -ne "Not Configured")) {
                                    $matchedSetting = $setting
                                    break
                                }
                            }
                            if ($matchedSetting) { break }
                        }
                    }
                }
            }
            
            if ($matchedSetting) {
                $matches += [PSCustomObject]@{
                    AdmxFile = $admx.Name
                    PolicyName = $policyName
                    PolicyDisplayName = $policyDisplayName
                    SettingName = $matchedSetting.Name
                    State = $matchedSetting.State
                    Category = $matchedSetting.Category
                    Scope = $matchedSetting.Scope
                }
                
                if ($VerboseOutput) {
                    Write-Host "  Match found: $($admx.Name) -> $($matchedSetting.Name)" -ForegroundColor Green
                }
            }
        }
    }
    
    Write-Progress -Activity "Scanning ADMX files" -Completed
    return $matches
}

# Find matches
$admxMatches = Find-AdmxMatches -Settings $adminTemplateSettings -RegistryEntries $allRegistryEntries -AdmxPath $AdmxStorePath

# Group by ADMX file
$requiredAdmxFiles = $admxMatches | Group-Object AdmxFile | Select-Object -ExpandProperty Name | Sort-Object

# Build ADML list
$requiredAdmlFiles = @()
foreach ($admxFile in $requiredAdmxFiles) {
    $admlPath = Join-Path -Path "$AdmxStorePath\$Language" -ChildPath $admxFile.Replace('.admx', '.adml')
    if (Test-Path $admlPath) {
        $requiredAdmlFiles += Split-Path -Leaf $admlPath
    } else {
        $requiredAdmlFiles += "$($admxFile.Replace('.admx','.adml')) [MISSING]"
    }
}

# Display results
Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "ANALYSIS COMPLETE" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

if ($requiredAdmxFiles.Count -eq 0 -and $adminTemplateSettings.Count -gt 0) {
    Write-Host "`nNo ADMX matches found, but GPO has $($adminTemplateSettings.Count) configured settings." -ForegroundColor Yellow
    Write-Host "Attempting to identify ADMX files by policy names..." -ForegroundColor Yellow
    
    # Try to guess ADMX files based on category names
    $categories = $adminTemplateSettings.Category | Where-Object { $_ -and $_ -ne "Unknown" } | Sort-Object -Unique
    if ($categories) {
        Write-Host "`nPolicy categories found:" -ForegroundColor Cyan
        $categories | ForEach-Object { Write-Host "  - $_" }
        
        Write-Host "`nLikely ADMX files needed (based on categories):" -ForegroundColor Cyan
        foreach ($cat in $categories) {
            if ($cat -match "Windows Defender") { Write-Host "  - WindowsDefender.admx" }
            elseif ($cat -match "Windows Update") { Write-Host "  - WindowsUpdate.admx" }
            elseif ($cat -match "Windows Components") { Write-Host "  - Various Windows Components ADMX files" }
            elseif ($cat -match "System") { Write-Host "  - System-related ADMX files" }
        }
    }
}

Write-Host "`nRequired ADMX Files ($($requiredAdmxFiles.Count)):" -ForegroundColor Green
if ($requiredAdmxFiles.Count -gt 0) {
    $requiredAdmxFiles | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host "  None identified - see unmatched settings report" -ForegroundColor Yellow
}

Write-Host "`nRequired ADML Files ($Language) ($($requiredAdmlFiles.Count)):" -ForegroundColor Green
if ($requiredAdmlFiles.Count -gt 0) {
    $requiredAdmlFiles | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host "  None identified" -ForegroundColor Yellow
}

if ($admxMatches.Count -gt 0) {
    Write-Host "`nMatched Administrative Template Settings:" -ForegroundColor Yellow
    $admxMatches | Group-Object AdmxFile | ForEach-Object {
        Write-Host "  $($_.Name):" -ForegroundColor Cyan
        $_.Group | ForEach-Object {
            Write-Host "    - $($_.SettingName) [$($_.State)]" -ForegroundColor Gray
        }
    }
}

# Export results
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$baseFileName = $GpoDisplayName -replace '[^\w\s-]', ''

# Required files CSVs
$admxCsv = Join-Path $OutputFolder "Required_ADMX_${baseFileName}_$timestamp.csv"
$admlCsv = Join-Path $OutputFolder "Required_ADML_${baseFileName}_$timestamp.csv"

$requiredAdmxFiles | ForEach-Object { [PSCustomObject]@{FileName = $_} } | Export-Csv -Path $admxCsv -NoTypeInformation
$requiredAdmlFiles | ForEach-Object { [PSCustomObject]@{FileName = $_} } | Export-Csv -Path $admlCsv -NoTypeInformation

Write-Host "`nExported required files to:" -ForegroundColor Cyan
Write-Host "  $admxCsv"
Write-Host "  $admlCsv"

# Detailed settings report
if ($ExportSettingsReport -or $VerboseOutput) {
    $settingsCsv = Join-Path $OutputFolder "Settings_Details_${baseFileName}_$timestamp.csv"
    $admxMatches | Select-Object AdmxFile, PolicyName, SettingName, State, Category, Scope | 
        Export-Csv -Path $settingsCsv -NoTypeInformation
    Write-Host "  $settingsCsv"
}

# Report unmatched settings
$unmatchedSettings = $adminTemplateSettings | Where-Object {
    $setting = $_
    -not ($admxMatches | Where-Object { $_.SettingName -eq $setting.Name })
}

if ($unmatchedSettings.Count -gt 0) {
    Write-Host "`nWarning: $($unmatchedSettings.Count) Administrative Template settings could not be matched:" -ForegroundColor Yellow
    $unmatchedSettings | Select-Object -First 10 | ForEach-Object {
        Write-Host "  $($_.Name) [$($_.State)]" -ForegroundColor Yellow
    }
    if ($unmatchedSettings.Count -gt 10) {
        Write-Host "  ... and $($unmatchedSettings.Count - 10) more" -ForegroundColor Yellow
    }
    
    $unmatchedCsv = Join-Path $OutputFolder "Unmatched_Settings_${baseFileName}_$timestamp.csv"
    $unmatchedSettings | Export-Csv -Path $unmatchedCsv -NoTypeInformation
    Write-Host "`nExported unmatched settings to: $unmatchedCsv" -ForegroundColor Cyan
}

Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Administrative Template settings found: $($adminTemplateSettings.Count)"
Write-Host "  Registry.pol entries found: $($allRegistryEntries.Count)"
Write-Host "  Settings matched to ADMX: $($admxMatches.Count)"
Write-Host "  Settings unmatched: $($unmatchedSettings.Count)"
Write-Host "  Required ADMX files: $($requiredAdmxFiles.Count)"
Write-Host "===============================================" -ForegroundColor Cyan