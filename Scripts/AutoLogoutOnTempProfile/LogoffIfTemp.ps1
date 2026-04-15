<#
.SYNOPSIS
    Logs off the current user if they are using a temporary profile.

.DESCRIPTION
    This script checks if the current user is logged in with a temporary profile
    and automatically logs them off if detected. Temporary profiles are typically
    created when Windows cannot load the user's normal profile.
    
    The script also removes any ProfileUnity logoff scripts from Group Policy
    registry entries that contain LwL.ProfileUnity.Client.Logoff.exe.

.PARAMETER Force
    Forces immediate logoff without confirmation prompt.

.PARAMETER LogPath
    Optional path to log file. If not specified, creates log in temp directory.

.EXAMPLE
    .\LogoffIfTemp.ps1
    
    Checks for temporary profile and logs off if detected.

.EXAMPLE
    .\LogoffIfTemp.ps1 -Force
    
    Forces immediate logoff without confirmation.

.EXAMPLE
    .\LogoffIfTemp.ps1 -LogPath "C:\Logs\LogoffIfTemp.log"
    
    Runs script and writes log to specified path.

.NOTES
    Script Name: LogoffIfTemp.ps1
    Relative Path: .\LogoffIfTemp.ps1
    Author: Auto-generated
    Requires: PowerShell 5.x
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$Force,
    
    [Parameter()]
    [string]$LogPath
)

#Requires -Version 5.0

# Setup logging
if ([string]::IsNullOrEmpty($LogPath)) {
    $logFileName = "LogoffIfTemp_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $LogPath = Join-Path -Path $env:TEMP -ChildPath $logFileName
}

# Create log file and write initial entry
try {
    $logDir = Split-Path -Path $LogPath -Parent
    if (-not (Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    $null = New-Item -Path $LogPath -ItemType File -Force -ErrorAction Stop
    Write-Host "Log file: $LogPath" -ForegroundColor Cyan
}
catch {
    Write-Warning "Could not create log file at $LogPath : $_"
    $LogPath = $null
}

# Function to write to both console and log file
function Write-LogMessage {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    # Remove ANSI color codes from message for log file
    $cleanMessage = $Message -replace '\x1b\[[0-9;]*m',''
    $logMessage = "[$timestamp] [$Level] $cleanMessage"
    
    # Write to console with colors
    switch ($Level) {
        "ERROR" { Write-Host $Message -ForegroundColor Red }
        "WARNING" { Write-Host $Message -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $Message -ForegroundColor Green }
        default { Write-Host $Message }
    }
    
    # Write to log file
    if ($null -ne $LogPath) {
        try {
            Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
        }
        catch {
            # Silently fail if we can't write to log
        }
    }
}

# Get current user SID
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$userSID = $currentUser.User.Value

Write-LogMessage "=== LogoffIfTemp Script Started ===" "INFO"
Write-LogMessage "Current user SID: $userSID" "INFO"
Write-LogMessage "Log file location: $LogPath" "INFO"
Write-Verbose "Current user SID: $userSID"

# Registry path for profile list
$profileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$userSID"

# Check if profile registry key exists
if (-not (Test-Path -Path $profileListPath)) {
    Write-Warning "Profile registry key not found for current user."
    exit 1
}

# Get profile information from registry
$profileImagePath = (Get-ItemProperty -Path $profileListPath -Name "ProfileImagePath" -ErrorAction SilentlyContinue).ProfileImagePath
$profileState = (Get-ItemProperty -Path $profileListPath -Name "State" -ErrorAction SilentlyContinue).State

Write-Verbose "Profile Image Path: $profileImagePath"
Write-Verbose "Profile State: $profileState"

# Check for temporary profile indicators
$isTempProfile = $false
$reason = ""

# Check if ProfileImagePath contains "Temp"
if ($null -ne $profileImagePath) {
    if ($profileImagePath -match "Temp|\.tmp|Temporary") {
        $isTempProfile = $true
        $reason = "Profile path contains temporary indicators: $profileImagePath"
    }
}

# Check profile state (0x200 = 512 decimal indicates temporary profile)
if ($null -ne $profileState) {
    if ($profileState -eq 0x200 -or $profileState -eq 512) {
        $isTempProfile = $true
        $reason = "Profile state indicates temporary profile (State: $profileState)"
    }
}

# Additional check: Compare USERPROFILE environment variable with registry path
$userProfileEnv = $env:USERPROFILE
if ($null -ne $profileImagePath -and $null -ne $userProfileEnv) {
    if ($userProfileEnv -ne $profileImagePath) {
        # If they don't match and profile path contains Temp, it's likely a temp profile
        if ($profileImagePath -match "Temp") {
            $isTempProfile = $true
            $reason = "Profile path mismatch detected with temporary indicators"
        }
    }
}

# Remove ProfileUnity logoff script from Group Policy if present
# Use HKU (HKEY_USERS) with SID since temp profiles may not load HKCU properly
# Clear ALL logoff scripts to prevent any from running
Write-LogMessage "=== Starting Group Policy Logoff Script Removal ===" "INFO"
$gpoLogoffPath = "HKU:\$userSID\Software\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Logoff"
Write-LogMessage "Checking registry path: $gpoLogoffPath" "INFO"

if (Test-Path -Path $gpoLogoffPath) {
    Write-Host "Registry path EXISTS - checking for scripts..." -ForegroundColor Yellow
    
    # Get all subkeys (numbered script entries) - single call
    $logoffScriptKeys = Get-ChildItem -Path $gpoLogoffPath -ErrorAction SilentlyContinue
    
    if ($null -ne $logoffScriptKeys) {
        Write-Host "Found $($logoffScriptKeys.Count) script entry/entries in registry" -ForegroundColor Yellow
        
        # Quick check for ProfileUnity - read all properties at once for each key
        $foundProfileUnity = $false
        foreach ($scriptKey in $logoffScriptKeys) {
            # Single Get-ItemProperty call to get all properties at once
            $props = Get-ItemProperty -Path $scriptKey.PSPath -ErrorAction SilentlyContinue
            if ($null -ne $props) {
                # Check all property values in one pass
                foreach ($prop in $props.PSObject.Properties) {
                    if ($null -ne $prop.Value -and $prop.Value -is [string] -and $prop.Value -match "LwL\.ProfileUnity\.Client\.Logoff\.exe") {
                        $foundProfileUnity = $true
                        Write-Host "  *** ProfileUnity logoff script FOUND in key: $($scriptKey.PSChildName) ***" -ForegroundColor Red
                        break
                    }
                }
            }
            if ($foundProfileUnity) { break }
        }
        
        if ($foundProfileUnity) {
            Write-Host "ProfileUnity logoff script detected - will be removed with all logoff scripts." -ForegroundColor Red
        }
    }
    else {
        Write-Host "No script entries found in registry path" -ForegroundColor Green
    }
    
    # Clear the entire Logoff scripts section to prevent ANY scripts from running
    Write-Host "Clearing entire Group Policy Logoff scripts section..." -ForegroundColor Yellow
    try {
        # Remove the entire key tree in one operation (faster than individual removals)
        Remove-Item -Path $gpoLogoffPath -Recurse -Force -ErrorAction Stop
        
        # Quick verification
        if (-not (Test-Path -Path $gpoLogoffPath)) {
            Write-Host "SUCCESS: Group Policy Logoff scripts section cleared." -ForegroundColor Green
        }
        else {
            Write-Warning "WARNING: Registry path still exists after removal attempt!"
        }
    }
    catch {
        Write-Warning "ERROR: Failed to clear Group Policy Logoff scripts section: $_"
    }
}
else {
    Write-Host "Registry path does NOT exist - no scripts found at this location." -ForegroundColor Green
}

# Also check and clear from HKCU as a fallback (in case it's accessible)
Write-Host "`n=== Checking HKCU Group Policy Logoff Scripts ===" -ForegroundColor Cyan
$gpoLogoffPathHKCU = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Logoff"
Write-Host "Checking registry path: $gpoLogoffPathHKCU"

if (Test-Path -Path $gpoLogoffPathHKCU) {
    Write-Host "HKCU registry path EXISTS - clearing scripts..." -ForegroundColor Yellow
    try {
        # Remove entire key tree in one operation (faster)
        Remove-Item -Path $gpoLogoffPathHKCU -Recurse -Force -ErrorAction Stop
        
        # Quick verification
        if (-not (Test-Path -Path $gpoLogoffPathHKCU)) {
            Write-Host "SUCCESS: HKCU Group Policy Logoff scripts section cleared." -ForegroundColor Green
        }
        else {
            Write-Warning "WARNING: HKCU registry path still exists after removal attempt!"
        }
    }
    catch {
        Write-Warning "ERROR: Failed to clear HKCU Group Policy Logoff scripts section: $_"
    }
}
else {
    Write-Host "HKCU registry path does NOT exist - no scripts found at this location." -ForegroundColor Green
}

# Check for additional possible script locations - batch removal
$additionalPaths = @(
    "HKU:\$userSID\Software\Policies\Microsoft\Windows\System\Scripts\Logoff",
    "HKCU:\Software\Policies\Microsoft\Windows\System\Scripts\Logoff",
    "HKU:\$userSID\Software\Microsoft\Windows\CurrentVersion\Group Policy\History",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Group Policy\History"
)

$foundAdditional = $false
foreach ($addPath in $additionalPaths) {
    if (Test-Path -Path $addPath) {
        $foundAdditional = $true
        try {
            Remove-Item -Path $addPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Verbose "Could not remove: $addPath - $_"
        }
    }
}
if ($foundAdditional) {
    Write-Host "Cleared additional script locations" -ForegroundColor Green
}

# Also clear script execution state/timestamps that might cause scripts to run
Write-Host "`n=== Clearing Script Execution State ===" -ForegroundColor Cyan
$gpoStatePath = "HKU:\$userSID\Software\Microsoft\Windows\CurrentVersion\Group Policy\State"
$gpoStatePathHKCU = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Group Policy\State"

foreach ($statePath in @($gpoStatePath, $gpoStatePathHKCU)) {
    if (Test-Path -Path $statePath) {
        try {
            # Clear script execution timestamps - check and remove in one operation
            $scriptStatePath = Join-Path -Path $statePath -ChildPath "Scripts\Logoff"
            if (Test-Path -Path $scriptStatePath) {
                Remove-Item -Path $scriptStatePath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "Cleared script execution state: $scriptStatePath" -ForegroundColor Green
            }
        }
        catch {
            Write-Verbose "Could not clear script execution state: $_"
        }
    }
}

# Disable logoff script execution via Group Policy registry setting
# This prevents Windows from running any logoff scripts
Write-Host "`n=== Disabling Logoff Script Execution ===" -ForegroundColor Cyan
$gpoScriptsPath = "HKU:\$userSID\Software\Policies\Microsoft\Windows\System\Scripts"
$gpoScriptsPathHKCU = "HKCU:\Software\Policies\Microsoft\Windows\System\Scripts"

foreach ($scriptsPath in @($gpoScriptsPath, $gpoScriptsPathHKCU)) {
    if (Test-Path -Path $scriptsPath) {
        try {
            # Set DisableLogoffScripts to 1 to disable logoff scripts
            Set-ItemProperty -Path $scriptsPath -Name "DisableLogoffScripts" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Verbose "Could not set DisableLogoffScripts in $scriptsPath : $_"
        }
    }
    else {
        try {
            # Create the path if it doesn't exist and set the value
            $parentPath = Split-Path -Path $scriptsPath -Parent
            if (-not (Test-Path -Path $parentPath)) {
                New-Item -Path $parentPath -Force -ErrorAction SilentlyContinue | Out-Null
            }
            New-Item -Path $scriptsPath -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path $scriptsPath -Name "DisableLogoffScripts" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Verbose "Could not create DisableLogoffScripts in $scriptsPath : $_"
        }
    }
}
Write-Host "Disabled logoff script execution via Group Policy" -ForegroundColor Green

Write-Host "`n=== Group Policy Script Removal Complete ===" -ForegroundColor Cyan

# If temporary profile detected, log off
if ($isTempProfile) {
    Write-Warning "Temporary profile detected: $reason"
    Write-Warning "User will be logged off."
    
    # Get current user information for process filtering
    $currentUserName = $env:USERNAME
    $currentUserDomain = $env:USERDOMAIN
    $currentUserFullName = "$currentUserDomain\$currentUserName"
    
    # Kill any running ProfileUnity logoff processes before logoff (only for current user)
    # Optimized: Get all processes once and filter
    Write-Host "Terminating any running ProfileUnity logoff processes for current user..."
    $processesToKill = @()
    
    # Get processes by name (faster than filtering all processes)
    $profileUnityProcesses = Get-Process -Name "LwL.ProfileUnity.Client.Logoff" -ErrorAction SilentlyContinue
    if ($null -ne $profileUnityProcesses) {
        $processesToKill += $profileUnityProcesses
    }
    
    # Also check for processes with the executable name in the path (only if we didn't find any by name)
    if ($processesToKill.Count -eq 0) {
        $allProcesses = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $null -ne $_.Path -and $_.Path -match "LwL\.ProfileUnity\.Client\.Logoff\.exe"
        }
        if ($null -ne $allProcesses) {
            $processesToKill += $allProcesses
        }
    }
    
    # Batch process ownership checks and terminations
    if ($processesToKill.Count -gt 0) {
        foreach ($proc in $processesToKill) {
            # Quick check: if process username matches current user (faster than WMI)
            try {
                $procOwner = (Get-WmiObject -Class Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue).GetOwner()
                if ($null -ne $procOwner -and "$($procOwner.Domain)\$($procOwner.User)" -eq $currentUserFullName) {
                    Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                    Write-Host "Terminated ProfileUnity logoff process (PID: $($proc.Id))"
                }
            }
            catch {
                Write-Verbose "Could not terminate process $($proc.Id): $_"
            }
        }
    }
    
    if (-not $Force) {
        Write-Host "Temporary profile detected. Logging off in 5 seconds..."
        Write-Host "Press Ctrl+C to cancel."
        Start-Sleep -Seconds 5
        
        # Check again for processes that might have started during the delay
        $profileUnityProcesses = Get-Process -Name "LwL.ProfileUnity.Client.Logoff" -ErrorAction SilentlyContinue
        if ($null -ne $profileUnityProcesses) {
            foreach ($proc in $profileUnityProcesses) {
                try {
                    $procOwner = (Get-WmiObject -Class Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue).GetOwner()
                    if ($null -ne $procOwner -and "$($procOwner.Domain)\$($procOwner.User)" -eq $currentUserFullName) {
                        Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                        Write-Host "Terminated ProfileUnity logoff process that started during delay (PID: $($proc.Id))"
                    }
                }
                catch {
                    Write-Verbose "Could not terminate process $($proc.Id): $_"
                }
            }
        }
    }
    
    try {
        # Log off the current user
        # Using shutdown.exe /l for local logoff (works in all Windows versions)
        Start-Process -FilePath "shutdown.exe" -ArgumentList "/l", "/f" -NoNewWindow -Wait -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to log off user: $_"
        exit 1
    }
}
else {
    Write-Verbose "Normal profile detected. No action required."
    if ($PSBoundParameters.ContainsKey('Verbose')) {
        Write-Host "Normal profile detected. No action required."
    }
    Write-LogMessage "Normal profile detected. No action required." "INFO"
}

# Final log entry
Write-LogMessage "=== LogoffIfTemp Script Completed ===" "INFO"
if ($null -ne $LogPath) {
    Write-Host "`nLog file saved to: $LogPath" -ForegroundColor Cyan
    Write-LogMessage "Log file location: $LogPath" "INFO"
}





