# Set log time
$datetime=get-date -format "mmddyyyyHHMMss"
#Add apps you want to process in the first line
$appxs="Microsoft.Windows.Cortana,Microsoft.Windows.ShellExperienceHost,windows.immersivecontrolpanel,Microsoft.WindowsCalculator,Microsoft.Windows.Photos"
$appxs=$appxs.Split(",")
foreach ($appx in $appxs) {
Get-AppXPackage -AllUsers -name *$appx* | Foreach {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"; $_ } | Out-File "$env:temp\$datetime-LW-AppXPackage.log" -append
}