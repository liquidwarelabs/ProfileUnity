<#
    
.SYNOPSIS
Install ProfileUnity Console

.DESCRIPTION
This script ...
makes use of powershell to silently install the ProfileUnity Console
can be setup as a computer startup script for automated installs on boot
will not run if any version of the ProfileUnity Console is already installed
will not upgrade or downgrade an existing version

#>
# Installer EXE required
$InstallerExe = "\\server\share\6.8.6 R1\ProfileUnity-Net.exe"
# Optional post-install patches
$Configfile = "\\server\share\6.8.6 R1\profileunity.host.exe.config"
$ConsoleHotfix = "\\server\share\6.8.6 R1\ProfileUnityConsole-Hotfix.zip"
$ClientToolsHotfix = "\\server\share\6.8.6 R1\client-tools.zip"
$FpcInstallerUpdate = "\\server\share\6.8.6 R1\fpcsetup.exe"

# Set the MongoDB prou_services account pw
$Password = "ShouldChangeTh1s!"
# Set the location where ProfileUnity will be installed so its skipped when already detected
$PathToHostExe = "C:\Program Files (x86)\Liquidware Labs\ProfileUnity\ProfileUnity.Host.exe"
$Logfile = "C:\Lab-Setup.log"

$ErrorActionPreference = "continue"

Function WaitForServices($SearchString, $Status) {
    # Get all services where name matches $SearchString and loop through each of them
    ForEach($Service In (Get-Service $SearchString)) {
        # Wait for the service to reach the $Status or a maximum of 5 minutes
        $Service.WaitForStatus($Status, "00:05:00")
    }
}

If (Test-Path $($InstallerExe) -PathType Leaf) {
	Try {
		# Log Output
		Start-Transcript -path $Logfile -append
		
		# Disable RDP Logins Until Configuration is Complete
		Write-Output "Disabling RDP Logins"
		& change logon /disable
	
		If (Test-Path $($PathToHostExe) -PathType Leaf) {
			Write-Output "ProfileUnity Console already installed."
		} Else {
			Write-Output "Installing ProfileUnity"
			& $InstallerExe /exenoui /qn USER=prou_services USER_PASSWORD="$Password" FLEXDISK_BROKER_MODE=0 MONGO_INSTALL_DIR="C:\Program Files\MongoDB" | Out-Null
			While ((Get-Service profileunity -ErrorAction SilentlyContinue) -eq $null) {
				Start-Sleep -Seconds 5
			}
			WaitForServices "profileunity" "Running"
		}
	
		# Check for and install hotfixes
		If ((Test-Path $($ConsoleHotfix),$($ClientToolsHotfix),$($FpcInstallerUpdate),$($Configfile) -PathType Leaf) -contains $true) {
			Stop-Service profileunity -Force -ErrorAction SilentlyContinue
			WaitForServices "profileunity" "Stopped"
	
			# Install Console Hotfix
			If (Test-Path $($ConsoleHotfix) -PathType Leaf) {
			Write-Output "Installing Console Hotfix $ConsoleHotfix"
			Expand-Archive -Path $($ConsoleHotfix) -DestinationPath "C:\Program Files (x86)\Liquidware Labs\ProfileUnity\" -Force
			}
			
			# Enable Metered Billing
			If (Test-Path $($Configfile) -PathType Leaf) {
			Write-Output "Installing profileunity.host.exe.config"
			Move-Item -Path $($Configfile) -Destination "C:\Program Files (x86)\Liquidware Labs\ProfileUnity\" -Force
			}
	
			Start-Service profileunity -ErrorAction SilentlyContinue
			
			# Install Client Tools Hotfix
			If (Test-Path $($ClientToolsHotfix) -PathType Leaf) {
			Write-Output "Installing Client Tools Hotfix $ClientToolsHotfix"
			Move-Item -Path $($ClientToolsHotfix) -Destination "C:\Program Files (x86)\Liquidware Labs\ProfileUnity\" -Force
			}
			
			# Install FPC Hotfix
			If (Test-Path $($FpcInstallerUpdate) -PathType Leaf) {
			Write-Output "Installing FPC Hotfix $FpcInstallerUpdate"
			Move-Item -Path $($FpcInstallerUpdate) -Destination "C:\Program Files (x86)\Liquidware Labs\ProfileUnity\" -Force
			}
		}
	
		# Enable RDP Login
		Write-Output "Enabling RDP Logins"
		& change logon /enable
		
		Write-Output "ProfileUnity Setup Finished"
		Exit $LastExitCode
	} Catch {
		$_
		Exit 0
	}
}