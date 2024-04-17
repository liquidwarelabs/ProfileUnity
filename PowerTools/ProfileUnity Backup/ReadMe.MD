## ProfileUnity Backup <br>

**Description** <br>
This Is a powershell script that will backup the items in the ProfileUnity Web Console.<br>

**How to Use** <br>

**Prerequisites** <br>
This was built on the latest version of PowerShell.<br>
https://www.microsoft.com/en-us/download/details.aspx?id=50395 <br>

Download Zip with Backup Script<br>
https://github.com/liquidwarelabs/ProfileUnity/raw/master/PowerTools/ProfileUnity%20Backup/BackupDBv3.zip

To load 
- **copy the PS1 down into a folder on the profileunity server.**
- **Make Secure Password file**
- 1.	Make secure password string file.

- **In PowerShell type**:
````
Run “MakeSecurePasswordfile-AES.ps1”
Follow prompts
````
- **If you get an Execution Policy error.**
````
Set-ExecutionPolicy -ExecutionPolicy Unrestricted
````
- **Edit Backup Script**

- Open “BackupDBv4.ps1”

-	**Example**
-	.\backupDBv3.ps1 -servername "pro2020.foo.local" -ASEKeyFileLocation "C:\temp\BackupDBv3\aeskey.txt" -passwordFileLocation "C:\temp\BackupDBv3\password.txt" -savepath "c:\temp\" -purgeold -backupcount 3

-	**Override Flags**
-	servername
-	user
-	passwordFileLocation
-	ASEKeyFileLocation
-	savepath
-	purgeold
-	backupcount

- **Make Task**
- On ProfileUnity server start “Task Scheduler”
- Create new task
- **Follow the instruction specified on this site.**
- https://community.spiceworks.com/how_to/17736-run-powershell-scripts-from-task-scheduler


Script Code MakeSecurePasswordfile-AES.ps1:
````
# Prompt you to enter the username and password
$credObject = Get-Credential

# The credObject now holds the password in a ‘securestring’ format
$passwordSecureString = $credObject.password

# Define a location to store the AESKey
$AESKeyFilePath = "C:\Program Files (x86)\Liquidware Labs\FlexApp Packaging Console\aeskey.txt"
# Define a location to store the file that hosts the encrypted password
$credentialFilePath = "C:\Program Files (x86)\Liquidware Labs\FlexApp Packaging Console\password.txt"

# Generate a random AES Encryption Key.
$AESKey = New-Object Byte[] 32
[Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($AESKey)

# Store the AESKey into a file. This file should be protected! (e.g. ACL on the file to allow only select people to read)

Set-Content $AESKeyFilePath $AESKey # Any existing AES Key file will be overwritten

$password = $passwordSecureString | ConvertFrom-SecureString -Key $AESKey

Add-Content $credentialFilePath $password
````



Script Code backupDBv3.ps1:
````
<#
.SYNOPSIS
   Back up Profile Unity Database Script for scheduled task
.DESCRIPTION
   Back up Profile Unity Database Script for scheduled task
.NOTES
   Version:        4.0
   Author:         Ryan Butler (AHEAD)
   Update Author: Jack Smith (Liquidware)
   Creation Date:  01-21-2019
   Purpose/Change: Based on https://github.com/liquidwarelabs/ProfileUnity/tree/master/PowerTools/ProfileUnity%20Backup
.PARAMETER servername 
   Profile Unity server name
.PARAMETER User
   Profile Unity username
.PARAMETER passwordFileLocation
   Password file location
.PARAMETER ASEKeyFileLocation
   ASE file location
.PARAMETER SavePath
   Location to store backup files (Need trailing \)
.PARAMETER purgeold
   Purge old local backup file(s) (optional)
.PARAMETER backupcount
   How many local backups to keep (works with PurgeOld)
.EXAMPLE
   Runs backup of the profileunity database and keeps the 3 latest backups
   .\backupDBv4.ps1 -servername "ProUserver.domain.local" -user "administrator" -ASEKeyFileLocation "C:\temp\aeskey.txt" -passwordFileLocation "C:\temp\password.txt" -savepath "c:\temp\" -purgeold -backupcount 3
#>
[cmdletbinding()]
Param
(
    [Parameter(Mandatory=$true)][string]$servername,
    [Parameter(Mandatory=$false)][string]$user,
    [Parameter(Mandatory=$true)][string]$passwordFileLocation,
    [Parameter(Mandatory=$true)][string]$ASEKeyFileLocation,
    [Parameter(Mandatory=$true)][string]$savepath,
    [Parameter(Mandatory=$false)][switch]$purgeold,
    [Parameter(Mandatory=$false)]$backupcount

)

###########################################################################

#$pass=Get-Content $passwordFileLocation | ConvertTo-SecureString

#use key and password to create local secure password
$AESKey = Get-Content -Path $ASEKeyFileLocation
$pwdTxt = Get-Content -Path $passwordFileLocation
$securePass = $pwdTxt | ConvertTo-SecureString -Key $AESKey

## login Function ##

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

$pass2=[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securepass))

#Connect to Server
Write-host "Logging into ProfileUnity Server"
Invoke-WebRequest https://"$servername":8000/authenticate -Body "username=$user&password=$pass2" -Method Post -SessionVariable session
$global:session=$session
}

##########################

Connect-ProfileUnityServer
Start-Sleep -Seconds 2



#Start Backup
Write-Host "Starting backup"
try {
    Invoke-restmethod "https://$($servername):8000/api/database/backup" -WebSession $session -Method GET|Out-Null
}
catch {
    throw $_
}

#Get list of backups
$PUBL = Invoke-restmethod "https://$($servername):8000/api/database/backup/list" -WebSession $session
#Get newest backup ID
$PUBID = $publ.Tag|Sort-Object created -Descending|Select-Object -First 1

#Wait for latest backup to finish
if($PUBID.State -eq "Processing")
{
    do{
    write-host "Waiting for backup to complete..."
    Start-Sleep -Seconds 3
    #getlist
    $PUBL = Invoke-restmethod "https://$($servername):8000/api/database/backup/list" -WebSession $session
    #Get newest backup ID
    $PUBID = $publ.Tag|Sort-Object created -Descending|Select-Object -First 1
    }
    until($PUBID.State -eq "Success")

}

#Download backup
Write-Host "Downloading $($PUBID.Filename)"
try {
    Invoke-WebRequest "https://$($servername):8000/api/database/backup/$($PUBID.id)" -WebSession $session -OutFile "$savepath\$($PUBID.Filename)"|Out-Null
}
catch
{
    throw $_
}


#Purge previous backups
if($purgeold)
{
    #Check for local backup copy amounts 
    $localbackups = Get-ChildItem -Path $savepath -Filter "*.zip"

    if($localbackups.count -gt $backupcount)
    {
       write-host "Purging extra local backups"
       $localbackups|Sort-Object name -Descending|Select-Object -Last ($localbackups.Count - $backupcount)|Remove-Item -Force
    }


}


````




| OS Version  | Verified |
| ------------- | ------------- |
|Windows 10 | Yes |
|Windows 2019 | Yes |
|Windows 2016 | Yes |
|Windows Server 2012 | No |
|Windows Server 2012 R2 | Yes |
|Windows 8 | No |
|Windows 7 | Yes |