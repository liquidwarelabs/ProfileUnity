##########################################################################################################################################################################
# ProfileUnity 6.8.5 and up has built-in caching support for all required files
# After one "on-network" login as a production user, ProfileUnity is then ready to function offline

# UserINIPath AND LicenseServerConnectionString ARE REQUIRED!
# Update at least the first 2 variables with your own environment and storage information
$UserINIPath = "\\some.server\somewhere\ProfileUnity" # or "AZ://blob/folder" or "S3://blob/folder" or "GS://blob/folder"
# Copy License Server Connection String from the ProfileUnity Console Administration screen, Client Settings section, click Manage Connection Strings and click the Copy to Clipboard button
$LicenseServerConnectionString = ""

# Optional settings based on environmental requirements - Defaults included, if any
$SystemINIPath = "$UserINIPath\Startup"
$ClientServiceExeCredsPath = "$UserINIPath"
$ProfileDiskConfigNodesXmlPath = "$UserINIPath"
$SecondaryPaths = ""
# Client Cloud credentials can be copied from the ProfileUnity Console Administration screen - Client creds, NOT Console!
$AzureStorageCredentials = ""
$SecondaryAzureStorageCredentials = ""
$AmazonS3Credentials = ""
$GoogleStorageCredentials = ""
# Comment out the CloudToolsInstallerPS1 value if you want to skip the ProfileUnity client-tools installation
$CloudToolsInstallerPS1 = "https://cdn.liquidware.com/6.8.6/ProfileUnity-CloudInstall_6.8.6r1ga3.ps1"

#################################################################################################################################################
# To skip running ProfileUnity and FlexApp for your local admin account, define the name of your local admin account here.
$localAdminUser = "admin"
# To skip for a service account, specify here.
$installerServiceAccount = "administrator"
# List of "Users" (read: folders in C:\Users) to be excluded from reg settings
$excludedUsers = @(
$env:computername+'$'
$installerServiceAccount
$localAdminUser
"Default"
"Public"
)
#################################################################################################################################################
# Uncomment this setting to skip the configuration of the logoff script GPO, If desired, to reduce logoff times - ONLY SPECIAL SCENARIOS!
# ONLY USE FOR FlexApp-ONLY DEPLOYMENTS TO NON-PERSISTENT MACHINES OR FlexAppOne-ONLY DEPLOYMENTS TO PERSISTENT OR NON-PERSISTENT MACHINES!
# $SkipLogoffGPO = $true
#################################################################################################################################################
Start-Transcript -Path "C:\windows\temp\lwinstallerlog.txt" -Append

# Define function to update HKCU for all existing profiles, including default user and logged on user
function Add-AllUserRegSetting {
    [CmdletBinding()]
    param (
        [string]$RegPath,
        [string]$PropertyName,
        $PropertyValue,
        [Parameter(Mandatory=$true)][ValidateSet('String','ExpandString','Binary','DWord','MultiString','Qword','Unknown')][string]$PropertyType,
        [Parameter(Mandatory=$false)][string]$DefaultUserMountPoint
    )
    
    begin {
        $StrippedPath = ($RegPath -split 'HKCU:\\')[1]
		$loggedOnUsers = (Get-WmiObject Win32_Process -f 'Name="explorer.exe"'  |%  getowner  |% user | Where-Object { ($_ -notin $excludedUsers) })
		Write-Host
		Write-Host "Setting value $PropertyName"
	}
    
    process {
        #Current user settings, if not an excluded user.
        if ($env:username -notin $excludedUsers) {
            if (!(Test-Path -Path $RegPath )) {
                $Item = New-Item -Path $RegPath -Force
                $Item.Handle.Close()
            }
			Write-Host "Current user $env:username being setup..."
            New-ItemProperty -Path $RegPath -Name $PropertyName -Value $PropertyValue -PropertyType $PropertyType -Force | Out-Null
			Write-Host
        }
		#DefaultUser settings (if defaultusermountpoint param is specified)
        if ($DefaultUserMountPoint){
            if (!(Test-Path -Path (Join-Path -Path $DefaultUserMountPoint -ChildPath $StrippedPath) )) {
                $Item = New-Item -Path (Join-Path -Path $DefaultUserMountPoint -ChildPath $StrippedPath) -Force
                $Item.Handle.Close()
            }
			Write-Host "Default user being setup..."
            New-ItemProperty -Path (Join-Path -Path $DefaultUserMountPoint -ChildPath $StrippedPath) -Name $PropertyName -Value $PropertyValue -PropertyType $PropertyType -Force | Out-Null
			Write-Host
        }

        #Existing users NOT logged on to machine that aren't excluded
        $users = (Get-ChildItem -Path c:\users | Where-Object { (($_.Name -notin $excludedUsers) -and ($_.Name -notin $loggedOnUsers) -and ($_.Name -ne $env:username)) }).Name
		$users
        ForEach ($user in $users) {
			Write-Host "Starting logged off user $user"
            reg load "HKLM\$user" "C:\Users\$user\NTUSER.DAT"
			$UserRegPath = Join-Path -Path "HKLM:\$user" -ChildPath $StrippedPath
            if (!(Test-Path -Path $UserRegPath )) {
                $Item = New-Item -Path $UserRegPath -Force
                $Item.Handle.Close()
            }
            New-ItemProperty -Path $UserRegPath -Name $PropertyName -Value $PropertyValue -PropertyType $PropertyType -Force | Out-Null
			Set-Location c:\
            Start-Sleep -Milliseconds 500
            [gc]::collect()
            Start-Sleep -Seconds 1
            reg unload "HKLM\$user"
            Write-Host "Done with logged off user $user"
			Write-Host
        }

		#Logged On Users that aren't the current user and aren't excluded
		$mountedhives = (Get-ItemProperty 'Registry::HKEY_USERS\*\Volatile Environment' -Name USERNAME -ErrorAction SilentlyContinue | Where-Object { (($_.USERNAME -notin $excludedUsers) -and ($_.USERNAME -ne $env:username)) }).PSParentPath
		$mountedhives
		Write-Host ($mountedhives).count mounted user hives found.
		($loggedOnUsers | Where-Object { ($_ -ne $env:username) })
		Write-Host ($loggedOnUsers | Where-Object { ($_ -ne $env:username) }).count logged on users found. These numbers should match!
		ForEach ($hive in $mountedhives) {
			$user = (Get-ItemProperty "$hive\Volatile Environment" -Name USERNAME -ErrorAction SilentlyContinue).USERNAME
			Write-Host "Starting logged on user $user"
			$path = (Join-Path -Path $hive -ChildPath "SOFTWARE\Liquidware Labs\ProfileUnity")
            if (!(Test-Path -Path $path )) {
				$Item = New-Item -Path $path -Force
			}
			Write-Host "KEY: $path"
			New-ItemProperty -Path $path -Name $PropertyName -Value $PropertyValue -PropertyType $PropertyType -Force | Out-Null
			Write-Host "Done with logged on user $user"
			Write-Host
		}
    }
    
    end {
        Write-Host "Done setting value $PropertyName"
		Write-Host
    }
}

# Set HKLM reg values
Write-Host "Start writing local machine registry keys..." -ForegroundColor GREEN
$MachineREG_ProU = "HKLM:\SOFTWARE\Liquidware Labs\ProfileUnity"
if (!(Test-Path -Path $MachineREG_ProU )) { 
	$Item = New-Item -Path $MachineREG_ProU -Force
	$Item.Handle.Close()
}
If ($AzureStorageCredentials) { New-ItemProperty -Path $MachineREG_ProU  -Name AzureStorageCredentials -PropertyType String -Value $AzureStorageCredentials -Force | Out-Null }
If ($SecondaryAzureStorageCredentials) { New-ItemProperty -Path $MachineREG_ProU  -Name SecondaryAzureStorageCredentials -PropertyType String -Value $SecondaryAzureStorageCredentials -Force | Out-Null }
If ($AmazonS3Credentials) { New-ItemProperty -Path $MachineREG_ProU  -Name AmazonS3Credentials -PropertyType String -Value $AmazonS3Credentials -Force | Out-Null }
If ($GoogleStorageCredentials) { New-ItemProperty -Path $MachineREG_ProU  -Name GoogleStorageCredentials -PropertyType String -Value $GoogleStorageCredentials -Force | Out-Null }
If ($SecondaryPaths) { New-ItemProperty -Path $MachineREG_ProU  -Name SecondaryPaths -PropertyType String -Value $SecondaryPaths -Force | Out-Null }
If ($ClientServiceExeCredsPath) { New-ItemProperty -Path $MachineREG_ProU  -Name ClientServiceExeCredsPath -PropertyType String -Value $ClientServiceExeCredsPath -Force | Out-Null }
If ($SystemINIPath) { New-ItemProperty -Path $MachineREG_ProU  -Name INIPath -PropertyType String -Value $SystemINIPath -Force | Out-Null }
If ($LicenseServerConnectionString) { New-ItemProperty -Path $MachineREG_ProU  -Name LicenseServerConnectionString -PropertyType String -Value $LicenseServerConnectionString -Force | Out-Null }
If ($ProfileDiskConfigNodesXmlPath) { New-ItemProperty -Path $MachineREG_ProU  -Name ProfileDiskConfigNodesXmlPath -PropertyType String -Value $ProfileDiskConfigNodesXmlPath -Force | Out-Null }
Write-Host "Finished writing local machine registry keys." -ForegroundColor GREEN
Write-Host

# Set HKCU reg values for Default user hive, current logged-on user and all other existing user profiles
Write-Host "Start writing HKU registry keys..." -ForegroundColor GREEN

#Load Default User registry hive
reg load "HKLM\DefaultUser" "C:\Users\Default\NTUSER.DAT"

#Add Liquidware settings to HKCU path of Default user AND all existing users on machine
Add-AllUserRegSetting -RegPath "HKCU:\SOFTWARE\Liquidware Labs\ProfileUnity" -PropertyName "Enabled" -PropertyValue "1" -PropertyType "String" -DefaultUserMountPoint "HKLM:\DefaultUser"
Add-AllUserRegSetting -RegPath "HKCU:\SOFTWARE\Liquidware Labs\ProfileUnity" -PropertyName "INIPath" -PropertyValue $UserINIPath -PropertyType "String" -DefaultUserMountPoint "HKLM:\DefaultUser"

#Cleanup
Set-Location c:\
Start-Sleep -Milliseconds 500
[gc]::collect()
Start-Sleep -Seconds 1

#Unload Default User registry hive
reg unload hklm\DefaultUser

#################################################################################################################################################
# Fix Old Policy (legacy from previous installers)

IF(test-path -path "C:\Windows\System32\GroupPolicy\Machine\*.pol"){
    Write-Host "Deleting old policy" -ForegroundColor Yellow
    Remove-Item -path "C:\Windows\System32\GroupPolicy\GPT.ini" -Force -ErrorAction SilentlyContinue
    Remove-Item -path "C:\Windows\System32\GroupPolicy\Machine\*.pol" -Force -ErrorAction SilentlyContinue
    Remove-Item -path "C:\Windows\System32\GroupPolicy\User\*.pol"    -Force -ErrorAction SilentlyContinue
    Remove-Item -path "C:\Windows\System32\GroupPolicy\ADM\*.adm"     -Force -ErrorAction SilentlyContinue
}ELSE{
    Write-Host "No legacy Policy found" -ForegroundColor Yellow}
Write-Host
#################################################################################################################################################

# Configure logoff script if SkipLogoffGPO is false
If (!($SkipLogoffGPO)) {
	Write-Host "Start writing local logoff script GPO..." -ForegroundColor GREEN
	$ScriptsContent = @"

[Logoff]
0CmdLine=C:\Program Files\ProfileUnity\Client.NET\LwL.ProfileUnity.Client.Logoff.exe
0Parameters=
"@

	If (Test-Path "C:\Windows\System32\GroupPolicy\User\Scripts\scripts.ini") { Remove-Item -Path "C:\Windows\System32\GroupPolicy\User\Scripts\scripts.ini" -Force }
	If (!(Test-Path "C:\Windows\System32\GroupPolicy\User\Scripts")) { New-Item -Path "C:\Windows\System32\GroupPolicy\User\Scripts" -ItemType Directory -Force }
	$ScriptsContent | Out-File -FilePath "C:\Windows\System32\GroupPolicy\User\Scripts\scripts.ini" -Force

	$GptContent = @"
[General]
gPCUserExtensionNames=[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F73-3407-48AE-BA88-E8213C6761F1}][{42B5FAAE-6536-11D2-AE5A-0000F87571E3}{40B66650-4972-11D1-A7CA-0000F87571E3}]
Version=300000
"@

	$GptContent | Out-File -FilePath "C:\Windows\System32\GroupPolicy\gpt.ini" -Force

	& "cmd.exe" "/c" "gpupdate.exe" "/force"
} Else { Write-Host "SkipLogoffGPO is True!  Skipping local logoff script GPO." -ForegroundColor GREEN
Write-Host }

# Last, install and/or reconfigure ProfileUnity Client Tools
If ($CloudToolsInstallerPS1) {
	Write-Host "Starting ProfileUnity Cloud Tools Installer..." -ForegroundColor GREEN
	(New-Object System.Net.WebClient).DownloadFile($CloudToolsInstallerPS1,$Env:Temp + '\ProfileUnity-CloudInstall.ps1');Invoke-Expression -Command (Join-Path $Env:Temp '\ProfileUnity-CloudInstall.ps1')
	Write-Host "Finished ProfileUnity Cloud Tools Installer." -ForegroundColor GREEN
} Else {
	Write-Host "No Cloud Tools PS1 specified, skipping ProfileUnity Cloud Tools installation!  Attempting to reconfigure by running local Startup.Update.exe instead..." -ForegroundColor GREEN
	$StartupUpdate = "C:\Program Files\ProfileUnity\Client.NET\LwL.ProfileUnity.Client.Startup.Update.exe"
	If (Test-Path $StartupUpdate) {
		Write-Host "Reconfiguring ProfileUnity Client Tools..." -ForegroundColor GREEN
		Start-Process "$StartupUpdate" -Wait | Out-Null
		Write-Host "ProfileUnity Client Tools have been reconfigured.  Done." -ForegroundColor GREEN
	} Else { Write-Host "No local ProfileUnity Client Tools installation found!  Ending with no tools." -ForegroundColor RED }
}
Write-Host