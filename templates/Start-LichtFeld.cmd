@echo off
setlocal
cd /d "%~dp0"
"%~dp0bin\LichtFeld-Studio.exe" %*
if errorlevel 1 (
  echo LichtFeld Studio is gestopt met een fout. Gebruik Controleer-computer.cmd.
  pause
)
