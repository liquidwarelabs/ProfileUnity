# Create Local ProfileUnity GPO

Description <br>
Automatically creates Local GPO for ProfileUnity<br>

Attached in this repository is:<br>
LocalGPO.Zip [LocalGPO.zip][localgpozip]<br>

In the Zip Archive is:<br>

''''
ADM
	GPT.ini
	ProfileUnity.adm
EditME
	ProUsettings.txt
	scripts.ini
Items
	AddLocalGPO.bat
	LGPO.exe
LocalInstallProU.bat
''''

How to Use<br>
Edit the Items in "EditMe"<br>
ProUsettings.txt and scripts.ini<br>

Edit "EDITME" items in ProUsettings.txt
''''
User
SOFTWARE\Liquidware Labs\ProfileUnity
INIPath
SZ:\\\\EDITME\\profileunity\\user
''''

Edit "EDITME" items in Scripts.ini
''''
[Logoff]
0CmdLine=\\EDITME\profileUnity\ClientTools\LwL.ProfileUnity.Client.Logoff.exe
''''

Edit "EDITME" items in "LocalInstallProU.bat"
''''
xcopy /s \\EDITME\LocalGPO\* %temp%\LocalGPO\
REM Optional Install of ProfileUnity client
REM %systemroot%\system32\cmd.exe /c \\EDITME\profileunity\clienttools\LwL.ProfileUnity.Client.Startup.exe
''''

[localgpozip]: https://github.com/liquidwarelabs/Profileunity/raw/master/



| OS Version  | Verified |
| ------------- | ------------- |
|Windows 10 | NO |
|Windows Server 2012 | NO |
|Windows Server 2012 R2 | NO |
|Windows Server 2008 R2 | NO |
|Windows Server 2008 | NO |
|Windows Server 2003 | No |
|Windows 8 | NO |
|Windows 7 | YES |
|Windows Vista | No |
|Windows XP | No |
|Windows 2000 | No |
