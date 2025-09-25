# Get-GPOPreferencesForProfileUnity.ps1
# Location: \Scripts\GPO-Analysis\Get-GPOPreferencesForProfileUnity.ps1
# Compatible with ProfileUnity PowerTools v3.0
# PowerShell 5.1+ Compatible

<#
.SYNOPSIS
    Extracts Group Policy Preferences for ProfileUnity migration analysis
.DESCRIPTION
    Analyzes a GPO and extracts specific Group Policy Preferences settings that can be
    migrated to ProfileUnity: Drive Mappings, Shortcuts, Registry, Environment Variables, and Printers
.PARAMETER GpoDisplayName
    Display name of the target GPO
.PARAMETER IncludeDrives
    Include Drive Mappings in the output
.PARAMETER IncludeShortcuts
    Include Shortcuts in the output
.PARAMETER IncludeRegistry
    Include Registry settings in the output
.PARAMETER IncludeEnvironment
    Include Environment Variables in the output
.PARAMETER IncludePrinters
    Include Printer settings in the output
.PARAMETER IncludeAll
    Include all supported GPP types
.PARAMETER OutputFolder
    Folder where output files are saved (default: script directory)
.PARAMETER ExportFiles
    Creates output files (CSV and JSON)
.PARAMETER ShowItemLevelTargeting
    Show Item-Level Targeting details for each preference
.EXAMPLE
    .\Get-GPOPreferencesForProfileUnity.ps1 -GpoDisplayName "User Preferences" -IncludeAll -ExportFiles
.EXAMPLE
    .\Get-GPOPreferencesForProfileUnity.ps1 -GpoDisplayName "Drive Maps" -IncludeDrives -ShowItemLevelTargeting
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$GpoDisplayName,

    [switch]$IncludeDrives,
    [switch]$IncludeShortcuts,
    [switch]$IncludeRegistry,
    [switch]$IncludeEnvironment,
    [switch]$IncludePrinters,
    [switch]$IncludeAll,

    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$OutputFolder = $PSScriptRoot,

    [switch]$ExportFiles,
    [switch]$ShowItemLevelTargeting
)

# Initialize error handling
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

# Set include flags if IncludeAll is specified
if ($IncludeAll) {
    $IncludeDrives = $true
    $IncludeShortcuts = $true
    $IncludeRegistry = $true
    $IncludeEnvironment = $true
    $IncludePrinters = $true
}

# Validate at least one type is selected
if (-not ($IncludeDrives -or $IncludeShortcuts -or $IncludeRegistry -or $IncludeEnvironment -or $IncludePrinters)) {
    throw "At least one preference type must be specified or use -IncludeAll"
}

# Import required modules
try {
    Import-Module GroupPolicy -ErrorAction Stop
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Verbose "Required modules imported successfully"
} catch {
    throw "Failed to import required modules: $($_.Exception.Message)"
}

# Get and validate GPO
Write-Host "Retrieving GPO information..." -ForegroundColor Yellow
try {
    $gpo = Get-GPO -Name $GpoDisplayName -ErrorAction Stop
    Write-Host "GPO found: $GpoDisplayName (ID: $($gpo.Id))" -ForegroundColor Green
} catch {
    throw "GPO '$GpoDisplayName' not found: $($_.Exception.Message)"
}

# Get GPO path in SYSVOL
try {
    $domain = (Get-ADDomain -ErrorAction Stop).DNSRoot
    $gpoPath = "\\$domain\SYSVOL\$domain\Policies\{$($gpo.Id)}"
    
    if (-not (Test-Path $gpoPath)) {
        throw "GPO path not found in SYSVOL: $gpoPath"
    }
    
    Write-Host "GPO path: $gpoPath" -ForegroundColor Cyan
} catch {
    throw "Could not access GPO in SYSVOL: $($_.Exception.Message)"
}

# Initialize results
$results = @{
    GPOName = $GpoDisplayName
    GPOID = $gpo.Id.ToString()
    AnalysisDate = Get-Date
    DriveMappings = @()
    Shortcuts = @()
    RegistrySettings = @()
    EnvironmentVariables = @()
    Printers = @()
    Summary = @{
        TotalItems = 0
        DriveCount = 0
        ShortcutCount = 0
        RegistryCount = 0
        EnvironmentCount = 0
        PrinterCount = 0
    }
}

# Function to parse Item-Level Targeting
function Get-ItemLevelTargeting {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Xml.XmlNode]$Node
    )
    
    if (-not $Node.Filters) {
        return $null
    }
    
    $targets = @()
    foreach ($filter in $Node.Filters.ChildNodes) {
        $target = @{
            Type = $filter.LocalName
            Not = if ($filter.not) { [bool]$filter.not } else { $false }
        }
        
        switch ($filter.LocalName) {
            'FilterGroup' {
                $target.Name = $filter.name
                $target.SID = $filter.sid
            }
            'FilterUser' {
                $target.Name = $filter.name
                $target.SID = $filter.sid
            }
            'FilterComputer' {
                $target.Name = $filter.name
            }
            'FilterOrganizationalUnit' {
                $target.Name = $filter.name
            }
            'FilterSite' {
                $target.Name = $filter.name
            }
            'FilterDomain' {
                $target.Name = $filter.name
            }
            'FilterWMI' {
                $target.Query = $filter.query
                $target.Namespace = $filter.namespace
            }
            'FilterRegistry' {
                $target.Key = $filter.key
                $target.ValueName = $filter.valueName
                $target.ValueType = $filter.type
            }
            'FilterEnvironmentVariable' {
                $target.Name = $filter.name
                $target.Value = $filter.value
            }
            'FilterIPAddressRange' {
                $target.FromAddress = $filter.fromAddress
                $target.ToAddress = $filter.toAddress
            }
            'FilterMSI' {
                $target.ProductCode = $filter.productCode
            }
            'FilterOperatingSystem' {
                $target.Class = $filter.class
                $target.Edition = $filter.edition
            }
            'FilterPortableComputer' {
                $target.Type = "Portable Computer"
            }
            'FilterRAM' {
                $target.Comparison = $filter.comparison
                $target.Value = $filter.value
            }
            'FilterDiskSpace' {
                $target.Comparison = $filter.comparison
                $target.Value = $filter.value
                $target.Drive = $filter.drive
            }
            'FilterProcessorSpeed' {
                $target.Comparison = $filter.comparison
                $target.Value = $filter.value
            }
            'FilterLanguage' {
                $target.LanguageCode = $filter.languageCode
            }
            'FilterTimeRange' {
                $target.StartTime = $filter.startTime
                $target.EndTime = $filter.endTime
                $target.DaysOfWeek = $filter.daysOfWeek
            }
            'FilterDialUpConnection' {
                $target.Type = "Dial-up Connection"
            }
            'FilterNetworkConnection' {
                $target.ConnectionType = $filter.connectionType
            }
            'FilterProcessRunning' {
                $target.ProcessName = $filter.processName
            }
            'FilterFileMatch' {
                $target.Path = $filter.path
                $target.PatternType = $filter.patternType
                $target.Pattern = $filter.pattern
            }
        }
        
        $targets += $target
    }
    
    return $targets
}

# Function to get action text
function Get-ActionText {
    param ([string]$Action)
    
    switch ($Action) {
        'C' { return 'Create' }
        'U' { return 'Update' }
        'R' { return 'Replace' }
        'D' { return 'Delete' }
        default { return $Action }
    }
}

# Process Drive Mappings
if ($IncludeDrives) {
    Write-Host "`nProcessing Drive Mappings..." -ForegroundColor Yellow
    
    foreach ($scope in @("Machine", "User")) {
        $drivesXml = Join-Path $gpoPath "$scope\Preferences\Drives\Drives.xml"
        
        if (Test-Path $drivesXml) {
            try {
                [xml]$xml = Get-Content $drivesXml -Raw -Encoding UTF8 -ErrorAction Stop
                
                foreach ($drive in $xml.Drives.Drive) {
                    if ($drive -and $drive.Properties) {
                        $props = $drive.Properties
                        
                        # Skip delete actions
                        if ($props.action -eq "D") {
                            Write-Verbose "Skipping delete action for drive $($props.letter)"
                            continue
                        }
                        
                        $driveItem = @{
                            Name = "$($props.letter): -> $($props.path)"
                            Letter = $props.letter
                            Path = $props.path
                            Label = $props.label
                            Action = Get-ActionText -Action $props.action
                            Persistent = if ($props.persistent) { [bool]$props.persistent } else { $false }
                            UseDriveLetter = if ($props.useLetter) { [bool]$props.useLetter } else { $true }
                            Scope = $scope
                            Enabled = if ($drive.disabled) { -not [bool]$drive.disabled } else { $true }
                        }
                        
                        if ($ShowItemLevelTargeting) {
                            $driveItem.ItemLevelTargeting = Get-ItemLevelTargeting -Node $drive
                        }
                        
                        $results.DriveMappings += $driveItem
                        $results.Summary.DriveCount++
                        
                        Write-Verbose "Found drive mapping: $($driveItem.Name) [$scope]"
                    }
                }
                
                Write-Host "  Found $($results.Summary.DriveCount) drive mappings in $scope scope" -ForegroundColor Green
                
            } catch {
                Write-Warning "Failed to process drives XML for $scope scope: $($_.Exception.Message)"
            }
        }
    }
}

# Process Shortcuts
if ($IncludeShortcuts) {
    Write-Host "`nProcessing Shortcuts..." -ForegroundColor Yellow
    
    foreach ($scope in @("Machine", "User")) {
        $shortcutsXml = Join-Path $gpoPath "$scope\Preferences\Shortcuts\Shortcuts.xml"
        
        if (Test-Path $shortcutsXml) {
            try {
                [xml]$xml = Get-Content $shortcutsXml -Raw -Encoding UTF8 -ErrorAction Stop
                
                foreach ($shortcut in $xml.Shortcuts.Shortcut) {
                    if ($shortcut -and $shortcut.Properties) {
                        $props = $shortcut.Properties
                        
                        # Skip delete actions
                        if ($props.action -eq "D") {
                            Write-Verbose "Skipping delete action for shortcut $($props.name)"
                            continue
                        }
                        
                        $shortcutItem = @{
                            Name = $props.name
                            TargetType = $props.targetType
                            TargetPath = $props.targetPath
                            Arguments = $props.arguments
                            StartIn = $props.startIn
                            Comment = $props.comment
                            IconPath = $props.iconPath
                            IconIndex = $props.iconIndex
                            Shortcut = $props.shortcutPath
                            Action = Get-ActionText -Action $props.action
                            Scope = $scope
                            Enabled = if ($shortcut.disabled) { -not [bool]$shortcut.disabled } else { $true }
                        }
                        
                        if ($ShowItemLevelTargeting) {
                            $shortcutItem.ItemLevelTargeting = Get-ItemLevelTargeting -Node $shortcut
                        }
                        
                        $results.Shortcuts += $shortcutItem
                        $results.Summary.ShortcutCount++
                        
                        Write-Verbose "Found shortcut: $($shortcutItem.Name) [$scope]"
                    }
                }
                
                Write-Host "  Found $($xml.Shortcuts.Shortcut.Count) shortcuts in $scope scope" -ForegroundColor Green
                
            } catch {
                Write-Warning "Failed to process shortcuts XML for $scope scope: $($_.Exception.Message)"
            }
        }
    }
}

# Process Registry Settings
if ($IncludeRegistry) {
    Write-Host "`nProcessing Registry Settings..." -ForegroundColor Yellow
    
    foreach ($scope in @("Machine", "User")) {
        $registryXml = Join-Path $gpoPath "$scope\Preferences\Registry\Registry.xml"
        
        if (Test-Path $registryXml) {
            try {
                [xml]$xml = Get-Content $registryXml -Raw -Encoding UTF8 -ErrorAction Stop
                
                # Process both Registry and Collection nodes
                $allNodes = @()
                if ($xml.RegistrySettings.Registry) { $allNodes += $xml.RegistrySettings.Registry }
                if ($xml.RegistrySettings.Collection) { $allNodes += $xml.RegistrySettings.Collection }
                
                foreach ($node in $allNodes) {
                    if ($node -and $node.Properties) {
                        $props = $node.Properties
                        
                        # Skip delete actions
                        if ($props.action -eq "D") {
                            Write-Verbose "Skipping delete action for registry value $($props.name)"
                            continue
                        }
                        
                        $registryItem = @{
                            Name = if ($props.name) { $props.name } else { "(Default)" }
                            Hive = $props.hive
                            Key = $props.key
                            ValueName = $props.name
                            ValueType = $props.type
                            Value = $props.value
                            Action = Get-ActionText -Action $props.action
                            Scope = $scope
                            Enabled = if ($node.disabled) { -not [bool]$node.disabled } else { $true }
                            FullPath = "$($props.hive)\$($props.key)"
                        }
                        
                        if ($ShowItemLevelTargeting) {
                            $registryItem.ItemLevelTargeting = Get-ItemLevelTargeting -Node $node
                        }
                        
                        $results.RegistrySettings += $registryItem
                        $results.Summary.RegistryCount++
                        
                        Write-Verbose "Found registry setting: $($registryItem.FullPath)\$($registryItem.ValueName) [$scope]"
                    }
                }
                
                Write-Host "  Found $($allNodes.Count) registry settings in $scope scope" -ForegroundColor Green
                
            } catch {
                Write-Warning "Failed to process registry XML for $scope scope: $($_.Exception.Message)"
            }
        }
    }
}

# Process Environment Variables
if ($IncludeEnvironment) {
    Write-Host "`nProcessing Environment Variables..." -ForegroundColor Yellow
    
    foreach ($scope in @("Machine", "User")) {
        $envXml = Join-Path $gpoPath "$scope\Preferences\EnvironmentVariables\EnvironmentVariables.xml"
        
        if (Test-Path $envXml) {
            try {
                [xml]$xml = Get-Content $envXml -Raw -Encoding UTF8 -ErrorAction Stop
                
                foreach ($envVar in $xml.EnvironmentVariables.EnvironmentVariable) {
                    if ($envVar -and $envVar.Properties) {
                        $props = $envVar.Properties
                        
                        # Skip delete actions
                        if ($props.action -eq "D") {
                            Write-Verbose "Skipping delete action for environment variable $($props.name)"
                            continue
                        }
                        
                        $envItem = @{
                            Name = $props.name
                            Value = $props.value
                            Action = Get-ActionText -Action $props.action
                            User = if ($props.user) { [bool]$props.user } else { $false }
                            System = if ($props.system) { [bool]$props.system } else { $true }
                            Partial = if ($props.partial) { [bool]$props.partial } else { $false }
                            Scope = $scope
                            Enabled = if ($envVar.disabled) { -not [bool]$envVar.disabled } else { $true }
                        }
                        
                        if ($ShowItemLevelTargeting) {
                            $envItem.ItemLevelTargeting = Get-ItemLevelTargeting -Node $envVar
                        }
                        
                        $results.EnvironmentVariables += $envItem
                        $results.Summary.EnvironmentCount++
                        
                        Write-Verbose "Found environment variable: $($envItem.Name) = $($envItem.Value) [$scope]"
                    }
                }
                
                Write-Host "  Found $($xml.EnvironmentVariables.EnvironmentVariable.Count) environment variables in $scope scope" -ForegroundColor Green
                
            } catch {
                Write-Warning "Failed to process environment variables XML for $scope scope: $($_.Exception.Message)"
            }
        }
    }
}

# Process Printers
if ($IncludePrinters) {
    Write-Host "`nProcessing Printers..." -ForegroundColor Yellow
    
    foreach ($scope in @("Machine", "User")) {
        $printersXml = Join-Path $gpoPath "$scope\Preferences\Printers\Printers.xml"
        
        if (Test-Path $printersXml) {
            try {
                [xml]$xml = Get-Content $printersXml -Raw -Encoding UTF8 -ErrorAction Stop
                
                # Process different printer types
                $printerNodes = @()
                if ($xml.Printers.SharedPrinter) { $printerNodes += $xml.Printers.SharedPrinter | ForEach-Object { @{Node = $_; Type = "SharedPrinter"} } }
                if ($xml.Printers.LocalPrinter) { $printerNodes += $xml.Printers.LocalPrinter | ForEach-Object { @{Node = $_; Type = "LocalPrinter"} } }
                if ($xml.Printers.PortPrinter) { $printerNodes += $xml.Printers.PortPrinter | ForEach-Object { @{Node = $_; Type = "PortPrinter"} } }
                
                foreach ($printerNode in $printerNodes) {
                    $printer = $printerNode.Node
                    if ($printer -and $printer.Properties) {
                        $props = $printer.Properties
                        
                        # Skip delete actions
                        if ($props.action -eq "D") {
                            Write-Verbose "Skipping delete action for printer $($props.name)"
                            continue
                        }
                        
                        $printerItem = @{
                            Name = $props.name
                            Path = $props.path
                            Location = $props.location
                            Comment = $props.comment
                            PrinterType = $printerNode.Type
                            Action = Get-ActionText -Action $props.action
                            Default = if ($props.default) { [bool]$props.default } else { $false }
                            Scope = $scope
                            Enabled = if ($printer.disabled) { -not [bool]$printer.disabled } else { $true }
                        }
                        
                        # Add type-specific properties
                        if ($printerNode.Type -eq "LocalPrinter") {
                            $printerItem.Port = $props.port
                            $printerItem.DriverName = $props.driverName
                        } elseif ($printerNode.Type -eq "PortPrinter") {
                            $printerItem.IPAddress = $props.ipAddress
                            $printerItem.LocalName = $props.localName
                        }
                        
                        if ($ShowItemLevelTargeting) {
                            $printerItem.ItemLevelTargeting = Get-ItemLevelTargeting -Node $printer
                        }
                        
                        $results.Printers += $printerItem
                        $results.Summary.PrinterCount++
                        
                        Write-Verbose "Found printer: $($printerItem.Name) [$($printerItem.PrinterType), $scope]"
                    }
                }
                
                Write-Host "  Found $($printerNodes.Count) printers in $scope scope" -ForegroundColor Green
                
            } catch {
                Write-Warning "Failed to process printers XML for $scope scope: $($_.Exception.Message)"
            }
        }
    }
}

# Update total count
$results.Summary.TotalItems = $results.Summary.DriveCount + $results.Summary.ShortcutCount + 
                              $results.Summary.RegistryCount + $results.Summary.EnvironmentCount + 
                              $results.Summary.PrinterCount

# Display summary
Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "EXTRACTION RESULTS" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "GPO: $GpoDisplayName" -ForegroundColor Yellow
Write-Host "Total items found: $($results.Summary.TotalItems)" -ForegroundColor White

if ($IncludeDrives) { Write-Host "  Drive Mappings: $($results.Summary.DriveCount)" -ForegroundColor Green }
if ($IncludeShortcuts) { Write-Host "  Shortcuts: $($results.Summary.ShortcutCount)" -ForegroundColor Green }
if ($IncludeRegistry) { Write-Host "  Registry Settings: $($results.Summary.RegistryCount)" -ForegroundColor Green }
if ($IncludeEnvironment) { Write-Host "  Environment Variables: $($results.Summary.EnvironmentCount)" -ForegroundColor Green }
if ($IncludePrinters) { Write-Host "  Printers: $($results.Summary.PrinterCount)" -ForegroundColor Green }

# Export files if requested
if ($ExportFiles) {
    Write-Host "`nExporting results..." -ForegroundColor Yellow
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $safeGpoName = $GpoDisplayName -replace '[^\w\-_]', '_'
    
    # Export JSON (complete data structure)
    $jsonPath = Join-Path $OutputFolder "GPO_Preferences_${safeGpoName}_$timestamp.json"
    $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-Host "  JSON export: $jsonPath" -ForegroundColor White
    
    # Export individual CSV files for each type
    if ($IncludeDrives -and $results.Summary.DriveCount -gt 0) {
        $drivesCsv = Join-Path $OutputFolder "GPO_DriveMappings_${safeGpoName}_$timestamp.csv"
$results.DriveMappings | ForEach-Object { [PSCustomObject]$_ } | Export-Csv -Path $drivesCsv -NoTypeInformation -ErrorAction SilentlyContinue
        Write-Host "  Drive mappings CSV: $drivesCsv" -ForegroundColor White
    }
    
    if ($IncludeShortcuts -and $results.Summary.ShortcutCount -gt 0) {
        $shortcutsCsv = Join-Path $OutputFolder "GPO_Shortcuts_${safeGpoName}_$timestamp.csv"
        $results.Shortcuts | ForEach-Object { [PSCustomObject]$_ } | Export-Csv -Path $shortcutsCsv -NoTypeInformation -ErrorAction SilentlyContinue
        Write-Host "  Shortcuts CSV: $shortcutsCsv" -ForegroundColor White
    }
    
    if ($IncludeRegistry -and $results.Summary.RegistryCount -gt 0) {
        $registryCsv = Join-Path $OutputFolder "GPO_Registry_${safeGpoName}_$timestamp.csv"
        $results.RegistrySettings | ForEach-Object { [PSCustomObject]$_ } | Export-Csv -Path $registryCsv -NoTypeInformation -ErrorAction SilentlyContinue
        Write-Host "  Registry settings CSV: $registryCsv" -ForegroundColor White
    }
    
    if ($IncludeEnvironment -and $results.Summary.EnvironmentCount -gt 0) {
        $envCsv = Join-Path $OutputFolder "GPO_Environment_${safeGpoName}_$timestamp.csv"
        $results.EnvironmentVariables | ForEach-Object { [PSCustomObject]$_ } | Export-Csv -Path $envCsv -NoTypeInformation -ErrorAction SilentlyContinue
        Write-Host "  Environment variables CSV: $envCsv" -ForegroundColor White
    }
    
    if ($IncludePrinters -and $results.Summary.PrinterCount -gt 0) {
        $printersCsv = Join-Path $OutputFolder "GPO_Printers_${safeGpoName}_$timestamp.csv"
        $results.Printers | ForEach-Object { [PSCustomObject]$_ } | Export-Csv -Path $printersCsv -NoTypeInformation -ErrorAction SilentlyContinue
        Write-Host "  Printers CSV: $printersCsv" -ForegroundColor White
    }
}

# Return results object for further processing
Write-Host "`nAnalysis complete. Results object available in `$results variable." -ForegroundColor Cyan
Write-Output $results