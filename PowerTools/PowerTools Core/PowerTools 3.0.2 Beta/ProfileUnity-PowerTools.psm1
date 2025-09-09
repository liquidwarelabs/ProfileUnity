# ProfileUnity-PowerTools.psm1 - Main Module Loader for Split Files
# This loads component files in correct order without dependency issues

# Speed up PowerShell process
$ProgressPreference = 'SilentlyContinue'

# Get the module directory
$ModuleRoot = $PSScriptRoot

# Module configuration - Initialize before loading components
$script:ModuleConfig = @{
    BaseUrl = $null
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

# Import component modules in dependency order
$moduleComponents = @(
    # Core modules first - Authentication is now self-contained
    'Core\Variables.ps1',
    'Core\Authentication.ps1',    # Now self-contained, no dependencies
    'Core\Helpers.ps1',           # Can come after Authentication now
    'Core\Connection.ps1',
    'Core\TaskManagement.ps1',
    'Core\SearchFunctions.ps1',
    'Core\EventManagement.ps1',
    
    # Configuration modules
    'Configuration\Configuration.ps1',
    'Configuration\ConfigurationDeploy.ps1',
    
    # Server management
    'Server\ServerManagement.ps1',
    
    # Other core modules
    'Filters\Filters.ps1',
    'Portability\Portability.ps1',
    
    # FlexApp modules
    'FlexApp\FlexAppPackage.ps1',
    'FlexApp\FlexAppDIA.ps1',
    'FlexApp\FlexAppImport.ps1',
    
    # Additional modules
    'ADMX\ADMX.ps1',
    'ActiveDirectory\ADIntegration.ps1',
    'Backup\BackupAndRestore.ps1',
    'Cloud\CloudIntegration.ps1',
    'Database\DatabaseManagement.ps1',
    'Reports\ReportsAndAudit.ps1',
    'Templates\TemplateManagement.ps1',
    
    # Admin Enhancement modules
    'AdminEnhancements\IntegrationHelpers.ps1',
    'AdminEnhancements\TroubleshootingTools.ps1',
    'AdminEnhancements\AdminEnhancements.ps1',
    
    # Optional modules (load with error suppression)
    'Core\AutoCompletion.ps1',
    'Configuration\VersionControl.ps1'
)

# Import each component with error handling
$loadedComponents = @()
$failedComponents = @()

foreach ($component in $moduleComponents) {
    $componentPath = Join-Path $ModuleRoot $component
    
    if (Test-Path $componentPath) {
        try {
            . $componentPath
            $loadedComponents += $component
            Write-Verbose "Loaded component: $component"
        }
        catch {
            $failedComponents += @{
                Component = $component
                Error = $_.Exception.Message
            }
            # Only show warnings for critical components, not optional ones
            if ($component -notin @('Core\AutoCompletion.ps1', 'Configuration\VersionControl.ps1')) {
                Write-Warning "Failed to load component '$component': $($_.Exception.Message)"
            } else {
                Write-Verbose "Optional component '$component' failed to load: $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-Verbose "Component not found (optional): $componentPath"
    }
}

# Display loading results
$moduleVersion = "3.0"
Write-Host "ProfileUnity PowerTools v$moduleVersion loaded" -ForegroundColor Green
Write-Host "  Components loaded: $($loadedComponents.Count)" -ForegroundColor Cyan

if ($failedComponents.Count -gt 0) {
    $criticalFailures = $failedComponents | Where-Object { $_.Component -notin @('Core\AutoCompletion.ps1', 'Configuration\VersionControl.ps1') }
    if ($criticalFailures.Count -gt 0) {
        Write-Warning "  Failed to load $($criticalFailures.Count) critical components:"
        $criticalFailures | ForEach-Object {
            Write-Warning "    $($_.Component): $($_.Error)"
        }
    }
}

Write-Host "Use 'Connect-ProfileUnityServer' to connect to a ProfileUnity server" -ForegroundColor Yellow

# Export all public functions - this list matches your working single-file module
Export-ModuleMember -Function @(
    # Connection functions
    'Connect-ProfileUnityServer', 
    'Disconnect-ProfileUnityServer',
    'Get-ProfileUnityConnectionStatus',
    
    # Configuration functions
    'Get-ProUConfigs', 
    'Edit-ProUConfig', 
    'New-ProUConfig',
    'Save-ProUConfig', 
    'Remove-ProUConfig',
    'Export-ProUConfig', 
    'Export-ProUConfigAll', 
    'Import-ProUConfig', 
    'Import-ProUConfigAll'
    
    # Filter functions
    'Get-ProUFilters', 
    'Edit-ProUFilter', 
    'New-ProUFilter',
    'Save-ProUFilter',
    'Remove-ProUFilter',
    'Export-ProUFilter',
    'Export-ProUFilterAll',
    'Import-ProUFilter',
    'Import-ProUFilterAll',
    
    # Portability functions
    'Get-ProUPortRules', 
    'Edit-ProUPortRule', 
    'New-ProUPortRule',
    'Save-ProUPortRule',
    'Remove-ProUPortRule',
    'Export-ProUPortRule',
    'Export-ProUPortRuleAll',
    'Import-ProUPortRule',
    'Import-ProUPortRuleAll',
    
    # FlexApp functions
    'Get-ProUFlexapps', 
    'Edit-ProUFlexapp', 
    'Save-ProUFlexapp',
    'Remove-ProUFlexapp',
    'Import-ProUFlexapp',
    'Import-ProUFlexappsAll',
    'Add-ProUFlexappNote',
    'Add-ProUFlexAppDia',
    
    # ADMX functions
    'Add-ProUAdmx', 
    'Get-ProUAdmx', 
    'Remove-ProUAdmx', 
    'Set-ProUAdmxSequence',
    'Import-GpoAdmx',
    'Clean-ProUConfiguration',
    
    # Template functions
    'New-ProUTemplateFromConfig',
    'Get-ProUTemplate',
    
    # Helper functions (from Core/Connection.ps1 and Core/Helpers.ps1)
    'Get-ProfileUnityCredential',
    'Set-TrustAllCertsPolicy', 
    'Invoke-ProfileUnityApi',
    'Assert-ProfileUnityConnection',
    'Save-ProfileUnityItem',
    'Get-ProfileUnityItem',
    'Edit-ProfileUnityItem',
    'Confirm-Action',
    'Get-FileName',
    'ConvertTo-SafeFileName',
    'Write-LogMessage',
    'Format-ProfileUnityData',
    'Convert-ProfileUnityGuid',
    'Get-ProfileUnityErrorDetails',
    'Validate-ProfileUnityObject',
    'New-ProfileUnityGuid'
)
