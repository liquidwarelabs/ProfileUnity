# ProfileUnity-Share-Creation

Description <br>

Bat Script to create fileshares and sets ACLS for profileUnity<br>


How to Use<br>
Run Script as admin




Code<br>
````
mkdir c:\UserShare
net share UserShare="C:\UserShare" /GRANT:"authenticated users",FULL /Grant:"Domain admins",Full /Grant:"authenticated users",Full
Icacls c:\UserShare /inheritance:r /grant:r "Domain Users":(S,RD,AD) /grant:r "Domain Admins":(OI)(CI)(F) /grant:r "creator owner":(OI)(CI)(IO)(F) /grant:r "authenticated users":(S,RD,AD) /grant:r "system":(OI)(CI)(F)

mkdir c:\ProfileUnity
mkdir c:\ProfileUnity\ClientTools
mkdir c:\ProfileUnity\User
mkdir c:\ProfileUnity\Machine
mkdir c:\ProfileUnity\FlexApps
net share profileUnity="C:\ProfileUnity" /GRANT:"authenticated users",read /Grant:"Domain admins",Full /Grant:"Domain Users",read
Icacls c:\ProfileUnity /inheritance:r /grant:r "Domain Users":(OI)(CI)(RX) /grant:r "Domain Admins":(OI)(CI)(F) /grant:r "authenticated users":(OI)(CI)(RX) /grant:r "system":(OI)(CI)(F)

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

````



| OS Version  | Verified |
| ------------- | ------------- |
|Windows 10 | YES |
|Windows Server 2012 | YES |
|Windows Server 2012 R2 | YES |
|Windows Server 2008 R2 | YES |
|Windows Server 2008 | YES |
|Windows Server 2003 | YES |
|Windows 8 | YES |
|Windows 7 | YES |
|Windows Vista | YES |
|Windows XP | N0 |
|Windows 2000 | No |
