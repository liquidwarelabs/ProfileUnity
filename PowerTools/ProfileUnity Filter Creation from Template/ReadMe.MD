## ProfileUnity Backup <br>

**Description** <br>
This Is a powershell script that will pull filter options from a CSV and input them into the ProfileUnity Web Console.<br>

**How to Use** <br>

**Prerequisites** <br>
This was built on the latest version of PowerShell.<br>
https://www.microsoft.com/en-us/download/details.aspx?id=50395 <br>

Download Zip with Script<br>
https://github.com/liquidwarelabs/ProfileUnity/blob/master/PowerTools/ProfileUnity%20Filter%20Creation%20from%20Template/ProfileUnity%20Filter%20Creation%20from%20Template.zip?raw=true <br>

**To load** <br>

- **copy the PS1 down into a folder on the profileunity server.**
- **Edit the CSV with the items needed**
- 1.	Follow guide to set the fields correctly.
- 2.	https://github.com/liquidwarelabs/ProfileUnity/blob/master/PowerTools/ProfileUnity%20Filter%20Creation%20from%20Template/Creating%20a%20Filter.pdf

- **In PowerShell type**:
````
Run “New-Filter.ps1”
Follow prompts
````
- **If you get an Execution Policy error.**
````
Set-ExecutionPolicy -ExecutionPolicy Unrestricted
````


Script Code New-Filter.ps1:
````
##login Function

function connect-ProfileUnityServer{
##Ignore-SSL Library Code
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

##Get Creds
[string]$global:servername= Read-Host -Prompt 'FQDN of ProfileUnity Server Name'
$user = Read-Host "Enter Username"
$pass = Read-Host -assecurestring "Enter Password" 
$pass2=[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass))

#Connect to Server
Invoke-WebRequest https://"$servername":8000/authenticate -Body "username=$user&password=$pass2" -Method Post -SessionVariable session
$global:session=$session
}

Function Get-FileName($CSV)
{   
 [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") |
 Out-Null

 $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
 $OpenFileDialog.initialDirectory = $initialDirectory
 $OpenFileDialog.filter = "All files (*.*)| *.*"
 $OpenFileDialog.ShowDialog() | Out-Null
 $OpenFileDialog.filename
} #end function Get-FileName

connect-ProfileUnityServer

$ListCSVFile=Get-FileName
$lists=import-csv $ListCSVFile

Foreach ($item in $lists){
#FilterRules Hashing
$FilterRules=@{ConditionType=$item.FilterConditionType; MatchType=$item.FilterMatchType; Value=$item.Filtervalue}
$FilterRules=@($FilterRules)

##Make New FilterSettings
$newFilter=[pscustomobject]@{
Name=$item.Name;
Comments=$item.Comments;
RuleAggregate=$item.RuleAggregate;
FilterRules=$FilterRules;
MachineClasses=$item.MachineClasses;
OperatingSystems=$item.OperatingSystems;
SystemEvents=$item.SystemEvents;
Connections=$item.Connections;
}
Invoke-WebRequest https://"$servername":8000/api/filter -ContentType "application/json" -Method Post -WebSession $session -Body($NewFilter | ConvertTo-Json -Depth 10)

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