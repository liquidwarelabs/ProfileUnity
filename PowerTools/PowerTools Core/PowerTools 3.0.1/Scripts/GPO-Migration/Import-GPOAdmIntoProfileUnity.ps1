# Import-GPOAdmIntoProfileUnity.ps1
# Location: \Scripts\GPO-Migration\
# Compatible with ProfileUnity PowerTools v3.0
# PowerShell 5.1+ Compatible

<#
.SYNOPSIS
    Adds ADMX rules to ProfileUnity based on registry entries found in GPO
.DESCRIPTION
    Parses GPO registry.pol files and matches them to ADMX files, then adds matching
    ADMX templates using ProfileUnity PowerTools v3.0 Add-ProUAdmx function
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
.PARAMETER FilterName
    Optional filter name to apply to imported ADMX rules
.PARAMETER SkipProblematicAdmx
    Skip known problematic ADMX files
.PARAMETER ProblematicAdmxList
    List of ADMX files to skip due to known issues
.PARAMETER WhatIf
    Shows what would be imported without making changes
.EXAMPLE
    .\Import-GPOAdmIntoProfileUnity.ps1 -GpoDisplayName "Security Settings" -ConfigName "Production" -ProfileUnityModule "C:\Scripts\ProfileUnity-PowerTools.psm1"
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$GpoDisplayName,
    
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigName,
    
    [Parameter(Mandatory)]
    [ValidateScript({Test-Path $_})]
    [string]$ProfileUnityModule,
    
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$PolicyDefinitionsPath,
    
    [ValidatePattern('^[a-z]{2}-[A-Z]{2}$')]
    [string]$Language = "en-US",
    
    [string]$FilterName,
    
    [switch]$SkipProblematicAdmx,
    
    [string[]]$ProblematicAdmxList = @("UserExperienceVirtualization.admx"),
    
    [switch]$WhatIf
)

# Initialize error handling
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

# Import required modules
try {
    Import-Module GroupPolicy -ErrorAction Stop
    Write-Verbose "GroupPolicy module imported successfully"
} catch {
    throw "Failed to import GroupPolicy module: $($_.Exception.Message)"
}

# Set default PolicyDefinitions path if not provided
if (-not $PSBoundParameters.ContainsKey('PolicyDefinitionsPath')) {
    try {
        $domain = (Get-ADDomain -ErrorAction Stop).DNSRoot
        $PolicyDefinitionsPath = "\\$domain\SYSVOL\$domain\Policies\PolicyDefinitions"
        Write-Host "Using domain central store: $PolicyDefinitionsPath" -ForegroundColor Cyan
        
        if (-not (Test-Path $PolicyDefinitionsPath)) {
            throw "Central store path does not exist: $PolicyDefinitionsPath"
        }
    } catch {
        throw "Could not determine domain or access central store. Please specify -PolicyDefinitionsPath explicitly"
    }
}

# Load ProfileUnity module
Write-Host "Loading ProfileUnity PowerTools module..." -ForegroundColor Yellow
try {
    Import-Module $ProfileUnityModule -Force -ErrorAction Stop
    Write-Host "ProfileUnity module loaded successfully" -ForegroundColor Green
} catch {
    throw "Failed to load ProfileUnity module from '$ProfileUnityModule': $($_.Exception.Message)"
}

# Verify ProfileUnity connection
Write-Host "Verifying ProfileUnity connection..." -ForegroundColor Yellow
if (-not (Test-ProfileUnityConnection)) {
    Write-Host "Connecting to ProfileUnity server..." -ForegroundColor Yellow
    try {
        Connect-ProfileUnityServer | Out-Null
        Write-Host "Connected to ProfileUnity server" -ForegroundColor Green
    } catch {
        throw "Failed to connect to ProfileUnity server: $($_.Exception.Message)"
    }
}

# Load configuration
Write-Host "Loading ProfileUnity configuration: $ConfigName" -ForegroundColor Yellow
try {
    Edit-ProUConfig -Name $ConfigName -Quiet | Out-Null
    Write-Host "Configuration '$ConfigName' loaded successfully" -ForegroundColor Green
} catch {
    throw "Failed to load configuration '$ConfigName': $($_.Exception.Message)"
}

# Get and validate GPO
Write-Host "Retrieving GPO information..." -ForegroundColor Yellow
try {
    $gpo = Get-GPO -Name $GpoDisplayName -ErrorAction Stop
    $gpoId = $gpo.Id.ToString().ToUpper()
    Write-Host "GPO found - Name: $GpoDisplayName" -ForegroundColor Green
    Write-Host "GPO ID: {$gpoId}" -ForegroundColor Cyan
} catch {
    throw "Failed to find GPO '$GpoDisplayName': $($_.Exception.Message)"
}

# Validate filter if provided
$filterId = $null
if ($PSBoundParameters.ContainsKey('FilterName')) {
    Write-Host "Validating filter: $FilterName" -ForegroundColor Yellow
    try {
        $filter = Get-ProUFilters | Where-Object { $_.name -eq $FilterName }
        if ($filter) {
            $filterId = $filter.id
            Write-Host "Filter validated - ID: $filterId" -ForegroundColor Green
        } else {
            Write-Warning "Filter '$FilterName' not found - proceeding without filter"
            $FilterName = $null
        }
    } catch {
        Write-Warning "Failed to validate filter '$FilterName': $($_.Exception.Message)"
        $FilterName = $null
    }
}

# Function to parse registry.pol files
function Get-RegistryPolEntries {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path $_})]
        [string]$FilePath
    )
    
    Write-Verbose "Parsing registry.pol file: $FilePath"
    
    try {
        $data = [System.IO.File]::ReadAllBytes($FilePath)
        if ($data.Length -lt 16) {
            Write-Verbose "File too small to be valid registry.pol"
            return @()
        }
        
        # Verify PReg signature
        $signature = [System.Text.Encoding]::ASCII.GetString($data, 0, 4)
        if ($signature -ne "PReg") {
            Write-Warning "Invalid registry.pol signature in $FilePath"
            return @()
        }
        
        $pointer = 8  # Skip PReg header and version
        $results = @()
        
        while ($pointer -lt ($data.Length - 8)) {
            try {
                # Read bracket [
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
                if ($keyLength -gt 0) {
                    $registryKey = [System.Text.Encoding]::Unicode.GetString($data, $pointer, $keyLength)
                } else {
                    $registryKey = ""
                }
                $pointer = $keyEnd + 2
                
                # Skip semicolon
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
                if ($valueLength -gt 0) {
                    $valueName = [System.Text.Encoding]::Unicode.GetString($data, $pointer, $valueLength)
                } else {
                    $valueName = ""
                }
                $pointer = $valueEnd + 2
                
                # Skip to end of entry
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
                    }
                }
            } catch {
                Write-Verbose "Error parsing registry entry at position $pointer`: $($_.Exception.Message)"
                break
            }
        }
        
        Write-Verbose "Successfully parsed $($results.Count) registry entries"
        return $results
        
    } catch {
        Write-Error "Failed to parse registry.pol file '$FilePath': $($_.Exception.Message)"
        return @()
    }
}

# Function to find matching ADMX files
function Find-AdmxMatches {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [array]$RegistryEntries,
        
        [Parameter(Mandatory)]
        [ValidateScript({Test-Path $_ -PathType Container})]
        [string]$AdmxPath
    )
    
    Write-Verbose "Searching for ADMX matches in: $AdmxPath"
    
    try {
        $admxFiles = Get-ChildItem -Path $AdmxPath -Filter "*.admx" -ErrorAction Stop
        Write-Host "Scanning $($admxFiles.Count) ADMX files for registry matches..." -ForegroundColor Yellow
        
        $matches = @{}
        $processedCount = 0
        
        foreach ($admxFile in $admxFiles) {
            $processedCount++
            Write-Progress -Activity "Scanning ADMX Files" -Status $admxFile.Name -PercentComplete (($processedCount / $admxFiles.Count) * 100)
            
            try {
                [xml]$admx = Get-Content -Path $admxFile.FullName -Raw -ErrorAction Stop
                $namespaceManager = New-Object System.Xml.XmlNamespaceManager($admx.NameTable)
                $namespaceManager.AddNamespace("ns", $admx.DocumentElement.NamespaceURI)
                
                $policies = $admx.SelectNodes("//ns:policy", $namespaceManager)
                
                foreach ($policy in $policies) {
                    $policyKey = $policy.key
                    $policyValueName = $policy.valueName
                    
                    foreach ($regEntry in $RegistryEntries) {
                        # Flexible matching for registry keys and values
                        $keyMatch = $false
                        if ($policyKey) {
                            $keyMatch = ($regEntry.RegistryKey -like "*$policyKey*") -or 
                                       ($policyKey -like "*$($regEntry.RegistryKey)*") -or
                                       ($regEntry.RegistryKey -ieq $policyKey)
                        }
                        
                        $valueMatch = ($regEntry.ValueName -ieq $policyValueName)
                        
                        if ($keyMatch -and $valueMatch) {
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
                            
                            Write-Verbose "Match found: $($admxFile.Name) -> $($policy.name)"
                        }
                    }
                }
            } catch {
                Write-Verbose "Error processing ADMX file '$($admxFile.Name)': $($_.Exception.Message)"
                continue
            }
        }
        
        Write-Progress -Activity "Scanning ADMX Files" -Completed
        Write-Verbose "Found $($matches.Count) ADMX files with matches"
        
        return $matches.Values
        
    } catch {
        throw "Failed to scan ADMX files: $($_.Exception.Message)"
    }
}

# Main processing
Write-Host "`n=== GPO ADMX Import Process ===" -ForegroundColor Cyan
Write-Host "Source GPO: $GpoDisplayName" -ForegroundColor Yellow
Write-Host "Target Configuration: $ConfigName" -ForegroundColor Yellow
Write-Host "PolicyDefinitions Path: $PolicyDefinitionsPath" -ForegroundColor Yellow

# Get GPO registry entries
$domain = (Get-ADDomain).DNSRoot
$gpoPath = "\\$domain\SYSVOL\$domain\Policies\{$gpoId}"
$computerPolPath = Join-Path $gpoPath "Machine\registry.pol"
$userPolPath = Join-Path $gpoPath "User\registry.pol"

Write-Host "`nExtracting registry entries from GPO..." -ForegroundColor Yellow
$allRegistryEntries = @()

if (Test-Path $computerPolPath) {
    $computerEntries = Get-RegistryPolEntries -FilePath $computerPolPath
    $allRegistryEntries += $computerEntries
    Write-Host "Computer configuration entries: $($computerEntries.Count)" -ForegroundColor Green
}

if (Test-Path $userPolPath) {
    $userEntries = Get-RegistryPolEntries -FilePath $userPolPath
    $allRegistryEntries += $userEntries
    Write-Host "User configuration entries: $($userEntries.Count)" -ForegroundColor Green
}

Write-Host "Total registry entries found: $($allRegistryEntries.Count)" -ForegroundColor Cyan

if ($allRegistryEntries.Count -eq 0) {
    Write-Warning "No registry entries found in GPO. The GPO might not contain Administrative Template settings."
    exit 0
}

# Find matching ADMX files
Write-Host "`nFinding matching ADMX templates..." -ForegroundColor Yellow
$matchedAdmx = Find-AdmxMatches -RegistryEntries $allRegistryEntries -AdmxPath $PolicyDefinitionsPath

if ($matchedAdmx.Count -eq 0) {
    Write-Warning "No ADMX templates matched the registry entries in this GPO."
    Write-Host "This might indicate:" -ForegroundColor Yellow
    Write-Host "- GPO uses custom administrative templates" -ForegroundColor Yellow
    Write-Host "- Registry entries don't correspond to standard ADMX policies" -ForegroundColor Yellow
    Write-Host "- ADMX files are not available in the specified path" -ForegroundColor Yellow
    exit 0
}

Write-Host "`nMatched ADMX templates:" -ForegroundColor Green
foreach ($match in $matchedAdmx) {
    Write-Host "  - $($match.FileName) ($($match.Matches.Count) matching policies)" -ForegroundColor Cyan
}

# Process matched ADMX files
$addedCount = 0
$skippedCount = 0
$failedCount = 0

Write-Host "`nAdding ADMX templates to ProfileUnity configuration..." -ForegroundColor Yellow

foreach ($admxMatch in $matchedAdmx) {
    # Check if should skip problematic files
    if ($SkipProblematicAdmx -and $ProblematicAdmxList -contains $admxMatch.FileName) {
        Write-Warning "Skipping $($admxMatch.FileName) - marked as problematic"
        $skippedCount++
        continue
    }
    
    Write-Host "`nProcessing: $($admxMatch.FileName)" -ForegroundColor Yellow
    
    # Build file paths
    $admxPath = $admxMatch.FullPath
    $admlFileName = $admxMatch.FileName -replace '\.admx$', '.adml'
    $admlPath = Join-Path (Join-Path $PolicyDefinitionsPath $Language) $admlFileName
    
    # Verify files exist
    if (-not (Test-Path $admxPath)) {
        Write-Warning "ADMX file not found: $admxPath"
        $failedCount++
        continue
    }
    
    if (-not (Test-Path $admlPath)) {
        Write-Warning "ADML file not found: $admlPath - continuing without language file"
        $admlPath = ""
    }
    
    if ($WhatIf) {
        Write-Host "  [WHAT-IF] Would add $($admxMatch.FileName)" -ForegroundColor Cyan
        $addedCount++
        continue
    }
    
    # Add ADMX template using ProfileUnity PowerTools
    try {
        Write-Host "  Adding ADMX template..." -ForegroundColor Gray
        
        $addParams = @{
            AdmxFile = $admxPath
            GpoId = $gpoId
            Description = "Imported from GPO: $GpoDisplayName"
        }
        
        if ($admlPath) {
            $addParams.AdmlFile = $admlPath
        }
        
        if ($FilterName) {
            $addParams.FilterName = $FilterName
        }
        
        $result = Add-ProUAdmx @addParams
        
        if ($result) {
            Write-Host "  SUCCESS: $($admxMatch.FileName) added" -ForegroundColor Green
            Write-Host "  Policies matched: $($admxMatch.Matches.Count)" -ForegroundColor Gray
            $addedCount++
        } else {
            Write-Warning "Failed to add $($admxMatch.FileName) - no result returned"
            $failedCount++
        }
        
    } catch {
        Write-Error "Failed to add $($admxMatch.FileName): $($_.Exception.Message)"
        $failedCount++
    }
}

# Display results summary
Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "IMPORT SUMMARY" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "Registry entries analyzed: $($allRegistryEntries.Count)" -ForegroundColor Yellow
Write-Host "ADMX templates matched: $($matchedAdmx.Count)" -ForegroundColor Yellow
Write-Host "Templates added successfully: $addedCount" -ForegroundColor Green
if ($skippedCount -gt 0) {
    Write-Host "Templates skipped (problematic): $skippedCount" -ForegroundColor Yellow
}
if ($failedCount -gt 0) {
    Write-Host "Templates failed to add: $failedCount" -ForegroundColor Red
}

# Get current configuration status
try {
    $currentConfig = $script:ModuleConfig.CurrentItems.Config
    if (-not $currentConfig -and $global:CurrentConfig) {
        $currentConfig = $global:CurrentConfig
    }
    
    if ($currentConfig -and $currentConfig.AdministrativeTemplates) {
        Write-Host "Total ADMX templates in configuration: $($currentConfig.AdministrativeTemplates.Count)" -ForegroundColor Cyan
    }
} catch {
    Write-Verbose "Could not retrieve current configuration status"
}

# Handle saving
if ($WhatIf) {
    Write-Host "`n[WHAT-IF MODE] No changes were made to the configuration" -ForegroundColor Yellow
    Write-Host "Remove -WhatIf parameter to perform the actual import" -ForegroundColor Yellow
} elseif ($addedCount -gt 0) {
    Write-Host "`nConfiguration updated in memory" -ForegroundColor Green
    Write-Host "Use Save-ProUConfig to save changes to ProfileUnity server" -ForegroundColor Yellow
    
    # Offer to save automatically
    if (-not $WhatIf) {
        $save = Read-Host "`nSave configuration now? [Y/N]"
        if ($save -ieq 'Y' -or $save -ieq 'Yes') {
            try {
                Write-Host "Saving configuration..." -ForegroundColor Yellow
                Save-ProUConfig
                Write-Host "Configuration saved successfully!" -ForegroundColor Green
            } catch {
                Write-Error "Failed to save configuration: $($_.Exception.Message)"
                Write-Host "The configuration has been updated in memory but could not be saved." -ForegroundColor Yellow
                Write-Host "You can try saving manually using Save-ProUConfig" -ForegroundColor Yellow
            }
        } else {
            Write-Host "Configuration not saved. Use Save-ProUConfig when ready." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "`nNo changes were made to the configuration." -ForegroundColor Yellow
}

Write-Host "`n" + ("=" * 60) -ForegroundColor Green
Write-Host "PROCESS COMPLETED" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green

# Script location reference
Write-Verbose "Script: Import-GPOAdmIntoProfileUnity.ps1"
Write-Verbose "Location: \Scripts\GPO-Migration\"
Write-Verbose "Compatible with: ProfileUnity PowerTools v3.0"