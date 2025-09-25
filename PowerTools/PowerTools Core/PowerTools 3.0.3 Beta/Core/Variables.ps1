# Core\Variables.ps1 - Module Configuration and Global Variables
# Relative Path: \Core\Variables.ps1

# =============================================================================
# MODULE CONFIGURATION AND VARIABLES
# =============================================================================

# Module configuration storage
$script:ModuleConfig = @{
    # Connection settings
    BaseUrl = $null
    ServerName = $null
    Port = 8000
    Session = $null
    Connected = $false
    ConnectedAt = $null
    
    # Default settings
    DefaultTimeout = 30
    DefaultPageSize = 100
    
    # Current working items - Initialize with proper structure
    CurrentItems = @{
        Config = $null
        Filter = $null
        PortRule = $null
        FlexApp = $null
        ADMXTemplate = $null
        CloudCredential = $null
    }
    
    # Module paths
    ModulePath = $PSScriptRoot
    
    # Version info
    ModuleVersion = '3.0.0'
    
    # API version compatibility
    MinApiVersion = '7.0'
    MaxApiVersion = '8.0'
}

# Default export paths
$script:DefaultPaths = @{
    Export = [Environment]::GetFolderPath('MyDocuments')
    Import = [Environment]::GetFolderPath('MyDocuments')
    Backup = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ProfileUnity-Backups'
    Logs = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ProfileUnity-PowerTools\Logs'
}

# Common file filters for dialogs
$script:FileFilters = @{
    Json = "JSON files (*.json)|*.json|All files (*.*)|*.*"
    Xml = "XML files (*.xml)|*.xml|All files (*.*)|*.*"
    Config = "Config files (*.json;*.xml)|*.json;*.xml|All files (*.*)|*.*"
    All = "All files (*.*)|*.*"
}

# API endpoint mappings
$script:ApiEndpoints = @{
    # Core endpoints
    Authenticate = 'authenticate'
    Authenticated = 'authenticated'
    
    # Configuration endpoints
    Configuration = 'configuration'
    ConfigurationDeploy = 'configuration/{0}/script'
    ConfigurationModules = 'configuration/modules'
    ConfigurationReport = 'configuration/{0}/report/{1}'
    
    # Filter endpoints
    Filter = 'filter'
    FilterReport = 'filter/report/{0}'
    
    # Portability endpoints
    Portability = 'portability'
    PortabilityReport = 'portability/{0}/report/{1}'
    
    # FlexApp endpoints
    FlexAppPackage = 'flexapppackage'
    FlexAppImport = 'flexapppackage/import'
    FlexDisk = 'flexdisk'
    
    # Server endpoints
    ServerSettings = 'server/setting'
    ServerUpdate = 'server/update'
    ServerCertificate = 'server/certificate'
    ServerADMX = 'server/admxandxfiles'
    
    # Cloud endpoints
    CloudCredential = 'cloud/credential'
    CloudAzure = 'cloud/azure'
    
    # AD endpoints
    ADUsers = 'ad/user'
    ADGroups = 'ad/group'
    ADComputers = 'ad/computer'
    
    # Other endpoints
    Audit = 'audit'
    Task = 'task'
    Database = 'database'
    Cluster = 'cluster'
}

# Response parsing helpers
$script:ResponseParsers = @{
    Configuration = { param($response) $response.configurations }
    Filter = { param($response) $response.Filters }
    Portability = { param($response) $response.portability }
    FlexApp = { param($response) $response.flexapppackages }
}

# Initialize module
function Initialize-ProfileUnityModule {
    <#
    .SYNOPSIS
        Initializes the ProfileUnity PowerTools module.
    
    .DESCRIPTION
        Sets up required directories and validates module state.
    #>
    [CmdletBinding()]
    param()
    
    # Ensure ModuleConfig is properly initialized
    if (-not $script:ModuleConfig) {
        Write-Warning "Reinitializing ModuleConfig structure"
        $script:ModuleConfig = @{
            BaseUrl = $null
            ServerName = $null
            Port = 8000
            Session = $null
            Connected = $false
            ConnectedAt = $null
            DefaultTimeout = 30
            DefaultPageSize = 100
            CurrentItems = @{
                Config = $null
                Filter = $null
                PortRule = $null
                FlexApp = $null
                ADMXTemplate = $null
                CloudCredential = $null
            }
            ModulePath = $PSScriptRoot
            ModuleVersion = '3.0.0'
            MinApiVersion = '7.0'
            MaxApiVersion = '8.0'
        }
    }
    
    # Create required directories
    foreach ($path in $script:DefaultPaths.Values) {
        if (-not (Test-Path $path)) {
            try {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
                Write-Verbose "Created directory: $path"
            }
            catch {
                Write-Warning "Could not create directory: $path"
            }
        }
    }
    
    # Set up logging
    $script:LogFile = Join-Path $script:DefaultPaths.Logs "ProfileUnity-PowerTools_$(Get-Date -Format 'yyyyMMdd').log"
    
    Write-Verbose "ProfileUnity PowerTools module initialized"
}

function Get-ProfileUnityModuleConfig {
    <#
    .SYNOPSIS
        Gets the current module configuration.
    
    .DESCRIPTION
        Returns the module configuration for debugging or information purposes.
    
    .EXAMPLE
        Get-ProfileUnityModuleConfig
    #>
    [CmdletBinding()]
    param()
    
    return $script:ModuleConfig
}

function Set-ProfileUnityModuleConfig {
    <#
    .SYNOPSIS
        Sets module configuration values.
    
    .DESCRIPTION
        Updates module configuration settings.
    
    .PARAMETER Setting
        The setting name to update
    
    .PARAMETER Value
        The new value for the setting
    
    .EXAMPLE
        Set-ProfileUnityModuleConfig -Setting DefaultTimeout -Value 60
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Setting,
        
        [Parameter(Mandatory)]
        [object]$Value
    )
    
    if ($script:ModuleConfig.ContainsKey($Setting)) {
        $script:ModuleConfig[$Setting] = $Value
        Write-Verbose "Updated module setting: $Setting = $Value"
    }
    else {
        Write-Warning "Unknown module setting: $Setting"
    }
}

function Get-ProfileUnityDefaultPath {
    <#
    .SYNOPSIS
        Gets default paths used by the module.
    
    .DESCRIPTION
        Returns the default paths for exports, imports, backups, etc.
    
    .PARAMETER PathType
        The type of path to retrieve
    
    .EXAMPLE
        Get-ProfileUnityDefaultPath -PathType Export
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Export', 'Import', 'Backup', 'Logs')]
        [string]$PathType = 'Export'
    )
    
    return $script:DefaultPaths[$PathType]
}

function Set-ProfileUnityDefaultPath {
    <#
    .SYNOPSIS
        Sets a default path used by the module.
    
    .DESCRIPTION
        Updates the default path for a specific operation type.
    
    .PARAMETER PathType
        The type of path to set
    
    .PARAMETER Path
        The new path
    
    .EXAMPLE
        Set-ProfileUnityDefaultPath -PathType Export -Path "C:\ProfileUnity\Exports"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Export', 'Import', 'Backup', 'Logs')]
        [string]$PathType,
        
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    if (Test-Path $Path) {
        $script:DefaultPaths[$PathType] = $Path
        Write-Verbose "Updated $PathType path to: $Path"
    }
    else {
        Write-Warning "Path does not exist: $Path"
    }
}

function Reset-ProfileUnityModuleConfig {
    <#
    .SYNOPSIS
        Resets the module configuration to defaults.
    
    .DESCRIPTION
        Clears all module configuration and reinitializes with defaults.
    
    .EXAMPLE
        Reset-ProfileUnityModuleConfig
    #>
    [CmdletBinding()]
    param()
    
    Write-Warning "Resetting ProfileUnity module configuration"
    
    # Clear connection state
    $script:ModuleConfig.Session = $null
    $script:ModuleConfig.BaseUrl = $null
    $script:ModuleConfig.ServerName = $null
    $script:ModuleConfig.Connected = $false
    $script:ModuleConfig.ConnectedAt = $null
    
    # Clear current items
    $script:ModuleConfig.CurrentItems = @{
        Config = $null
        Filter = $null
        PortRule = $null
        FlexApp = $null
        ADMXTemplate = $null
        CloudCredential = $null
    }
    
    # Clear globals
    $global:session = $null
    $global:servername = $null
    $global:CurrentConfig = $null
    
    Write-Host "Module configuration reset" -ForegroundColor Yellow
}

# Initialize the module when loaded
try {
    Initialize-ProfileUnityModule
}
catch {
    Write-Warning "Failed to initialize module: $_"
}

# Export functions
# Functions will be exported by main ProfileUnity-PowerTools.psm1 module loader
Export-ModuleMember -Function @(
    'Get-ProfileUnityModuleConfig',
    'Set-ProfileUnityModuleConfig',
    'Get-ProfileUnityDefaultPath',
    'Set-ProfileUnityDefaultPath',
    'Reset-ProfileUnityModuleConfig'
)
#>
