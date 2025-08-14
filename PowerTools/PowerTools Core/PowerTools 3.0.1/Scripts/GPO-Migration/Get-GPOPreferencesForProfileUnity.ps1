# Get-GPOPreferencesForProfileUnity.ps1
# Location: \Scripts\GPO-Analysis\
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
    Creates output files (CSV and JSON). If not specified, only console output is shown
.EXAMPLE
    .\Get-GPOPreferencesForProfileUnity.ps1 -GpoDisplayName "UserSettings" -IncludeAll -ExportFiles
.EXAMPLE
    .\Get-GPOPreferencesForProfileUnity.ps1 -GpoDisplayName "DriveMapGPO" -IncludeDrives -IncludeShortcuts
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
    
    [switch]$ExportFiles
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

# Get and validate GPO
Write-Host "Retrieving GPO information..." -ForegroundColor Yellow
try {
    $gpo = Get-GPO -Name $GpoDisplayName -ErrorAction Stop
    Write-Host "GPO found: $GpoDisplayName (ID: $($gpo.Id))" -ForegroundColor Green
} catch {
    throw "GPO '$GpoDisplayName' not found: $($_.Exception.Message)"
}

Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "GPO PREFERENCES ANALYSIS" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "GPO: $GpoDisplayName" -ForegroundColor Yellow
Write-Host "GPO ID: $($gpo.Id)" -ForegroundColor Yellow

# Show what will be included
Write-Host "`nGPP Types to Extract:" -ForegroundColor Yellow
if ($IncludeDrives) { Write-Host "  [✓] Drive Mappings" -ForegroundColor Green }
if ($IncludeShortcuts) { Write-Host "  [✓] Shortcuts" -ForegroundColor Green }
if ($IncludeRegistry) { Write-Host "  [✓] Registry Settings" -ForegroundColor Green }
if ($IncludeEnvironment) { Write-Host "  [✓] Environment Variables" -ForegroundColor Green }
if ($IncludePrinters) { Write-Host "  [✓] Printers" -ForegroundColor Green }

# Get GPO path
$domain = (Get-ADDomain).DNSRoot
$gpoPath = "\\$domain\SYSVOL\$domain\Policies\{$($gpo.Id)}"

Write-Host "`nGPO Path: $gpoPath" -ForegroundColor Cyan

# Initialize results collection
$allItems = @()

# Function to parse Item Level Targeting
function Get-ItemLevelTargeting {
    [CmdletBinding()]
    param (
        [System.Xml.XmlElement]$FiltersNode
    )
    
    if (-not $FiltersNode) { 
        return $null 
    }
    
    $filters = @()
    
    foreach ($filter in $FiltersNode.ChildNodes) {
        if ($filter.NodeType -ne [System.Xml.XmlNodeType]::Element) { 
            continue 
        }
        
        $filterInfo = @{
            Type = $filter.LocalName
            Not = ($filter.not -eq "1")
            Details = @{}
        }
        
        switch ($filter.LocalName) {
            "FilterGroup" {
                $filterInfo.Details.GroupName = $filter.name
                $filterInfo.Details.UserInGroup = ($filter.userContext -eq "1")
                $filterInfo.Details.SID = $filter.sid
            }
            "FilterComputer" {
                $filterInfo.Details.Name = $filter.name
                $filterInfo.Details.DirectMatch = ($filter.directMatch -eq "1")
            }
            "FilterOrgUnit" {
                $filterInfo.Details.OU = $filter.name
                $filterInfo.Details.DirectMatch = ($filter.directMatch -eq "1")
            }
            "FilterWMI" {
                $filterInfo.Details.Query = $filter.query
                $filterInfo.Details.Namespace = $filter.nameSpace
            }
            "FilterCollection" {
                $filterInfo.Details.Operator = if ($filter.bool -eq "AND") { "AND" } else { "OR" }
                $filterInfo.Details.Filters = Get-ItemLevelTargeting -FiltersNode $filter
            }
            default {
                # Generic attribute extraction
                foreach ($attr in $filter.Attributes) {
                    if ($attr.Name -notin @('not', 'bool')) {
                        $filterInfo.Details[$attr.Name] = $attr.Value
                    }
                }
            }
        }
        
        $filters += $filterInfo
    }
    
    return $filters
}

# Function to process GPP elements recursively
function Get-GPPElement {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Xml.XmlElement]$Element,
        
        [string]$ParentPath = "",
        
        [Parameter(Mandatory)]
        [string]$Scope,
        
        [Parameter(Mandatory)]
        [string]$GPPSection
    )
    
    $results = @()
    
    Write-Verbose "Processing element: $($Element.LocalName) '$($Element.name)'"
    
    # Check if this is a Collection container
    $isCollection = ($Element.LocalName -eq "Collection") -or 
                    ($Element.clsid -eq "{53B533F5-224C-47e3-B01B-CA3B3F3FF4BF}")
    
    if ($isCollection) {
        # Process collection children
        $collectionPath = if ($ParentPath) { "$ParentPath\$($Element.name)" } else { $Element.name }
        
        Write-Verbose "Processing collection with $($Element.ChildNodes.Count) children"
        
        foreach ($child in $Element.ChildNodes) {
            if ($child.NodeType -eq [System.Xml.XmlNodeType]::Element) {
                $childResults = Get-GPPElement -Element $child -ParentPath $collectionPath -Scope $Scope -GPPSection $GPPSection
                $results += $childResults
            }
        }
    } else {
        # Process actual preference item
        $item = @{
            Type = $Element.LocalName
            GPPSection = $GPPSection
            Scope = $Scope
            Path = $ParentPath
            Name = $Element.name
            Status = $Element.status
            Changed = $Element.changed
            UID = $Element.uid
            Disabled = ($Element.disabled -eq "1")
            Properties = @{}
            ItemLevelTargeting = $null
        }
        
        # Extract properties based on GPP section type
        $propsNode = $Element.Properties
        if ($propsNode) {
            switch ($GPPSection) {
                "Registry" {
                    $item.Properties = @{
                        Action = switch ($propsNode.action) {
                            "C" { "Create" }
                            "R" { "Replace" }
                            "U" { "Update" }
                            "D" { "Delete" }
                            default { $propsNode.action }
                        }
                        Hive = $propsNode.hive
                        Key = $propsNode.key
                        ValueName = if ($propsNode.name) { $propsNode.name } else { "(Default)" }
                        Type = $propsNode.type
                        Value = $propsNode.value
                        Default = ($propsNode.default -eq "1")
                    }
                    $item.Type = "Registry"
                }
                "NetworkShares" {
                    $item.Properties = @{
                        Action = switch ($propsNode.action) {
                            "C" { "Create" }
                            "R" { "Replace" }
                            "U" { "Update" }
                            "D" { "Delete" }
                            default { $propsNode.action }
                        }
                        DriveLetter = $propsNode.letter
                        Path = $propsNode.path
                        Label = $propsNode.label
                        Comment = $propsNode.comment
                        Persistent = ($propsNode.persistent -eq "1")
                        UseLetter = ($propsNode.useLetter -eq "1")
                        ReconnectEnabled = ($propsNode.reconnectEnable -eq "1")
                    }
                    $item.Type = "DriveMapping"
                }
                "Shortcuts" {
                    $item.Properties = @{
                        Action = switch ($propsNode.action) {
                            "C" { "Create" }
                            "R" { "Replace" }
                            "U" { "Update" }
                            "D" { "Delete" }
                            default { $propsNode.action }
                        }
                        Name = $propsNode.shortcutName
                        TargetPath = $propsNode.targetPath
                        TargetType = $propsNode.targetType
                        ShortcutPath = $propsNode.shortcutPath
                        Arguments = $propsNode.arguments
                        StartIn = $propsNode.startIn
                        IconPath = $propsNode.iconPath
                        IconIndex = $propsNode.iconIndex
                        Comment = $propsNode.comment
                        WindowStyle = $propsNode.windowStyle
                    }
                    $item.Type = "Shortcut"
                }
                "EnvironmentVariables" {
                    $item.Properties = @{
                        Action = switch ($propsNode.action) {
                            "C" { "Create" }
                            "R" { "Replace" }
                            "U" { "Update" }
                            "D" { "Delete" }
                            default { $propsNode.action }
                        }
                        Name = $propsNode.name
                        Value = $propsNode.value
                        User = ($propsNode.user -eq "1")
                        Partial = ($propsNode.partial -eq "1")
                    }
                    $item.Type = "EnvironmentVariable"
                }
                "Printers" {
                    $item.Properties = @{
                        Action = switch ($propsNode.action) {
                            "C" { "Create" }
                            "R" { "Replace" }
                            "U" { "Update" }
                            "D" { "Delete" }
                            default { $propsNode.action }
                        }
                        Name = $propsNode.name
                        Path = $propsNode.path
                        Default = ($propsNode.default -eq "1")
                        Location = $propsNode.location
                        Comment = $propsNode.comment
                        SharedPrinter = $true
                    }
                    $item.Type = "Printer"
                }
                default {
                    # Generic property extraction for unknown types
                    foreach ($attr in $propsNode.Attributes) {
                        $item.Properties[$attr.Name] = $attr.Value
                    }
                }
            }
        }
        
        # Parse Item Level Targeting if present
        if ($Element.Filters) {
            $item.ItemLevelTargeting = Get-ItemLevelTargeting -FiltersNode $Element.Filters
        }
        
        $results += $item
        Write-Verbose "Added item: $($item.Name) (Type: $($item.Type))"
    }
    
    return $results
}

# Function to process preference XML files
function Get-PreferenceItems {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$XmlPath,
        
        [Parameter(Mandatory)]
        [string]$PreferenceType,
        
        [Parameter(Mandatory)]
        [string]$Scope,
        
        [Parameter(Mandatory)]
        [string]$GPPSection
    )
    
    if (-not (Test-Path $XmlPath)) {
        Write-Verbose "XML file not found: $XmlPath"
        return @()
    }
    
    Write-Host "  Processing $PreferenceType..." -ForegroundColor Yellow
    
    try {
        [xml]$xml = Get-Content $XmlPath -Raw -Encoding UTF8 -ErrorAction Stop
        Write-Verbose "Successfully loaded XML: $XmlPath"
    } catch {
        Write-Warning "Failed to parse XML file '$XmlPath': $($_.Exception.Message)"
        return @()
    }
    
    Write-Verbose "XML Root: $($xml.DocumentElement.LocalName)"
    Write-Verbose "Root children count: $($xml.DocumentElement.ChildNodes.Count)"
    
    $results = @()
    
    # Process all root-level elements
    foreach ($element in $xml.DocumentElement.ChildNodes) {
        if ($element.NodeType -eq [System.Xml.XmlNodeType]::Element) {
            $elementResults = Get-GPPElement -Element $element -Scope $Scope -GPPSection $GPPSection
            $results += $elementResults
        }
    }
    
    Write-Host "    Found $($results.Count) items" -ForegroundColor Cyan
    return $results
}

# Define preference locations to process
$preferenceConfig = @{}

if ($IncludeDrives) {
    $preferenceConfig["NetworkShares"] = @{
        Path = "Drives\Drives.xml"
        DisplayName = "Drive Mappings"
    }
}

if ($IncludeShortcuts) {
    $preferenceConfig["Shortcuts"] = @{
        Path = "Shortcuts\Shortcuts.xml"
        DisplayName = "Shortcuts"
    }
}

if ($IncludeRegistry) {
    $preferenceConfig["Registry"] = @{
        Path = "Registry\Registry.xml"
        DisplayName = "Registry Settings"
    }
}

if ($IncludeEnvironment) {
    $preferenceConfig["EnvironmentVariables"] = @{
        Path = "EnvironmentVariables\EnvironmentVariables.xml"
        DisplayName = "Environment Variables"
    }
}

if ($IncludePrinters) {
    $preferenceConfig["Printers"] = @{
        Path = "Printers\Printers.xml"
        DisplayName = "Printers"
    }
}

# Process both Computer and User preferences
Write-Host "`nScanning GPO preferences..." -ForegroundColor Yellow

foreach ($scope in @("Machine", "User")) {
    $preferencesPath = Join-Path $gpoPath "$scope\Preferences"
    
    if (Test-Path $preferencesPath) {
        Write-Host "`n$scope Configuration:" -ForegroundColor Green
        
        foreach ($prefConfig in $preferenceConfig.GetEnumerator()) {
            $xmlPath = Join-Path $preferencesPath $prefConfig.Value.Path
            
            if (Test-Path $xmlPath) {
                $items = Get-PreferenceItems -XmlPath $xmlPath -PreferenceType $prefConfig.Key -Scope $scope -GPPSection $prefConfig.Key
                
                if ($items.Count -gt 0) {
                    $allItems += $items
                    Write-Verbose "Added $($items.Count) $($prefConfig.Value.DisplayName) items from $scope scope"
                }
            } else {
                Write-Verbose "Preferences XML not found: $xmlPath"
            }
        }
    } else {
        Write-Verbose "Preferences folder not found: $preferencesPath"
    }
}

# Display console results
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "PROFILEUNITY-COMPATIBLE GPP ITEMS" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan

if ($allItems.Count -eq 0) {
    Write-Host "`nNo items found matching the selected criteria." -ForegroundColor Yellow
    Write-Host "This might indicate:" -ForegroundColor Yellow
    Write-Host "  - No Group Policy Preferences are configured in this GPO" -ForegroundColor Yellow
    Write-Host "  - The selected preference types are not used in this GPO" -ForegroundColor Yellow
    Write-Host "  - GPO preference files are missing or corrupted" -ForegroundColor Yellow
} else {
    # Group items for display
    $itemGroups = @{}
    foreach ($item in $allItems) {
        $key = "$($item.GPPSection)_$($item.Scope)"
        if (-not $itemGroups.ContainsKey($key)) {
            $itemGroups[$key] = @()
        }
        $itemGroups[$key] += $item
    }
    
    Write-Verbose "Created $($itemGroups.Count) display groups"
    
    foreach ($groupKey in ($itemGroups.Keys | Sort-Object)) {
        $keyParts = $groupKey -split '_'
        $section = $keyParts[0]
        $scope = $keyParts[1]
        $items = $itemGroups[$groupKey]
        
        # Get friendly display name
        $displayName = switch ($section) {
            "NetworkShares" { "Drive Mappings" }
            "Shortcuts" { "Shortcuts" }
            "Registry" { "Registry Settings" }
            "EnvironmentVariables" { "Environment Variables" }
            "Printers" { "Printers" }
            default { $section }
        }
        
        Write-Host "`n$displayName - $scope ($($items.Count) items):" -ForegroundColor Yellow
        
        foreach ($item in $items) {
            Write-Host "`n  Item: $($item.Name)" -ForegroundColor Cyan
            
            if ($item.Path) {
                Write-Host "  Collection Path: $($item.Path)" -ForegroundColor Gray
            }
            
            if ($item.Disabled) {
                Write-Host "  STATUS: DISABLED" -ForegroundColor Red
            }
            
            # Display properties based on section type
            Write-Host "  Properties:" -ForegroundColor Green
            
            switch ($item.GPPSection) {
                "Registry" {
                    Write-Host "    Action: $($item.Properties.Action)" -ForegroundColor White
                    Write-Host "    Registry Key: $($item.Properties.Hive)\$($item.Properties.Key)" -ForegroundColor White
                    Write-Host "    Value Name: $($item.Properties.ValueName)" -ForegroundColor White
                    if ($item.Properties.Type) {
                        Write-Host "    Value Type: $($item.Properties.Type)" -ForegroundColor White
                        Write-Host "    Value Data: $($item.Properties.Value)" -ForegroundColor White
                    }
                }
                "NetworkShares" {
                    Write-Host "    Action: $($item.Properties.Action)" -ForegroundColor White
                    Write-Host "    Drive Letter: $($item.Properties.DriveLetter)" -ForegroundColor White
                    Write-Host "    Network Path: $($item.Properties.Path)" -ForegroundColor White
                    if ($item.Properties.Label) {
                        Write-Host "    Label: $($item.Properties.Label)" -ForegroundColor White
                    }
                    Write-Host "    Persistent: $($item.Properties.Persistent)" -ForegroundColor White
                }
                "Shortcuts" {
                    Write-Host "    Action: $($item.Properties.Action)" -ForegroundColor White
                    Write-Host "    Shortcut Location: $($item.Properties.ShortcutPath)" -ForegroundColor White
                    Write-Host "    Target Path: $($item.Properties.TargetPath)" -ForegroundColor White
                    if ($item.Properties.Arguments) {
                        Write-Host "    Arguments: $($item.Properties.Arguments)" -ForegroundColor White
                    }
                    if ($item.Properties.StartIn) {
                        Write-Host "    Working Directory: $($item.Properties.StartIn)" -ForegroundColor White
                    }
                }
                "EnvironmentVariables" {
                    Write-Host "    Action: $($item.Properties.Action)" -ForegroundColor White
                    Write-Host "    Variable Name: $($item.Properties.Name)" -ForegroundColor White
                    Write-Host "    Variable Value: $($item.Properties.Value)" -ForegroundColor White
                    Write-Host "    User Variable: $($item.Properties.User)" -ForegroundColor White
                }
                "Printers" {
                    Write-Host "    Action: $($item.Properties.Action)" -ForegroundColor White
                    Write-Host "    Printer Name: $($item.Properties.Name)" -ForegroundColor White
                    Write-Host "    Printer Path: $($item.Properties.Path)" -ForegroundColor White
                    Write-Host "    Set as Default: $($item.Properties.Default)" -ForegroundColor White
                    if ($item.Properties.Location) {
                        Write-Host "    Location: $($item.Properties.Location)" -ForegroundColor White
                    }
                }
            }
            
            # Display Item Level Targeting if present
            if ($item.ItemLevelTargeting) {
                Write-Host "  Item Level Targeting:" -ForegroundColor Magenta
                foreach ($filter in $item.ItemLevelTargeting) {
                    $notText = if ($filter.Not) { "NOT " } else { "" }
                    Write-Host "    - $notText$($filter.Type)" -ForegroundColor Yellow
                    
                    foreach ($detail in $filter.Details.GetEnumerator()) {
                        Write-Host "      $($detail.Key): $($detail.Value)" -ForegroundColor Gray
                    }
                }
            }
        }
    }
}

# Summary by type
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "MIGRATION SUMMARY" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan

if ($allItems.Count -gt 0) {
    $typeSummary = $allItems | Group-Object -Property GPPSection | Sort-Object Name
    
    foreach ($typeGroup in $typeSummary) {
        $displayName = switch ($typeGroup.Name) {
            "NetworkShares" { "Drive Mappings" }
            "Shortcuts" { "Shortcuts" }
            "Registry" { "Registry Settings" }  
            "EnvironmentVariables" { "Environment Variables" }
            "Printers" { "Printers" }
            default { $typeGroup.Name }
        }
        
        $computerCount = ($typeGroup.Group | Where-Object { $_.Scope -eq "Machine" }).Count
        $userCount = ($typeGroup.Group | Where-Object { $_.Scope -eq "User" }).Count
        $iltCount = ($typeGroup.Group | Where-Object { $_.ItemLevelTargeting }).Count
        
        Write-Host "`n$displayName`: $($typeGroup.Count) total" -ForegroundColor Yellow
        Write-Host "  Computer Configuration: $computerCount" -ForegroundColor Gray
        Write-Host "  User Configuration: $userCount" -ForegroundColor Gray
        
        if ($iltCount -gt 0) {
            Write-Host "  Items with Targeting: $iltCount" -ForegroundColor Magenta
        }
    }
}

Write-Host "`nTotal ProfileUnity-compatible items: $($allItems.Count)" -ForegroundColor Green

# Export files if requested
if ($ExportFiles -and $allItems.Count -gt 0) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $safeGpoName = $GpoDisplayName -replace '[^\w\s-]', '' -replace '\s+', '_'
    
    # Create ProfileUnity-specific JSON export
    Write-Host "`nExporting analysis results..." -ForegroundColor Yellow
    
    $jsonPath = Join-Path $OutputFolder "GPO_ProfileUnity_Analysis_${safeGpoName}_$timestamp.json"
    $exportData = @{
        GPOName = $GpoDisplayName
        GPOID = $gpo.Id.ToString()
        Generated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        AnalysisScope = @{
            IncludeDrives = $IncludeDrives
            IncludeShortcuts = $IncludeShortcuts
            IncludeRegistry = $IncludeRegistry
            IncludeEnvironment = $IncludeEnvironment
            IncludePrinters = $IncludePrinters
        }
        ProfileUnityMigration = @{
            DriveMappings = @($allItems | Where-Object { $_.GPPSection -eq "NetworkShares" })
            Shortcuts = @($allItems | Where-Object { $_.GPPSection -eq "Shortcuts" })
            Registry = @($allItems | Where-Object { $_.GPPSection -eq "Registry" })
            EnvironmentVariables = @($allItems | Where-Object { $_.GPPSection -eq "EnvironmentVariables" })
            Printers = @($allItems | Where-Object { $_.GPPSection -eq "Printers" })
        }
        Summary = @{
            TotalItems = $allItems.Count
            TypeBreakdown = @{}
        }
    }
    
    # Add summary breakdown
    if ($allItems.Count -gt 0) {
        $typeSummary = $allItems | Group-Object -Property GPPSection
        foreach ($typeGroup in $typeSummary) {
            $displayName = switch ($typeGroup.Name) {
                "NetworkShares" { "DriveMappings" }
                "Shortcuts" { "Shortcuts" }
                "Registry" { "Registry" }
                "EnvironmentVariables" { "EnvironmentVariables" }
                "Printers" { "Printers" }
                default { $typeGroup.Name }
            }
            
            $exportData.Summary.TypeBreakdown[$displayName] = @{
                Total = $typeGroup.Count
                Computer = ($typeGroup.Group | Where-Object { $_.Scope -eq "Machine" }).Count
                User = ($typeGroup.Group | Where-Object { $_.Scope -eq "User" }).Count
                WithILT = ($typeGroup.Group | Where-Object { $_.ItemLevelTargeting }).Count
            }
        }
    }
    
    try {
        $exportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8 -ErrorAction Stop
        Write-Host "JSON export saved: $jsonPath" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to export JSON: $($_.Exception.Message)"
    }
    
    # Create CSV for easy analysis
    $csvPath = Join-Path $OutputFolder "GPO_ProfileUnity_Items_${safeGpoName}_$timestamp.csv"
    $csvData = @()
    
    foreach ($item in $allItems) {
        $csvRow = [PSCustomObject]@{
            GPPType = switch ($item.GPPSection) {
                "NetworkShares" { "Drive Mappings" }
                "Shortcuts" { "Shortcuts" }
                "Registry" { "Registry Settings" }
                "EnvironmentVariables" { "Environment Variables" }
                "Printers" { "Printers" }
                default { $item.GPPSection }
            }
            Scope = $item.Scope
            ItemName = $item.Name
            CollectionPath = $item.Path
            Disabled = $item.Disabled
            HasILT = [bool]$item.ItemLevelTargeting
            Action = $item.Properties.Action
        }
        
        # Add type-specific columns
        switch ($item.GPPSection) {
            "Registry" {
                $csvRow | Add-Member -NotePropertyName "RegistryKey" -NotePropertyValue "$($item.Properties.Hive)\$($item.Properties.Key)"
                $csvRow | Add-Member -NotePropertyName "ValueName" -NotePropertyValue $item.Properties.ValueName
                $csvRow | Add-Member -NotePropertyName "ValueType" -NotePropertyValue $item.Properties.Type
                $csvRow | Add-Member -NotePropertyName "ValueData" -NotePropertyValue $item.Properties.Value
            }
            "NetworkShares" {
                $csvRow | Add-Member -NotePropertyName "DriveLetter" -NotePropertyValue $item.Properties.DriveLetter
                $csvRow | Add-Member -NotePropertyName "NetworkPath" -NotePropertyValue $item.Properties.Path
                $csvRow | Add-Member -NotePropertyName "DriveLabel" -NotePropertyValue $item.Properties.Label
                $csvRow | Add-Member -NotePropertyName "Persistent" -NotePropertyValue $item.Properties.Persistent
            }
            "Shortcuts" {
                $csvRow | Add-Member -NotePropertyName "ShortcutLocation" -NotePropertyValue $item.Properties.ShortcutPath
                $csvRow | Add-Member -NotePropertyName "TargetPath" -NotePropertyValue $item.Properties.TargetPath
                $csvRow | Add-Member -NotePropertyName "Arguments" -NotePropertyValue $item.Properties.Arguments
                $csvRow | Add-Member -NotePropertyName "WorkingDirectory" -NotePropertyValue $item.Properties.StartIn
            }
            "EnvironmentVariables" {
                $csvRow | Add-Member -NotePropertyName "VariableName" -NotePropertyValue $item.Properties.Name
                $csvRow | Add-Member -NotePropertyName "VariableValue" -NotePropertyValue $item.Properties.Value
                $csvRow | Add-Member -NotePropertyName "UserVariable" -NotePropertyValue $item.Properties.User
            }
            "Printers" {
                $csvRow | Add-Member -NotePropertyName "PrinterName" -NotePropertyValue $item.Properties.Name
                $csvRow | Add-Member -NotePropertyName "PrinterPath" -NotePropertyValue $item.Properties.Path
                $csvRow | Add-Member -NotePropertyName "SetAsDefault" -NotePropertyValue $item.Properties.Default
                $csvRow | Add-Member -NotePropertyName "PrinterLocation" -NotePropertyValue $item.Properties.Location
            }
        }
        
        $csvData += $csvRow
    }
    
    if ($csvData.Count -gt 0) {
        try {
            $csvData | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
            Write-Host "CSV export saved: $csvPath" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to export CSV: $($_.Exception.Message)"
        }
    }
    
    Write-Host "`nExport files created in: $OutputFolder" -ForegroundColor Cyan
    
} elseif ($ExportFiles -and $allItems.Count -eq 0) {
    Write-Host "`nNo items found to export." -ForegroundColor Yellow
} else {
    Write-Host "`nTip: Use -ExportFiles to save results to JSON and CSV files" -ForegroundColor Gray
}

Write-Host "`n" + ("=" * 70) -ForegroundColor Green
Write-Host "ANALYSIS COMPLETED" -ForegroundColor Green
Write-Host ("=" * 70) -ForegroundColor Green

# Script reference  
Write-Verbose "Script: Get-GPOPreferencesForProfileUnity.ps1"
Write-Verbose "Location: \Scripts\GPO-Analysis\"
Write-Verbose "Compatible with: ProfileUnity PowerTools v3.0"