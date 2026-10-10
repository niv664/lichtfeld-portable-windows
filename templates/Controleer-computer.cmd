@echo off
setlocal
powershell.exe -NoProfile -File "%~dp0scripts\Test-TargetComputer.ps1" -PackageRoot "%~dp0."
pause
