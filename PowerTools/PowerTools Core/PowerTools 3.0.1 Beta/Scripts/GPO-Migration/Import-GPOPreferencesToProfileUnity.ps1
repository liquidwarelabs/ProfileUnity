# Import-GPOPreferencesToProfileUnity.ps1
# Location: \Scripts\GPO-Migration\
# Compatible with ProfileUnity PowerTools v3.0
# PowerShell 5.1+ Compatible

<#
.SYNOPSIS
    Imports Group Policy Preferences directly into ProfileUnity configuration
.DESCRIPTION
    Analyzes a GPO, extracts Group Policy Preferences settings (Drive Mappings, Shortcuts,
    Registry, Environment Variables, Printers), and imports them into ProfileUnity using
    PowerTools v3.0 functions
.PARAMETER GpoDisplayName
    Display name of the source GPO
.PARAMETER ConfigName
    ProfileUnity configuration name to update
.PARAMETER ProfileUnityModule
    Path to ProfileUnity PowerShell module (required)
.PARAMETER FilterName
    Optional filter name to apply to imported items
.PARAMETER IncludeDrives
    Include Drive Mappings in the import
.PARAMETER IncludeShortcuts
    Include Shortcuts in the import
.PARAMETER IncludeRegistry
    Include Registry settings in the import
.PARAMETER IncludeEnvironment
    Include Environment Variables in the import
.PARAMETER IncludePrinters
    Include Printer settings in the import
.PARAMETER IncludeAll
    Include all supported GPP types
.PARAMETER ProcessPostLogin
    Set ProcessActionPostLogin flag for applicable items
.PARAMETER StartingSequence
    Starting sequence number for imported items
.PARAMETER WhatIf
    Shows what would be imported without making changes
.EXAMPLE
    .\Import-GPOPreferencesToProfileUnity.ps1 -GpoDisplayName "UserSettings" -ConfigName "Production" -ProfileUnityModule ".\ProfileUnity-PowerTools.psm1" -IncludeAll
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$GpoDisplayName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ConfigName,
    
    [Parameter(Mandatory)]
    [ValidateScript({Test-Path $_})]
    [string]$ProfileUnityModule,
    
    [string]$FilterName,

    [switch]$IncludeDrives,
    [switch]$IncludeShortcuts,
    [switch]$IncludeRegistry,
    [switch]$IncludeEnvironment,
    [switch]$IncludePrinters,
    [switch]$IncludeAll,
    
    [bool]$ProcessPostLogin = $true,
    
    [ValidateRange(0, 1000)]
    [int]$StartingSequence = 0,
    
    [switch]$WhatIf
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

# Validate that at least one type is selected
if (-not ($IncludeDrives -or $IncludeShortcuts -or $IncludeRegistry -or $IncludeEnvironment -or $IncludePrinters -or $IncludeAll)) {
    Write-Host "`nAvailable GPP types:" -ForegroundColor Yellow
    Write-Host "  -IncludeDrives      : Drive Mappings" -ForegroundColor Gray
    Write-Host "  -IncludeShortcuts   : Shortcuts" -ForegroundColor Gray
    Write-Host "  -IncludeRegistry    : Registry Settings" -ForegroundColor Gray
    Write-Host "  -IncludeEnvironment : Environment Variables" -ForegroundColor Gray
    Write-Host "  -IncludePrinters    : Printers" -ForegroundColor Gray
    Write-Host "  -IncludeAll         : All types above" -ForegroundColor Gray
    throw "Please specify at least one GPP type to include (use -IncludeAll for all types)"
}

# If IncludeAll is specified, enable all types
if ($IncludeAll) {
    $IncludeDrives = $true
    $IncludeShortcuts = $true
    $IncludeRegistry = $true
    $IncludeEnvironment = $true
    $IncludePrinters = $true
}

Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "GPO PREFERENCES TO PROFILEUNITY IMPORT" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "Source GPO: $GpoDisplayName" -ForegroundColor Yellow
Write-Host "Target Configuration: $ConfigName" -ForegroundColor Yellow

# Load ProfileUnity module
Write-Host "`nLoading ProfileUnity PowerTools module..." -ForegroundColor Yellow
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
    Write-Host "Configuration loaded successfully" -ForegroundColor Green
} catch {
    throw "Failed to load configuration '$ConfigName': $($_.Exception.Message)"
}

# Validate filter if specified
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

# Get and validate GPO
Write-Host "Retrieving GPO information..." -ForegroundColor Yellow
try {
    $gpo = Get-GPO -Name $GpoDisplayName -ErrorAction Stop
    Write-Host "GPO found: $GpoDisplayName (ID: $($gpo.Id))" -ForegroundColor Green
} catch {
    throw "GPO '$GpoDisplayName' not found: $($_.Exception.Message)"
}

# Helper functions for data conversion
function Convert-GPPAction {
    [CmdletBinding()]
    param([string]$Action)
    
    switch ($Action) {
        "C" { return 0 } # Create
        "R" { return 1 } # Replace  
        "U" { return 0 } # Update -> Create
        "D" { return 2 } # Delete
        default { return 0 }
    }
}

function Convert-RegistryHive {
    [CmdletBinding()]
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

function Convert-RegistryType {
    [CmdletBinding()]
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

function Convert-ShortcutLocation {
    [CmdletBinding()]
    param([string]$Path)
    
    if ($Path -match "Desktop") { return 0 }
    elseif ($Path -match "Start Menu") { return 1 }
    elseif ($Path -match "Programs") { return 2 }
    elseif ($Path -match "Startup") { return 3 }
    elseif ($Path -match "Quick Launch") { return 4 }
    elseif ($Path -match "SendTo") { return 5 }
    else { return 0 } # Default to Desktop
}

# Initialize counters and get current configuration
$counters = @{
    Drives = 0; Shortcuts = 0; Registry = 0; Environment = 0; Printers = 0
}

# Get current configuration for editing
$currentConfig = $script:ModuleConfig.CurrentItems.Config
if (-not $currentConfig -and $global:CurrentConfig) {
    $currentConfig = $global:CurrentConfig
}

if (-not $currentConfig) {
    throw "Failed to load configuration for editing. Ensure Edit-ProUConfig was successful."
}

# Initialize arrays if they don't exist
$configArrays = @('DriveMappings', 'Shortcuts', 'Registries', 'EnvironmentVariables', 'Printers')
foreach ($arrayName in $configArrays) {
    if ($null -eq $currentConfig.$arrayName) {
        $currentConfig | Add-Member -NotePropertyName $arrayName -NotePropertyValue @() -Force
    }
}

# Determine starting sequences for each type
$sequences = @{
    Drives = 1; Shortcuts = 1; Registry = 1; Environment = 1; Printers = 1
}

if ($StartingSequence -eq 0) {
    # Auto-detect existing sequences
    foreach ($type in @('Drives', 'Shortcuts', 'Registry', 'Environment', 'Printers')) {
        $arrayName = switch ($type) {
            'Drives' { 'DriveMappings' }
            'Registry' { 'Registries' }
            'Environment' { 'EnvironmentVariables' }
            default { $type }
        }
        
        if ($currentConfig.$arrayName -and $currentConfig.$arrayName.Count -gt 0) {
            $maxSeq = ($currentConfig.$arrayName | Measure-Object -Property Sequence -Maximum).Maximum
            if ($maxSeq) { $sequences[$type] = $maxSeq + 1 }
        }
    }
} else {
    # Use provided starting sequence for all types
    foreach ($key in $sequences.Keys) {
        $sequences[$key] = $StartingSequence
    }
}

Write-Host "`nStarting sequences:" -ForegroundColor Cyan
foreach ($type in $sequences.Keys) {
    Write-Host "  ${type}: $($sequences[$type])" -ForegroundColor Gray
}

# Get GPO paths
$domain = (Get-ADDomain).DNSRoot
$gpoPath = "\\$domain\SYSVOL\$domain\Policies\{$($gpo.Id)}"

Write-Host "`nProcessing GPO preferences from: $gpoPath" -ForegroundColor Yellow

# Process Drive Mappings
if ($IncludeDrives) {
    Write-Host "`nProcessing Drive Mappings..." -ForegroundColor Yellow
    
    foreach ($scope in @("Machine", "User")) {
        $drivesXml = Join-Path $gpoPath "$scope\Preferences\Drives\Drives.xml"
        
        if (Test-Path $drivesXml) {
            try {
                [xml]$xml = Get-Content $drivesXml -Raw -Encoding UTF8 -ErrorAction Stop
                
                foreach ($drive in $xml.Drives.Drive) {
                    if ($drive.Properties) {
                        $props = $drive.Properties
                        
                        # Skip delete actions
                        if ($props.action -eq "D") {
                            Write-Verbose "Skipping delete action for drive $($props.letter)"
                            continue
                        }
                        
                        $driveMapping = @{
                            Action = 0  # Always use Create for drives
                            DisconnectBeforeMapping = $true
                            DriveLetter = if ($props.letter -match ':) { $props.letter } else { "$($props.letter):" }
                            ExplorerLabel = if ($props.label) { $props.label } else { "" }
                            HideDrive = $false
                            MapPersistent = ($props.persistent -eq "1")
                            ProcessActionPostLogin = $ProcessPostLogin
                            UncPath = $props.path
                            DriveUsername = ""
                            DrivePassword = ""
                            IsPasswordEncrypted = $true
                            Filter = if ($filterId) { $FilterName } else { $null }
                            FilterId = $filterId
                            Description = "Imported from GPO: $GpoDisplayName ($scope)"
                            Disabled = ($drive.disabled -eq "1")
                            Sequence = $sequences.Drives
                        }
                        
                        if ($drive.Filters) {
                            $driveMapping.Description += " (Has ILT)"
                        }
                        
                        if ($WhatIf) {
                            Write-Host "  [WHAT-IF] Would add drive $($driveMapping.DriveLetter) -> $($driveMapping.UncPath)" -ForegroundColor Cyan
                        } else {
                            $currentConfig.DriveMappings += $driveMapping
                            Write-Host "  Added drive $($driveMapping.DriveLetter) -> $($driveMapping.UncPath)" -ForegroundColor Green
                        }
                        
                        $counters.Drives++
                        $sequences.Drives++
                    }
                }
                
                Write-Verbose "Processed drives XML for $scope scope: $($counters.Drives) items"
                
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
                    if ($shortcut.Properties) {
                        $props = $shortcut.Properties
                        
                        # Skip delete actions
                        if ($props.action -eq "D") {
                            Write-Verbose "Skipping delete action for shortcut $($props.shortcutName)"
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
                            Description = "Imported from GPO: $GpoDisplayName ($scope)"
                            Disabled = ($shortcut.disabled -eq "1")
                            Sequence = $sequences.Shortcuts
                        }
                        
                        if ($shortcut.Filters) {
                            $shortcutItem.Description += " (Has ILT)"
                        }
                        
                        if ($WhatIf) {
                            Write-Host "  [WHAT-IF] Would add shortcut '$($shortcutItem.Name)' -> $($shortcutItem.Target)" -ForegroundColor Cyan
                        } else {
                            $currentConfig.Shortcuts += $shortcutItem
                            Write-Host "  Added shortcut '$($shortcutItem.Name)' -> $($shortcutItem.Target)" -ForegroundColor Green
                        }
                        
                        $counters.Shortcuts++
                        $sequences.Shortcuts++
                    }
                }
                
                Write-Verbose "Processed shortcuts XML for $scope scope: $($counters.Shortcuts) items"
                
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
                        
                        # Skip delete actions (ProfileUnity handles deletes differently)
                        if ($props.action -eq "D") {
                            Write-Verbose "Skipping delete action for registry value $($props.name)"
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
                            Description = "Imported from GPO: $GpoDisplayName ($scope)"
                            Disabled = ($node.disabled -eq "1")
                            Sequence = $sequences.Registry
                        }
                        
                        if ($node.Filters) {
                            $registryItem.Description += " (Has ILT)"
                        }
                        
                        if ($WhatIf) {
                            Write-Host "  [WHAT-IF] Would add registry $($props.hive)\$($props.key)\$($props.name)" -ForegroundColor Cyan
                        } else {
                            $currentConfig.Registries += $registryItem
                            Write-Host "  Added registry $($props.hive)\$($props.key)\$($props.name)" -ForegroundColor Green
                        }
                        
                        $counters.Registry++
                        $sequences.Registry++
                    }
                }
                
                Write-Verbose "Processed registry XML for $scope scope: $($counters.Registry) items"
                
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
                    if ($envVar.Properties) {
                        $props = $envVar.Properties
                        
                        # Skip delete actions
                        if ($props.action -eq "D") {
                            Write-Verbose "Skipping delete action for variable $($props.name)"
                            continue
                        }
                        
                        $envItem = @{
                            Value = if ($props.value) { $props.value } else { "" }
                            Variable = $props.name
                            VariableType = if ($props.user -eq "1") { 1 } else { 0 }  # 0=System, 1=User
                            Filter = if ($filterId) { $FilterName } else { $null }
                            FilterId = $filterId
                            Description = "Imported from GPO: $GpoDisplayName ($scope)"
                            Disabled = ($envVar.disabled -eq "1")
                            Sequence = $sequences.Environment
                        }
                        
                        if ($envVar.Filters) {
                            $envItem.Description += " (Has ILT)"
                        }
                        
                        if ($WhatIf) {
                            Write-Host "  [WHAT-IF] Would add environment variable '$($envItem.Variable)' = '$($envItem.Value)'" -ForegroundColor Cyan
                        } else {
                            $currentConfig.EnvironmentVariables += $envItem
                            Write-Host "  Added environment variable '$($envItem.Variable)' = '$($envItem.Value)'" -ForegroundColor Green
                        }
                        
                        $counters.Environment++
                        $sequences.Environment++
                    }
                }
                
                Write-Verbose "Processed environment variables XML for $scope scope: $($counters.Environment) items"
                
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
                
                foreach ($printer in $xml.Printers.SharedPrinter) {
                    if ($printer.Properties) {
                        $props = $printer.Properties
                        
                        # Skip delete actions
                        if ($props.action -eq "D") {
                            Write-Verbose "Skipping delete action for printer $($props.path)"
                            continue
                        }
                        
                        $printerItem = @{
                            Action = 0  # Always use Create
                            AutoAdd = $true
                            DoNotCapturePortIfLocalIsOnPort = $false
                            DoNotDefaultIfLocalIsDefault = $false
                            Port = 0
                            ProcessActionPostLogin = $ProcessPostLogin
                            SetAsDefault = ($props.default -eq "1")
                            SharedPrinter = $props.path
                            Filter = if ($filterId) { $FilterName } else { $null }
                            FilterId = $filterId
                            Description = "Imported from GPO: $GpoDisplayName ($scope)"
                            Disabled = ($printer.disabled -eq "1")
                            Sequence = $sequences.Printers
                        }
                        
                        if ($printer.Filters) {
                            $printerItem.Description += " (Has ILT)"
                        }
                        
                        if ($WhatIf) {
                            Write-Host "  [WHAT-IF] Would add printer '$($printerItem.SharedPrinter)'" -ForegroundColor Cyan
                        } else {
                            $currentConfig.Printers += $printerItem
                            Write-Host "  Added printer '$($printerItem.SharedPrinter)'" -ForegroundColor Green
                        }
                        
                        $counters.Printers++
                        $sequences.Printers++
                    }
                }
                
                Write-Verbose "Processed printers XML for $scope scope: $($counters.Printers) items"
                
            } catch {
                Write-Warning "Failed to process printers XML for $scope scope: $($_.Exception.Message)"
            }
        }
    }
}

# Update configuration storage
if ($script:ModuleConfig -and $script:ModuleConfig.CurrentItems) {
    $script:ModuleConfig.CurrentItems.Config = $currentConfig
}
$global:CurrentConfig = $currentConfig

# Display summary
$totalImported = $counters.Drives + $counters.Shortcuts + $counters.Registry + $counters.Environment + $counters.Printers

Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "IMPORT SUMMARY" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "Items imported from GPO '$GpoDisplayName':" -ForegroundColor Yellow

if ($IncludeDrives) { Write-Host "  Drive Mappings: $($counters.Drives)" -ForegroundColor Green }
if ($IncludeShortcuts) { Write-Host "  Shortcuts: $($counters.Shortcuts)" -ForegroundColor Green }
if ($IncludeRegistry) { Write-Host "  Registry Settings: $($counters.Registry)" -ForegroundColor Green }
if ($IncludeEnvironment) { Write-Host "  Environment Variables: $($counters.Environment)" -ForegroundColor Green }
if ($IncludePrinters) { Write-Host "  Printers: $($counters.Printers)" -ForegroundColor Green }

Write-Host "`nTotal items imported: $totalImported" -ForegroundColor Cyan

if ($filterId) {
    Write-Host "Filter applied: $FilterName (ID: $filterId)" -ForegroundColor Yellow
}

# Handle saving
if ($WhatIf) {
    Write-Host "`n[WHAT-IF MODE] No changes were made to the configuration" -ForegroundColor Yellow
    Write-Host "Remove -WhatIf parameter to perform the actual import" -ForegroundColor Yellow
} elseif ($totalImported -gt 0) {
    Write-Host "`nConfiguration updated in memory" -ForegroundColor Green
    Write-Host "Use Save-ProUConfig to save changes to ProfileUnity server" -ForegroundColor Yellow
    
    # Offer to save automatically
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
} else {
    Write-Host "`nNo items were imported from the GPO." -ForegroundColor Yellow
    Write-Host "This might indicate:" -ForegroundColor Yellow
    Write-Host "  - No Group Policy Preferences are configured in the GPO" -ForegroundColor Yellow
    Write-Host "  - All preference items are set to 'Delete' action" -ForegroundColor Yellow
    Write-Host "  - GPO preference XML files are missing or corrupted" -ForegroundColor Yellow
}

Write-Host "`n" + ("=" * 60) -ForegroundColor Green
Write-Host "IMPORT PROCESS COMPLETED" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green

# Script reference
Write-Verbose "Script: Import-GPOPreferencesToProfileUnity.ps1"
Write-Verbose "Location: \Scripts\GPO-Migration\"
Write-Verbose "Compatible with: ProfileUnity PowerTools v3.0"