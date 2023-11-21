<# 
.DISCLAIMER
 This script is provided "AS IS" with no warranties, confers no rights, and is not supported by Liquidware Labs.
 
.SYNOPSIS 
ProfileUnity Powershell Commands and Functions

  .DESCRIPTION 
 Made for ProfileUnity Command line modifications to configurations, Filters, and Portability Rules
  .NOTES 
     NAME:  ProUPowerTools.v1.psm1
      AUTHOR: Jack Smith
		Email Address: Jack.Smith@liquidwarelabs.com
		Twitter: @MrSmithLWL
		Github: https://github.com/liquidwarelabs
      LASTEDIT: 1/8/2020
      KEYWORDS: ProfileUnity, Powershell, Flexapp, Json
		Notes: v2.0
#> 

## Supporting Core Functions ##

##Prompt-Choice Function Library code
	function Prompt-Choice {
        #param (
        #   [parameter(mandatory=$true)][string]$Title,
        #   [parameter(mandatory=$true)][string]$Message
        #)

        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Yes."
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "No."
        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
        $result = $host.ui.PromptForChoice($title, $message, $options, 0) 
        switch ($result)
        {
            0 { $true }
            1 { $false }
        }
    }


## Get file path ##
Function Get-FileName($jsonfile)
{   
 [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") |
 Out-Null

 $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
 $OpenFileDialog.initialDirectory = $initialDirectory
 $OpenFileDialog.filter = "All files (*.json*)| *.json*"
 $OpenFileDialog.ShowDialog() | Out-Null
 $OpenFileDialog.filename
} #end function Get-FileName


##login Functions Cert exceptions##

function connect-ProfileUnityServer{

########################################
# Adding certificate exception to prevent API errors
########################################
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
#optional security bypass
#[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'


##Prof
[string]$global:servername= Read-Host -Prompt 'FQDN of ProfileUnity Server Name'
$user = Read-Host "Enter Username"
$pass = Read-Host -assecurestring "Enter Password" 
$pass2=[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass))

#Connect to Server
Invoke-WebRequest https://"$servername":8000/authenticate -Body "username=$user&password=$pass2" -Method Post -SessionVariable session
$global:session=$session
}


## Filter Functions (api/filter)

## Get Filter ##
function get-ProUFilters
{
$PUG = ((Invoke-WebRequest https://"$servername":8000/api/Filter -WebSession $session).Content) | ConvertFrom-Json
$PUG.Tag.Rows
}

## Load ProfileUnity Filters ##
function edit-ProUFilter([string]$name)
{
$PUG = ((Invoke-WebRequest https://"$servername":8000/api/Filter -WebSession $session).Content) | ConvertFrom-Json
[string]$ID=$PUG.Tag.Rows | Where-Object {$_.name -Match $name} | foreach-object {$_.id}
$configR= ((Invoke-WebRequest https://"$servername":8000/api/Filter/"$ID" -WebSession $session).Content) | ConvertFrom-Json
$config=$configR.tag
$global:CurrentFilter = $config
}

## Save Filter settings ##
Function Save-ProUFilter{
    $answer=prompt-choice
    if ($answer -eq $False)
    {Write-Host "Save Canceled" -ForegroundColor "red" -BackgroundColor "yellow"}
    else 
    {
    Invoke-WebRequest https://"$servername":8000/api/Filter -ContentType "application/json" -Method Post -WebSession $session -Body($CurrentFilter | ConvertTo-Json -Depth 10)
    }
    }


## Delete Filter ##
function remove-ProUFilter([string]$name)
{
$PUG = ((Invoke-WebRequest https://"$servername":8000/api/filter -WebSession $session).Content) | ConvertFrom-Json
[string]$ID=$PUG.Tag.Rows | Where-Object {$_.name -EQ $name} | ForEach-Object {$_.id}
$response = Invoke-WebRequest https://"$servername":8000/api/Filter"$ID"?force=false -Method Delete -WebSession $session
$Message=$response.Content | ConvertFrom-Json
write-host $message.message
}


## Export Single Filter Json
function export-ProUFilter([string]$name, $savepath)
{
if (!$savepath)
	{
	Write-host -ForegroundColor red "Missing Save Path" 
	}
else 
{
#Load Filter into memory
$PUG = ((Invoke-WebRequest https://"$servername":8000/api/Filter -WebSession $session).Content) | ConvertFrom-Json
[string]$ID=$PUG.Tag.Rows | Where-Object {$_.name -Match $name} | foreach-object {$_.id}
#Export Filter
$ProgressPreference = 'SilentlyContinue'
Invoke-RestMethod -ContentType "application/octet-stream" -Uri https://"$servername":8000/api/Filter/"$ID"/download?encoding=default -WebSession $session -OutFile "$savepath$name.json"
}
}

## Export All Filters Jsons ##
Function Export-ProUFilterAll ($savepath)
{
if (!$savepath)
	{
	Write-host -ForegroundColor red "Missing Save Path" 
	}
else 
	{
	#get List
	$list=get-ProUFilters
	[array]$list=$list.name
	#export out all
	foreach ($name in $list)
		{
		#Load Configs into memory
		$PUG = ((Invoke-WebRequest https://"$servername":8000/api/Filter -WebSession $session).Content) | ConvertFrom-Json
		[string]$ID=$PUG.Tag.Rows | Where-Object {$_.name -Match $name} | foreach-object {$_.id}

		#Export Items
		#Invoke-WebRequest https://"$servername":8000/api/Filter/"$ID" -WebSession $session -OutFile "$savepath$name.json" -PassThru
		$ProgressPreference = 'SilentlyContinue'
		Invoke-RestMethod -ContentType "application/octet-stream" -Uri https://"$servername":8000/api/Filter/"$ID"/download?encoding=default -WebSession $session -OutFile "$savepath$name.json"
		}
	}
}

## Import Filter Json ##

## Import Single Filter Json
Function Import-ProUFilter{

#Import Json
$jsonfile=Get-FileName
$jsonimport=Get-Content $jsonFile | ConvertFrom-Json

#Change Name and ID
$connectionString = $jsonimport | select-object -expand Filters
$connectionString.name = $jsonimport.Filters.name + " - Imported"
$connectionString.ID = $Null


#Save Json
Invoke-WebRequest https://"$servername":8000/api/Filter -ContentType "application/json" -Method Post -WebSession $session -Body($jsonimport.Filters | ConvertTo-Json -Depth 10)

}


## Import All Filter Jsons ##
Function Import-ProUFilterAll ($sourceDir)
{
if (!$sourcedir)
	{
	Write-host -ForegroundColor red "Missing Source Path Dir" 
	}
else 
	{
	
	$lists=Get-ChildItem $sourcedir
	$lists=$lists.VersionInfo.filename
	foreach ($json in $lists) 

		{

		#Import Json
		$jsonfile=$json
		$jsonimport = Get-Content $jsonFile | ConvertFrom-Json
		
		#Change Name and ID
		$connectionString = $jsonimport | Select-Object -expand Filters
		$connectionString.name = $jsonimport.Filters.name + " - Imported"
		$connectionString.ID = $Null
	
		
		#Save Json
		Invoke-WebRequest https://"$servername":8000/api/Filter -ContentType "application/json" -Method Post -WebSession $session -Body($jsonimport.Filters | ConvertTo-Json -Depth 10)

		}
}
}

## Portability Functions (api/portability) ##

## Get PortRule ##
function get-ProUPortRule
{
$PUG = ((Invoke-WebRequest https://"$servername":8000/api/portability -WebSession $session).Content) | ConvertFrom-Json
$PUG.Tag.Rows
}

## Load ProfileUnity PortRules ##
function edit-ProUPortRule([string]$name)
{
$PUG = ((Invoke-WebRequest https://"$servername":8000/api/portability -WebSession $session).Content) | ConvertFrom-Json
[string]$ID=$PUG.Tag.Rows | Where-Object {$_.name -Match $name} | foreach-object {$_.id}
$configR= ((Invoke-WebRequest https://"$servername":8000/api/portability/"$ID" -WebSession $session).Content) | ConvertFrom-Json
$config=$configR.tag
$global:CurrentPortRule= $config
}

## Save PortRule settings ##
Function Save-ProUPortRule{
    $answer=prompt-choice
    if ($answer -eq $False)
    {Write-Host "Save Canceled" -ForegroundColor "red" -BackgroundColor "yellow"}
    else 
    {
    Invoke-WebRequest https://"$servername":8000/api/portability -ContentType "application/json" -Method Post -WebSession $session -Body($CurrentPortRule | ConvertTo-Json -Depth 10)
    }
    }


## Delete PortRule ##
function remove-ProUPortRule([string]$name)
{
$PUG = ((Invoke-WebRequest https://"$servername":8000/api/portability -WebSession $session).Content) | ConvertFrom-Json
[string]$ID=$PUG.Tag.Rows | Where-Object {$_.name -EQ $name} | ForEach-Object {$_.id}
$response = Invoke-WebRequest https://"$servername":8000/api/portability"$ID"?force=false -Method Delete -WebSession $session
$Message=$response.Content | ConvertFrom-Json
write-host $message.message
}


## Export Single PortRule Json
function export-ProUPortRule([string]$name, $savepath)
{
if (!$savepath)
	{
	Write-host -ForegroundColor red "Missing Save Path" 
	}
else 
{
#Load PortRule into memory
$PUG = ((Invoke-WebRequest https://"$servername":8000/api/portability -WebSession $session).Content) | ConvertFrom-Json
[string]$ID=$PUG.Tag.Rows | Where-Object {$_.name -Match $name} | foreach-object {$_.id}
#Export PortRule
$ProgressPreference = 'SilentlyContinue'
Invoke-RestMethod -ContentType "application/octet-stream" -Uri https://"$servername":8000/api/portability/"$ID"/download?encoding=default -WebSession $session -OutFile "$savepath$name.json"
}
}

## Export All PortRules Jsons ##
Function Export-ProUPortRuleAll ($savepath)
{
if (!$savepath)
	{
	Write-host -ForegroundColor red "Missing Save Path" 
	}
else 
	{
	#get List
	$list=get-ProUPortRules
	[array]$list=$list.name
	#export out all
	foreach ($name in $list)
		{
		#Load Configs into memory
		$PUG = ((Invoke-WebRequest https://"$servername":8000/api/portability -WebSession $session).Content) | ConvertFrom-Json
		[string]$ID=$PUG.Tag.Rows | Where-Object {$_.name -Match $name} | foreach-object {$_.id}

		#Export Items
		#Invoke-WebRequest https://"$servername":8000/api/portability/"$ID" -WebSession $session -OutFile "$savepath$name.json" -PassThru
		$ProgressPreference = 'SilentlyContinue'
		Invoke-RestMethod -ContentType "application/octet-stream" -Uri https://"$servername":8000/api/portability/"$ID"/download?encoding=default -WebSession $session -OutFile "$savepath$name.json"
		}
	}
}

## Import PortRule Json ##

## Import Single PortRule Json
Function Import-ProUPortRule{

#Import Json
$jsonfile=Get-FileName
$jsonimport=Get-Content $jsonFile | ConvertFrom-Json

#Change Name and ID
$connectionString = $jsonimport | select-object -expand portability
$connectionString.name = $jsonimport.portability.name + " - Imported"
$connectionString.ID = $Null


#Save Json
Invoke-WebRequest https://"$servername":8000/api/portability -ContentType "application/json" -Method Post -WebSession $session -Body($jsonimport.portrules | ConvertTo-Json -Depth 10)

}


## Import All PortRule Jsons ##
Function Import-ProUPortRuleAll ($sourcedir)
{
if (!$sourcedir)
	{
	Write-host -ForegroundColor red "Missing Source Path Dir" 
	}
else 
	{
	
	$lists=Get-ChildItem $sourcedir
	$lists=$lists.VersionInfo.filename
	foreach ($json in $lists) 

		{

		#Import Json
		$jsonfile=$json
		$jsonimport = Get-Content $jsonFile | ConvertFrom-Json
		
		#Change Name and ID
		$connectionString = $jsonimport | Select-Object -expand PortRules
		$connectionString.name = $jsonimport.PortRules.name + " - Imported"
		$connectionString.ID = $Null
	
		
		#Save Json
		Invoke-WebRequest https://"$servername":8000/api/portability -ContentType "application/json" -Method Post -WebSession $session -Body($jsonimport.PortRules | ConvertTo-Json -Depth 10)

		}
}
}

## flexapppackage Functions (api/flexapppackage) ##

## List all Flexapps
function get-ProUFlexapps
{
$PUG = ((Invoke-WebRequest https://"$servername":8000/api/flexapppackage/ -WebSession $session).Content) | ConvertFrom-Json
$PUG.TAG.ROWS
}


## Load Flexapp ##
function edit-proUflexapp([string]$name)
{
$PUG = ((Invoke-WebRequest https://"$servername":8000/api/flexapppackage -WebSession $session).Content) | ConvertFrom-Json
[string]$ID=$PUG.Tag.Rows | Where-Object {$_.name -EQ $name} | ForEach-Object {$_.id}
$PUG= ((Invoke-WebRequest https://"$servername":8000/api/flexapppackage/"$ID" -WebSession $session).Content) | ConvertFrom-Json
$PUG=$PUG.tag
$global:CurrentFlexapp = $PUG
}

## Save Flexapp settings ##
Function Save-ProUFlexapp{
    $answer=prompt-choice
    if ($answer -eq $False)
    {Write-Host "Save Canceled" -ForegroundColor "red" -BackgroundColor "yellow"}
    else 
    {
    Invoke-WebRequest https://"$servername":8000/api/flexapppackage -ContentType "application/json" -Method Post -WebSession $session -Body($CurrentFlexapp | ConvertTo-Json -Depth 10)
    }
    }

## Delete FlexApp ##
function remove-proUFlexapp([string]$name)
{
$PUG = ((Invoke-WebRequest https://"$servername":8000/api/flexapppackage -WebSession $session).Content) | ConvertFrom-Json
[string]$ID=$PUG.Tag.Rows | Where-Object {$_.name -EQ $name} | ForEach-Object {$_.id}
$response = Invoke-WebRequest https://"$servername":8000/api/flexapppackage/"$ID" -Method Delete -WebSession $session
$Message=$response.Content | ConvertFrom-Json
write-host $message.message
}

## Import single Flexapp ##
function Import-Prouflexapp([string]$path)
{
if (!$path)
	{
	Write-host -ForegroundColor red "Missing Source Path" 
    }
else 
    {
        $response = ((Invoke-WebRequest https://"$servername":8000/api/server/flexapppackagexml?path=$path -Method GET -WebSession $session).Content) | ConvertFrom-Json
        $package = $response.Tag
        $response = (Invoke-WebRequest https://"$servername":8000/api/flexapppackage/import -Method Post -ContentType "application/json" -WebSession $session -Body (ConvertTo-Json -depth 10 @($package))) | ConvertFrom-Json
    }   
}

## Import All Flexapps ##
Function Import-ProUFlexappsAll ($sourcedir)
{
if (!$sourcedir)
	{
	Write-host -ForegroundColor red "Missing Source Path dir" 
	}
else 
    {
    
        $list=(Get-ChildItem $sourcedir -Recurse -include *.xml) | foreach-object {$_.FullName}
        foreach ($path in $list)
        {
        $response = ((Invoke-WebRequest https://"$servername":8000/api/server/flexapppackagexml?path=$path -Method GET -WebSession $session).Content) | ConvertFrom-Json
        $package = $response.Tag
        $response = (Invoke-WebRequest https://"$servername":8000/api/flexapppackage/import -Method Post -ContentType "application/json" -WebSession $session -Body (ConvertTo-Json -depth 10 @($package))) | ConvertFrom-Json
        }
    }
}

## Add Flexapp Note ##
function add-proUflexappNote([string]$note)
{
$m = $currentflexapp.History + "`n " + "Note:" + "$note"
$currentflexapp.History = $m
write-host "Use command Save-ProuFlexapp to save note to package" -BackgroundColor yellow -ForegroundColor red
}

## Configuration Functions (api/configuration) ##

## Configuration Functions ##

## Get Configurations ##
function get-ProUconfig
{
$PUG = ((Invoke-WebRequest https://"$servername":8000/api/configuration -WebSession $session).Content) | ConvertFrom-Json
$PUG.Tag.Rows
}

## Load ProfileUnity Configurations ##
function edit-proUconfig([string]$name)
{
$PUG = ((Invoke-WebRequest https://"$servername":8000/api/configuration -WebSession $session).Content) | ConvertFrom-Json
[string]$ID=$PUG.Tag.Rows | Where-Object {$_.name -Match $name} | foreach-object {$_.id}
$configR= ((Invoke-WebRequest https://"$servername":8000/api/configuration/"$ID" -WebSession $session).Content) | ConvertFrom-Json
$config=$configR.tag
$global:CurrentConfig = $config
}

## Save Configuration settings ##
Function Save-ProUConfig{
    $answer=prompt-choice
    if ($answer -eq $False)
    {Write-Host "Save Canceled" -ForegroundColor "red" -BackgroundColor "yellow"}
    else 
    {
    Invoke-WebRequest https://"$servername":8000/api/configuration -ContentType "application/json" -Method Post -WebSession $session -Body($Currentconfig | ConvertTo-Json -Depth 10)
    }
    }


## Delete Configuration ##
function remove-proUConfig([string]$name)
{
$PUG = ((Invoke-WebRequest https://"$servername":8000/api/filter -WebSession $session).Content) | ConvertFrom-Json
[string]$ID=$PUG.Tag.Rows | Where-Object {$_.name -EQ $name} | ForEach-Object {$_.id}
$response = Invoke-WebRequest https://"$servername":8000/api/configuration"$ID"?force=false -Method Delete -WebSession $session
$Message=$response.Content | ConvertFrom-Json
write-host $message.message
}


## Export Single Configuration Json
function export-proUconfig([string]$name, $savepath)
{
if (!$savepath)
	{
	Write-host -ForegroundColor red "Missing Save Path" 
	}
else 
{
#Load Config into memory
$PUG = ((Invoke-WebRequest https://"$servername":8000/api/configuration -WebSession $session).Content) | ConvertFrom-Json
[string]$ID=$PUG.Tag.Rows | Where-Object {$_.name -Match $name} | foreach-object {$_.id}
#Export Config
$ProgressPreference = 'SilentlyContinue'
Invoke-RestMethod -ContentType "application/octet-stream" -Uri https://"$servername":8000/api/configuration/"$ID"/download?encoding=default -WebSession $session -OutFile "$savepath$name.json"
}
}

## Export All Configurations Jsons ##
Function Export-ProUConfigAll ($savepath)
{
if (!$savepath)
	{
	Write-host -ForegroundColor red "Missing Save Path" 
	}
else 
	{
	#get List
	$configlist=get-prouconfigs
	[array]$configlist=$configlist.name
	#export out all
	foreach ($name in $configlist)
		{
		#Load Configs into memory
		$PUG = ((Invoke-WebRequest https://"$servername":8000/api/configuration -WebSession $session).Content) | ConvertFrom-Json
		[string]$ID=$PUG.Tag.Rows | Where-Object {$_.name -Match $name} | foreach-object {$_.id}

		#Export Config
		#Invoke-WebRequest https://"$servername":8000/api/configuration/"$ID" -WebSession $session -OutFile "$savepath$name.json" -PassThru
		$ProgressPreference = 'SilentlyContinue'
		Invoke-RestMethod -ContentType "application/octet-stream" -Uri https://"$servername":8000/api/configuration/"$ID"/download?encoding=default -WebSession $session -OutFile "$savepath$name.json"
		}
	}
}

## Import Configuration Json ##

## Import Single Configuration Json
Function Import-ProuConfig{

#Import Json
$jsonfile=Get-FileName
$jsonimport=Get-Content $jsonFile | ConvertFrom-Json

#Change Name and ID
$connectionString = $jsonimport | select-object -expand configurations
$connectionString.name = $jsonimport.Configurations.name + " - Imported"
$connectionString.ID = $Null


#Save Json
Invoke-WebRequest https://"$servername":8000/api/configuration -ContentType "application/json" -Method Post -WebSession $session -Body($jsonimport.configurations | ConvertTo-Json -Depth 10)

}


## Import All Configuration Jsons ##
Function Import-ProuConfigAll ($sourcedir)
{
if (!$sourcedir)
	{
	Write-host -ForegroundColor red "Missing Source Path dir" 
	}
else 
	{
	
	$lists=Get-ChildItem $sourcedir
	$lists=$lists.VersionInfo.filename
	foreach ($json in $lists) 

		{

		#Import Json
		$jsonfile=$json
		$jsonimport = Get-Content $jsonFile | ConvertFrom-Json
		
		#Change Name and ID
		$connectionString = $jsonimport | Select-Object -expand configurations
		$connectionString.name = $jsonimport.Configurations.name + " - Imported"
		$connectionString.ID = $Null
	
		
		#Save Json
		Invoke-WebRequest https://"$servername":8000/api/configuration -ContentType "application/json" -Method Post -WebSession $session -Body($jsonimport.configurations | ConvertTo-Json -Depth 10)

		}
}
}

## Deploy Configuration ##
Function Deploy-ProUConfig([string]$name)
{
$answer=prompt-choice
if ($answer -eq $False)
{Write-Host "Save Canceled" -ForegroundColor "red" -BackgroundColor "yellow"}
else 
{
    $PUG = ((Invoke-WebRequest https://"$servername":8000/api/configuration -WebSession $session).Content) | ConvertFrom-Json
    [string]$ID=$PUG.Tag.Rows | Where-Object {$_.name -Match $name} | ForEach-Object {$_.id}
    $URL="https://'$servername':8000/api/configuration/'$Id'/script?encoding=ascii&deploy=true"
    $URL=$URL -replace "'", ""
    Invoke-WebRequest "$URL" -WebSession $session
}
}

## Configuration Edit functions (api/configuration), When using edit-proUconfig##

## Add-Flexapp to ProUConfig ##

function Add-proUFlexAppDia([string]$DIAname, [string]$filtername){

    $dianame1 = get-ProUFlexapps | Where-Object {$_.Name -eq "$DIAname"}
    $filterID1 = get-ProUFilters | Where-Object {$_.Name -eq "$filtername"}
    $filterID = $filterID1.id
    
    $DIAPackage = @{
    DifferencingPath="%systemdrive%\FADIA-T\VHDW\%username%"
    UseJit="False"
    CacheLocal="False"
    PredictiveBlockCaching="False"
    FlexAppPackageId=$DIAname1.id
    FlexAppPackageUuid=$DIAName1.uuid
    Sequence = "0"
    }
    
    $global:moduleItem = @{
    FlexAppPackages=@($DIAPackage);
    Playback = "0"
    ReversePlay = "False"
    FilterId = "$filterID"
    Description="DIA package added with PowerTools"
    Disabled = "False"
    }
    
    $currentconfig.FlexAppDias += @($moduleItem)
    
    }
    
    #########################