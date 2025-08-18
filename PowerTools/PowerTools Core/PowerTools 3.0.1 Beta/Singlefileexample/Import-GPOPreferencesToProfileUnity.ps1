<#
.SYNOPSIS
    Imports Group Policy Preferences directly into ProfileUnity configuration.
.DESCRIPTION
    This script analyzes a GPO, extracts Group Policy Preferences settings, and imports them
    directly into a ProfileUnity configuration using the ProfileUnity PowerTools module.
.PARAMETER GpoDisplayName
    Display name of the source GPO.
.PARAMETER ConfigName
    ProfileUnity configuration name to update.
.PARAMETER ProfileUnityModule
    Path to ProfileUnity PowerShell module (required).
.PARAMETER FilterName
    Optional filter name to apply to imported items.
.PARAMETER IncludeDrives
    Include Drive Mappings in the import.
.PARAMETER IncludeShortcuts
    Include Shortcuts in the import.
.PARAMETER IncludeRegistry
    Include Registry settings in the import.
.PARAMETER IncludeEnvironment
    Include Environment Variables in the import.
.PARAMETER IncludePrinters
    Include Printer settings in the import.
.PARAMETER IncludeAll
    Include all supported GPP types.
.PARAMETER ProcessPostLogin
    Set ProcessActionPostLogin flag for applicable items (default: true).
.PARAMETER StartingSequence
    Starting sequence number for imported items (default: auto-detect).
.PARAMETER WhatIf
    Shows what would be imported without making changes.
.EXAMPLE
    .\Import-GPOPreferencesToProfileUnity.ps1 -GpoDisplayName "UserSettings" -ConfigName "Production" -ProfileUnityModule ".\ProfileUnity-PowerTools.psm1" -IncludeAll
.EXAMPLE
    .\Import-GPOPreferencesToProfileUnity.ps1 -GpoDisplayName "DriveMapGPO" -ConfigName "Test" -ProfileUnityModule "C:\Scripts\ProfileUnity-PowerTools.psm1" -IncludeDrives -FilterName "Domain Users"
#>

param (
    [Parameter(Mandatory)]
    [string]$GpoDisplayName,

    [Parameter(Mandatory)]
    [string]$ConfigName,
    
    [Parameter(Mandatory)]
    [string]$ProfileUnityModule,
    
    [string]$FilterName,

    [switch]$IncludeDrives,
    
    [switch]$IncludeShortcuts,
    
    [switch]$IncludeRegistry,
    
    [switch]$IncludeEnvironment,
    
    [switch]$IncludePrinters,
    
    [switch]$IncludeAll,
    
    [bool]$ProcessPostLogin = $true,
    
    [int]$StartingSequence = 0,
    
    [switch]$WhatIf
)

# Import required modules
Import-Module GroupPolicy -ErrorAction Stop

# Validate that at least one type is selected
if (-not ($IncludeDrives -or $IncludeShortcuts -or $IncludeRegistry -or $IncludeEnvironment -or $IncludePrinters -or $IncludeAll)) {
    Write-Error "Please specify at least one GPP type to include (use -IncludeAll for all types)"
    Write-Host "`nAvailable options:" -ForegroundColor Yellow
    Write-Host "  -IncludeDrives      : Drive Mappings" -ForegroundColor Gray
    Write-Host "  -IncludeShortcuts   : Shortcuts" -ForegroundColor Gray
    Write-Host "  -IncludeRegistry    : Registry Settings" -ForegroundColor Gray
    Write-Host "  -IncludeEnvironment : Environment Variables" -ForegroundColor Gray
    Write-Host "  -IncludePrinters    : Printers" -ForegroundColor Gray
    Write-Host "  -IncludeAll         : All of the above" -ForegroundColor Gray
    exit 1
}

# If IncludeAll is specified, enable all types
if ($IncludeAll) {
    $IncludeDrives = $true
    $IncludeShortcuts = $true
    $IncludeRegistry = $true
    $IncludeEnvironment = $true
    $IncludePrinters = $true
}

Write-Host "`n=== GPO to ProfileUnity Import ===" -ForegroundColor Cyan
Write-Host "Source GPO: $GpoDisplayName" -ForegroundColor Yellow
Write-Host "Target Config: $ConfigName" -ForegroundColor Yellow

# Load ProfileUnity module
if (Test-Path $ProfileUnityModule) {
    Import-Module $ProfileUnityModule -Force
    Write-Host "Loaded ProfileUnity module" -ForegroundColor Green
} else {
    Write-Error "ProfileUnity module not found at: $ProfileUnityModule"
    exit 1
}

# Connect if needed
if (!(Test-ProfileUnityConnection)) {
    Write-Host "`nConnecting to ProfileUnity..." -ForegroundColor Yellow
    Connect-ProfileUnityServer | Out-Null
}

# Load configuration
Write-Host "`nLoading configuration: $ConfigName" -ForegroundColor Yellow
try {
    Edit-ProUConfig -Name $ConfigName -Quiet | Out-Null
} catch {
    Write-Error "Failed to load configuration: $_"
    exit 1
}

# Get filter ID if filter name provided
$filterId = $null
if ($FilterName) {
    $filter = Get-ProUFilters | Where-Object { $_.name -eq $FilterName }
    if ($filter) {
        $filterId = $filter.id
        Write-Host "Using filter: $FilterName (ID: $filterId)" -ForegroundColor Green
    } else {
        Write-Warning "Filter '$FilterName' not found - proceeding without filter"
    }
}

# Get GPO
try {
    $Gpo = Get-GPO -Name $GpoDisplayName -ErrorAction Stop
} catch {
    Write-Error "GPO '$GpoDisplayName' not found."
    exit 1
}

Write-Host "GPO ID: $($Gpo.Id)" -ForegroundColor Cyan

# Get GPO path
$Domain = (Get-ADDomain).DNSRoot
$GpoPath = "\\$Domain\SYSVOL\$Domain\Policies\{$($Gpo.Id)}"

# Function to parse Item Level Targeting (simplified for now)
function Parse-ItemLevelTargeting {
    param ([System.Xml.XmlElement]$FiltersNode)
    
    if (-not $FiltersNode) { return $null }
    
    # For now, we'll just note that ILT exists
    # Full ILT conversion would require mapping to ProfileUnity filters
    return $true
}

# Function to convert GPP action to ProfileUnity action
function Convert-GPPAction {
    param([string]$Action)
    
    switch ($Action) {
        "C" { return 0 } # Create
        "R" { return 1 } # Replace
        "U" { return 0 } # Update -> Create
        "D" { return 2 } # Delete
        default { return 0 }
    }
}

# Function to convert registry hive to ProfileUnity format
function Convert-RegistryHive {
    param([string]$Hive)
    
    switch ($Hive) {
        "HKEY_CLASSES_ROOT" { return 0 }
        "HKEY_CURRENT_USER" { return 1 }
        "HKEY_LOCAL_MACHINE" { return 2 }
        "HKEY_USERS" { return 3 }
        "HKEY_CURRENT_CONFIG" { return 4 }
        default { return 1 } # Default to HKCU
    }
}

# Function to convert registry type to ProfileUnity format
function Convert-RegistryType {
    param([string]$Type)
    
    switch ($Type) {
        "REG_SZ" { return 0 }
        "REG_DWORD" { return 1 }
        "REG_BINARY" { return 2 }
        "REG_EXPAND_SZ" { return 3 }
        "REG_MULTI_SZ" { return 4 }
        "REG_QWORD" { return 5 }
        default { return 0 }
    }
}

# Function to convert shortcut location to ProfileUnity format
function Convert-ShortcutLocation {
    param([string]$Path)
    
    if ($Path -match "Desktop") { return 0 }
    elseif ($Path -match "Start Menu") { return 1 }
    elseif ($Path -match "Programs") { return 2 }
    elseif ($Path -match "Startup") { return 3 }
    elseif ($Path -match "Quick Launch") { return 4 }
    elseif ($Path -match "SendTo") { return 5 }
    else { return 0 } # Default to Desktop
}

# Initialize counters
$counters = @{
    Drives = 0
    Shortcuts = 0
    Registry = 0
    Environment = 0
    Printers = 0
}

# Determine starting sequences for each type
$sequences = @{}
if ($StartingSequence -eq 0) {
    # Auto-detect existing sequences
    $sequences.Drives = 1
    $sequences.Shortcuts = 1
    $sequences.Registry = 1
    $sequences.Environment = 1
    $sequences.Printers = 1
    
    if ($global:CurrentConfig.DriveMappings -and $global:CurrentConfig.DriveMappings.Count -gt 0) {
        $maxSeq = ($global:CurrentConfig.DriveMappings | Measure-Object -Property Sequence -Maximum).Maximum
        if ($maxSeq) { $sequences.Drives = $maxSeq + 1 }
    }
    
    if ($global:CurrentConfig.Shortcuts -and $global:CurrentConfig.Shortcuts.Count -gt 0) {
        $maxSeq = ($global:CurrentConfig.Shortcuts | Measure-Object -Property Sequence -Maximum).Maximum
        if ($maxSeq) { $sequences.Shortcuts = $maxSeq + 1 }
    }
    
    if ($global:CurrentConfig.Registries -and $global:CurrentConfig.Registries.Count -gt 0) {
        $maxSeq = ($global:CurrentConfig.Registries | Measure-Object -Property Sequence -Maximum).Maximum
        if ($maxSeq) { $sequences.Registry = $maxSeq + 1 }
    }
    
    if ($global:CurrentConfig.EnvironmentVariables -and $global:CurrentConfig.EnvironmentVariables.Count -gt 0) {
        $maxSeq = ($global:CurrentConfig.EnvironmentVariables | Measure-Object -Property Sequence -Maximum).Maximum
        if ($maxSeq) { $sequences.Environment = $maxSeq + 1 }
    }
    
    if ($global:CurrentConfig.Printers -and $global:CurrentConfig.Printers.Count -gt 0) {
        $maxSeq = ($global:CurrentConfig.Printers | Measure-Object -Property Sequence -Maximum).Maximum
        if ($maxSeq) { $sequences.Printers = $maxSeq + 1 }
    }
} else {
    # Use provided starting sequence
    $sequences.Drives = $StartingSequence
    $sequences.Shortcuts = $StartingSequence
    $sequences.Registry = $StartingSequence
    $sequences.Environment = $StartingSequence
    $sequences.Printers = $StartingSequence
}

Write-Host "`nStarting sequences:" -ForegroundColor Cyan
Write-Host "  Drives: $($sequences.Drives)" -ForegroundColor Gray
Write-Host "  Shortcuts: $($sequences.Shortcuts)" -ForegroundColor Gray
Write-Host "  Registry: $($sequences.Registry)" -ForegroundColor Gray
Write-Host "  Environment: $($sequences.Environment)" -ForegroundColor Gray
Write-Host "  Printers: $($sequences.Printers)" -ForegroundColor Gray

# Initialize arrays if they don't exist
if ($null -eq $global:CurrentConfig.DriveMappings) { $global:CurrentConfig | Add-Member -NotePropertyName DriveMappings -NotePropertyValue @() -Force }
if ($null -eq $global:CurrentConfig.Shortcuts) { $global:CurrentConfig | Add-Member -NotePropertyName Shortcuts -NotePropertyValue @() -Force }
if ($null -eq $global:CurrentConfig.Registries) { $global:CurrentConfig | Add-Member -NotePropertyName Registries -NotePropertyValue @() -Force }
if ($null -eq $global:CurrentConfig.EnvironmentVariables) { $global:CurrentConfig | Add-Member -NotePropertyName EnvironmentVariables -NotePropertyValue @() -Force }
if ($null -eq $global:CurrentConfig.Printers) { $global:CurrentConfig | Add-Member -NotePropertyName Printers -NotePropertyValue @() -Force }

# Process Drive Mappings
if ($IncludeDrives) {
    Write-Host "`nProcessing Drive Mappings..." -ForegroundColor Yellow
    
    foreach ($scope in @("Machine", "User")) {
        $drivesXml = Join-Path $GpoPath "$scope\Preferences\Drives\Drives.xml"
        
        if (Test-Path $drivesXml) {
            try {
                [xml]$xml = Get-Content $drivesXml -Raw -Encoding UTF8
                
                foreach ($drive in $xml.Drives.Drive) {
                    if ($drive.Properties) {
                        $props = $drive.Properties
                        
                        # Skip if action is Delete
                        if ($props.action -eq "D") {
                            Write-Host "  Skipping delete action for drive $($props.letter)" -ForegroundColor Yellow
                            continue
                        }
                        
                        $driveMapping = @{
                            Action = 0  # Always use Create for drives
                            DisconnectBeforeMapping = $true
                            DriveLetter = if ($props.letter -match ':$') { $props.letter } else { "$($props.letter):" }
                            ExplorerLabel = if ($props.label) { $props.label } else { "" }
                            HideDrive = $false
                            MapPersistent = $props.persistent -eq "1"
                            ProcessActionPostLogin = $ProcessPostLogin
                            UncPath = $props.path
                            DriveUsername = ""
                            DrivePassword = ""
                            IsPasswordEncrypted = $true
                            Filter = if ($filterId) { $FilterName } else { $null }
                            FilterId = $filterId
                            Description = "Imported from GPO: $GpoDisplayName"
                            Disabled = $drive.disabled -eq "1"
                            Sequence = $sequences.Drives
                        }
                        
                        if ($drive.Filters) {
                            $driveMapping.Description += " (Has ILT)"
                        }
                        
                        if ($WhatIf) {
                            Write-Host "  What-If: Would add drive $($driveMapping.DriveLetter) -> $($driveMapping.UncPath)" -ForegroundColor Cyan
                        } else {
                            $global:CurrentConfig.DriveMappings += $driveMapping
                            Write-Host "  Added drive $($driveMapping.DriveLetter) -> $($driveMapping.UncPath)" -ForegroundColor Green
                        }
                        
                        $counters.Drives++
                        $sequences.Drives++
                    }
                }
            } catch {
                Write-Warning "Failed to process drives XML: $_"
            }
        }
    }
}

# Process Shortcuts
if ($IncludeShortcuts) {
    Write-Host "`nProcessing Shortcuts..." -ForegroundColor Yellow
    
    foreach ($scope in @("Machine", "User")) {
        $shortcutsXml = Join-Path $GpoPath "$scope\Preferences\Shortcuts\Shortcuts.xml"
        
        if (Test-Path $shortcutsXml) {
            try {
                [xml]$xml = Get-Content $shortcutsXml -Raw -Encoding UTF8
                
                foreach ($shortcut in $xml.Shortcuts.Shortcut) {
                    if ($shortcut.Properties) {
                        $props = $shortcut.Properties
                        
                        # Skip if action is Delete
                        if ($props.action -eq "D") {
                            Write-Host "  Skipping delete action for shortcut $($props.shortcutName)" -ForegroundColor Yellow
                            continue
                        }
                        
                        $shortcutItem = @{
                            Action = 0  # Always use Create
                            Arguments = if ($props.arguments) { $props.arguments } else { "" }
                            Icon = if ($props.iconPath) { $props.iconPath } else { $props.targetPath }
                            IconIndex = if ($props.iconIndex) { [int]$props.iconIndex } else { 0 }
                            Location = Convert-ShortcutLocation -Path $props.shortcutPath
                            Name = if ($props.shortcutName) { [System.IO.Path]::GetFileNameWithoutExtension($props.shortcutName) } else { $shortcut.name }
                            Overwrite = $true
                            PinnedLocation = 0
                            ProcessActionPostLogin = $ProcessPostLogin
                            StartIn = if ($props.startIn) { $props.startIn } else { "" }
                            Target = $props.targetPath
                            Type = 0  # File/Folder
                            WindowStyle = if ($props.windowStyle) { [int]$props.windowStyle } else { 0 }
                            Filter = if ($filterId) { $FilterName } else { $null }
                            FilterId = $filterId
                            Description = "Imported from GPO: $GpoDisplayName"
                            Disabled = $shortcut.disabled -eq "1"
                            Sequence = $sequences.Shortcuts
                        }
                        
                        if ($shortcut.Filters) {
                            $shortcutItem.Description += " (Has ILT)"
                        }
                        
                        if ($WhatIf) {
                            Write-Host "  What-If: Would add shortcut '$($shortcutItem.Name)' -> $($shortcutItem.Target)" -ForegroundColor Cyan
                        } else {
                            $global:CurrentConfig.Shortcuts += $shortcutItem
                            Write-Host "  Added shortcut '$($shortcutItem.Name)' -> $($shortcutItem.Target)" -ForegroundColor Green
                        }
                        
                        $counters.Shortcuts++
                        $sequences.Shortcuts++
                    }
                }
            } catch {
                Write-Warning "Failed to process shortcuts XML: $_"
            }
        }
    }
}

# Process Registry
if ($IncludeRegistry) {
    Write-Host "`nProcessing Registry Settings..." -ForegroundColor Yellow
    
    foreach ($scope in @("Machine", "User")) {
        $registryXml = Join-Path $GpoPath "$scope\Preferences\Registry\Registry.xml"
        
        if (Test-Path $registryXml) {
            try {
                [xml]$xml = Get-Content $registryXml -Raw -Encoding UTF8
                
                # Process both Registry and Collection nodes
                $allNodes = @()
                $allNodes += $xml.RegistrySettings.Registry
                $allNodes += $xml.RegistrySettings.Collection
                
                foreach ($node in $allNodes) {
                    if ($node -and $node.Properties) {
                        $props = $node.Properties
                        
                        # Skip if action is Delete (ProfileUnity handles deletes differently)
                        if ($props.action -eq "D") {
                            Write-Host "  Skipping delete action for registry value $($props.name)" -ForegroundColor Yellow
                            continue
                        }
                        
                        $registryItem = @{
                            Action = 0  # Always use Create
                            Data = if ($props.value) { $props.value } else { "" }
                            DataType = Convert-RegistryType -Type $props.type
                            Hive = Convert-RegistryHive -Hive $props.hive
                            Key = $props.key
                            ProcessActionPostLogin = $ProcessPostLogin
                            Value = if ($props.name) { $props.name } else { "" }
                            Filter = if ($filterId) { $FilterName } else { $null }
                            FilterId = $filterId
                            Description = "Imported from GPO: $GpoDisplayName"
                            Disabled = $node.disabled -eq "1"
                            Sequence = $sequences.Registry
                        }
                        
                        if ($node.Filters) {
                            $registryItem.Description += " (Has ILT)"
                        }
                        
                        if ($WhatIf) {
                            Write-Host "  What-If: Would add registry $($props.hive)\$($props.key)\$($props.name)" -ForegroundColor Cyan
                        } else {
                            $global:CurrentConfig.Registries += $registryItem
                            Write-Host "  Added registry $($props.hive)\$($props.key)\$($props.name)" -ForegroundColor Green
                        }
                        
                        $counters.Registry++
                        $sequences.Registry++
                    }
                }
            } catch {
                Write-Warning "Failed to process registry XML: $_"
            }
        }
    }
}

# Process Environment Variables
if ($IncludeEnvironment) {
    Write-Host "`nProcessing Environment Variables..." -ForegroundColor Yellow
    
    foreach ($scope in @("Machine", "User")) {
        $envXml = Join-Path $GpoPath "$scope\Preferences\EnvironmentVariables\EnvironmentVariables.xml"
        
        if (Test-Path $envXml) {
            try {
                [xml]$xml = Get-Content $envXml -Raw -Encoding UTF8
                
                foreach ($envVar in $xml.EnvironmentVariables.EnvironmentVariable) {
                    if ($envVar.Properties) {
                        $props = $envVar.Properties
                        
                        # Skip if action is Delete
                        if ($props.action -eq "D") {
                            Write-Host "  Skipping delete action for variable $($props.name)" -ForegroundColor Yellow
                            continue
                        }
                        
                        $envItem = @{
                            Value = if ($props.value) { $props.value } else { "" }
                            Variable = $props.name
                            VariableType = if ($props.user -eq "1") { 1 } else { 0 }  # 0=System, 1=User
                            Filter = if ($filterId) { $FilterName } else { $null }
                            FilterId = $filterId
                            Description = "Imported from GPO: $GpoDisplayName"
                            Disabled = $envVar.disabled -eq "1"
                            Sequence = $sequences.Environment
                        }
                        
                        if ($envVar.Filters) {
                            $envItem.Description += " (Has ILT)"
                        }
                        
                        if ($WhatIf) {
                            Write-Host "  What-If: Would add environment variable '$($envItem.Variable)' = '$($envItem.Value)'" -ForegroundColor Cyan
                        } else {
                            $global:CurrentConfig.EnvironmentVariables += $envItem
                            Write-Host "  Added environment variable '$($envItem.Variable)' = '$($envItem.Value)'" -ForegroundColor Green
                        }
                        
                        $counters.Environment++
                        $sequences.Environment++
                    }
                }
            } catch {
                Write-Warning "Failed to process environment variables XML: $_"
            }
        }
    }
}

# Process Printers
if ($IncludePrinters) {
    Write-Host "`nProcessing Printers..." -ForegroundColor Yellow
    
    foreach ($scope in @("Machine", "User")) {
        $printersXml = Join-Path $GpoPath "$scope\Preferences\Printers\Printers.xml"
        
        if (Test-Path $printersXml) {
            try {
                [xml]$xml = Get-Content $printersXml -Raw -Encoding UTF8
                
                foreach ($printer in $xml.Printers.SharedPrinter) {
                    if ($printer.Properties) {
                        $props = $printer.Properties
                        
                        # Skip if action is Delete
                        if ($props.action -eq "D") {
                            Write-Host "  Skipping delete action for printer $($props.path)" -ForegroundColor Yellow
                            continue
                        }
                        
                        $printerItem = @{
                            Action = 0  # Always use Create
                            AutoAdd = $true
                            DoNotCapturePortIfLocalIsOnPort = $false
                            DoNotDefaultIfLocalIsDefault = $false
                            Port = 0
                            ProcessActionPostLogin = $ProcessPostLogin
                            SetAsDefault = $props.default -eq "1"
                            SharedPrinter = $props.path
                            Filter = if ($filterId) { $FilterName } else { $null }
                            FilterId = $filterId
                            Description = "Imported from GPO: $GpoDisplayName"
                            Disabled = $printer.disabled -eq "1"
                            Sequence = $sequences.Printers
                        }
                        
                        if ($printer.Filters) {
                            $printerItem.Description += " (Has ILT)"
                        }
                        
                        if ($WhatIf) {
                            Write-Host "  What-If: Would add printer '$($printerItem.SharedPrinter)'" -ForegroundColor Cyan
                        } else {
                            $global:CurrentConfig.Printers += $printerItem
                            Write-Host "  Added printer '$($printerItem.SharedPrinter)'" -ForegroundColor Green
                        }
                        
                        $counters.Printers++
                        $sequences.Printers++
                    }
                }
            } catch {
                Write-Warning "Failed to process printers XML: $_"
            }
        }
    }
}

# Update script-scoped variable if exists
if ($script:ModuleConfig -and $script:ModuleConfig.CurrentItems) {
    $script:ModuleConfig.CurrentItems.Config = $global:CurrentConfig
}

# Show summary
Write-Host "`n=== Import Summary ===" -ForegroundColor Cyan
Write-Host "Items imported from GPO '$GpoDisplayName':" -ForegroundColor Yellow
if ($IncludeDrives) { Write-Host "  Drive Mappings: $($counters.Drives)" -ForegroundColor Green }
if ($IncludeShortcuts) { Write-Host "  Shortcuts: $($counters.Shortcuts)" -ForegroundColor Green }
if ($IncludeRegistry) { Write-Host "  Registry: $($counters.Registry)" -ForegroundColor Green }
if ($IncludeEnvironment) { Write-Host "  Environment Variables: $($counters.Environment)" -ForegroundColor Green }
if ($IncludePrinters) { Write-Host "  Printers: $($counters.Printers)" -ForegroundColor Green }

$totalImported = $counters.Drives + $counters.Shortcuts + $counters.Registry + $counters.Environment + $counters.Printers
Write-Host "`nTotal items imported: $totalImported" -ForegroundColor Cyan

if ($filterId) {
    Write-Host "Filter applied: $FilterName" -ForegroundColor Yellow
}

if ($WhatIf) {
    Write-Host "`nWhat-If mode: No changes were made" -ForegroundColor Yellow
    Write-Host "Remove -WhatIf to perform the actual import" -ForegroundColor Yellow
} elseif ($totalImported -gt 0) {
    Write-Host "`nConfiguration updated in memory" -ForegroundColor Green
    Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
    
    # Offer to save
    $save = Read-Host "`nSave configuration now? (Y/N)"
    if ($save -eq 'Y') {
        try {
            Save-ProUConfig
            Write-Host "Configuration saved successfully!" -ForegroundColor Green
        } catch {
            Write-Error "Failed to save configuration: $_"
        }
    } else {
        Write-Host "Configuration not saved. Use Save-ProUConfig when ready." -ForegroundColor Yellow
    }
} else {
    Write-Host "`nNo items were imported." -ForegroundColor Yellow
}

Write-Host "`n=== Import Complete ===" -ForegroundColor Green