<#
.SYNOPSIS
    Extracts Group Policy Preferences for ProfileUnity migration.
.DESCRIPTION
    This script analyzes a GPO and extracts specific Group Policy Preferences settings
    that can be migrated to ProfileUnity: Drive Mappings, Shortcuts, Registry, Environment Variables, and Printers.
.PARAMETER GpoDisplayName
    Display name of the target GPO.
.PARAMETER IncludeDrives
    Include Drive Mappings in the output.
.PARAMETER IncludeShortcuts
    Include Shortcuts in the output.
.PARAMETER IncludeRegistry
    Include Registry settings in the output.
.PARAMETER IncludeEnvironment
    Include Environment Variables in the output.
.PARAMETER IncludePrinters
    Include Printer settings in the output.
.PARAMETER IncludeAll
    Include all supported GPP types (Drives, Shortcuts, Registry, Environment Variables, Printers).
.PARAMETER OutputFolder
    Folder where output files are saved (default: script directory).
.PARAMETER ExportFiles
    Creates output files (TXT report, CSV, and JSON). If not specified, only console output is shown.
.PARAMETER VerboseOutput
    Shows detailed processing information for troubleshooting.
.EXAMPLE
    .\Get-GPOPreferencesForProfileUnity-Clean.ps1 -GpoDisplayName "UserSettings" -IncludeAll
.EXAMPLE
    .\Get-GPOPreferencesForProfileUnity-Clean.ps1 -GpoDisplayName "UserSettings" -IncludeRegistry -IncludeDrives -ExportFiles
#>

param (
    [Parameter(Mandatory)]
    [string]$GpoDisplayName,

    [switch]$IncludeDrives,
    
    [switch]$IncludeShortcuts,
    
    [switch]$IncludeRegistry,
    
    [switch]$IncludeEnvironment,
    
    [switch]$IncludePrinters,
    
    [switch]$IncludeAll,

    [string]$OutputFolder = "$PSScriptRoot",
    
    [switch]$ExportFiles,
    
    [switch]$VerboseOutput
)

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

# Get GPO info
try {
    $Gpo = Get-GPO -Name $GpoDisplayName -ErrorAction Stop
} catch {
    Write-Error "GPO '$GpoDisplayName' not found."
    exit 1
}

Write-Host "`nAnalyzing GPO: $GpoDisplayName" -ForegroundColor Cyan
Write-Host "GPO ID: $($Gpo.Id)" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

# Show what will be included
Write-Host "`nGPP Types to Extract:" -ForegroundColor Yellow
if ($IncludeDrives) { Write-Host "  [X] Drive Mappings" -ForegroundColor Green }
if ($IncludeShortcuts) { Write-Host "  [X] Shortcuts" -ForegroundColor Green }
if ($IncludeRegistry) { Write-Host "  [X] Registry Settings" -ForegroundColor Green }
if ($IncludeEnvironment) { Write-Host "  [X] Environment Variables" -ForegroundColor Green }
if ($IncludePrinters) { Write-Host "  [X] Printers" -ForegroundColor Green }

# Get GPO path
$Domain = (Get-ADDomain).DNSRoot
$GpoPath = "\\$Domain\SYSVOL\$Domain\Policies\{$($Gpo.Id)}"

# Initialize results
$allItems = @()

# Function to parse Item Level Targeting
function Parse-ItemLevelTargeting {
    param ([System.Xml.XmlElement]$FiltersNode)
    
    if (-not $FiltersNode) { return $null }
    
    $filters = @()
    
    foreach ($filter in $FiltersNode.ChildNodes) {
        if ($filter.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
        
        $filterInfo = @{
            Type = $filter.LocalName
            Not = $filter.not -eq "1"
            Details = @{}
        }
        
        switch ($filter.LocalName) {
            "FilterGroup" {
                $filterInfo.Details.GroupName = $filter.name
                $filterInfo.Details.UserInGroup = $filter.userContext -eq "1"
                $filterInfo.Details.SID = $filter.sid
            }
            "FilterComputer" {
                $filterInfo.Details.Name = $filter.name
                $filterInfo.Details.DirectMatch = $filter.directMatch -eq "1"
            }
            "FilterOrgUnit" {
                $filterInfo.Details.OU = $filter.name
                $filterInfo.Details.DirectMatch = $filter.directMatch -eq "1"
            }
            "FilterWMI" {
                $filterInfo.Details.Query = $filter.query
                $filterInfo.Details.Namespace = $filter.nameSpace
            }
            "FilterCollection" {
                $filterInfo.Details.Operator = if ($filter.bool -eq "AND") { "AND" } else { "OR" }
                $filterInfo.Details.Filters = Parse-ItemLevelTargeting -FiltersNode $filter
            }
            default {
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

# Function to recursively process collections and items
function Process-GPPElement {
    param (
        [System.Xml.XmlElement]$Element,
        [string]$ParentPath = "",
        [string]$Scope,
        [string]$GPPSection
    )
    
    $results = @()
    
    if ($script:VerboseOutput) {
        Write-Host "      Processing: $($Element.LocalName) '$($Element.name)' (CLSID: $($Element.clsid))" -ForegroundColor DarkYellow
    }
    
    # Check if this is a Collection
    $isCollection = ($Element.LocalName -eq "Collection") -or 
                    ($Element.clsid -eq "{53B533F5-224C-47e3-B01B-CA3B3F3FF4BF}")
    
    if ($isCollection) {
        # This is a collection, process its children
        $collectionPath = if ($ParentPath) { "$ParentPath\$($Element.name)" } else { $Element.name }
        
        if ($script:VerboseOutput) {
            Write-Host "        Collection with $($Element.ChildNodes.Count) children" -ForegroundColor DarkGray
        }
        
        foreach ($child in $Element.ChildNodes) {
            if ($child.NodeType -eq [System.Xml.XmlNodeType]::Element) {
                $childResults = Process-GPPElement -Element $child -ParentPath $collectionPath -Scope $Scope -GPPSection $GPPSection
                $results += $childResults
            }
        }
    }
    else {
        # This is an actual preference item
        $item = @{
            Type = $Element.LocalName
            GPPSection = $GPPSection
            Scope = $Scope
            Path = $ParentPath
            Name = $Element.name
            Status = $Element.status
            Changed = $Element.changed
            UID = $Element.uid
            Disabled = $Element.disabled -eq "1"
            Properties = @{}
            ItemLevelTargeting = $null
        }
        
        # Get properties based on type
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
                        Default = $propsNode.default -eq "1"
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
                        Persistent = $propsNode.persistent -eq "1"
                        UseLetter = $propsNode.useLetter -eq "1"
                        ReconnectEnabled = $propsNode.reconnectEnable -eq "1"
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
                        User = $propsNode.user -eq "1"
                        Partial = $propsNode.partial -eq "1"
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
                        Default = $propsNode.default -eq "1"
                        Location = $propsNode.location
                        Comment = $propsNode.comment
                        SharedPrinter = $true
                    }
                    $item.Type = "Printer"
                }
                default {
                    # Generic property extraction
                    foreach ($attr in $propsNode.Attributes) {
                        $item.Properties[$attr.Name] = $attr.Value
                    }
                }
            }
        }
        
        # Parse Item Level Targeting
        if ($Element.Filters) {
            $item.ItemLevelTargeting = Parse-ItemLevelTargeting -FiltersNode $Element.Filters
        }
        
        $results += $item
        
        if ($script:VerboseOutput) {
            Write-Host "        Added item: $($item.Name)" -ForegroundColor DarkGreen
        }
    }
    
    return $results
}

# Function to process preference XML files
function Process-PreferenceXml {
    param (
        [string]$XmlPath,
        [string]$PreferenceType,
        [string]$Scope,
        [string]$GPPSection
    )
    
    if (-not (Test-Path $XmlPath)) {
        return @()
    }
    
    Write-Host "`n  Processing $($PreferenceType)..." -ForegroundColor Yellow
    
    try {
        [xml]$xml = Get-Content $XmlPath -Raw -Encoding UTF8
    } catch {
        Write-Warning "Failed to parse ${XmlPath}: $_"
        return @()
    }
    
    if ($VerboseOutput) {
        Write-Host "    XML Root: $($xml.DocumentElement.LocalName)" -ForegroundColor DarkGray
        Write-Host "    Root children: $($xml.DocumentElement.ChildNodes.Count)" -ForegroundColor DarkGray
        Write-Host "    GPPSection being passed: $GPPSection" -ForegroundColor DarkGray
    }
    
    $results = @()
    
    # Process all root elements
    foreach ($element in $xml.DocumentElement.ChildNodes) {
        if ($element.NodeType -eq [System.Xml.XmlNodeType]::Element) {
            $elementResults = Process-GPPElement -Element $element -Scope $Scope -GPPSection $GPPSection
            $results += $elementResults
        }
    }
    
    Write-Host "    Actual items found: $($results.Count)" -ForegroundColor Cyan
    
    return $results
}

# Define which preference locations to process based on parameters
$preferenceLocations = @{}

if ($IncludeDrives) {
    $preferenceLocations["NetworkShares"] = @{
        Paths = @("Drives\Drives.xml")
        DisplayName = "Drive Mappings"
    }
}

if ($IncludeShortcuts) {
    $preferenceLocations["Shortcuts"] = @{
        Paths = @("Shortcuts\Shortcuts.xml")
        DisplayName = "Shortcuts"
    }
}

if ($IncludeRegistry) {
    $preferenceLocations["Registry"] = @{
        Paths = @("Registry\Registry.xml")
        DisplayName = "Registry Settings"
    }
}

if ($IncludeEnvironment) {
    $preferenceLocations["EnvironmentVariables"] = @{
        Paths = @("EnvironmentVariables\EnvironmentVariables.xml")
        DisplayName = "Environment Variables"
    }
}

if ($IncludePrinters) {
    $preferenceLocations["Printers"] = @{
        Paths = @("Printers\Printers.xml")
        DisplayName = "Printers"
    }
}

# Process both Computer and User preferences
foreach ($scope in @("Machine", "User")) {
    $preferencesPath = Join-Path $GpoPath "$scope\Preferences"
    
    if (Test-Path $preferencesPath) {
        Write-Host "`n$scope Configuration:" -ForegroundColor Green
        
        foreach ($prefType in $preferenceLocations.GetEnumerator()) {
            foreach ($path in $prefType.Value.Paths) {
                $xmlPath = Join-Path $preferencesPath $path
                
                if (Test-Path $xmlPath) {
                    $items = Process-PreferenceXml -XmlPath $xmlPath -PreferenceType $prefType.Key -Scope $scope -GPPSection $prefType.Key
                    
                    if ($items.Count -gt 0) {
                        $allItems += $items
                        
                        if ($VerboseOutput) {
                            Write-Host "    Total items in collection: $($allItems.Count)" -ForegroundColor DarkGray
                        }
                    }
                }
            }
        }
    }
}

# Console output
Write-Host ("`n" + "=" * 60) -ForegroundColor Cyan
Write-Host "PROFILEUNITY-COMPATIBLE GPP ITEMS" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

if ($allItems.Count -eq 0) {
    Write-Host "`nNo items found matching the selected criteria." -ForegroundColor Yellow
} else {
    # Group items by GPP section for display - create proper groups
    $manualGroups = @{}
    foreach ($item in $allItems) {
        $key = "$($item.GPPSection)|$($item.Scope)"
        if (-not $manualGroups.ContainsKey($key)) {
            $manualGroups[$key] = @()
        }
        $manualGroups[$key] += $item
    }
    
    if ($VerboseOutput) {
        Write-Host "`nCreated $($manualGroups.Count) groups:" -ForegroundColor DarkGray
        foreach ($key in $manualGroups.Keys) {
            Write-Host "  $key`: $($manualGroups[$key].Count) items" -ForegroundColor DarkGray
        }
    }
    
    foreach ($groupKey in $manualGroups.Keys | Sort-Object) {
        $items = $manualGroups[$groupKey]
        $parts = $groupKey -split '\|'
        $section = $parts[0]
        $scope = $parts[1]
        
        # Get display name for section
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
                Write-Host "  STATE: DISABLED" -ForegroundColor Red
            }
            
            # Display section-specific properties
            Write-Host "  Properties:" -ForegroundColor Green
            
            switch ($item.GPPSection) {
                "Registry" {
                    Write-Host "    Action: $($item.Properties.Action)" -ForegroundColor White
                    Write-Host "    Key: $($item.Properties.Hive)\$($item.Properties.Key)" -ForegroundColor White
                    Write-Host "    Value: $($item.Properties.ValueName)" -ForegroundColor White
                    if ($item.Properties.Type) {
                        Write-Host "    Type: $($item.Properties.Type)" -ForegroundColor White
                        Write-Host "    Data: $($item.Properties.Value)" -ForegroundColor White
                    }
                }
                "NetworkShares" {
                    Write-Host "    Action: $($item.Properties.Action)" -ForegroundColor White
                    Write-Host "    Drive: $($item.Properties.DriveLetter)" -ForegroundColor White
                    Write-Host "    Path: $($item.Properties.Path)" -ForegroundColor White
                    if ($item.Properties.Label) {
                        Write-Host "    Label: $($item.Properties.Label)" -ForegroundColor White
                    }
                    Write-Host "    Persistent: $($item.Properties.Persistent)" -ForegroundColor White
                }
                "Shortcuts" {
                    Write-Host "    Action: $($item.Properties.Action)" -ForegroundColor White
                    Write-Host "    Location: $($item.Properties.ShortcutPath)" -ForegroundColor White
                    Write-Host "    Target: $($item.Properties.TargetPath)" -ForegroundColor White
                    if ($item.Properties.Arguments) {
                        Write-Host "    Arguments: $($item.Properties.Arguments)" -ForegroundColor White
                    }
                    if ($item.Properties.StartIn) {
                        Write-Host "    Start In: $($item.Properties.StartIn)" -ForegroundColor White
                    }
                }
                "EnvironmentVariables" {
                    Write-Host "    Action: $($item.Properties.Action)" -ForegroundColor White
                    Write-Host "    Variable: $($item.Properties.Name)" -ForegroundColor White
                    Write-Host "    Value: $($item.Properties.Value)" -ForegroundColor White
                    Write-Host "    User Variable: $($item.Properties.User)" -ForegroundColor White
                }
                "Printers" {
                    Write-Host "    Action: $($item.Properties.Action)" -ForegroundColor White
                    Write-Host "    Printer: $($item.Properties.Name)" -ForegroundColor White
                    Write-Host "    Path: $($item.Properties.Path)" -ForegroundColor White
                    Write-Host "    Default: $($item.Properties.Default)" -ForegroundColor White
                    if ($item.Properties.Location) {
                        Write-Host "    Location: $($item.Properties.Location)" -ForegroundColor White
                    }
                    if ($item.Properties.Comment) {
                        Write-Host "    Comment: $($item.Properties.Comment)" -ForegroundColor White
                    }
                }
                default {
                    # Fallback for any properties
                    foreach ($prop in $item.Properties.GetEnumerator()) {
                        if ($prop.Value) {
                            Write-Host "    $($prop.Key): $($prop.Value)" -ForegroundColor White
                        }
                    }
                }
            }
            
            # Display ILT if present
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
Write-Host ("`n" + "=" * 60) -ForegroundColor Cyan
Write-Host "SUMMARY FOR PROFILEUNITY MIGRATION" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

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
        
        Write-Host "`n${displayName}: $($typeGroup.Count) total" -ForegroundColor Yellow
        Write-Host "  Computer: $computerCount" -ForegroundColor Gray
        Write-Host "  User: $userCount" -ForegroundColor Gray
        
        # ILT summary - count actual items with ILT, not a phantom 11
        $iltCount = @($typeGroup.Group | Where-Object { $_.ItemLevelTargeting }).Count
        if ($iltCount -gt 0) {
            Write-Host "  With Item Level Targeting: $iltCount" -ForegroundColor Magenta
        }
    }
}

Write-Host ("`n" + "=" * 60) -ForegroundColor Cyan
Write-Host "Total items found: $($allItems.Count)" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Cyan

# Only create files if requested
if ($ExportFiles) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $baseFileName = $GpoDisplayName -replace '[^\w\s-]', ''
    
    # Create ProfileUnity-specific JSON export
    $jsonPath = Join-Path $OutputFolder "GPO_ProfileUnity_${baseFileName}_$timestamp.json"
    $profileUnityData = @{
        GPOName = $GpoDisplayName
        GPOID = $Gpo.Id.ToString()
        Generated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ProfileUnityMigration = @{
            DriveMappings = @($allItems | Where-Object { $_.GPPSection -eq "NetworkShares" })
            Shortcuts = @($allItems | Where-Object { $_.GPPSection -eq "Shortcuts" })
            Registry = @($allItems | Where-Object { $_.GPPSection -eq "Registry" })
            EnvironmentVariables = @($allItems | Where-Object { $_.GPPSection -eq "EnvironmentVariables" })
            Printers = @($allItems | Where-Object { $_.GPPSection -eq "Printers" })
        }
        Summary = @{}
    }
    
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
            $profileUnityData.Summary[$displayName] = @{
                Total = $typeGroup.Count
                Computer = ($typeGroup.Group | Where-Object { $_.Scope -eq "Machine" }).Count
                User = ($typeGroup.Group | Where-Object { $_.Scope -eq "User" }).Count
                WithILT = ($typeGroup.Group | Where-Object { $_.ItemLevelTargeting }).Count
            }
        }
    }
    
    $profileUnityData | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
    Write-Host "`nProfileUnity JSON saved to: $jsonPath" -ForegroundColor Green
    
    # Create CSV for easy analysis
    $csvPath = Join-Path $OutputFolder "GPO_ProfileUnity_${baseFileName}_$timestamp.csv"
    $csvData = @()
    
    foreach ($item in $allItems) {
        $csvRow = [PSCustomObject]@{
            GPPSection = switch ($item.GPPSection) {
                "NetworkShares" { "Drive Mappings" }
                "Shortcuts" { "Shortcuts" }
                "Registry" { "Registry" }
                "EnvironmentVariables" { "Environment Variables" }
                "Printers" { "Printers" }
                default { $item.GPPSection }
            }
            Scope = $item.Scope
            Name = $item.Name
            CollectionPath = $item.Path
            Disabled = $item.Disabled
            HasILT = [bool]$item.ItemLevelTargeting
            Action = $item.Properties.Action
        }
        
        # Add section-specific columns
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
                $csvRow | Add-Member -NotePropertyName "Label" -NotePropertyValue $item.Properties.Label
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
                $csvRow | Add-Member -NotePropertyName "Location" -NotePropertyValue $item.Properties.Location
            }
        }
        
        $csvData += $csvRow
    }
    
    if ($csvData.Count -gt 0) {
        $csvData | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Host "CSV export saved to: $csvPath" -ForegroundColor Green
    }
}
else {
    Write-Host "`nTip: Use -ExportFiles to save results to JSON and CSV files for ProfileUnity migration" -ForegroundColor Gray
}