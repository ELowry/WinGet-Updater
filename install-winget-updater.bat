:: Winget Updater Installation/Update Script
:: Copyright (c) 2025 Eric Lowry
:: Licensed under the MIT License.
:: https://opensource.org/licenses/MIT

@echo off
net session >nul 2>&1
if %errorLevel% == 0 (
	echo Administrative rights confirmed.
) else (
	echo Requesting administrative privileges...
	powershell -Command "Start-Process '%~f0' -Verb RunAs"
	exit /b
)

cd /d "%~dp0"

echo Launching configuration tool...

where wt >nul 2>&1
if %errorlevel% equ 0 (
	start "" wt -w new powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0winget-updater-core\configure.ps1"
) else (
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0winget-updater-core\configure.ps1"
)
