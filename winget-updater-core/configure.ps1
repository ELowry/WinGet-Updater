<#
.SYNOPSIS
	Installer and Configurator for Winget Updater
	Copyright 2025 Eric Lowry
	Licensed under the MIT License.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
param(
	[switch]$Unattended,
	[switch]$EnableStartup,
	[switch]$EnableWake
)

try {
	$AppName = "Winget Updater"
	$AppVersion = "1.1.3"
	$InstallDir = "$env:LOCALAPPDATA\WingetUpdater"
	$SourceDir = $PSScriptRoot

	Write-Host "Winget Updater Setup (v$AppVersion)" -ForegroundColor Cyan
	Write-Host "--------------------" -ForegroundColor DarkGray

	Write-Host "Installing application..." -ForegroundColor Yellow

	if (-not (Test-Path $InstallDir)) {
		New-Item -Path $InstallDir -ItemType Directory | Out-Null
	}

	if (Test-Path $InstallDir) {
		Get-ChildItem -Path $InstallDir | Where-Object {
			$_.Name -ne "winget-updater-data.json" -and
			$_.Name -ne "winget-updater-log.txt"
		} | Remove-Item -Recurse -Force
	}

	Copy-Item -Path "$SourceDir\winget-updater.ps1" -Destination $InstallDir -Force
	Copy-Item -Path "$SourceDir\uninstall.ps1" -Destination $InstallDir -Force
	Copy-Item -Path "$SourceDir\launcher.bat" -Destination $InstallDir -Force

	Write-Host "Setting up shortcuts..." -ForegroundColor Yellow
	$StartMenuPrograms = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
	$LinkPath = "$StartMenuPrograms\$AppName.lnk"

	$WshShell = New-Object -comObject WScript.Shell

	$Shortcut = $WshShell.CreateShortcut($LinkPath)
	$Shortcut.TargetPath = "cmd.exe"
	$Shortcut.Arguments = "/c start `"`" /min `"$InstallDir\launcher.bat`" -Forced"
	$Shortcut.IconLocation = "shell32.dll,238"
	$Shortcut.Save()

	# Register in "Add/Remove Programs" (ARP)
	$UninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WingetUpdater"
	if (-not (Test-Path $UninstallKey)) {
		New-Item -Path $UninstallKey -Force | Out-Null
	}

	$ArpValues = @{
		"DisplayName"     = $AppName
		"DisplayVersion"  = $AppVersion
		"Publisher"       = "Winget Updater"
		"UninstallString" = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\uninstall.ps1`""
		"DisplayIcon"     = "shell32.dll,238"
		"InstallLocation" = $InstallDir
		"NoModify"        = 1
		"NoRepair"        = 1
	}

	foreach ($Key in $ArpValues.Keys) {
		New-ItemProperty -Path $UninstallKey -Name $Key -Value $ArpValues[$Key] -PropertyType String -Force | Out-Null
	}
	Write-Host " -> Registered uninstaller." -ForegroundColor Green
	Write-Host " -> Shortcuts updated." -ForegroundColor Green

	Write-Host "Automation Settings" -ForegroundColor Cyan

	if ($Unattended) {
		$RunStartup = if ($EnableStartup) { "y" } else { "n" }
	}
	else {
		$RunStartup = Read-Host "Run at system startup? (Y/n)"
	}
	if ([string]::IsNullOrWhiteSpace($RunStartup)) {
		$RunStartup = "y"
	}

	if ($Unattended) {
		$RunWake = if ($EnableWake) { "y" } else { "n" }
	}
	else {
		$RunWake = Read-Host "Run on system wake/unlock? (y/N)"
	}
	if ([string]::IsNullOrWhiteSpace($RunWake)) {
		$RunWake = "n"
	}

	$TaskName = "Winget Updater"
	Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

	$Values_Triggers = ""

	if ($RunStartup -eq "y") {
		$Values_Triggers += @"
		<LogonTrigger>
		<Enabled>true</Enabled>
		</LogonTrigger>
"@
	}

	if ($RunWake -eq "y") {
		$Values_Triggers += @"
		<SessionStateChangeTrigger>
		<Enabled>true</Enabled>
		<StateChange>SessionUnlock</StateChange>
		</SessionStateChangeTrigger>
"@
	}

	$SafeInstallDir = $InstallDir.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("`"", "&quot;")
	$ArgString = "/c start /min &quot;&quot; &quot;$SafeInstallDir\launcher.bat&quot; -Minimal"
	$User = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

	$TaskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
<RegistrationInfo>
	<Description>Runs Winget Updater interactively.</Description>
	<URI>\$TaskName</URI>
</RegistrationInfo>
<Triggers>
$Values_Triggers
</Triggers>
<Principals>
	<Principal id="Author">
	<UserId>$User</UserId>
	<LogonType>InteractiveToken</LogonType>
	<RunLevel>HighestAvailable</RunLevel>
	</Principal>
</Principals>
<Settings>
	<MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
	<DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
	<StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
	<AllowHardTerminate>true</AllowHardTerminate>
	<StartWhenAvailable>false</StartWhenAvailable>
	<RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
	<IdleSettings>
	<StopOnIdleEnd>true</StopOnIdleEnd>
	<RestartOnIdle>false</RestartOnIdle>
	</IdleSettings>
	<AllowStartOnDemand>true</AllowStartOnDemand>
	<Enabled>true</Enabled>
	<Hidden>false</Hidden>
	<RunOnlyIfIdle>false</RunOnlyIfIdle>
	<WakeToRun>false</WakeToRun>
	<ExecutionTimeLimit>PT1H</ExecutionTimeLimit>
	<Priority>7</Priority>
</Settings>
<Actions Context="Author">
	<Exec>
	<Command>cmd.exe</Command>
	<Arguments>$ArgString</Arguments>
	</Exec>
</Actions>
</Task>
"@

	if ($Values_Triggers -ne "") {
		Register-ScheduledTask -TaskName $TaskName -Xml $TaskXml -Force | Out-Null
		Write-Host "Automatic updates enabled." -ForegroundColor Green
	}
	else {
		Write-Host "No automation triggers selected." -ForegroundColor DarkGray
	}

	Write-Host "`nSetup complete." -ForegroundColor Green

	if ($Unattended) {
		$RunNow = "n"
	}
	else {
		$RunNow = Read-Host "Run Winget Updater now? (y/N)"
	}
	if ([string]::IsNullOrWhiteSpace($RunNow)) {
		$RunNow = "n"
	}
	if ($RunNow -eq "y") {
		Write-Host "Launching Winget Updater..." -ForegroundColor Cyan
		Start-Process -FilePath "cmd.exe" -ArgumentList "/c start `"`" /min `"$InstallDir\launcher.bat`" -Forced" -WindowStyle Hidden
	}
}
catch {
	$err = $_.Exception.Message
	Write-Host "Error during installation: $err" -ForegroundColor Red
	exit 1
}
