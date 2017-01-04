::Script Name = BootEnvVar.bat
::Script Last Modified: 10/20/2016
::Script Last Modified by: chris.walker@liquidwarelabs.com
::Support: None - Best Effort
::Script Use Case:
::   ProfileUnity Portability, Folder Redirection and other modules can use environment variables for many functions. This script provides
::   		an example on how to create an environment variable at boot time based on part of the machine name. This environment variable can then be used by 
::      any of the ProfileUnity modules to change the behavior of the rule based on parts of the machine name.
::   One of the reasons you would want to do this is to simplify and reduce the number of rules needed to be created in the Portability or Folder Redirection 
::      modules. 

::      Example: ATL - HQ
::        Machine Name Examples: ATL010-vm1, ATL010-vm2
::        Machine Names All Start with ATL010
::        - Output would be: "ATL010"
::
::Script Function:
::   1. Determine Data Center Location - (USA or UK)
::      - Determined by looking for "UK" in machine Name
::      - ***This can be modified for your needs***
::      - Used to set UNC Base Mapping
::   2. Get environment variable "computername"
::   3. Return all characters from computer name up to first instance of "-"
::      - ***This can be modified for your needs***
::   4. Create New Environment Variables to be used by ProfileUnity
::
::Script Notes:
::	1. This script is not supported by Liquidware Labs.
::      Reason: You can modify scripts to do an infinite number of things. Liquidware Labs cannot support this.
::  2. This script should only be used in environments where the computer name is controllable and predictable.
::
::Revision Notes:
::  ID        Date        Notes
::  cwalker   10/20/2016  First release to general public after testing with MSP client


:: Notes:
::   1. Good Web Site for Batch File String Manipulation
::      http://www.dostips.com/DtTipsStringManipulation.php
::   2. Return Characters of an Environment Variable - Based on Start and Length
::      %VariableName:~Offset,Length%
::   3. Return Characters of an Environment Variable - Based on a Token
::      for /f "tokens=1 delims=- " %%a in ("%computername%") do SET ComputerCommonName_s=%%a
::         *** In the example above the "Token" is the "-"
::

:: -------- Start BootEnvVar.bat--------

::------ Define Script Variables - Start --------
:: UNC Base Path to Store User Profile Information
:: Note: User must have access to directory
:: Note: A hidden directory is recommended - Use "$" at the end of the share name
:: Profile Storage Location Definition
:: US Data Center - Profile Storage Path
SET USA_Path_s=\\MyDomain.com\Server\ShareName$\
:: UK Data Center - Profile Storage Path
SET UK_Path_s=\\MyDomain.com\UKServer\ShareName$\
::------ Define Script Variables - End ----------

::  Default Base Path is US Data Center 
SET UNC_Base_Path_s=%USA_Path_s%

:: If UK Machine - Change UNC_Base_Path_s - If Not then SkipUK 
::    - (Checks Environment Variable COMPUTERNAME contains "UK")
IF x%COMPUTERNAME:UK=%==x%COMPUTERNAME% GOTO SkipUK
:: Set Base Path for UK Machine - Since ATL was not found in ComputerName Variable
SET UNC_Base_Path_s=%UK_Path_s%
:SkipUK


:: Get %COMPUTERNAME% Environment Variable and split it to get Common Name (Common Name is Before First "-")
for /f "tokens=1 delims=- " %%a in ("%computername%") do SET ComputerCommonName_s=%%a

:: Set Environment Variables for ProfileUnity
:: SETX for Permanent Environment Variable 
::    - /M option is for HKLM - Since this is ran at boot time
:: In this example a new environment variable will be created called "MachineNameMap"
SETX MachineNameMap "%UNC_Base_Path_s%%ComputerCommonName_s%" /M

:: No Need to Clean up SET Variables - They go away after exit of CMD Shell

:: Exit Shell
exit

:: Script Processing - End
:: -------- end BootEnvVar.bat--------