## ProfileUnity Backup <br>

**Description** <br>
This Is a powershell script that will backup the items in the ProfileUnity Web Console.<br>

**How to Use** <br>

**Prerequisites** <br>
This was built on the latest version of PowerShell.<br>
https://www.microsoft.com/en-us/download/details.aspx?id=50395

To load 
- **copy the PS1 down into a folder on the profileunity server.**
- **Make Secure Password file**
- 1.	Make secure password string file.

- **In PowerShell type**:
````
Run “MakeSecurePasswordfile.ps1”
Follow prompts
````
- **If you get an Execution Policy error.**
````
Set-ExecutionPolicy -ExecutionPolicy Unrestricted
````
- **Edit Backup Script**

- Open “BackupDB.ps1”
- **Edit the following lines**
- [string]$global:servername= "ProU Server Name"
- $user= "ProU User"
- $pass=Get-Content c:\temp\Password.txt | ConvertTo-SecureString
- [string]$global:savepath= "c:\temp\"

- **Make Task**
- On ProfileUnity server start “Task Scheduler”
- Create new task
- **Follow the instruction specified on this site.**
- https://community.spiceworks.com/how_to/17736-run-powershell-scripts-from-task-scheduler


Script Code MakeSecurePasswordfile.ps1:
````
$savepath=Read-Host "Password File Save location?" 
Read-Host "Enter Password" -AsSecureString |  ConvertFrom-SecureString | Out-File "$savepath\Password.txt"
````



Script Code backupDB.ps1:
````
## Env Variables (EDIT THESE) ##
#ProfileUnity Server name (E.G. (Prou.server.domain))#
[string]$global:servername= "ProU Server Name"
#login for proU Console#
$user= "ProU User"
#Follow run Secure String instruction to make Password file. (path to password.txt)#
$pass=Get-Content c:\temp\Password.txt | ConvertTo-SecureString
#Save Path for Backup.zip#
[string]$global:savepath= "c:\temp\"

#####################################################################

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
#[string]$global:servername= Read-Host -Prompt 'FQDN of ProfileUnity Server Name'

$pass2=[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass))

#Connect to Server
Invoke-WebRequest https://"$servername":8000/authenticate -Body "username=$user&password=$pass2" -Method Post -SessionVariable session
$global:session=$session
}


## Download latest Backup
function Backup-Proulatest
{
##Start Backup
$PUBC= ((Invoke-WebRequest https://"$servername":8000//api/database/backup -WebSession $session).Content) | ConvertFrom-Json
##Pause for backup to complete
timeout /t 10 /nobreak
#getlist
$PUBL = ((Invoke-WebRequest https://"$servername":8000/api/database/backup/list -WebSession $session).Content) | ConvertFrom-Json
#Get latest Backup ID
$PUBID=$PUBL.tag | Foreach-Object {$_.Created = [DateTime]$_.Created; $_} | 
Group-Object Computer | 
Foreach-Object {$_.Group | Sort-Object Created | Select-Object -Last 1} | foreach {$_.Id}
#back it up
$pubfilename="ProU-Backup-" + "$PUBID" +".zip"
$backup=((Invoke-WebRequest https://"$servername":8000/api/database/backup/$PUBID -WebSession $session))
$savepath1="$savepath" + "$pubfilename"
$saveAttachment = [System.IO.File]::WriteAllBytes("$savepath1", $backup.content)
}

## Connect to ProfileUnity Server and backup database ##
connect-ProfileUnityServer
timeout /t 2 /nobreak
Backup-Proulatest

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
