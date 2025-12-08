:: Winget Updater Launcher
:: Copyright (c) 2025 Eric Lowry
:: Licensed under the MIT License.
:: https://opensource.org/licenses/MIT

@echo off
cd /d "%~dp0"

where wt >nul 2>&1
if %errorlevel% equ 0 (
	start "" wt -w new powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0winget-updater.ps1" %*
) else (
	start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0winget-updater.ps1" %*
)
exit
