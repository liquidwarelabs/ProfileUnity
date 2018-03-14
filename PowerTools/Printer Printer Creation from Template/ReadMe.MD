## ProfileUnity Backup <br>

**Description** <br>
This Is a powershell script that will pull printer settings from a CSV and input them into the ProfileUnity Web Console.<br>

**How to Use** <br>

**Prerequisites** <br>
This was built on the latest version of PowerShell.<br>
https://www.microsoft.com/en-us/download/details.aspx?id=50395 <br>

Download Zip with Script<br>
ZipLink <br>

**To load** <br>

- **copy the PS1 down into a folder on the profileunity server.**
- **Edit the CSV with the items needed**

- 1.	Follow guide to set the fields correctly.

- **In PowerShell type**:
````
Run “add-printer.ps1”
Follow prompts
````
- **If you get an Execution Policy error.**
````
Set-ExecutionPolicy -ExecutionPolicy Unrestricted
````


Script Code add-printer.ps1:
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

$PrinterCSV=Get-FileName
$list=import-csv $PrinterCSV

foreach ($Printer in $list){
$newPrinter=[pscustomobject]$list
$PUGC = ((Invoke-WebRequest https://"$servername":8000/api/configuration -WebSession $session).Content) | ConvertFrom-Json
[string]$configID=$PUGC.Tag.Rows | Where-Object {$_.name -EQ $Configname} | foreach {$_.id}
$configR= ((Invoke-WebRequest https://"$servername":8000/api/configuration/"$configID" -WebSession $session).Content) | ConvertFrom-Json
$config=$configR.tag

$config.Printers += $Printer
Invoke-WebRequest https://"$servername":8000/api/configuration -ContentType "application/json" -Method Post -WebSession $session -Body($config | ConvertTo-Json -Depth 10)
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
