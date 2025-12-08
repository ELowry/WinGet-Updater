<#
.SYNOPSIS
	Uninstall Winget Updater
	Copyright 2025 Eric Lowry
	Licensed under the MIT License.
#>

[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
param()

$AppName = "Winget Updater"
$InstallDir = "$env:LOCALAPPDATA\WingetUpdater"
$StartMenuLink = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$AppName.lnk"
$StartMenuFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$AppName"
$TaskName = "Winget Updater"
$RegistryKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WingetUpdater"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
	# Try to use Windows Terminal if available
	if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
		Start-Process wt.exe -ArgumentList "-w new powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
	}
	else {
		Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
	}
	exit
}

Write-Host "Uninstalling $AppName..." -ForegroundColor Cyan

if (Test-Path $RegistryKey) {
	Remove-Item -Path $RegistryKey -Recurse -Force -ErrorAction SilentlyContinue
	Write-Host " -> Registry cleaned." -ForegroundColor Green
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Write-Host " -> Scheduled task removed." -ForegroundColor Green

if (Test-Path $StartMenuLink) {
	Remove-Item -Path $StartMenuLink -Force -ErrorAction SilentlyContinue
}
if (Test-Path $StartMenuFolder) {
	Remove-Item -Path $StartMenuFolder -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host " -> Shortcuts removed." -ForegroundColor Green

Write-Host " -> Removing application files..." -ForegroundColor Yellow
Write-Host "`nUninstallation complete. Goodbye!" -ForegroundColor Green
Start-Sleep -Seconds 2

Start-Process -FilePath "cmd.exe" -ArgumentList "/c timeout /t 3 /nobreak > NUL & rmdir /s /q `"$InstallDir`"" -WindowStyle Hidden

exit