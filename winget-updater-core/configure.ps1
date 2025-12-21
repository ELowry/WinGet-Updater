<#
.SYNOPSIS
	Installer and Configurator for Winget Updater
	Copyright 2025 Eric Lowry
	Licensed under the MIT License.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseBOMForUnicodeEncodedFile", "")]
param(
	[switch]$Unattended,
	[switch]$EnableStartup,
	[switch]$EnableWake,
	[switch]$Forced
)

$ConfigRegPath = "HKCU:\Software\EricLowry\WingetUpdater\Config"

function Get-ConfigValue {
	param([string]$Name, $Default)
	try {
		if (Test-Path $ConfigRegPath) {
			$value = Get-ItemProperty -Path $ConfigRegPath -Name $Name -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $Name
			if ($null -ne $value) {
				return $value
			}
		}
	}
	catch {
		$null = $_
	}
	return $Default
}

function Set-ConfigValue {
	[CmdletBinding(SupportsShouldProcess)]
	param([string]$Name, $Value)
	if (-not (Test-Path $ConfigRegPath)) {
		# Create parent keys if they don't exist
		$parentPath = "HKCU:\Software\EricLowry"
		if (-not (Test-Path $parentPath)) {
			New-Item -Path $parentPath -Force | Out-Null
		}
		New-Item -Path $ConfigRegPath -Force | Out-Null
	}
	if ($PSCmdlet.ShouldProcess($Name, "Set configuration value")) {
		Set-ItemProperty -Path $ConfigRegPath -Name $Name -Value $Value -Force
	}
}

try {
	. "$PSScriptRoot\utils.ps1" -EntryScriptPath $PSCommandPath
	$AppName = "Winget Updater"
	$AppVersion = Get-AppVersion

	Find-OnlineUpdate -CurrentVersion $AppVersion
	$InstallDir = "$env:LOCALAPPDATA\WingetUpdater"
	$SourceDir = $PSScriptRoot

	$TargetLockFile = Join-Path $InstallDir "winget-updater.lock"
	if (Test-Path $TargetLockFile) {
		if (-not $Forced) {
			Write-Host "Error: Winget Updater appears to be running in '$InstallDir'." -ForegroundColor Red
			Write-Host "Please close it before continuing, or run this script with -Forced." -ForegroundColor Yellow
			exit 1
		}
		else {
			Write-Host "Overriding existing lock file as requested." -ForegroundColor Gray
			Remove-Item $TargetLockFile -Force -ErrorAction SilentlyContinue
		}
	}

	$PreviousVersion = Get-ConfigValue -Name "InstalledVersion" -Default $null

	if ($null -eq $PreviousVersion) {
		Write-Host "Installing Winget Updater v$AppVersion" -ForegroundColor Cyan
	}
	elseif ($PreviousVersion -eq $AppVersion) {
		Write-Host "Reinstalling Winget Updater v$AppVersion" -ForegroundColor Cyan
	}
	else {
		Write-Host "Upgrading Winget Updater: v$PreviousVersion → v$AppVersion" -ForegroundColor Cyan
	}
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
	Copy-Item -Path "$SourceDir\scheduled-updater.ps1" -Destination $InstallDir -Force
	Copy-Item -Path "$SourceDir\utils.ps1" -Destination $InstallDir -Force
	Copy-Item -Path "$SourceDir\uninstall.ps1" -Destination $InstallDir -Force
	Copy-Item -Path "$SourceDir\launcher.bat" -Destination $InstallDir -Force
	Copy-Item -Path "$SourceDir\silent.vbs" -Destination $InstallDir -Force

	Write-Host "Setting up shortcuts..." -ForegroundColor Yellow
	$StartMenuPrograms = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
	$LinkPath = "$StartMenuPrograms\$AppName.lnk"

	$WshShell = New-Object -comObject WScript.Shell

	$Shortcut = $WshShell.CreateShortcut($LinkPath)
	$Shortcut.TargetPath = "cmd.exe"
	$Shortcut.Arguments = "/c start `"`" /min `"$InstallDir\launcher.bat`""
	$Shortcut.IconLocation = "shell32.dll,238"
	$Shortcut.Description = "Update Windows applications using WinGet"
	$Shortcut.WorkingDirectory = $InstallDir
	$Shortcut.Save()

	$UninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WingetUpdater"
	if (-not (Test-Path $UninstallKey)) {
		New-Item -Path $UninstallKey -Force | Out-Null
	}

	$ArpValues = @{
		"DisplayName"     = $AppName
		"DisplayVersion"  = $AppVersion
		"Publisher"       = "Eric Lowry"
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

	$PrevStartup = Get-ConfigValue -Name "AutoStartup" -Default 1
	$PrevWake = Get-ConfigValue -Name "AutoWake" -Default 0

	$StartupDefault = if ($PrevStartup -eq 1) {
		"Y"
	}
	else {
		"n"
	}
	$WakeDefault = if ($PrevWake -eq 1) {
		"Y"
	}
	else {
		"n"
	}

	if ($Unattended) {
		$RunStartup = if ($EnableStartup) {
			"y"
		}
		else {
			"n"
		}
	}
	else {
		$prompt = "Run at system startup? ($(
			if ($StartupDefault -eq 'Y') {
				'Y/n'
			}
			else {
				'y/N'
			}
		)): "
		Write-Host $prompt -NoNewline -ForegroundColor Yellow
		$RunStartup = Read-Host
	}
	if ([string]::IsNullOrWhiteSpace($RunStartup)) {
		$RunStartup = if ($StartupDefault -eq "Y") {
			"y"
		}
		else {
			"n"
		}
	}

	if ($Unattended) {
		$RunWake = if ($EnableWake) {
			"y"
		}
		else {
			"n"
		}
	}
	else {
		$prompt = "Run on system wake/unlock? ($(
			if ($WakeDefault -eq 'Y') {
				'Y/n'
			}
			else {
				'y/N'
			}
		)): "
		Write-Host $prompt -NoNewline -ForegroundColor Yellow
		$RunWake = Read-Host
	}
	if ([string]::IsNullOrWhiteSpace($RunWake)) {
		$RunWake = if ($WakeDefault -eq "Y") {
			"y"
		}
		else {
			"n"
		}
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

	$VbsScript = "$InstallDir\silent.vbs"
	$TargetScript = "$InstallDir\scheduled-updater.ps1"

	$SafeVbs = $VbsScript.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("`"", "&quot;")
	$SafeTarget = $TargetScript.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("`"", "&quot;")

	$ArgString = "`"$SafeVbs`" `"$SafeTarget`""
	$User = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

	$TaskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
<RegistrationInfo>
	<Description>Runs Winget Updater to check for and install Windows application updates.</Description>
	<Author>Eric Lowry</Author>
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
	<Command>wscript.exe</Command>
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

	try {
		$startupValue = if ($RunStartup -eq "y") {
			1
		}
		else {
			0
		}
		$wakeValue = if ($RunWake -eq "y") {
			1
		}
		else {
			0
		}

		Set-ConfigValue -Name "AutoStartup" -Value $startupValue
		Set-ConfigValue -Name "AutoWake" -Value $wakeValue
		Set-ConfigValue -Name "InstalledVersion" -Value $AppVersion
		Write-Host " -> Configuration saved." -ForegroundColor Green
	}
	catch {
		Write-Host "Warning: Could not save configuration to registry: $($_.Exception.Message)" -ForegroundColor Yellow
	}

	Write-Host "`nSetup complete." -ForegroundColor Green

	if ($Unattended) {
		$RunNow = "n"
	}
	else {
		Write-Host "Run Winget Updater now? (y/N): " -NoNewline -ForegroundColor Yellow
		$RunNow = Read-Host
	}
	if ([string]::IsNullOrWhiteSpace($RunNow)) {
		$RunNow = "n"
	}
	if ($RunNow -eq "y") {
		Write-Host "Launching Winget Updater..." -ForegroundColor Yellow
		Start-Process -FilePath "cmd.exe" -ArgumentList "/c start `"`" /min `"$InstallDir\launcher.bat`"" -WindowStyle Hidden
	}
}
catch {
	$err = $_.Exception.Message
	Write-Host "Error during installation: $err" -ForegroundColor Red
	exit 1
}
