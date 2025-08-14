# ProfileUnity-PowerTools.psm1 - Main Module Loader
# Updated to include AdminEnhancements folder

# Speed up PowerShell process
$ProgressPreference = 'SilentlyContinue'

# Get the module directory
$ModuleRoot = $PSScriptRoot

# Import all component modules in the correct order
$moduleComponents = @(
    # Core modules first
    'Core\Variables.ps1'
    'Core\Helpers.ps1'
    'Core\Authentication.ps1'
    'Core\Connection.ps1'
    'Core\TaskManagement.ps1'
    'Core\SearchFunctions.ps1'
    'Core\EventManagement.ps1'
    
    # Server management
    'Server\ServerManagement.ps1'
    
    # Configuration modules
    'Configuration\Configuration.ps1'
    'Configuration\ConfigurationDeploy.ps1'
    
    # Other modules  
    'Filters\Filters.ps1'
    'Portability\Portability.ps1'
    
    # FlexApp modules
    'FlexApp\FlexAppPackage.ps1'
    'FlexApp\FlexAppDIA.ps1'
    'FlexApp\FlexAppImport.ps1'
    
    # Additional modules
    'ADMX\ADMX.ps1'
    'ActiveDirectory\ADIntegration.ps1'
    'Backup\BackupAndRestore.ps1'
    'Cloud\CloudIntegration.ps1'
    'Database\DatabaseManagement.ps1'
    'Reports\ReportsAndAudit.ps1'
    'Templates\TemplateManagement.ps1'
    
    # Admin Enhancement modules
    'AdminEnhancements\IntegrationHelpers.ps1'
    'AdminEnhancements\TroubleshootingTools.ps1'
    'AdminEnhancements\AdminEnhancements.ps1'
)

# Import each component
foreach ($component in $moduleComponents) {
    $componentPath = Join-Path $ModuleRoot $component
    
    if (Test-Path $componentPath) {
        try {
            . $componentPath
            Write-Verbose "Loaded component: $component"
        }
        catch {
            Write-Error "Failed to load component '$component': $_"
            throw
        }
    }
    else {
        Write-Error "Component not found: $componentPath"
        throw "Missing required component: $component"
    }
}

# Display module information
$moduleVersion = $script:ModuleConfig.ModuleVersion
Write-Host "ProfileUnity PowerTools v$moduleVersion loaded" -ForegroundColor Green
Write-Host "Use 'Connect-ProfileUnityServer' to connect to a ProfileUnity server" -ForegroundColor Yellow

# Export module member is handled by individual component files