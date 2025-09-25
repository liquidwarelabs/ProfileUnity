# Import-GpoAdmx.ps1 - Enhanced GPO ADMX Import with Registry Matching
# Location: \ADMx\Import-GpoAdmx.ps1

function Import-GpoAdmx {
    <#
    .SYNOPSIS
        Imports ADMX templates from a GPO based on registry policy matches.
    
    .DESCRIPTION
        Parses GPO registry.pol files and matches them to ADMX files, only adding those with actual policy matches.
        This provides intelligent ADMX import that only includes templates with configured policies.
    
    .PARAMETER GpoDisplayName
        Display name of the GPO to import from
    
    .PARAMETER PolicyDefinitionsPath
        Path to PolicyDefinitions folder (defaults to domain central store)
    
    .PARAMETER Language
        Language folder for ADML files (default: en-US)
    
    .PARAMETER SkipProblematicAdmx
        Skip known problematic ADMX files
    
    .PARAMETER ProblematicAdmxList
        List of ADMX files to skip due to known issues
    
    .PARAMETER WhatIf
        Show what would be done without making changes
    
    .EXAMPLE
        Import-GpoAdmx -GpoDisplayName "Windows 10 Policys"
    
    .EXAMPLE
        Import-GpoAdmx -GpoDisplayName "Security Settings" -PolicyDefinitionsPath "C:\PolicyDefinitions"
    
    .EXAMPLE
        Import-GpoAdmx -GpoDisplayName "Chrome Policy" -SkipProblematicAdmx -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$GpoDisplayName,
        
        [string]$PolicyDefinitionsPath,
        
        [string]$Language = "en-US",
        
        [switch]$SkipProblematicAdmx = $false,
        
        [string[]]$ProblematicAdmxList = @("UserExperienceVirtualization.admx"),
        
        [switch]$WhatIf
    )
    
    Begin {
        Assert-ProfileUnityConnection
        
        # Check if configuration is loaded
        $currentConfig = if ($script:ModuleConfig.CurrentItems.Config) { 
            $script:ModuleConfig.CurrentItems.Config 
        } elseif ($global:CurrentConfig) { 
            $global:CurrentConfig 
        } else {
            throw "No configuration loaded for editing. Use Edit-ProUConfig first."
        }
        
        # Set default PolicyDefinitions path if not provided
        if (-not $PolicyDefinitionsPath) {
            try {
                $domain = (Get-ADDomain).DNSRoot
                $PolicyDefinitionsPath = "\\$domain\SYSVOL\$domain\Policies\PolicyDefinitions"
                Write-Host "Using domain central store: $PolicyDefinitionsPath" -ForegroundColor Gray
            } catch {
                throw "Could not determine domain. Please specify -PolicyDefinitionsPath"
            }
        }
    }
    
    Process {
        Write-Host "`n=== ADMX Import by Registry Matching ===" -ForegroundColor Cyan
        Write-Host "GPO: $GpoDisplayName" -ForegroundColor Yellow
        Write-Host "Target Config: $($currentConfig.name)" -ForegroundColor Yellow
        Write-Host "PolicyDefinitions: $PolicyDefinitionsPath" -ForegroundColor Yellow
        
        # Get GPO
        try {
            $gpo = Get-GPO -Name $GpoDisplayName -ErrorAction Stop
            $gpoId = $gpo.Id.ToString().ToUpper()
            Write-Host "GPO ID: $gpoId" -ForegroundColor Green
            Write-Host "GPO ID Format: {$gpoId}" -ForegroundColor DarkGray
        } catch {
            throw "Failed to find GPO '$GpoDisplayName': $_"
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
            return
        }
        
        # Find matching ADMX files
        Write-Host "`nSearching for matching ADMX files..." -ForegroundColor Yellow
        $matchedAdmx = Find-MatchingAdmx -RegistryEntries $allRegistryEntries -AdmxPath $PolicyDefinitionsPath
        
        Write-Host "`nMatched ADMX files:" -ForegroundColor Green
        if ($matchedAdmx.Count -eq 0) {
            Write-Warning "No ADMX files matched the registry entries in this GPO"
            return
        }
        
        $matchedAdmx | ForEach-Object {
            Write-Host "  - $($_.FileName) ($($_.Matches.Count) matching policies)" -ForegroundColor Cyan
        }
        
        # Initialize AdministrativeTemplates if needed
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
            
            if ($WhatIf) {
                Write-Host "  What-If: Would add $($admxFile.FileName) with sequence $sequence" -ForegroundColor Cyan
                $addedCount++
                $sequence++
                continue
            }
            
            # Use our existing Add-ProUAdmx function
            try {
                Write-Host "  Querying ProfileUnity..." -ForegroundColor Gray
                
                $admxRule = Add-ProUAdmx -AdmxFile $admxPath -AdmlFile $admlPath -GpoId $gpoId -Description "Imported from GPO: $GpoDisplayName" -Sequence $sequence
                
                if ($admxRule) {
                    Write-Host "  SUCCESS: Added with sequence $sequence" -ForegroundColor Green
                    Write-Host "  Matched policies: $($admxFile.Matches.Count)" -ForegroundColor Gray
                    
                    $addedCount++
                    $sequence++
                } else {
                    Write-Warning "No data returned for $($admxFile.FileName)"
                }
                
            } catch {
                Write-Error "Failed to add $($admxFile.FileName): $_"
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
        
        if ($WhatIf) {
            Write-Host "`nWhat-If mode: No changes were made" -ForegroundColor Yellow
        } elseif ($addedCount -gt 0) {
            Write-Host "`nUse Save-ProUConfig to save changes" -ForegroundColor Yellow
        } else {
            Write-Host "`nNo changes made to configuration." -ForegroundColor Yellow
        }
        
        Write-Host "`n=== Complete ===" -ForegroundColor Green
    }
}

function Parse-RegistryPol {
    <#
    .SYNOPSIS
        Parses a registry.pol file to extract registry entries.
    
    .DESCRIPTION
        Reads and parses the binary registry.pol format to extract registry keys and values.
    
    .PARAMETER FilePath
        Path to the registry.pol file
    
    .RETURNS
        Array of registry entry objects
    #>
    [CmdletBinding()]
    param([string]$FilePath)
    
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
            
            # Read value
            $valueEnd = $pointer
            while ($valueEnd -lt $data.Length - 1 -and -not ($data[$valueEnd] -eq 0x00 -and $data[$valueEnd + 1] -eq 0x00)) {
                $valueEnd += 2
            }
            $valueLen = $valueEnd - $pointer
            if ($valueLen -gt 0) {
                $value = [System.Text.Encoding]::Unicode.GetString($data, $pointer, $valueLen)
            } else {
                $value = ""
            }
            $pointer = $valueEnd + 2
            
            # Read data type
            if ($pointer + 3 -lt $data.Length) {
                $dataType = [System.BitConverter]::ToInt32($data, $pointer)
                $pointer += 4
            } else {
                $dataType = 0
            }
            
            # Read data size
            if ($pointer + 3 -lt $data.Length) {
                $dataSize = [System.BitConverter]::ToInt32($data, $pointer)
                $pointer += 4
            } else {
                $dataSize = 0
            }
            
            # Read data
            $dataValue = ""
            if ($dataSize -gt 0 -and $pointer + $dataSize -le $data.Length) {
                if ($dataType -eq 1) { # REG_SZ
                    $dataValue = [System.Text.Encoding]::Unicode.GetString($data, $pointer, $dataSize - 2)
                } elseif ($dataType -eq 4) { # REG_DWORD
                    $dataValue = [System.BitConverter]::ToInt32($data, $pointer)
                } else {
                    $dataValue = [System.BitConverter]::ToString($data, $pointer, [Math]::Min($dataSize, 16))
                }
                $pointer += $dataSize
            }
            
            # Read closing bracket ]
            if ($pointer + 1 -lt $data.Length -and $data[$pointer] -eq 0x5D -and $data[$pointer + 1] -eq 0x00) {
                $pointer += 2
                
                $results += [PSCustomObject]@{
                    Key = $key
                    Value = $value
                    DataType = $dataType
                    DataSize = $dataSize
                    DataValue = $dataValue
                }
            }
            
        } catch {
            $pointer += 2
        }
    }
    
    return $results
}

function Find-MatchingAdmx {
    <#
    .SYNOPSIS
        Finds ADMX files that match registry entries from a GPO.
    
    .DESCRIPTION
        Scans ADMX files in the PolicyDefinitions folder to find those that contain
        registry keys matching the entries found in the GPO.
    
    .PARAMETER RegistryEntries
        Array of registry entries from Parse-RegistryPol
    
    .PARAMETER AdmxPath
        Path to the PolicyDefinitions folder
    
    .RETURNS
        Array of matching ADMX files with their matched policies
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$RegistryEntries,
        
        [Parameter(Mandatory)]
        [string]$AdmxPath
    )
    
    if (-not (Test-Path $AdmxPath)) {
        Write-Warning "PolicyDefinitions path not found: $AdmxPath"
        return @()
    }
    
    $admxFiles = Get-ChildItem -Path $AdmxPath -Filter "*.admx" -File
    Write-Host "Scanning $($admxFiles.Count) ADMX files for registry matches..." -ForegroundColor Gray
    
    $matches = @{}
    
    foreach ($admxFile in $admxFiles) {
        try {
            $content = Get-Content -Path $admxFile.FullName -Raw -ErrorAction Stop
            $matchedPolicies = @()
            
            foreach ($entry in $RegistryEntries) {
                # Look for registry key patterns in the ADMX file
                $keyPattern = [regex]::Escape($entry.Key)
                if ($content -match $keyPattern) {
                    # Extract policy name from the ADMX file
                    $policyMatch = [regex]::Match($content, '<policy name="([^"]+)"[^>]*>')
                    if ($policyMatch.Success) {
                        $matchedPolicies += [PSCustomObject]@{
                            PolicyName = $policyMatch.Groups[1].Value
                            RegistryKey = $entry.Key
                            RegistryValue = $entry.Value
                        }
                    }
                }
            }
            
            if ($matchedPolicies.Count -gt 0) {
                $matches[$admxFile.Name] = [PSCustomObject]@{
                    FileName = $admxFile.Name
                    FilePath = $admxFile.FullName
                    Matches = $matchedPolicies
                }
            }
            
        } catch {
            Write-Verbose "Error processing $($admxFile.Name): $_"
        }
    }
    
    return $matches.Values
}
