# Selectively choose which Modern apps to load

Description <br>
Powershell script to Selectively load which modern apps you want to load for new user logins<br>

How to Use<br>

Disable appreadiness services in your master image, use Start-fix.reg keys if Optimization tool breaks startmenu registration or do not disable the privacy options in your optimization.<br>

Set the execution policy<br>

```
Set-ExecutionPolicy -ExecutionPolicy Unrestricted
```
Run Script<br>

Run this command with admin rights to get the app name listings

````
Get-AppxPackage -allusers | select name
````

Select which apps you want to add back to the user, then modify first line of powershell script with apps you want to add.

````
$appxs="Microsoft.MicrosoftEdge,Microsoft.Windows.ShellExperienceHost,Microsoft.Windows.Cortana,windows.immersivecontrolpanel"
````

````
Make AppLauncher Rule
%systemroot%\system32\cmd.exe 
/c powershell.exe -executionpolicy bypass \\path\Scripts\ProcessAppX.ps1
After Config
Run Asyn
````


Code <br>
ProcessAppX.ps1<br>
````
#Add apps you want to process in the first line
$appxs="Microsoft.MicrosoftEdge,Microsoft.Windows.ShellExperienceHost,Microsoft.Windows.Cortana,windows.immersivecontrolpanel"
$appxs=$appxs.Split(",")
foreach ($appx in $appxs) {
Get-AppXPackage -AllUsers -name *$appx* | Foreach {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
}

````



| OS Version  | Verified |
| ------------- | ------------- |
|Windows 10 1803 | NO |
|Windows 10 1709 | YES |
|Windows 10 1703 | YES |
|Windows 10 1607 | YES |
