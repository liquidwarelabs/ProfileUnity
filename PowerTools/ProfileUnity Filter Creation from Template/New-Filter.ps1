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
