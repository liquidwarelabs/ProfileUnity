# Scripts\GPO-Migration\Import-GPOAdmIntoProfileUnity.ps1
# Location: \Scripts\GPO-Migration\Import-GPOAdmIntoProfileUnity.ps1
# PowerShell 5.x Compatible

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
    Path to ProfileUnity PowerShell module (optional - uses pre-loaded module if not specified)
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
.PARAMETER VerboseOutput
    Show detailed output during processing
.EXAMPLE
    .\Import-GPOAdmIntoProfileUnity.ps1 -GpoDisplayName "Security Settings" -ConfigName "Production"
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$GpoDisplayName,
    
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigName,
    
    [string]$ProfileUnityModule,
    
    [string]$PolicyDefinitionsPath,
    
    [ValidatePattern('^[a-z]{2}-[A-Z]{2}$')]
    [string]$Language = "en-US",
    
    [string]$FilterName,
    [switch]$SkipProblematicAdmx,
    [string[]]$ProblematicAdmxList = @("UserExperienceVirtualization.admx"),
    [switch]$VerboseOutput
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
$ProgressPreference = 'SilentlyContinue'

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

# Validate PolicyDefinitions path
if (-not (Test-Path $PolicyDefinitionsPath -PathType Container)) {
    throw "PolicyDefinitions path not found: $PolicyDefinitionsPath"
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
            $pointer += 2
        }
    }

    return $results
}

# Function to get policy display name from ADML file
function Get-PolicyDisplayName {
    param(
        [string]$PolicyId,
        [string]$AdmxPath,
        [string]$Language = "en-US"
    )
    
    try {
        # Find the ADML file that corresponds to the ADMX file
        $admlFiles = Get-ChildItem -Path (Join-Path $AdmxPath $Language) -Filter "*.adml" -ErrorAction SilentlyContinue
        foreach ($admlFile in $admlFiles) {
            [xml]$adml = Get-Content -Path $admlFile.FullName -Raw -ErrorAction SilentlyContinue
            if ($adml) {
                $ns = New-Object System.Xml.XmlNamespaceManager($adml.NameTable)
                $ns.AddNamespace("ns", $adml.DocumentElement.NamespaceURI)
                
                # Look for the policy ID in string elements
                $stringNode = $adml.SelectSingleNode("//ns:string[@id='$PolicyId']", $ns)
                if ($stringNode) {
                    return $stringNode.InnerText.Trim()
                }
            }
        }
    } catch {
        # Silently fail and return the original policy ID
    }
    
    return $PolicyId
}

# Function to find ADMX files that match registry entries
function Find-MatchingAdmx {
    param(
        [array]$RegistryEntries,
        [string]$AdmxPath,
        [string]$Language = "en-US"
    )
    
    $matches = @{}
    $admxFiles = Get-ChildItem -Path $AdmxPath -Filter "*.admx" -ErrorAction Stop
    
    Write-Host "Scanning $($admxFiles.Count) ADMX files for registry matches..." -ForegroundColor Yellow
    Write-Host "Registry entries to match: $($RegistryEntries.Count)" -ForegroundColor Gray

foreach ($admxFile in $admxFiles) {
    try {
            [xml]$admx = Get-Content -Path $admxFile.FullName -Raw
            $ns = New-Object System.Xml.XmlNamespaceManager($admx.NameTable)
            $ns.AddNamespace("ns", $admx.DocumentElement.NamespaceURI)
            
            $policies = $admx.SelectNodes("//ns:policy", $ns)
            
            foreach ($policy in $policies) {
                $policyKey = $policy.GetAttribute("key")
                $policyValueName = $policy.GetAttribute("valueName")
                
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
                        $policyId = $policy.GetAttribute("name")
                        $policyDisplayName = Get-PolicyDisplayName -PolicyId $policyId -AdmxPath $AdmxPath -Language $Language
                        
                        $matches[$admxFile.Name].Matches += [PSCustomObject]@{
                            PolicyId = $policyId
                            PolicyName = $policyDisplayName
                            RegistryKey = $regEntry.RegistryKey
                            ValueName = $regEntry.ValueName
                        }
                        if ($VerboseOutput) {
                            Write-Host "  Match: $($admxFile.Name) -> $policyDisplayName" -ForegroundColor DarkGray
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

# Import required modules
try {
    Import-Module GroupPolicy -ErrorAction Stop
    Write-Host "GroupPolicy module loaded successfully" -ForegroundColor Green
    
    if ($ProfileUnityModule -and (Test-Path $ProfileUnityModule)) {
    Import-Module $ProfileUnityModule -ErrorAction Stop
        Write-Host "ProfileUnity module imported from: $ProfileUnityModule" -ForegroundColor Green
    } else {
        Write-Host "Using pre-loaded ProfileUnity PowerTools module" -ForegroundColor Green
    }
    Write-Host "Required modules imported successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to import required modules: $($_.Exception.Message)"
    Write-Host "`nREQUIRED: Group Policy Management Tools must be installed to use this script." -ForegroundColor Red
    Write-Host "Installation options:" -ForegroundColor Yellow
    Write-Host "  - Windows Server: Install 'Group Policy Management' feature via Server Manager" -ForegroundColor White
    Write-Host "  - Windows 10/11: Install 'Group Policy Management Tools' via Optional Features" -ForegroundColor White
    Write-Host "  - Or download from: https://www.microsoft.com/en-us/download/details.aspx?id=45520" -ForegroundColor White
    throw "GroupPolicy module is required but not available. Please install Group Policy Management Tools."
}

# Main script
Write-Host "`n=== ADMX Import by Registry Matching ===" -ForegroundColor Cyan
Write-Host "GPO: $GpoDisplayName" -ForegroundColor Yellow
Write-Host "Target Config: $ConfigName" -ForegroundColor Yellow
Write-Host "PolicyDefinitions: $PolicyDefinitionsPath" -ForegroundColor Yellow

# Connect to ProfileUnity and load configuration
try {
    if (-not (Get-Command Connect-ProfileUnityServer -ErrorAction SilentlyContinue)) {
        throw "ProfileUnity PowerTools not properly loaded"
    }
    
    # Connect if needed
    if (!(Get-ProfileUnityConnectionStatus)) {
        Write-Host "`nConnecting to ProfileUnity..." -ForegroundColor Yellow
        Connect-ProfileUnityServer | Out-Null
    }
    
    Edit-ProUConfig -Name $ConfigName
    Write-Host "ProfileUnity configuration '$ConfigName' loaded for editing" -ForegroundColor Green
} catch {
    throw "Failed to load ProfileUnity configuration: $($_.Exception.Message)"
}

# Get and validate GPO
try {
    $gpo = Get-GPO -Name $GpoDisplayName -ErrorAction Stop
    $gpoId = $gpo.Id.ToString().ToUpper()
    Write-Host "GPO ID: $gpoId" -ForegroundColor Green
    Write-Host "GPO ID Format: {$gpoId}" -ForegroundColor DarkGray
} catch {
    throw "GPO '$GpoDisplayName' not found: $($_.Exception.Message)"
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
    if ($VerboseOutput) {
        $compEntries | ForEach-Object { Write-Host "    $($_.RegistryKey) -> $($_.ValueName)" -ForegroundColor DarkGray }
    }
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
$matchedAdmx = Find-MatchingAdmx -RegistryEntries $allRegistryEntries -AdmxPath $PolicyDefinitionsPath -Language $Language

Write-Host "`nMatched ADMX files:" -ForegroundColor Green
if ($matchedAdmx.Count -eq 0) {
    Write-Warning "No ADMX files matched the registry entries in this GPO"
    exit 0
}

$matchedAdmx | ForEach-Object {
    Write-Host "  - $($_.FileName) ($($_.Matches.Count) matching policies)" -ForegroundColor Cyan
    if ($VerboseOutput) {
        $_.Matches | ForEach-Object {
            Write-Host "    Policy: $($_.PolicyName) (ID: $($_.PolicyId))" -ForegroundColor DarkGray
        }
    }
}

# Initialize AdministrativeTemplates if needed
$currentConfig = $global:CurrentConfig
if (-not $currentConfig) {
    throw "No configuration loaded for editing. Use Edit-ProUConfig first."
}

if ($null -eq $currentConfig.AdministrativeTemplates) {
    Write-Host "`nInitializing AdministrativeTemplates array" -ForegroundColor Yellow
    $currentConfig | Add-Member -NotePropertyName AdministrativeTemplates -NotePropertyValue @() -Force
}

# Get starting sequence
$sequence = 1
if ($currentConfig.AdministrativeTemplates.Count -gt 0) {
    $maxSeq = ($currentConfig.AdministrativeTemplates | Measure-Object -Property Sequence -Maximum).Maximum
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
    
    if (-not $PSCmdlet.ShouldProcess("Add ADMX template", "Would add ADMX: $($admxFile.FileName)")) {
        Write-Host "  What-If: Would add $($admxFile.FileName) with sequence $sequence" -ForegroundColor Cyan
        $addedCount++
        $sequence++
        continue
    }
    
    # Use the Add-ProUAdmx function with proper parameters
    try {
        Write-Host "  Querying ProfileUnity..." -ForegroundColor Gray
        
        $addParams = @{
            AdmxFile = $admxPath
            AdmlFile = $admlPath
            GpoId = $gpoId
            Description = "Imported from GPO: $GpoDisplayName"
            Sequence = $sequence
        }
        
        if ($FilterName) {
            $addParams.FilterName = $FilterName
        }
        
        if ($VerboseOutput) {
            Write-Host "  Calling Add-ProUAdmx with parameters: $($addParams | ConvertTo-Json)" -ForegroundColor DarkGray
        }
        
        $result = Add-ProUAdmx @addParams
        
        if ($result) {
            Write-Host "  SUCCESS: Added with sequence $sequence" -ForegroundColor Green
            Write-Host "  Matched policies: $($admxFile.Matches.Count)" -ForegroundColor Gray
            
            $addedCount++
            $sequence++
                } else {
            Write-Warning "No data returned for $($admxFile.FileName)"
            if ($VerboseOutput) {
                Write-Host "  No result returned from Add-ProUAdmx" -ForegroundColor DarkGray
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

# Show results
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Registry entries analyzed: $($allRegistryEntries.Count)" -ForegroundColor Yellow
Write-Host "ADMX files matched: $($matchedAdmx.Count)" -ForegroundColor Yellow
Write-Host "ADMX files added: $addedCount" -ForegroundColor Green
if ($skippedCount -gt 0) {
    Write-Host "ADMX files skipped: $skippedCount" -ForegroundColor Yellow
}
Write-Host "Total AdministrativeTemplates in config: $($currentConfig.AdministrativeTemplates.Count)" -ForegroundColor Green

if ($addedCount -gt 0) {
    Write-Verbose "`nCleaning configuration to prevent JSON parsing errors..."
    Clean-ProUConfiguration
    Write-Host "`nUse Save-ProUConfig to save changes to ProfileUnity" -ForegroundColor Cyan
} else {
    Write-Host "`nNo changes made to configuration." -ForegroundColor Yellow
}

Write-Host "`n=== Complete ===" -ForegroundColor Green

