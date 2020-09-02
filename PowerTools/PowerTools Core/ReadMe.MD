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
Import-module .\ProUPowerTools.v1.4.psm1
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



| OS Version  | Verified |
| ------------- | ------------- |
|Windows 2019 | Yes |
|Windows 10 | Yes |
|Windows Server 2012 | No |
|Windows Server 2012 R2 | Yes |
|Windows 8 | No |
|Windows 7 | Yes |