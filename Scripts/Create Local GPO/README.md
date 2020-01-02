# Create Local ProfileUnity GPO

Description <br>
Automatically creates Local GPO for ProfileUnity<br>

Attached in this repository is:<br>
LocalGPO.Zip [LocalGPO.zip][localgpozip]<br>

In the Zip Archive is:<br>

````
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
````

How to Use<br>
Edit the Items in "EditMe"<br>
ProUsettings.txt<br>

Edit "EDITME" items in ProUsettings.txt
````
User
SOFTWARE\Liquidware Labs\ProfileUnity
INIPath
SZ:\\\\EDITME\\profileunity\\user
````

Edit "EDITME" items in "LocalInstallProU.bat"
````
xcopy /s \\EDITME\LocalGPO\* %temp%\LocalGPO\
REM Optional Install of ProfileUnity client
REM %systemroot%\system32\cmd.exe /c \\EDITME\profileunity\clienttools\LwL.ProfileUnity.Client.Startup.exe
````

Once Edited Run "LocalInstallProU.bat" as administrator on the local machine. This will copy the directory into the local "temp" folder and run from there.<br>

Side notes:<br>
If you don't see the logoff script on your configuration, Edit the version number to a higher number. Then rerun the script:<br>
````
ADM
	GPT.ini
	
	Version=300000
````


[localgpozip]: https://github.com/liquidwarelabs/ProfileUnity/blob/master/Scripts/Create%20Local%20GPO/LocalGPO.zip



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
