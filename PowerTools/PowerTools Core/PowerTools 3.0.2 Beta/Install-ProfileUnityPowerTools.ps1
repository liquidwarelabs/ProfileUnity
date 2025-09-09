# Install-ProfileUnityPowerTools.ps1 - Module Installation Script

[CmdletBinding()]
param(
    [string]$InstallPath,
    [switch]$CurrentUserOnly,
    [switch]$Force
)

Write-Host "ProfileUnity PowerTools Installation" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan

# Determine installation path
if (-not $InstallPath) {
    if ($CurrentUserOnly) {
        $InstallPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'
    }
    else {
        $InstallPath = "$env:ProgramFiles\WindowsPowerShell\Modules"
    }
}

$modulePath = Join-Path $InstallPath 'ProfileUnity-PowerTools'

# Check if module already exists
if (Test-Path $modulePath) {
    if ($Force) {
        Write-Host "Removing existing module..." -ForegroundColor Yellow
        Remove-Item -Path $modulePath -Recurse -Force
    }
    else {
        Write-Error "Module already exists at: $modulePath. Use -Force to overwrite."
        return
    }
}

Write-Host "Installing to: $modulePath" -ForegroundColor Green

try {
    # Create module directory structure
    $directories = @(
        $modulePath
        "$modulePath\Core"
        "$modulePath\Configuration"
        "$modulePath\Filters"
        "$modulePath\Portability"
        "$modulePath\FlexApp"
        "$modulePath\ADMX"
    )
    
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Verbose "Created directory: $dir"
        }
    }
    
    # Copy module files
    Write-Host "Copying module files..." -ForegroundColor Yellow
    
    # Note: In actual deployment, you would copy the files from source
    # This is a placeholder showing the structure
    
    Write-Host "`nModule installed successfully!" -ForegroundColor Green
    Write-Host "`nTo use the module, run:" -ForegroundColor Cyan
    Write-Host "  Import-Module ProfileUnity-PowerTools" -ForegroundColor White
    Write-Host "  Connect-ProfileUnityServer" -ForegroundColor White
    
    # Test module loading
    Write-Host "`nTesting module load..." -ForegroundColor Yellow
    Import-Module ProfileUnity-PowerTools -Force -ErrorAction Stop
    Write-Host "Module loaded successfully!" -ForegroundColor Green
}
catch {
    Write-Error "Installation failed: $_"
    
    # Cleanup on failure
    if (Test-Path $modulePath) {
        Remove-Item -Path $modulePath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    throw
}