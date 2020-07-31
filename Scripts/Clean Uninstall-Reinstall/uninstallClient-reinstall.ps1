
# Set Path to Current ProfileUnity Client Startup
$CurrentVersionPath = "\\SERVER\profileUnity\ClientTools\LwL.ProfileUnity.Client.Startup.exe"
$OldVersionPath = "\\SERVER\profileUnity\Clienttools6.8.2\LwL.ProfileUnity.Client.Startup.exe"


# Check Client Install
$uninstall64 = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall" | ForEach-Object { Get-ItemProperty $_.PSPath } | ? { $_ -match "ProfileUnity Client" }

# Version Check
$CurrentVersion = (Get-ItemProperty $CurrentVersionPath).VersionInfo.FileVersion
$VersionCheck = $uninstall64.DisplayVersion -like "*$CurrentVersion*"

# Uninstall if needed 
If ( $VersionCheck -eq "true") {
    Write-host "Current ProfileUnity Client Installed"

    break

  }  Else {

Write-Output "Uninstalling ProfileUnity Client..."
start-process $OldVersionPath -ArgumentList "/uninstall" -Wait
Write-Output "Removing Leftover Registery Items..."
Remove-Item -Path "HKLM:\SOFTWARE\WOW6432Node\Liquidware Labs" -Recurse
Remove-Item -Path "HKLM:\SOFTWARE\Liquidware Labs" -Recurse

if( ( (test-path "HKLM:\SOFTWARE\WOW6432Node\Liquidware Labs","HKLM:\SOFTWARE\Liquidware Labs","C:\Program Files\ProfileUnity") -eq $false).Count ){
            Write-host "ProfileUnity Uninstalled"
            Write-host "Installing Current ProfileUnity Client"
            start-process $CurrentVersionPath -arg "/WaitOnExit false" -wait
            Write-host "Rebooting Workstation"
            Restart-Computer
        }Else
        {
        Write-host "Uninstall failed..."
            break
        }        
} 
exit