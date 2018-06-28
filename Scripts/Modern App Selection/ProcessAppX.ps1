#Add apps you want to process in the first line
$appxs="Microsoft.MicrosoftEdge,Microsoft.Windows.ShellExperienceHost,Microsoft.Windows.Cortana,windows.immersivecontrolpanel"
$appxs=$appxs.Split(",")
foreach ($appx in $appxs) {
Get-AppXPackage -AllUsers -name *$appx* | Foreach {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
}