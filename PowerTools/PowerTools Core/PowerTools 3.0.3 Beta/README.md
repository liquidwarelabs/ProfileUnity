# ProfileUnity PowerTools v3.1

A comprehensive PowerShell module for managing ProfileUnity configurations, filters, portability rules, FlexApp packages, ADMX templates, and administrative operations.

## Features

**Core Functionality**
- Configuration management with deployment scripting
- Advanced filter creation and management  
- Portability rules with condition-based automation
- FlexApp package management and import tools
- ADMX template integration with validation
- Active Directory integration helpers
- Server management and monitoring
- Backup and restore capabilities
- Cloud integration (Azure support)
- Comprehensive reporting and auditing

**Administrative Enhancements**
- Interactive dashboard with real-time monitoring
- Advanced troubleshooting toolkit
- Batch operations for bulk management
- Excel export integration
- Automated log analysis
- System health scoring
- Configuration wizards

## Installation

```powershell
# Install for current user
.\Install-ProfileUnityPowerTools.ps1 -CurrentUserOnly

# Install for all users (requires admin)
.\Install-ProfileUnityPowerTools.ps1

# Force reinstall
.\Install-ProfileUnityPowerTools.ps1 -Force
```

## Quick Start

```powershell
# Import the module
Import-Module ProfileUnity-PowerTools

# Connect to ProfileUnity server
Connect-ProfileUnityServer -ServerUrl "https://your-server" -Credential (Get-Credential)

# Launch interactive dashboard
Show-ProUDashboard

# Or start troubleshooting
Start-ProUTroubleshooter

# Basic operations
Get-ProUConfigs | Format-Table Name, Disabled, ModuleCount
Get-ProUFilters | Where-Object {$_.Disabled -eq $false}
```

## Module Structure

```
ProfileUnity-PowerTools/
├── Core/                           # Core functionality
│   ├── Variables.ps1              # Module variables and configuration  
│   ├── Helpers.ps1                # Utility functions
│   ├── Authentication.ps1         # Authentication handling
│   ├── Connection.ps1             # Server connection management
│   ├── TaskManagement.ps1         # Background task handling
│   ├── SearchFunctions.ps1        # Search and filtering utilities
│   ├── EventManagement.ps1        # Event handling and logging
│   └── AutoCompletion.ps1         # Tab completion enhancements
├── Configuration/                  # Configuration management
│   ├── Configuration.ps1          # Core configuration functions
│   ├── ConfigurationDeploy.ps1    # Deployment and scripting
│   ├── ConfigurationValidation.ps1 # Validation and testing
│   └── VersionControl.ps1         # Version tracking and comparison
├── Filters/                       # Filter management
│   └── Filters.ps1                # Filter operations
├── Portability/                   # Portability rules
│   └── Portability.ps1            # Portability rule management
├── FlexApp/                       # FlexApp management
│   ├── FlexAppPackage.ps1         # Package operations
│   ├── FlexAppDIA.ps1             # DIA integration
│   └── FlexAppImport.ps1          # Import utilities
├── ADMX/                          # ADMX template management
│   └── ADMX.ps1                   # Template operations
├── ActiveDirectory/               # AD integration
│   └── ADIntegration.ps1          # AD helper functions
├── Server/                        # Server management
│   └── ServerManagement.ps1       # Server operations
├── Cloud/                         # Cloud integration
│   └── CloudIntegration.ps1       # Cloud operations
├── Database/                      # Database management
│   └── DatabaseManagement.ps1     # Database operations
├── Backup/                        # Backup and restore
│   └── BackupAndRestore.ps1       # Backup operations
├── Reports/                       # Reporting and monitoring
│   ├── ReportsAndAudit.ps1        # Audit and compliance reports
│   └── PerformanceMonitoring.ps1  # Performance monitoring
├── Templates/                     # Template management
│   └── TemplateManagement.ps1     # Template operations
├── AdminEnhancements/             # Admin tools
│   ├── AdminEnhancements.ps1      # Main admin dashboard
│   ├── TroubleshootingTools.ps1   # Diagnostic tools
│   └── IntegrationHelpers.ps1     # Integration utilities
└── Scripts/                      # Utility scripts
    └── GPO-Migration/            # GPO migration tools
        ├── Get-GPOAdmxDependencies.ps1
        ├── Get-GPOPreferencesForProfileUnity.ps1
        ├── Import-GPOAdmIntoProfileUnity.ps1
        └── Import-GPOPreferencesToProfileUnity.ps1
```

## Available Commands

### Connection Management
```powershell
# Server connection
Connect-ProfileUnityServer -ServerUrl "https://your-server" -Credential (Get-Credential)
Disconnect-ProfileUnityServer
Get-ProfileUnityConnectionStatus
Test-ProfileUnityConnection

# Authentication
Get-ProfileUnityCredential
Set-TrustAllCertsPolicy
```

### Configuration Management
```powershell
# Basic operations
Get-ProUConfigs
Get-ProUConfigs -Name "Production"
Edit-ProUConfig -Name "Production"
Save-ProUConfig
Remove-ProUConfig -Name "OldConfig"

# Create and modify
New-ProUConfig -Name "Development" -Description "Dev environment"
Copy-ProUConfig -SourceName "Production" -TargetName "Production-Copy"
Test-ProUConfig -Name "Production"

# Import/Export
Export-ProUConfig -Name "Production" -Path "C:\Backup\prod.json"
Export-ProUConfigAll -Path "C:\Backup\"
Import-ProUConfig -Path "C:\Backup\prod.json"
Import-ProUConfigAll -SourceDir "C:\Backup\"

# Deployment
Update-ProUConfig -Name "Production"
Get-ProUConfigScript -Name "Production"
Deploy-ProUConfiguration -Name "Production" -TargetPath "\\server\share"

# Configuration modules
Get-ProUConfigModules -Name "Production"
Add-ProUConfigurationModules -ConfigName "Production" -Modules @("Filter1", "Filter2")

# Validation and health
Test-ProUBestPractices -ConfigName "Production"
Test-ProUSecurityBestPractices -ConfigName "Production"
Test-ProUPerformanceBestPractices -ConfigName "Production"
Test-ProUComplianceBestPractices -ConfigName "Production"
Test-ProUMaintenanceBestPractices -ConfigName "Production"
Calculate-ProUBestPracticesScore -ConfigName "Production"
Get-ProUConfigurationHealthScore -ConfigName "Production"
Show-ProUBestPracticesConsoleReport -ConfigName "Production"

# Version control
Backup-ProUConfigurationState -ConfigName "Production" -BackupPath "C:\Backups"
Restore-ProUConfigurationState -ConfigName "Production" -BackupPath "C:\Backups\backup.json"
Get-ProUConfigurationBackups -ConfigName "Production"
Compare-ProUConfigurations -ConfigName1 "Production" -ConfigName2 "Development"
New-ProUConfigurationCheckpoint -ConfigName "Production" -Description "Before major changes"
Restore-ProUConfigurationCheckpoint -ConfigName "Production" -CheckpointId "checkpoint123"
```

### Filter Management
```powershell
# Basic operations
Get-ProUFilters
Edit-ProUFilter -Name "Sales Team"
Save-ProUFilter
Remove-ProUFilter -Name "Old Filter"

# Create and modify
New-ProUFilter -Name "Sales Team" -Type "User" -Value "CN=Sales,OU=Groups,DC=company,DC=com"
Copy-ProUFilter -SourceName "Sales Team" -TargetName "Sales Team Copy"
Test-ProUFilter -Name "Sales Team" -TestValue "john.doe@company.com"

# Import/Export
Export-ProUFilter -Name "Sales Team" -Path "C:\Backup\filter.json"
Export-ProUFilterAll -Path "C:\Backup\"
Import-ProUFilter -Path "C:\Backup\filter.json"
Import-ProUFilterAll -SourceDir "C:\Backup\"

# Filter types
Get-ProUFilterTypes
```

### Portability Rules
```powershell
# Basic operations
Get-ProUPortRules
Edit-ProUPortRule -Name "User Profile Rule"
Save-ProUPortRule
Remove-ProUPortRule -Name "Old Rule"

# Create and modify
New-ProUPortRule -Name "User Profile Rule" -Type "User" -Source "C:\Users\%USERNAME%" -Target "\\server\profiles\%USERNAME%"
Copy-ProUPortRule -SourceName "User Profile Rule" -TargetName "User Profile Rule Copy"
Test-ProUPortRule -Name "User Profile Rule"

# Import/Export
Export-ProUPortRule -Name "User Profile Rule" -Path "C:\Backup\rule.json"
Export-ProUPortRuleAll -Path "C:\Backup\"
Import-ProUPortRule -Path "C:\Backup\rule.json"
Import-ProUPortRuleAll -SourceDir "C:\Backup\"

# Rule types
Get-ProUPortRuleTypes
```

### FlexApp Management
```powershell
# Basic operations
Get-ProUFlexapps
Edit-ProUFlexapp -Name "Notepad++"
Save-ProUFlexapp
Remove-ProUFlexapp -Name "Old App"

# Create and modify
New-ProUFlexapp -Name "Notepad++" -PackagePath "C:\Apps\notepad.flexapp"
Copy-ProUFlexapp -SourceName "Notepad++" -TargetName "Notepad++ Copy"
Test-ProUFlexapp -Name "Notepad++"

# Import/Export
Import-ProUFlexapp -PackagePath "C:\Apps\notepad.flexapp" -ConfigName "Production"
Import-ProUFlexappsAll -SourceDir "C:\Apps\" -ConfigName "Production"

# Notes and DIA
Add-ProUFlexappNote -Name "Notepad++" -Note "Updated to latest version"
Add-ProUFlexAppDia -Name "Notepad++" -DiaPath "C:\DIA\notepad.dia"
```

### ADMX Template Management
```powershell
# Basic operations
Get-ProUAdmx
Add-ProUAdmx -AdmxFile "C:\PolicyDefinitions\chrome.admx" -AdmlFile "C:\PolicyDefinitions\en-US\chrome.adml"
Remove-ProUAdmx -Name "Chrome Policy"
Set-ProUAdmxSequence -Name "Chrome Policy" -Sequence 1

# Import from GPO
Import-GpoAdmx -GpoDisplayName "Chrome Policy" -ConfigName "Production"

# Management
Enable-ProUAdmx -Name "Chrome Policy"
Disable-ProUAdmx -Name "Chrome Policy"
Copy-ProUAdmx -SourceName "Chrome Policy" -TargetName "Chrome Policy Copy"
Test-ProUAdmx -Name "Chrome Policy"

# Configuration cleanup
Clean-ProUConfiguration -ConfigName "Production"
```

### Template Management
```powershell
# Template operations
Get-ProUTemplate
New-ProUTemplateFromConfig -ConfigName "Production" -TemplateName "Production Template"
Export-ProUTemplate -TemplateName "Production Template" -Path "C:\Templates\"
Import-ProUTemplate -TemplatePath "C:\Templates\production.json"
Test-ProUTemplate -TemplateName "Production Template"
Deploy-ProUTemplate -TemplateName "Production Template" -TargetConfigName "Development"
Compare-ProUTemplate -TemplateName1 "Template1" -TemplateName2 "Template2"
```

### Server Management
```powershell
# Server information
Get-ProUServerSettings
Set-ProUServerSetting -SettingName "LogLevel" -Value "Debug"
Get-ProUServerAbout
Get-ProUServerCertificates
Add-ProUServerCertificate -CertificatePath "C:\certs\server.pfx"
Get-ProUServerUpdate
Start-ProUServerUpdate
Get-ProUServerVariables
Set-ProUServerServiceAccount -ServiceAccount "DOMAIN\ServiceAccount" -Password (ConvertTo-SecureString "Password" -AsPlainText -Force)
Test-ProUServerConfiguration

# Service management
Restart-ProUWebServices
```

### Active Directory Integration
```powershell
# Domain operations
Get-ProUADDomains
Get-ProUADDomainControllers
Test-ProUADConnectivity

# User and group operations
Get-ProUADUsers -SearchBase "OU=Users,DC=company,DC=com"
Get-ProUADGroups -SearchBase "OU=Groups,DC=company,DC=com"
Get-ProUUserGroupAccess -UserName "john.doe"

# Computer operations
Get-ProUADComputers -SearchBase "OU=Computers,DC=company,DC=com"

# Organizational units
Get-ProUADOrganizationalUnits -SearchBase "DC=company,DC=com"

# Search operations
Search-ProUAD -SearchTerm "Sales" -ObjectType "User"
Connect-ProUToAD -Domain "company.com"
```

### Administrative Tools
```powershell
# Interactive dashboard
Show-ProUDashboard
Get-ProUSystemHealthScore
Invoke-ProUSystemHealthCheck

# Troubleshooting
Start-ProUTroubleshooter
Invoke-ProUConnectionTroubleshooter
Invoke-ProUConfigurationTroubleshooter
Invoke-ProUFilterTroubleshooter
Invoke-ProUFlexAppTroubleshooter
Invoke-ProUPerformanceTroubleshooter
Invoke-ProUDatabaseTroubleshooter
Invoke-ProUSystemHealthTroubleshooter

# Log analysis
Analyze-ProULogs -LogPath "C:\Logs" -StartDate (Get-Date).AddDays(-7)
Find-ProUProblem -LogPath "C:\Logs"
Show-ProURecentErrors

# Wizards
Start-ProUConfigurationWizard
Start-ProUNewConfigurationWizard
Start-ProUEditConfigurationWizard
Start-ProUDeploymentWizard
Start-ProUSingleDeployment
Start-ProUServerWizard
Start-ProUFilterWizard
Start-ProUHealthCheck

# Batch operations
Start-ProUBatchOperations
Start-ProUBatchConfigurationOperations
Start-ProUBatchFilterOperations
Start-ProUBatchPortabilityOperations
Start-ProUBatchFlexAppOperations
Start-ProUBulkExport
Start-ProUBulkImport
```

### Reporting and Monitoring
```powershell
# Performance monitoring
Get-ProUPerformanceMetrics -ConfigName "Production"
Get-ProUServerPerformanceMetrics
Get-ProUDeploymentMetrics -ConfigName "Production"
Get-ProUUserExperienceMetrics -ConfigName "Production"
Get-ProUStorageMetrics
Get-ProUNetworkMetrics
Show-ProUPerformanceMetricsConsole -ConfigName "Production"
Show-ProUPerformanceDashboard

# Audit and reports
Get-ProUAuditLog -StartDate (Get-Date).AddDays(-30)
Get-ProUReport -ReportType "Configuration" -ConfigName "Production"
Get-ProfileUnitySummaryReport
Get-ProfileUnityUsageReport
Get-ProfileUnityConfigurationReport -ConfigName "Production"
Get-ProfileUnityFlexAppReport
Get-ProfileUnityAuditReport -StartDate (Get-Date).AddDays(-7)
Get-ProfileUnityPerformanceReport
Export-ProUHealthCheck -OutputPath "C:\Reports\health.html"

# Report formatting
Format-Report -InputObject $reportData
ConvertTo-HtmlReport -InputObject $reportData -OutputPath "C:\Reports\report.html"
ConvertTo-CsvReport -InputObject $reportData -OutputPath "C:\Reports\report.csv"
ConvertTo-XmlReport -InputObject $reportData -OutputPath "C:\Reports\report.xml"
```

### Excel Integration
```powershell
# Excel export
Export-ProUToExcel -Type "Configurations" -Path "C:\Reports\configs.xlsx"
Export-ConfigurationToExcel -ConfigName "Production" -Path "C:\Reports\config.xlsx"
Export-FilterToExcel -FilterName "Sales Team" -Path "C:\Reports\filter.xlsx"
Export-FlexAppToExcel -FlexAppName "Notepad++" -Path "C:\Reports\flexapp.xlsx"
Export-ADMXToExcel -ConfigName "Production" -Path "C:\Reports\admx.xlsx"
Export-EventsToExcel -StartDate (Get-Date).AddDays(-30) -Path "C:\Reports\events.xlsx"
Export-ServerToExcel -Path "C:\Reports\server.xlsx"

# Excel testing
Test-ProUExcelExport -Type "Configurations"
Get-ProUIntegrationStatus
```

### Backup and Restore
```powershell
# Environment backup
Backup-ProUEnvironment -BackupPath "C:\Backups" -IncludeConfigurations -IncludeFilters -IncludeFlexApps
Restore-ProUEnvironment -BackupPath "C:\Backups\backup_20231201" -ConfigName "Production"
Get-ProUBackupInfo -BackupPath "C:\Backups"
Compare-ProUBackups -BackupPath1 "C:\Backups\backup1" -BackupPath2 "C:\Backups\backup2"
```

### Auto-Completion and IntelliSense
```powershell
# Auto-completion
Get-ProUIntelliSenseData
Show-ProUObjectPreview -ObjectType "Configuration"
Get-ProUSmartSuggestions -Context "Configuration"
Enable-ProUAutoComplete
Update-ProUAutoCompleteCache
Save-ProURecentServer -ServerName "profileunity.company.com"
```

### Helper Functions
```powershell
# Utility functions
Confirm-Action -Message "Are you sure you want to delete this configuration?"
Get-FileName -InitialDirectory "C:\" -Filter "JSON files (*.json)|*.json"
ConvertTo-SafeFileName -InputString "My Configuration"
Write-LogMessage -Message "Operation completed" -Level "Info"
Format-ProfileUnityData -InputObject $configData
Convert-ProfileUnityGuid -Guid "12345678-1234-1234-1234-123456789012"
Get-ProfileUnityErrorDetails -ErrorObject $error
Validate-ProfileUnityObject -InputObject $configData
New-ProfileUnityGuid
```

## GPO Migration Scripts

Located in `Scripts\GPO-Migration\`:

- **Get-GPOAdmxDependencies.ps1** - Analyzes GPO ADMX dependencies
- **Get-GPOPreferencesForProfileUnity.ps1** - Extracts GPO preferences
- **Import-GPOAdmIntoProfileUnity.ps1** - Imports GPO ADMX into ProfileUnity  
- **Import-GPOPreferencesToProfileUnity.ps1** - Imports GPO preferences

## PowerShell 5.x Compatibility

All scripts are fully compatible with PowerShell 5.1 and later:
- Uses compatible syntax and cmdlets
- Avoids PowerShell Core specific features
- Includes proper error handling
- Supports Windows PowerShell ISE

## Performance Optimization

- Connection pooling for API efficiency
- Caching of frequently accessed data
- Batch operations for bulk modifications
- Async task management
- Progress indicators for long operations

## Security Features

- Secure credential storage using PowerShell credential objects
- HTTPS enforcement for all API communications
- Session timeout management
- Input validation to prevent injection attacks
- Audit logging of administrative actions

## Error Handling

- Comprehensive try/catch blocks
- Detailed error messages with context
- Graceful degradation for non-critical failures
- Automatic retry logic for transient failures
- Built-in troubleshooting guidance

## Troubleshooting

```powershell
# Common issues and solutions

# 1. Module import errors
Get-ExecutionPolicy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -CurrentUser

# 2. Connection issues
Test-NetConnection -ComputerName "profileunity-server" -Port 443
Connect-ProfileUnityServer -ServerUrl "https://your-server" -Credential $cred -Verbose

# 3. Permission issues
Get-ProfileUnitySession
# Verify role assignments in ProfileUnity console

# 4. Use built-in troubleshooter
Start-ProUTroubleshooter
```

## Getting Help

```powershell
# Get help for any function
Get-Help Show-ProUDashboard -Full
Get-Help Start-ProUTroubleshooter -Examples

# List all available functions
Get-Command -Module ProfileUnity-PowerTools

# Use the interactive troubleshooter
Start-ProUTroubleshooter
```

## Version History

### v3.1 (Current)
- Improved PowerShell 5.x compatibility
- Syntax error fixes across all modules
- Optimized token usage for large scripts
- Modular architecture with sub-1000 line files
- Enhanced error handling and validation

### v3.0
- Interactive admin dashboard
- Advanced troubleshooting toolkit
- Batch operations for bulk management
- Excel export integration
- System health monitoring

## Support

1. Use the built-in troubleshooter: `Start-ProUTroubleshooter`
2. Check the module documentation: `Get-Help <CommandName> -Full`
3. Review log files in `%LOCALAPPDATA%\ProfileUnity-PowerTools\Logs`
4. Enable verbose logging: `$VerbosePreference = 'Continue'`

## Contributing

When contributing to this project:
- Maintain PowerShell 5.1 compatibility
- Keep scripts under 1000 lines
- Include comprehensive error handling
- Add appropriate help documentation
- Test with both Windows PowerShell and PowerShell Core
- Avoid emoji in scripts (use in documentation only)

## License

This project is licensed under the MIT License.