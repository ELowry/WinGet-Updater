<#
.SYNOPSIS
	Uninstall Winget Updater
	Copyright 2025 Eric Lowry
	Licensed under the MIT License.

.DESCRIPTION
	Removes Winget Updater installation files, scheduled tasks, registry entries, and Start Menu shortcuts.

.PARAMETER Forced
	Overrides any active instance lock file and proceeds with uninstallation.

.PARAMETER TargetLocalAppData
	The target LocalAppData path where application files are located. Defaults to $env:LOCALAPPDATA.

.PARAMETER TargetAppData
	The target AppData path where Start Menu shortcuts are located. Defaults to $env:APPDATA.
#>

[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
param(
	[switch]$Forced,
	[string]$TargetLocalAppData = $env:LOCALAPPDATA,
	[string]$TargetAppData = $env:APPDATA
)

$AppName = "Winget Updater"
$InstallDir = "$TargetLocalAppData\WingetUpdater"
$StartMenuLink = "$TargetAppData\Microsoft\Windows\Start Menu\Programs\$AppName.lnk"
$StartMenuFolder = "$TargetAppData\Microsoft\Windows\Start Menu\Programs\$AppName"
$TaskName = "Winget Updater"
$RegistryKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WingetUpdater"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
	$argsList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -TargetLocalAppData `"$TargetLocalAppData`" -TargetAppData `"$TargetAppData`""
	if ($Forced) { $argsList += " -Forced" }

	if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
		Start-Process wt.exe -ArgumentList "-w new powershell.exe $argsList" -Verb RunAs
	}
	else {
		Start-Process powershell.exe -ArgumentList $argsList -Verb RunAs
	}
	exit
}

$LockFile = Join-Path $InstallDir "winget-updater.lock"
if (Test-Path $LockFile) {
	if (-not $Forced) {
		Write-Host "Error: Winget Updater appears to be running." -ForegroundColor Red
		Write-Host "Please close it before uninstalling, or run with -Forced." -ForegroundColor Yellow
		exit 1
	}
	else {
		Write-Host "Overriding lock file as requested." -ForegroundColor Gray
		Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
	}
}

Write-Host "Uninstalling $AppName..." -ForegroundColor Cyan

# Remove uninstall registry entry
if (Test-Path $RegistryKey) {
	Remove-Item -Path $RegistryKey -Recurse -Force -ErrorAction SilentlyContinue
	Write-Host " -> Uninstall registry cleaned." -ForegroundColor Green
}

# Remove configuration registry
$ConfigKey = "HKCU:\Software\EricLowry\WingetUpdater"
if (Test-Path $ConfigKey) {
	Remove-Item -Path $ConfigKey -Recurse -Force -ErrorAction SilentlyContinue
	Write-Host " -> Configuration registry cleaned." -ForegroundColor Green
}

# Remove parent key if empty
$ParentKey = "HKCU:\Software\EricLowry"
if (Test-Path $ParentKey) {
	$children = Get-ChildItem -Path $ParentKey -ErrorAction SilentlyContinue
	if ($null -eq $children -or $children.Count -eq 0) {
		Remove-Item -Path $ParentKey -Force -ErrorAction SilentlyContinue
		Write-Host " -> Parent registry key cleaned." -ForegroundColor Green
	}
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