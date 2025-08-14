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
Get-ProUConfig | Format-Table Name, Disabled, ModuleCount
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

## Configuration Management

```powershell
# Get configurations
Get-ProUConfig
Get-ProUConfig -Name "Production"

# Create and modify configurations
New-ProUConfig -Name "Development" -Description "Dev environment"
Set-ProUConfig -Name "Production" -Disabled $false

# Deploy configurations
Get-ProUConfigScript -Name "Production"
Deploy-ProUConfig -Name "Production" -TargetPath "\\server\share"

# Export/Import
Export-ProUConfig -Name "Production" -Path "C:\Backup\prod.json"
Import-ProUConfig -Path "C:\Backup\prod.json"
```

## Filter Management

```powershell
# Manage filters
Get-ProUFilters
New-ProUFilter -Name "Sales Team" -Type "User" -Value "CN=Sales,OU=Groups,DC=company,DC=com"
Set-ProUFilter -Name "Sales Team" -Disabled $false
Remove-ProUFilter -Name "Old Filter"

# Filter testing
Test-ProUFilter -Name "Sales Team" -TestValue "john.doe@company.com"
```

## ADMX Template Management

```powershell
# ADMX operations
Get-ProUAdmxTemplates
Add-ProUAdmx -AdmxPath "C:\PolicyDefinitions\chrome.admx" -ConfigName "Production"
Set-ProUAdmxSetting -Template "Chrome Policy" -Key "DefaultSearchProviderEnabled" -Value "1"
Test-ProUAdmxTemplates -ConfigName "Production"
```

## FlexApp Management

```powershell
# FlexApp operations  
Get-ProUFlexAppPackages
Import-ProUFlexApp -PackagePath "C:\Apps\notepad.flexapp" -ConfigName "Production"
Export-ProUFlexApp -Name "Notepad++" -Path "C:\Export\"
Test-ProUFlexApp -Name "Notepad++" -TestPath "C:\Program Files\Notepad++\notepad++.exe"
```

## Administrative Tools

```powershell
# Interactive dashboard
Show-ProUDashboard

# Troubleshooting
Start-ProUTroubleshooter

# Batch operations
Start-ProUBatchOperation -Operation "Enable" -ConfigNames @("Prod1", "Prod2")
Export-ProUToExcel -Type "Configurations" -Path "C:\Reports\configs.xlsx"

# Health monitoring
Get-ProUSystemHealth
Test-ProUConnectivity
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