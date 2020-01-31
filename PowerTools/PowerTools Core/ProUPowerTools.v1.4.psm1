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
		Notes: v1.2 Fixed Save Functions
			   v1.4 Fixed Config export and import functions	
 
#> 

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

## Get Functions ##

## Get Configurations
function get-ProUconfigs
{
$PUGC = ((Invoke-WebRequest https://"$servername":8000/api/configuration -WebSession $session).Content) | ConvertFrom-Json
$PUGC.Tag.Rows
}

## Get Filters
function get-ProUFilters
{
$PUGF = ((Invoke-WebRequest https://"$servername":8000/api/filter -WebSession $session).Content) | ConvertFrom-Json
$PUGF.Tag.Rows
}

## Get FlexApps
function get-ProUFlexapps
{
$PUFA = ((Invoke-WebRequest https://"$servername":8000/api/flexapppackage/vhd? -WebSession $session).Content) | ConvertFrom-Json
$PUFA.TAG.ROWS
}

## Get Portability Rules
function get-ProUPortRules
{
$PUFP = ((Invoke-WebRequest https://"$servername":8000/api/portability -WebSession $session).Content) | ConvertFrom-Json
$PUFP.TAG.ROWS
}



## Load Functions ##

## Load ProfileUnity Configurations
function load-proUconfig([string]$name)
{
$PUGC = ((Invoke-WebRequest https://"$servername":8000/api/configuration -WebSession $session).Content) | ConvertFrom-Json
[string]$configID=$PUGC.Tag.Rows | Where-Object {$_.name -Match $name} | foreach-object {$_.id}
$configR= ((Invoke-WebRequest https://"$servername":8000/api/configuration/"$configID" -WebSession $session).Content) | ConvertFrom-Json
$config=$configR.tag
$global:CurrentConfig = $config
}


## Load Portability Rule Set
function load-proUPortRule([string]$name)
{
$PUGP = ((Invoke-WebRequest https://"$servername":8000/api/portability -WebSession $session).Content) | ConvertFrom-Json
[string]$configID=$PUGP.Tag.Rows | Where-Object {$_.name -Match $name} | foreach-object {$_.id}
$configR= ((Invoke-WebRequest https://"$servername":8000/api/portability/"$configID" -WebSession $session).Content) | ConvertFrom-Json
$config=$configR.tag
$global:CurrentPortRule = $config
}


## Load ProfileUnity Filter
function load-proUfilter([string]$name)
{
$PUGF = ((Invoke-WebRequest https://"$servername":8000/api/filter -WebSession $session).Content) | ConvertFrom-Json
[string]$configID=$PUGF.Tag.Rows | Where-Object {$_.name -EQ $name} | foreach-object {$_.id}
$configR= ((Invoke-WebRequest https://"$servername":8000/api/filter/"$configID" -WebSession $session).Content) | ConvertFrom-Json
$config=$configR.tag
$global:Currentfilter = $config
}


## Save Functions ##

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

##Save Configuration settings##
Function Save-ProUConfig{
$answer=prompt-choice
if ($answer -eq $False)
{Write-Host "Save Canceled" -ForegroundColor "red" -BackgroundColor "yellow"}
else 
{
Invoke-WebRequest https://"$servername":8000/api/configuration -ContentType "application/json" -Method Post -WebSession $session -Body($Currentconfig | ConvertTo-Json -Depth 10)
}
}

##Save Portability Rule settings##
Function Save-ProUPortRule{
$answer=prompt-choice
if ($answer -eq $False)
{Write-Host "Save Canceled" -ForegroundColor "red" -BackgroundColor "yellow"}
else 
{
Invoke-WebRequest https://"$servername":8000/api/portability -ContentType "application/json" -Method Post -WebSession $session -Body($CurrentPortRule | ConvertTo-Json -Depth 10)
}
}

##Save Filter settings##
Function Save-ProUFilter{
$answer=prompt-choice
if ($answer -eq $False)
{Write-Host "Save Canceled" -ForegroundColor "red" -BackgroundColor "yellow"}
else 
{
Invoke-WebRequest https://"$servername":8000/api/filter -ContentType "application/json" -Method Post -WebSession $session -Body($Currentfilter | ConvertTo-Json -Depth 10)
}
}


## Export Configuration Json ##

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
$PUGC = ((Invoke-WebRequest https://"$servername":8000/api/configuration -WebSession $session).Content) | ConvertFrom-Json
[string]$configID=$PUGC.Tag.Rows | Where-Object {$_.name -Match $name} | foreach-object {$_.id}
#Export Config
$ProgressPreference = 'SilentlyContinue'
Invoke-RestMethod -ContentType "application/octet-stream" -Uri https://"$servername":8000/api/configuration/"$configID"/download?encoding=default -WebSession $session -OutFile "$savepath$name.json"
}
}

## Export All Configurations Jsons
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
		$PUGC = ((Invoke-WebRequest https://"$servername":8000/api/configuration -WebSession $session).Content) | ConvertFrom-Json
		[string]$configID=$PUGC.Tag.Rows | Where-Object {$_.name -Match $name} | foreach-object {$_.id}

		#Export Config
		#Invoke-WebRequest https://"$servername":8000/api/configuration/"$configID" -WebSession $session -OutFile "$savepath$name.json" -PassThru
		$ProgressPreference = 'SilentlyContinue'
		Invoke-RestMethod -ContentType "application/octet-stream" -Uri https://"$servername":8000/api/configuration/"$configID"/download?encoding=default -WebSession $session -OutFile "$savepath$name.json"
		}
	}
}

## Import Configuration Json ##

## Import Single Configuration Json
Function Import-ProuConfig{

#get file path
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

#Get ProU Redirtection #
function get-ProUredirection {
	$PUGinvred = ((Invoke-WebRequest https://"$servername":8000/api/collector/redirection -WebSession $session).Content) | ConvertFrom-Json
	$PUGinvred.Tag.rows
	}

## Import All Configuration Jsons
Function Import-ProuConfigAll ($source)
{
if (!$source)
	{
	Write-host -ForegroundColor red "Missing Source Path" 
	}
else 
	{
	
	$lists=Get-ChildItem $source
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

## End Of Code, Have a Wonderful Day ##










