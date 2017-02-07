REM Adjust variables for needed folder paths
SET usershare=c:\UserShare
SET profileunity=c:\profileUnity

mkdir "%usershare%"
net share UserShare="%usershare%" /GRANT:"authenticated users",FULL /Grant:"Domain admins",Full /Grant:"authenticated users",Full
Icacls "%usershare%" /inheritance:r /grant:r "Domain Users":(S,RD,AD) /grant:r "Domain Admins":(OI)(CI)(F) /grant:r "creator owner":(OI)(CI)(IO)(F) /grant:r "authenticated users":(S,RD,AD) /grant:r "system":(OI)(CI)(F)

mkdir "%profileunity%"
mkdir "%profileunity%\ClientTools"
mkdir "%profileunity%\User"
mkdir "%profileunity%\Machine"
mkdir "%profileunity%\FlexApps"
net share profileUnity="%profileunity%" /GRANT:"authenticated users",read /Grant:"Domain admins",Full /Grant:"Domain Users",read
Icacls "%profileunity%" /inheritance:r /grant:r "Domain Users":(OI)(CI)(RX) /grant:r "Domain Admins":(OI)(CI)(F) /grant:r "authenticated users":(OI)(CI)(RX) /grant:r "system":(OI)(CI)(F)

Echo off
Echo ---GPO startup path--- >> %userprofile%\desktop\ProfileUnityPaths.txt
Echo \\%computername%\profileunity\clienttools\LwL.ProfileUnity.Client.Startup.exe >> %userprofile%\desktop\ProfileUnityPaths.txt

Echo off
Echo ---GPO logoff path--- >> %userprofile%\desktop\ProfileUnityPaths.txt
Echo \\%computername%\profileunity\clienttools\LwL.ProfileUnity.Client.Logoff.exe >> %userprofile%\desktop\ProfileUnityPaths.txt

Echo off
Echo ---GPO User INI path--- >> %userprofile%\desktop\ProfileUnityPaths.txt
Echo \\%computername%\profileunity\Running\ >> %userprofile%\desktop\ProfileUnityPaths.txt

Echo off

Echo ---GPO Computer INI path--- >> %userprofile%\desktop\ProfileUnityPaths.txt
Echo \\%computername%\profileunity\startup\ >> %userprofile%\desktop\ProfileUnityPaths.txt

Echo off
ECho ---User share--- >> %userprofile%\desktop\ProfileUnityPaths.txt
Echo "\\%computername%\UserShare\%username%" >> %userprofile%\desktop\ProfileUnityPaths.txt

Echo off
Echo ---Profile Disk Share--- >> %userprofile%\desktop\ProfileUnityPaths.txt
Echo "\\%computername%\UserShare\%username%\VHD-ProfileDisk\%username%.vhd" >> %userprofile%\desktop\ProfileUnityPaths.txt

exit
