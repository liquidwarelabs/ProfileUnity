<#
.SYNOPSIS
    Adds ADMX rules based on registry entries found in GPO
.DESCRIPTION
    Parses GPO registry.pol files and matches them to ADMX files, only adding those with matches
.PARAMETER GpoDisplayName
    Display name of the GPO to import
.PARAMETER ConfigName
    ProfileUnity configuration name to update
.PARAMETER ProfileUnityModule
    Path to ProfileUnity PowerShell module (required)
.PARAMETER PolicyDefinitionsPath
    Path to PolicyDefinitions folder (defaults to domain central store)
.PARAMETER Language
    Language folder for ADML files (default: en-US)
.PARAMETER SkipProblematicAdmx
    Skip known problematic ADMX files (default: false)
.PARAMETER ProblematicAdmxList
    List of ADMX files to skip due to known issues
.EXAMPLE
    .\Add-AdmxByRegistry.ps1 -GpoDisplayName "Security Settings" -ConfigName "Production" -ProfileUnityModule ".\ProfileUnity-PowerTools.psm1"
.EXAMPLE
    .\Add-AdmxByRegistry.ps1 -GpoDisplayName "Chrome Policy" -ConfigName "Browsers" -ProfileUnityModule "C:\Scripts\ProfileUnity-PowerTools.psm1" -PolicyDefinitionsPath "C:\PolicyDefinitions"
#>

param(
    [Parameter(Mandatory)]
    [string]$GpoDisplayName,
    
    [Parameter(Mandatory)]
    [string]$ConfigName,
    
    [Parameter(Mandatory)]
    [string]$ProfileUnityModule,
    
    [string]$PolicyDefinitionsPath,
    
    [string]$Language = "en-US",
    
    [switch]$SkipProblematicAdmx = $false,
    
    [string[]]$ProblematicAdmxList = @("UserExperienceVirtualization.admx"),
    
    [switch]$VerboseOutput,
    
    [switch]$WhatIf
)

# Set default PolicyDefinitions path if not provided
if (-not $PolicyDefinitionsPath) {
    try {
        $domain = (Get-ADDomain).DNSRoot
        $PolicyDefinitionsPath = "\\$domain\SYSVOL\$domain\Policies\PolicyDefinitions"
        Write-Host "Using domain central store: $PolicyDefinitionsPath" -ForegroundColor Gray
    } catch {
        Write-Error "Could not determine domain. Please specify -PolicyDefinitionsPath"
        exit 1
    }
}

# Function to parse registry.pol
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
            
            # Skip the rest of the entry to get to the next one
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
                }
            }
        } catch {
            break
        }
    }

    return $results
}

# Function to find ADMX files that match registry entries
function Find-MatchingAdmx {
    param(
        [array]$RegistryEntries,
        [string]$AdmxPath
    )
    
    $matches = @{}
    $admxFiles = Get-ChildItem -Path $AdmxPath -Filter "*.admx" -ErrorAction Stop
    
    Write-Host "Scanning $($admxFiles.Count) ADMX files for registry matches..." -ForegroundColor Yellow
    
    foreach ($admxFile in $admxFiles) {
        try {
            [xml]$admx = Get-Content -Path $admxFile.FullName -Raw
            $ns = New-Object System.Xml.XmlNamespaceManager($admx.NameTable)
            $ns.AddNamespace("ns", $admx.DocumentElement.NamespaceURI)
            
            $policies = $admx.SelectNodes("//ns:policy", $ns)
            
            foreach ($policy in $policies) {
                $policyKey = $policy.key
                $policyValueName = $policy.valueName
                
                foreach ($regEntry in $RegistryEntries) {
                    # More flexible matching - handle case differences and partial matches
                    $keyMatch = $false
                    if ($policyKey) {
                        $keyMatch = $regEntry.RegistryKey -like "*$policyKey*" -or $policyKey -like "*$($regEntry.RegistryKey)*"
                    }
                    
                    if ($keyMatch -and $regEntry.ValueName -eq $policyValueName) {
                        if (-not $matches.ContainsKey($admxFile.Name)) {
                            $matches[$admxFile.Name] = @{
                                FileName = $admxFile.Name
                                FullPath = $admxFile.FullName
                                Matches = @()
                            }
                        }
                        $matches[$admxFile.Name].Matches += [PSCustomObject]@{
                            PolicyName = $policy.name
                            RegistryKey = $regEntry.RegistryKey
                            ValueName = $regEntry.ValueName
                        }
                        if ($VerboseOutput) {
                            Write-Host "  Match: $($admxFile.Name) -> $($policy.name)" -ForegroundColor DarkGray
                        }
                    }
                }
            }
        } catch {
            if ($VerboseOutput) {
                Write-Warning "Error parsing $($admxFile.Name): $_"
            }
            continue
        }
    }
    
    return $matches.Values
}

# Main script
Write-Host "`n=== ADMX Import by Registry Matching ===" -ForegroundColor Cyan
Write-Host "GPO: $GpoDisplayName" -ForegroundColor Yellow
Write-Host "Target Config: $ConfigName" -ForegroundColor Yellow
Write-Host "PolicyDefinitions: $PolicyDefinitionsPath" -ForegroundColor Yellow

# Load ProfileUnity module
if (Test-Path $ProfileUnityModule) {
    Import-Module $ProfileUnityModule -Force
    Write-Host "Loaded ProfileUnity module from: $ProfileUnityModule" -ForegroundColor Green
} else {
    Write-Error "ProfileUnity module not found at: $ProfileUnityModule"
    exit 1
}

# Connect if needed
if (!(Test-ProfileUnityConnection)) {
    Write-Host "`nConnecting to ProfileUnity..." -ForegroundColor Yellow
    Connect-ProfileUnityServer | Out-Null
}

$servername = if ($global:servername) { $global:servername } else { $script:ModuleConfig.ServerName }
if (-not $servername) {
    $servername = Read-Host "Enter ProfileUnity server name"
}

# Load configuration
Write-Host "`nLoading configuration: $ConfigName" -ForegroundColor Yellow
try {
    Edit-ProUConfig -Name $ConfigName -Quiet | Out-Null
} catch {
    Write-Error "Failed to load configuration: $_"
    exit 1
}

# Get GPO
try {
    $gpo = Get-GPO -Name $GpoDisplayName -ErrorAction Stop
    $gpoId = $gpo.Id.ToString().ToUpper()
    Write-Host "GPO ID: $gpoId" -ForegroundColor Green
    Write-Host "GPO ID Format: {$gpoId}" -ForegroundColor DarkGray  # Show with brackets to see exact format
} catch {
    Write-Error "Failed to find GPO: $_"
    exit 1
}

# Parse registry.pol files
$Domain = (Get-ADDomain).DNSRoot
$GpoPath = "\\$Domain\SYSVOL\$Domain\Policies\{$gpoId}"
$computerPolPath = Join-Path $GpoPath "Machine\registry.pol"
$userPolPath = Join-Path $GpoPath "User\registry.pol"

Write-Host "`nParsing registry.pol files..." -ForegroundColor Yellow
$allRegistryEntries = @()

if (Test-Path $computerPolPath) {
    $compEntries = Parse-RegistryPol -FilePath $computerPolPath
    Write-Host "  Computer entries: $($compEntries.Count)" -ForegroundColor Green
    $allRegistryEntries += $compEntries
}

if (Test-Path $userPolPath) {
    $userEntries = Parse-RegistryPol -FilePath $userPolPath
    Write-Host "  User entries: $($userEntries.Count)" -ForegroundColor Green
    $allRegistryEntries += $userEntries
}

if ($allRegistryEntries.Count -eq 0) {
    Write-Warning "No registry entries found in GPO. The GPO might not have any Administrative Template settings."
    exit 0
}

# Find matching ADMX files
Write-Host "`nSearching for matching ADMX files..." -ForegroundColor Yellow
$matchedAdmx = Find-MatchingAdmx -RegistryEntries $allRegistryEntries -AdmxPath $PolicyDefinitionsPath

Write-Host "`nMatched ADMX files:" -ForegroundColor Green
if ($matchedAdmx.Count -eq 0) {
    Write-Warning "No ADMX files matched the registry entries in this GPO"
    exit 0
}

$matchedAdmx | ForEach-Object {
    Write-Host "  - $($_.FileName) ($($_.Matches.Count) matching policies)" -ForegroundColor Cyan
    if ($VerboseOutput) {
        $_.Matches | ForEach-Object {
            Write-Host "    Policy: $($_.PolicyName)" -ForegroundColor DarkGray
        }
    }
}

# Initialize AdministrativeTemplates if needed
if ($null -eq $global:CurrentConfig.AdministrativeTemplates) {
    Write-Host "`nInitializing AdministrativeTemplates array" -ForegroundColor Yellow
    $global:CurrentConfig | Add-Member -NotePropertyName AdministrativeTemplates -NotePropertyValue @() -Force
}

# Get starting sequence
$sequence = 1
if ($global:CurrentConfig.AdministrativeTemplates.Count -gt 0) {
    $maxSeq = ($global:CurrentConfig.AdministrativeTemplates | Measure-Object -Property Sequence -Maximum).Maximum
    if ($maxSeq) { $sequence = $maxSeq + 1 }
}

Write-Host "`nStarting sequence: $sequence" -ForegroundColor Cyan

# Add each matched ADMX file
$addedCount = 0
$skippedCount = 0

foreach ($admxFile in $matchedAdmx) {
    # Check if should skip problematic files
    if ($SkipProblematicAdmx -and $ProblematicAdmxList -contains $admxFile.FileName) {
        Write-Warning "Skipping $($admxFile.FileName) - known to cause issues"
        $skippedCount++
        continue
    }
    
    Write-Host "`nProcessing $($admxFile.FileName)..." -ForegroundColor Yellow
    
    # Build full paths
    $admxPath = Join-Path $PolicyDefinitionsPath $admxFile.FileName
    $admlFileName = $admxFile.FileName -replace '\.admx$', '.adml'
    $admlPath = Join-Path (Join-Path $PolicyDefinitionsPath $Language) $admlFileName
    
    # Verify files exist
    if (!(Test-Path $admxPath)) {
        Write-Warning "ADMX file not found: $admxPath"
        continue
    }
    
    if (!(Test-Path $admlPath)) {
        Write-Warning "ADML file not found: $admlPath"
        # Don't continue - some ADMX files might work without ADML
    }
    
    if ($VerboseOutput) {
        Write-Host "  ADMX Path: $admxPath" -ForegroundColor DarkGray
        Write-Host "  ADML Path: $admlPath" -ForegroundColor DarkGray
    }
    
    if ($WhatIf) {
        Write-Host "  What-If: Would add $($admxFile.FileName) with sequence $sequence" -ForegroundColor Cyan
        $addedCount++
        $sequence++
        continue
    }
    
    # Build URL for ProfileUnity API
    $URL = "https://'$servername':8000/api/server/admxadmlfiles?admx=$admxPath&adml=$admlPath&gpoid=$gpoId"
    $URL = $URL -replace "'", ""
    
    try {
        Write-Host "  Querying ProfileUnity..." -ForegroundColor Gray
        if ($VerboseOutput) {
            Write-Host "  URL: $URL" -ForegroundColor DarkGray  # Debug output
        }
        
        $response = Invoke-WebRequest "$URL" -WebSession $global:session -UseBasicParsing
        $responseData = $response.Content | ConvertFrom-Json
        $ADMxRule = $responseData.tag
        
        if ($ADMxRule) {
            # Clean the ADMX data to fix parsing issues
            Write-Host "  Cleaning ADMX data..." -ForegroundColor Gray
            
            # Function to clean text
            function Clean-Text {
                param([string]$Text)
                if ([string]::IsNullOrEmpty($Text)) { return $Text }
                
                # Replace problematic characters
                $Text = $Text -replace '["""]', '"'
                $Text = $Text -replace "[''']", "'"
                $Text = $Text -replace '[–—]', '-'
                $Text = $Text -replace '•', '*'
                $Text = $Text -replace '…', '...'
                
                return $Text
            }
            
            # Clean HelpText in all settings
            if ($ADMxRule.Categories) {
                foreach ($category in $ADMxRule.Categories) {
                    if ($category.Children) {
                        foreach ($child in $category.Children) {
                            if ($child.Children) {
                                foreach ($subchild in $child.Children) {
                                    if ($subchild.Settings) {
                                        foreach ($setting in $subchild.Settings) {
                                            if ($setting.HelpText) {
                                                $setting.HelpText = Clean-Text -Text $setting.HelpText
                                            }
                                            if ($setting.DisplayName) {
                                                $setting.DisplayName = Clean-Text -Text $setting.DisplayName
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            # Also clean TemplateSettingStates if present
            if ($ADMxRule.TemplateSettingStates) {
                foreach ($state in $ADMxRule.TemplateSettingStates) {
                    if ($state.HelpText) {
                        $state.HelpText = Clean-Text -Text $state.HelpText
                    }
                }
            }
            
            $ADMxRule.Sequence = $sequence
            $ADMxRule.Description = "Imported from GPO: $GpoDisplayName"
            $global:CurrentConfig.AdministrativeTemplates += @($ADMxRule)
            
            Write-Host "  SUCCESS: Added with sequence $sequence" -ForegroundColor Green
            Write-Host "  Matched policies: $($admxFile.Matches.Count)" -ForegroundColor Gray
            
            $addedCount++
            $sequence++
        } else {
            Write-Warning "No data returned for $($admxFile.FileName)"
            if ($VerboseOutput) {
                Write-Host "  Response Status: $($response.StatusCode)" -ForegroundColor DarkGray
                Write-Host "  Response Content: $($response.Content)" -ForegroundColor DarkGray
            }
        }
        
    } catch {
        Write-Error "Failed to add $($admxFile.FileName): $_"
        if ($VerboseOutput) {
            Write-Host "  Error Details: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  Error Type: $($_.Exception.GetType().FullName)" -ForegroundColor Red
        }
    }
}

# Update script-scoped variable if exists
if ($script:ModuleConfig -and $script:ModuleConfig.CurrentItems) {
    $script:ModuleConfig.CurrentItems.Config = $global:CurrentConfig
}

# Show results
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Registry entries analyzed: $($allRegistryEntries.Count)" -ForegroundColor Yellow
Write-Host "ADMX files matched: $($matchedAdmx.Count)" -ForegroundColor Yellow
Write-Host "ADMX files added: $addedCount" -ForegroundColor Green
if ($skippedCount -gt 0) {
    Write-Host "ADMX files skipped: $skippedCount" -ForegroundColor Yellow
}
Write-Host "Total AdministrativeTemplates in config: $($global:CurrentConfig.AdministrativeTemplates.Count)" -ForegroundColor Green

if ($WhatIf) {
    Write-Host "`nWhat-If mode: No changes were made" -ForegroundColor Yellow
} elseif ($addedCount -gt 0) {
    Write-Host "`nSaving configuration..." -ForegroundColor Yellow
    try {
        # Suppress the default output from Save-ProUConfig
        $saveOutput = Save-ProUConfig
        Write-Host "Configuration saved successfully!" -ForegroundColor Green
    } catch {
        Write-Error "Failed to save: $_"
        Write-Host "`nThe configuration has been updated in memory but could not be saved." -ForegroundColor Yellow
        Write-Host "You may need to remove problematic ADMX files or save manually." -ForegroundColor Yellow
    }
} else {
    Write-Host "`nNo changes made to configuration." -ForegroundColor Yellow
}

Write-Host "`n=== Complete ===" -ForegroundColor Green