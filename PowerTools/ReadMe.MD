## ProfileUnity PowerTools <br>

**Description** <br>
This Is a powershell module that can be used to create change and save items with in the ProfileUnity Web Console.<br>

**How to Use** <br>

**Prerequisites** <br>
This was built on the latest version of PowerShell.<br>
https://www.microsoft.com/en-us/download/details.aspx?id=50395

To load 
- **copy the PSM1 down into a folder.**
- **In PowerShell type**:
````
Import-module .\ProUPowerTools.v1.psm1
````
- **If you get an Execution Policy error.**
````
Set-ExecutionPolicy -ExecutionPolicy Unrestricted
````
This is really basic, no editing stuff just yet just doing a quick trial run on it.

**Please be careful, with this as you could break your stuff if you aren’t careful mainly in the import/Export json stuff, thought it should be ok.**


Things you can do in V1:
````
connect-ProfileUnityServer
Type in command and follow the prompts

get-ProUconfigs
Type in command get responce

get-ProUFilters
Type in command get responce

get-ProUFlexapps
Type in command get responce

get-ProUPortRules
Type in command get responce

load-proUconfig([string]$name)
Example: load-proUconfig -name "configuration name"
$Currentconfig

load-proUPortRule([string]$name)
Example: load-proUPortRule -name "Port Rule Name"
$CurrentPortRule

load-proUfilter([string]$name)
Example: load-proUfilter -name "Filter Name"
$Currentfilter

Save-ProUConfig
Type in command get responce

Save-ProUPortRule
Type in command get responce

Save-ProUFilter
Type in command get responce

export-proUconfig([string]$name, $savepath)
Example: export-proUconfig -name "configuration name" -savepath "c:\Path\"
The backslash at the end of the path is important

Export-ProUConfigAll ($savepath)
Example: Export-ProUConfigAll -savepath "c:\Path\"
The backslash at the end of the path is important

Import-ProuConfig
Type in command and follow the prompts

Import-ProuConfigAll ($source)
Example: Import-ProuConfigAll -source "c:\Path\"
The backslash at the end of the path is important
````


Future Build Information<br>
````
V2:
Load Filters from CSV
Load Printers from CSV (updated)
Set-ProUPortabiltysetting (sets all option settings)
Set-ProUFolderRedirection (sets all option settings)
Set-ProUFilterValue (sets/Adds condition values)
Replace-ProUPortSettings (find/Replace function)
Replace-ProUFolderRedirection (find/Replace function)
Replace-ProUFilter (find/Replace function)
````
````
V3:
(Experimental Stuff)
Import GPP Regkeys
Import GPP Folder redirect
Import GPP shortcuts
Import POL into regkey module
Import Groups from AD OU to create proU Filters
Import Printer List from print server to create ProU Filters
````





| OS Version  | Verified |
| ------------- | ------------- |
|Windows 10 | No |
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
