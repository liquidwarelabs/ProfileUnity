***************************************************************************
@echo off
cls

for /f "tokens=*" %%G in ('dir /b /s /a:d "%localappdata%\Mozilla\Firefox\Profiles\*.default"') Do (
echo %%G
rmdir /s /q %%G\Cache
rmdir /s /q %%G\cache2
)
***************************************************************************