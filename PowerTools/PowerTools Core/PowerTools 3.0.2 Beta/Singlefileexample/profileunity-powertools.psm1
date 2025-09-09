# ProfileUnity-PowerTools.psm1 - Refactored Main Module with ADMX Support

# Speed up PowerShell process
$ProgressPreference = 'SilentlyContinue'

# Module configuration
$script:ModuleConfig = @{
    BaseUrl = $null  # Will be set during connection
    DefaultPort = 8000
    Session = $null
    ServerName = $null
    CurrentItems = @{
        Config = $null
        Filter = $null
        PortRule = $null
        FlexApp = $null
    }
}

#region Core Functions

function Connect-ProfileUnityServer {
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [string]$ServerName,
        [Parameter(ParameterSetName = 'PlainText')]
        [string]$Username,
        [Parameter(ParameterSetName = 'PlainText')]
        [string]$Password,
        [int]$Port = 8000,
        [switch]$EnforceSSLValidation
    )
    
    try {
        # Get server name if not provided
        if (-not $ServerName) {
            $ServerName = Read-Host -Prompt 'Enter FQDN of ProfileUnity Server'
            if ([string]::IsNullOrWhiteSpace($ServerName)) {
                throw "Server name cannot be empty"
            }
        }
        
        # Get credentials
        $Credential = Get-ProfileUnityCredential -Username $Username -Password $Password
        
        # Configure SSL
        if (-not $EnforceSSLValidation) {
            Set-TrustAllCertsPolicy
        }
        
        # Set TLS protocols
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
        
        # Authenticate
        $authUrl = "https://${ServerName}:${Port}/authenticate"
        $authBody = "username=$($Credential.UserName)&password=$($Credential.GetNetworkCredential().Password)"
        
        $response = Invoke-WebRequest -Uri $authUrl -Method POST -Body $authBody -SessionVariable webSession -TimeoutSec 30
        
        if ($response.StatusCode -eq 200) {
            $script:ModuleConfig.Session = $webSession
            $script:ModuleConfig.ServerName = $ServerName
            $script:ModuleConfig.BaseUrl = "https://${ServerName}:${Port}/api"
            
            # Also set global variables for backward compatibility
            $global:session = $webSession
            $global:servername = $ServerName
            
            Write-Host "Successfully connected to ProfileUnity server: $ServerName" -ForegroundColor Green
            return [PSCustomObject]@{
                ServerName = $ServerName
                Port = $Port
                Connected = $true
                AuthenticationTime = Get-Date
            }
        }
        
        throw "Authentication failed with status code: $($response.StatusCode)"
    }
    catch {
        Write-Error "Connection failed: $($_.Exception.Message)"
        throw
    }
}

function Test-ProfileUnityConnection {
    if (($script:ModuleConfig.Session -and $script:ModuleConfig.ServerName) -or ($global:session -and $global:servername)) {
        $serverName = if ($script:ModuleConfig.ServerName) { $script:ModuleConfig.ServerName } else { $global:servername }
        Write-Host "Connection active to: $serverName" -ForegroundColor Green
        return $true
    }
    Write-Host "No active connection found" -ForegroundColor Yellow
    return $false
}

#endregion

#region Helper Functions

function Get-ProfileUnityCredential {
    param($Username, $Password)
    
    if ([string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($Password)) {
        Write-Host "Please enter your ProfileUnity credentials:" -ForegroundColor Yellow
        if ([string]::IsNullOrWhiteSpace($Username)) {
            $Username = Read-Host -Prompt "Username"
        }
        $SecurePassword = Read-Host -Prompt "Password for $Username" -AsSecureString
        return New-Object System.Management.Automation.PSCredential($Username, $SecurePassword)
    }
    
    $securePass = ConvertTo-SecureString -String $Password -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential($Username, $securePass)
}

function Set-TrustAllCertsPolicy {
    Write-Verbose "SSL certificate validation will be bypassed"
    
    if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
        Add-Type @"
            using System.Net;
            using System.Security.Cryptography.X509Certificates;
            public class TrustAllCertsPolicy : ICertificatePolicy {
                public bool CheckValidationResult(
                    ServicePoint srvPoint, X509Certificate certificate,
                    WebRequest request, int certificateProblem) {
                    return true;
                }
            }
"@
    }
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
}

function Invoke-ProfileUnityApi {
    param(
        [string]$Endpoint,
        [string]$Method = 'GET',
        [object]$Body,
        [string]$ContentType = 'application/json',
        [string]$OutFile
    )
    
    Assert-ProfileUnityConnection
    
    # Ensure we have a valid BaseUrl
    if (-not $script:ModuleConfig.BaseUrl) {
        $serverName = if ($script:ModuleConfig.ServerName) { $script:ModuleConfig.ServerName } else { $global:servername }
        $script:ModuleConfig.BaseUrl = "https://${serverName}:8000/api"
    }
    
    $params = @{
        Uri = "$($script:ModuleConfig.BaseUrl)/$Endpoint"
        Method = $Method
        WebSession = if ($script:ModuleConfig.Session) { $script:ModuleConfig.Session } else { $global:session }
    }
    
    if ($Body) {
        $params.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 }
        $params.ContentType = $ContentType
    }
    
    if ($OutFile) {
        $params.OutFile = $OutFile
    }
    
    Invoke-RestMethod @params
}

function Assert-ProfileUnityConnection {
    if (-not (Test-ProfileUnityConnection)) {
        throw "Not connected to ProfileUnity server. Please run Connect-ProfileUnityServer first."
    }
    
    # Ensure both storage methods have the session info
    if ($global:session -and -not $script:ModuleConfig.Session) {
        $script:ModuleConfig.Session = $global:session
        $script:ModuleConfig.ServerName = $global:servername
        $script:ModuleConfig.BaseUrl = "https://${global:servername}:8000/api"
    }
}

function Confirm-Action {
    param(
        [string]$Title = "Confirm Action",
        [string]$Message = "Do you want to continue?"
    )
    
    $choices = @(
        [System.Management.Automation.Host.ChoiceDescription]::new("&Yes", "Proceed with the action")
        [System.Management.Automation.Host.ChoiceDescription]::new("&No", "Cancel the action")
    )
    
    $result = $host.UI.PromptForChoice($Title, $Message, $choices, 1)
    return $result -eq 0
}

function Get-FileName {
    param(
        [string]$Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*",
        [string]$InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    )
    
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog -Property @{
        InitialDirectory = $InitialDirectory
        Filter = $Filter
    }
    
    if ($dialog.ShowDialog() -eq 'OK') {
        return $dialog.FileName
    }
    return $null
}

#endregion

#region Generic CRUD Operations

function Get-ProfileUnityItem {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('configuration', 'filter', 'portability', 'flexapppackage')]
        [string]$ItemType,
        [string]$Name
    )
    
    $response = Invoke-ProfileUnityApi -Endpoint $ItemType
    $items = $response.Tag.Rows
    
    if ($Name) {
        return $items | Where-Object { $_.name -like "*$Name*" }
    }
    return $items
}

function Edit-ProfileUnityItem {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('configuration', 'filter', 'portability', 'flexapppackage')]
        [string]$ItemType,
        [Parameter(Mandatory)]
        [string]$Name,
        [switch]$Quiet
    )
    
    $items = Get-ProfileUnityItem -ItemType $ItemType
    $item = $items | Where-Object { $_.name -eq $Name }
    
    if (-not $item) {
        throw "$ItemType '$Name' not found"
    }
    
    $response = Invoke-ProfileUnityApi -Endpoint "$ItemType/$($item.id)"
    $itemData = $response.tag
    
    # Store in appropriate current item AND global variable for backward compatibility
    $currentKey = switch ($ItemType) {
        'configuration' { 'Config' }
        'filter' { 'Filter' }
        'portability' { 'PortRule' }
        'flexapppackage' { 'FlexApp' }
    }
    
    $script:ModuleConfig.CurrentItems[$currentKey] = $itemData
    
    # Also set global variables for backward compatibility
    switch ($ItemType) {
        'configuration' { $global:CurrentConfig = $itemData }
        'filter' { $global:CurrentFilter = $itemData }
        'portability' { $global:CurrentPortRule = $itemData }
        'flexapppackage' { $global:CurrentFlexapp = $itemData }
    }
    
    if (-not $Quiet) {
        Write-Host "$Name loaded for editing" -ForegroundColor Green
    }
}

function Save-ProfileUnityItem {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('configuration', 'filter', 'portability', 'flexapppackage')]
        [string]$ItemType
    )
    
    $currentKey = switch ($ItemType) {
        'configuration' { 'Config' }
        'filter' { 'Filter' }
        'portability' { 'PortRule' }
        'flexapppackage' { 'FlexApp' }
    }
    
    $currentItem = $script:ModuleConfig.CurrentItems[$currentKey]
    
    # Also check global variables for backward compatibility
    if (-not $currentItem) {
        $currentItem = switch ($ItemType) {
            'configuration' { $global:CurrentConfig }
            'filter' { $global:CurrentFilter }
            'portability' { $global:CurrentPortRule }
            'flexapppackage' { $global:CurrentFlexapp }
        }
    }
    
    if (-not $currentItem) {
        throw "No $ItemType loaded for editing. Use Edit-ProU$currentKey first."
    }
    
    if (-not (Confirm-Action -Title "Save $ItemType" -Message "Are you sure you want to save this $ItemType?")) {
        Write-Host "Save cancelled" -ForegroundColor Yellow
        return
    }
    
    try {
        Invoke-ProfileUnityApi -Endpoint $ItemType -Method POST -Body $currentItem
        Write-Host "$ItemType saved successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to save ${ItemType}: $_"
        throw
    }
}

function Remove-ProfileUnityItem {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('configuration', 'filter', 'portability', 'flexapppackage')]
        [string]$ItemType,
        [Parameter(Mandatory)]
        [string]$Name,
        [switch]$Force
    )
    
    $items = Get-ProfileUnityItem -ItemType $ItemType
    $item = $items | Where-Object { $_.name -eq $Name }
    
    if (-not $item) {
        throw "$ItemType '$Name' not found"
    }
    
    if (-not $Force -and -not (Confirm-Action -Title "Delete $ItemType" -Message "Are you sure you want to delete '$Name'?")) {
        Write-Host "Delete cancelled" -ForegroundColor Yellow
        return
    }
    
    try {
        $response = Invoke-ProfileUnityApi -Endpoint "$ItemType/$($item.id)?force=false" -Method DELETE
        Write-Host "$ItemType '$Name' deleted successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to delete ${ItemType}: $_"
        throw
    }
}

function Export-ProfileUnityItem {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('configuration', 'filter', 'portability')]
        [string]$ItemType,
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$SavePath,
        [switch]$All
    )
    
    if (-not (Test-Path $SavePath)) {
        throw "Save path does not exist: $SavePath"
    }
    
    $SavePath = $SavePath.TrimEnd('\') + '\'
    
    if ($All) {
        $items = Get-ProfileUnityItem -ItemType $ItemType
        Write-Host "Exporting $($items.Count) ${ItemType}s..." -ForegroundColor Cyan
        
        foreach ($item in $items) {
            Export-SingleItem -ItemType $ItemType -ItemId $item.id -Name $item.name -SavePath $SavePath
        }
        
        Write-Host "$ItemType export completed" -ForegroundColor Green
    }
    else {
        if (-not $Name) {
            throw "Name parameter is required when not using -All"
        }
        
        $items = Get-ProfileUnityItem -ItemType $ItemType
        $item = $items | Where-Object { $_.name -eq $Name }
        
        if (-not $item) {
            throw "$ItemType '$Name' not found"
        }
        
        Export-SingleItem -ItemType $ItemType -ItemId $item.id -Name $Name -SavePath $SavePath
    }
}

function Export-SingleItem {
    param($ItemType, $ItemId, $Name, $SavePath)
    
    try {
        $outputFile = Join-Path $SavePath "$Name.json"
        Invoke-ProfileUnityApi -Endpoint "$ItemType/$ItemId/download?encoding=default" -OutFile $outputFile
        Write-Host "  Exported: $Name" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to export $ItemType '$Name': $_"
    }
}

function Import-ProfileUnityItem {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('configuration', 'filter', 'portability')]
        [string]$ItemType,
        [string]$JsonFile,
        [string]$SourceDir,
        [switch]$All
    )
    
    if ($All) {
        if (-not $SourceDir -or -not (Test-Path $SourceDir)) {
            throw "Valid source directory required when using -All"
        }
        
        $jsonFiles = Get-ChildItem -Path $SourceDir -Filter "*.json"
        
        if (-not $jsonFiles) {
            Write-Host "No JSON files found in: $SourceDir" -ForegroundColor Yellow
            return
        }
        
        Write-Host "Importing $($jsonFiles.Count) $ItemType files..." -ForegroundColor Cyan
        
        foreach ($file in $jsonFiles) {
            Import-SingleItem -ItemType $ItemType -FilePath $file.FullName
        }
        
        Write-Host "$ItemType import completed" -ForegroundColor Green
    }
    else {
        if (-not $JsonFile) {
            $JsonFile = Get-FileName
            if (-not $JsonFile) {
                Write-Host "No file selected" -ForegroundColor Yellow
                return
            }
        }
        
        Import-SingleItem -ItemType $ItemType -FilePath $JsonFile
    }
}

function Import-SingleItem {
    param($ItemType, $FilePath)
    
    try {
        $jsonContent = Get-Content $FilePath | ConvertFrom-Json
        
        # Extract the appropriate object based on item type
        $itemObject = switch ($ItemType) {
            'configuration' { $jsonContent.configurations }
            'filter' { $jsonContent.Filters }
            'portability' { $jsonContent.portability }
        }
        
        # Modify for import
        $itemObject.name = "$($itemObject.name) - Imported"
        $itemObject.ID = $null
        
        Invoke-ProfileUnityApi -Endpoint $ItemType -Method POST -Body $itemObject
        Write-Host "  Imported: $($itemObject.name)" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to import from '$([System.IO.Path]::GetFileName($FilePath))': $_"
    }
}

#endregion

#region Wrapper Functions for Backward Compatibility

# Configuration Functions
function Get-ProUConfigs { Get-ProfileUnityItem -ItemType 'configuration' }
function Edit-ProUConfig { param($Name, [switch]$Quiet) Edit-ProfileUnityItem -ItemType 'configuration' -Name $Name -Quiet:$Quiet }
function Save-ProUConfig { Save-ProfileUnityItem -ItemType 'configuration' }
function Remove-ProUConfig { param($Name) Remove-ProfileUnityItem -ItemType 'configuration' -Name $Name }
function Export-ProUConfig { param($Name, $SavePath) Export-ProfileUnityItem -ItemType 'configuration' -Name $Name -SavePath $SavePath }
function Export-ProUConfigAll { param($SavePath) Export-ProfileUnityItem -ItemType 'configuration' -SavePath $SavePath -All }
function Import-ProUConfig { param($JsonFile) Import-ProfileUnityItem -ItemType 'configuration' -JsonFile $JsonFile }
function Import-ProUConfigAll { param($SourceDir) Import-ProfileUnityItem -ItemType 'configuration' -SourceDir $SourceDir -All }

# Filter Functions
function Get-ProUFilters { Get-ProfileUnityItem -ItemType 'filter' }
function Edit-ProUFilter { param($Name, [switch]$Quiet) Edit-ProfileUnityItem -ItemType 'filter' -Name $Name -Quiet:$Quiet }
function Save-ProUFilter { Save-ProfileUnityItem -ItemType 'filter' }
function Remove-ProUFilter { param($Name) Remove-ProfileUnityItem -ItemType 'filter' -Name $Name }
function Export-ProUFilter { param($Name, $SavePath) Export-ProfileUnityItem -ItemType 'filter' -Name $Name -SavePath $SavePath }
function Export-ProUFilterAll { param($SavePath) Export-ProfileUnityItem -ItemType 'filter' -SavePath $SavePath -All }
function Import-ProUFilter { param($JsonFile) Import-ProfileUnityItem -ItemType 'filter' -JsonFile $JsonFile }
function Import-ProUFilterAll { param($SourceDir) Import-ProfileUnityItem -ItemType 'filter' -SourceDir $SourceDir -All }

# Portability Rule Functions
function Get-ProUPortRule { Get-ProfileUnityItem -ItemType 'portability' }
function Edit-ProUPortRule { param($Name, [switch]$Quiet) Edit-ProfileUnityItem -ItemType 'portability' -Name $Name -Quiet:$Quiet }
function Save-ProUPortRule { Save-ProfileUnityItem -ItemType 'portability' }
function Remove-ProUPortRule { param($Name) Remove-ProfileUnityItem -ItemType 'portability' -Name $Name }
function Export-ProUPortRule { param($Name, $SavePath) Export-ProfileUnityItem -ItemType 'portability' -Name $Name -SavePath $SavePath }
function Export-ProUPortRuleAll { param($SavePath) Export-ProfileUnityItem -ItemType 'portability' -SavePath $SavePath -All }
function Import-ProUPortRule { param($JsonFile) Import-ProfileUnityItem -ItemType 'portability' -JsonFile $JsonFile }
function Import-ProUPortRuleAll { param($SourceDir) Import-ProfileUnityItem -ItemType 'portability' -SourceDir $SourceDir -All }

# FlexApp Functions
function Get-ProUFlexapps { Get-ProfileUnityItem -ItemType 'flexapppackage' }
function Edit-ProUFlexapp { param($Name, [switch]$Quiet) Edit-ProfileUnityItem -ItemType 'flexapppackage' -Name $Name -Quiet:$Quiet }
function Save-ProUFlexapp { Save-ProfileUnityItem -ItemType 'flexapppackage' }
function Remove-ProUFlexapp { param($Name) Remove-ProfileUnityItem -ItemType 'flexapppackage' -Name $Name }

#endregion

#region Specialized Functions

function Update-ProUConfig {
    param([Parameter(Mandatory)]$Name)
    
    if (-not (Confirm-Action -Title "Deploy Configuration" -Message "Are you sure you want to deploy configuration '$Name'?")) {
        Write-Host "Deploy cancelled" -ForegroundColor Yellow
        return
    }
    
    try {
        $configs = Get-ProfileUnityItem -ItemType 'configuration'
        $config = $configs | Where-Object { $_.name -eq $Name }
        
        if (-not $config) {
            throw "Configuration '$Name' not found"
        }
        
        Invoke-ProfileUnityApi -Endpoint "configuration/$($config.id)/script?encoding=ascii&deploy=true"
        Write-Host "Configuration '$Name' deployed successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to deploy configuration: $_"
        throw
    }
}

function Add-ProUFlexAppDia {
    param(
        [Parameter(Mandatory)]$DIAName,
        [Parameter(Mandatory)]$FilterName
    )
    
    Assert-ProfileUnityConnection
    
    if (-not $script:ModuleConfig.CurrentItems.Config -and -not $global:CurrentConfig) {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    # Use whichever is available
    $currentConfig = if ($script:ModuleConfig.CurrentItems.Config) { 
        $script:ModuleConfig.CurrentItems.Config 
    } else { 
        $global:CurrentConfig 
    }
    
    # Get FlexApp and Filter details
    $flexApp = Get-ProfileUnityItem -ItemType 'flexapppackage' -Name $DIAName
    $filter = Get-ProfileUnityItem -ItemType 'filter' -Name $FilterName
    
    if (-not $flexApp) { throw "FlexApp package '$DIAName' not found" }
    if (-not $filter) { throw "Filter '$FilterName' not found" }
    
    # Create DIA package object
    $diaPackage = @{
        DifferencingPath = "%systemdrive%\FADIA-T\VHDW\%username%"
        UseJit = "False"
        CacheLocal = "False"
        PredictiveBlockCaching = "False"
        FlexAppPackageId = $flexApp[0].id
        FlexAppPackageUuid = $flexApp[0].uuid
        Sequence = "0"
    }
    
    # Create module item
    $moduleItem = @{
        FlexAppPackages = @($diaPackage)
        Playback = "0"
        ReversePlay = "False"
        FilterId = $filter[0].id
        Description = "DIA package added with PowerTools"
        Disabled = "False"
    }
    
    # Add to current configuration
    if (-not $currentConfig.FlexAppDias) {
        $currentConfig | Add-Member -NotePropertyName FlexAppDias -NotePropertyValue @()
    }
    
    $currentConfig.FlexAppDias += $moduleItem
    
    # Update both storage locations
    $script:ModuleConfig.CurrentItems.Config = $currentConfig
    $global:CurrentConfig = $currentConfig
    
    Write-Host "FlexApp DIA '$DIAName' with filter '$FilterName' added to configuration" -ForegroundColor Green
    Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
}

function Add-ProUFlexappNote {
    param([Parameter(Mandatory)]$Note)
    
    if (-not $script:ModuleConfig.CurrentItems.FlexApp -and -not $global:CurrentFlexapp) {
        throw "No FlexApp package loaded for editing. Use Edit-ProUFlexapp first."
    }
    
    # Use whichever is available
    $currentFlexApp = if ($script:ModuleConfig.CurrentItems.FlexApp) { 
        $script:ModuleConfig.CurrentItems.FlexApp 
    } else { 
        $global:CurrentFlexapp 
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $newNote = "`n[$timestamp] Note: $Note"
    $currentFlexApp.History += $newNote
    
    # Update both storage locations
    $script:ModuleConfig.CurrentItems.FlexApp = $currentFlexApp
    $global:CurrentFlexapp = $currentFlexApp
    
    Write-Host "Note added to FlexApp package history" -ForegroundColor Green
    Write-Host "Use Save-ProUFlexapp to save changes" -ForegroundColor Yellow
}

function Import-ProUFlexapp {
    param([Parameter(Mandatory)]$Path)
    
    Assert-ProfileUnityConnection
    
    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }
    
    try {
        $response = Invoke-ProfileUnityApi -Endpoint "server/flexapppackagexml?path=$Path"
        $package = $response.Tag
        
        Invoke-ProfileUnityApi -Endpoint "flexapppackage/import" -Method POST -Body @($package)
        Write-Host "FlexApp package imported successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to import FlexApp package: $_"
        throw
    }
}

function Import-ProUFlexappsAll {
    param([Parameter(Mandatory)]$SourceDir)
    
    Assert-ProfileUnityConnection
    
    if (-not (Test-Path $SourceDir)) {
        throw "Source directory does not exist: $SourceDir"
    }
    
    $xmlFiles = Get-ChildItem -Path $SourceDir -Recurse -Include *.xml
    
    if (-not $xmlFiles) {
        Write-Host "No XML files found in: $SourceDir" -ForegroundColor Yellow
        return
    }
    
    Write-Host "Importing $($xmlFiles.Count) FlexApp package files..." -ForegroundColor Cyan
    
    foreach ($file in $xmlFiles) {
        try {
            Import-ProUFlexapp -Path $file.FullName
            Write-Host "  Imported: $($file.Name)" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to import FlexApp package from '${($file.Name)}': $_"
        }
    }
    
    Write-Host "FlexApp package import completed" -ForegroundColor Green
}

#endregion

#region ADMX Functions

function Add-ProUAdmx {
    <#
    .SYNOPSIS
        Adds ADMx/ADMl templates to the current ProfileUnity configuration.
    .DESCRIPTION
        This function queries the ProfileUnity server for ADMX policy settings and adds them
        to the currently loaded configuration.
    .PARAMETER AdmxFile
        The ADMX file name (e.g., "chrome.admx")
    .PARAMETER AdmlFile
        The ADML file name (e.g., "chrome.adml")
    .PARAMETER GpoId
        The GPO ID to use for the ADMX settings
    .PARAMETER FilterName
        Optional filter name to apply to the ADMX settings
    .PARAMETER Description
        Optional description for the ADMX settings
    .PARAMETER Sequence
        The sequence number for the ADMX settings (default: 1)
    .EXAMPLE
        Add-ProUAdmx -AdmxFile "chrome.admx" -AdmlFile "chrome.adml" -GpoId "12345"
    .EXAMPLE
        Add-ProUAdmx -AdmxFile "firefox.admx" -AdmlFile "firefox.adml" -GpoId "67890" -FilterName "Domain Computers"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AdmxFile,
        
        [Parameter(Mandatory)]
        [string]$AdmlFile,
        
        [Parameter(Mandatory)]
        [string]$GpoId,
        
        [string]$FilterName,
        
        [string]$Description = "Added via PowerTools",
        
        [int]$Sequence = 1
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
    }
    
    Process {
        try {
            Write-Host "Querying ProfileUnity server for ADMX settings..." -ForegroundColor Yellow
            
            # Build the query URL
            $queryUrl = "server/admxadmlfiles?admx=$AdmxFile&adml=$AdmlFile&gpoid=$GpoId"
            
            # Query the server
            $response = Invoke-ProfileUnityApi -Endpoint $queryUrl
            
            if (-not $response -or -not $response.tag) {
                throw "No ADMX data returned from server"
            }
            
            $admxRule = $response.tag
            
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
            
            # Update the ADMX rule with our settings
            if ($filterId) {
                $admxRule.FilterId = $filterId
                $admxRule.Filter = $FilterName
            }
            
            if ($Description) {
                $admxRule.Description = $Description
            }
            
            if ($Sequence) {
                $admxRule.Sequence = $Sequence
            }
            
            # Initialize AdministrativeTemplates array if it doesn't exist
            if ($null -eq $currentConfig.AdministrativeTemplates) {
                $currentConfig | Add-Member -NotePropertyName AdministrativeTemplates -NotePropertyValue @() -Force
            }
            
            # Add the new rule
            $currentConfig.AdministrativeTemplates += $admxRule
            
            # Update both storage locations
            $script:ModuleConfig.CurrentItems.Config = $currentConfig
            $global:CurrentConfig = $currentConfig
            
            Write-Host "Successfully added ADMX rule:" -ForegroundColor Green
            Write-Host "  ADMX: $AdmxFile" -ForegroundColor Cyan
            Write-Host "  ADML: $AdmlFile" -ForegroundColor Cyan
            Write-Host "  GPO ID: $GpoId" -ForegroundColor Cyan
            if ($filterId) {
                Write-Host "  Filter: $FilterName" -ForegroundColor Cyan
            }
            
            # Count settings
            $settingCount = 0
            if ($admxRule.TemplateSettingStates) {
                $settingCount = @($admxRule.TemplateSettingStates).Count
            }
            
            Write-Host "  Settings: $settingCount" -ForegroundColor Cyan
            Write-Host "`nUse Save-ProUConfig to save changes" -ForegroundColor Yellow
            
            return $admxRule
        }
        catch {
            Write-Error "Failed to add ADMX configuration: $_"
            throw
        }
    }
}

function Get-ProUAdmx {
    <#
    .SYNOPSIS
        Gets ADMX templates from the current ProfileUnity configuration.
    .DESCRIPTION
        Retrieves all ADMX templates from the currently loaded configuration.
    .PARAMETER Name
        Optional filter by ADMX file name
    .EXAMPLE
        Get-ProUAdmx
    .EXAMPLE
        Get-ProUAdmx -Name "chrome"
    #>
    [CmdletBinding()]
    param(
        [string]$Name
    )
    
    # Check if configuration is loaded
    $currentConfig = if ($script:ModuleConfig.CurrentItems.Config) { 
        $script:ModuleConfig.CurrentItems.Config 
    } elseif ($global:CurrentConfig) { 
        $global:CurrentConfig 
    } else {
        Write-Warning "No configuration loaded. Use Edit-ProUConfig first."
        return
    }
    
    if (-not $currentConfig.AdministrativeTemplates) {
        Write-Host "No ADMX templates found in current configuration" -ForegroundColor Yellow
        return
    }
    
    $templates = $currentConfig.AdministrativeTemplates
    
    if ($Name) {
        $templates = $templates | Where-Object { 
            $_.AdmxFile -like "*$Name*" -or 
            $_.Description -like "*$Name*" 
        }
    }
    
    # Format output
    $templates | ForEach-Object {
        [PSCustomObject]@{
            Sequence = $_.Sequence
            AdmxFile = Split-Path $_.AdmxFile -Leaf
            AdmlFile = Split-Path $_.AdmlFile -Leaf
            Filter = $_.Filter
            Description = $_.Description
            Disabled = $_.Disabled
            SettingsCount = if ($_.TemplateSettingStates) { @($_.TemplateSettingStates).Count } else { 0 }
            ControlsCount = if ($_.SettingControlStates) { @($_.SettingControlStates).Count } else { 0 }
        }
    }
}

function Remove-ProUAdmx {
    <#
    .SYNOPSIS
        Removes an ADMX template from the current ProfileUnity configuration.
    .DESCRIPTION
        Removes an ADMX template by sequence number from the currently loaded configuration.
    .PARAMETER Sequence
        The sequence number of the ADMX template to remove
    .EXAMPLE
        Remove-ProUAdmx -Sequence 1
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [int]$Sequence
    )
    
    # Check if configuration is loaded
    $currentConfig = if ($script:ModuleConfig.CurrentItems.Config) { 
        $script:ModuleConfig.CurrentItems.Config 
    } elseif ($global:CurrentConfig) { 
        $global:CurrentConfig 
    } else {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    if (-not $currentConfig.AdministrativeTemplates) {
        Write-Warning "No ADMX templates found in current configuration"
        return
    }
    
    $template = $currentConfig.AdministrativeTemplates | Where-Object { $_.Sequence -eq $Sequence }
    
    if (-not $template) {
        Write-Warning "No ADMX template found with sequence number: $Sequence"
        return
    }
    
    $admxName = Split-Path $template.AdmxFile -Leaf
    
    if ($PSCmdlet.ShouldProcess($admxName, "Remove ADMX template")) {
        $currentConfig.AdministrativeTemplates = @($currentConfig.AdministrativeTemplates | Where-Object { $_.Sequence -ne $Sequence })
        
        # Update both storage locations
        $script:ModuleConfig.CurrentItems.Config = $currentConfig
        $global:CurrentConfig = $currentConfig
        
        Write-Host "Removed ADMX template: $admxName" -ForegroundColor Green
        Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
    }
}

function Set-ProUAdmxSequence {
    <#
    .SYNOPSIS
        Updates the sequence numbers of ADMX templates in the current configuration.
    .DESCRIPTION
        Renumbers all ADMX templates in the current configuration sequentially.
    .EXAMPLE
        Set-ProUAdmxSequence
    #>
    [CmdletBinding()]
    param()
    
    # Check if configuration is loaded
    $currentConfig = if ($script:ModuleConfig.CurrentItems.Config) { 
        $script:ModuleConfig.CurrentItems.Config 
    } elseif ($global:CurrentConfig) { 
        $global:CurrentConfig 
    } else {
        throw "No configuration loaded for editing. Use Edit-ProUConfig first."
    }
    
    if (-not $currentConfig.AdministrativeTemplates -or $currentConfig.AdministrativeTemplates.Count -eq 0) {
        Write-Warning "No ADMX templates found in current configuration"
        return
    }
    
    Write-Host "Resequencing ADMX templates..." -ForegroundColor Yellow
    
    $sequence = 1
    foreach ($template in $currentConfig.AdministrativeTemplates) {
        $template.Sequence = $sequence
        $sequence++
    }
    
    # Update both storage locations
    $script:ModuleConfig.CurrentItems.Config = $currentConfig
    $global:CurrentConfig = $currentConfig
    
    Write-Host "ADMX templates resequenced (1 to $($sequence - 1))" -ForegroundColor Green
    Write-Host "Use Save-ProUConfig to save changes" -ForegroundColor Yellow
}

#endregion

# Export all public functions
Export-ModuleMember -Function @(
    'Connect-ProfileUnityServer', 'Test-ProfileUnityConnection',
    'Get-ProUFilters', 'Edit-ProUFilter', 'Save-ProUFilter', 'Remove-ProUFilter',
    'Export-ProUFilter', 'Export-ProUFilterAll', 'Import-ProUFilter', 'Import-ProUFilterAll',
    'Get-ProUPortRule', 'Edit-ProUPortRule', 'Save-ProUPortRule', 'Remove-ProUPortRule',
    'Export-ProUPortRule', 'Export-ProUPortRuleAll', 'Import-ProUPortRule', 'Import-ProUPortRuleAll',
    'Get-ProUFlexapps', 'Edit-ProUFlexapp', 'Save-ProUFlexapp', 'Remove-ProUFlexapp',
    'Import-ProUFlexapp', 'Import-ProUFlexappsAll', 'Add-ProUFlexappNote',
    'Get-ProUConfigs', 'Edit-ProUConfig', 'Save-ProUConfig', 'Remove-ProUConfig',
    'Export-ProUConfig', 'Export-ProUConfigAll', 'Import-ProUConfig', 'Import-ProUConfigAll',
    'Update-ProUConfig', 'Add-ProUFlexAppDia',
    'Add-ProUAdmx', 'Get-ProUAdmx', 'Remove-ProUAdmx', 'Set-ProUAdmxSequence'
)