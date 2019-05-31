## ProfileUnity Portability Restore <br>

**Description** <br>
This is a powershell script that is a GUI for profile restore from the fileshare.<br>

**How to Use** <br>
Run powershell, follow prompts. This restores all portaibity archives

**Prerequisites** <br>
This was built on the latest version of PowerShell.<br>
https://www.microsoft.com/en-us/download/details.aspx?id=50395 <br>


- **In PowerShell type**:
````
Run “restoreRetentionv4.ps1”
Follow prompts
````
- **If you get an Execution Policy error.**
````
Set-ExecutionPolicy -ExecutionPolicy Unrestricted
````


Script Code restoreRetentionv4.ps1:
````
$t = '[DllImport("user32.dll")] public static extern bool ShowWindow(int handle, int state);'
add-type -name win -member $t -namespace native
[native.win]::ShowWindow(([System.Diagnostics.Process]::GetCurrentProcess() | Get-Process).MainWindowHandle, 0)

[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null

# Show input box popup and return the value entered by the user.
function Read-InputBoxDialog([string]$Message, [string]$WindowTitle, [string]$DefaultText)
{
    Add-Type -AssemblyName Microsoft.VisualBasic
    return [Microsoft.VisualBasic.Interaction]::InputBox($Message, $WindowTitle, $DefaultText)
}


$usershare="\\pro2016\ProfileShare"
#$username = Read-host -Prompt 'input users username'
$username = Read-InputBoxDialog -Message "Please enter the username for your selected user'" -WindowTitle "Select User" -DefaultText "jsmith"

if ($username -eq "") { Write-Host "You clicked Cancel" }

elseif ($username -ne $null)  

{ $selection = Get-ChildItem $usershare\$username\portability\Retention -Directory

$selection = $selection | out-gridview -Title "Please Select a Restore Point" -passthru

$OUTPUT= [System.Windows.Forms.MessageBox]::Show("Are you sure you would like to restore $selection for $username." , "Status" , 4) 
if ($OUTPUT -eq "YES" ) 

{
Copy $usershare\$username\portability\win10\Retention\$selection.Name\*.* $usershare\$username\portability\win10\
Copy $usershare\$username\portability\win7\Retention\$selection.Name\*.* $usershare\$username\portability\win7\
Copy $usershare\$username\portability\Retention\$selection.Name\*.* $usershare\$username\portability\
Remove-Item -Path $usershare\$username\portability\*.manifest -Confirm:$false -Force
Remove-Item -Path $usershare\$username\portability\Win10\*.manifest -Confirm:$false -Force
Remove-Item -Path $usershare\$username\portability\Win7\*.manifest -Confirm:$false -Force
} 
else 

{ 
exit 
}   
    
}


````




| OS Version  | Verified |
| ------------- | ------------- |
|Windows 10 | Yes |
|Windows Server 2012 | No |
|Windows Server 2012 R2 | Yes |
|Windows Server 2008 R2 | Yes |
|Windows Server 2008 | No |
|Windows Server 2003 | No |
|Windows 8 | No |
|Windows 7 | Yes |
|Windows Vista | No |
|Windows XP | No |
|Windows 2000 | No | 