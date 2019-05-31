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