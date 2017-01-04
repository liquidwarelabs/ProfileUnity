***Description :*** <br>

 - ProfileUnity Portability, Folder Redirection and other modules can use environment variables for many functions. 
 - This script provides an example on how to create an environment variable at boot time based on part of the machine name. This environment variable can then be used by any of the ProfileUnity modules to change the behavior of the rule based on parts of the machine name.
 - One of the reasons you would want to do this is to simplify and reduce the number of rules needed to be created in the Portability or Folder Redirection modules. 

Example: ATL - HQ<br>
* Machine Name Examples: ATL010-vm1, ATL010-vm2…ATL010-vm250<br>
* Machine Names All Start with ATL010<br>
* Output would be: "ATL010"<br>

Script Function:<br>

1. Determine Data Center Location - (USA or UK)<br>
	- Determined by looking for "UK" in machine Name<br>
	- ***This can be modified for your needs***<br>
	- Used to set UNC Base Mapping<br>
2. Get environment variable "COMPUTERNAME"<br>
3. Return all characters from computer name up to first instance of "-" <br>
 	- * ***This can be modified for your needs***<br>
4. Create New Environment Variables to be used by ProfileUnity<br>

***Script Notes:***<br>

1. This script is not supported by Liquidware Labs.
	- Reason: You can modify scripts to do an infinite number of things. Liquidware Labs cannot support this.<br>
2. This script should only be used in environments where the computer name is controllable and predictable.<br>

Example of Usage<br>
https://github.com/MrSmithLWL/ProfileUnity-Boot-Enviroment-Variables/blob/master/Script%20Deployment.pdf

This script has been tested on: <br>
***2012R2 in “Published Desktop” , DO NOT USE on a Multi-User OS!!!*** <BR>

| OS Version  | Verified |
| ------------- | ------------- |
|Windows 10 | Yes |
|Windows Server 2012 | No |
|Windows Server 2012 R2 | Yes |
|Windows Server 2008 R2 | No |
|Windows Server 2008 | No |
|Windows Server 2003 | No |
|Windows 8 | No |
|Windows 7 | Yes |
|Windows Vista | No |
|Windows XP | No |
|Windows 2000 | No |

| ID | Date | Notes |
| ------------- | ------------- | ------------- |
| cwalker | 10/20/2016 | First release to general public |
