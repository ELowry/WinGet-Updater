<#
.SYNOPSIS
	WinGet Updater - Scheduled Task Runner
	Copyright 2025 Eric Lowry
	Licensed under the MIT License.

.DESCRIPTION
	Executes as a background scheduled task runner to query available WinGet updates, evaluate configured package rules (whitelists, blocklists, forcelists), and hand off execution to winget-updater.ps1 either silently or via an interactive terminal window.

.PARAMETER Silent
	Runs the updater process silently in the background, suppressing terminal window launching.
#>
[CmdletBinding()]
param(
	[switch]$Silent
)

. "$PSScriptRoot\utils.ps1" -EntryScriptPath $PSCommandPath

$data = $null
$bakFile = $DataFile -replace '\.json$', '.bak'

if (Test-Path $DataFile) {
	try {
		$fileContent = Get-Content $DataFile -Raw -Encoding utf8
		if (-not [string]::IsNullOrWhiteSpace($fileContent)) {
			$data = $fileContent | ConvertFrom-Json
		}
	}
	catch {
		Write-UpdaterLog "Error parsing $DataFile. Attempting to load backup. Error: $($_.Exception.Message)"
	}
}

if ($null -eq $data -and (Test-Path $bakFile)) {
	try {
		$fileContent = Get-Content $bakFile -Raw -Encoding utf8
		if (-not [string]::IsNullOrWhiteSpace($fileContent)) {
			$data = $fileContent | ConvertFrom-Json
			Write-UpdaterLog "Successfully recovered configuration from backup file."
		}
	}
	catch {
		Write-UpdaterLog "Warning: Failed to load backup data file. Starting fresh. Error: $($_.Exception.Message)"
	}
}

$lastRunDate = Get-LastRunDate -Data $data

if ($lastRunDate.Date -eq (Get-Date).Date) {
	exit
}

if (-not (Request-Lock -Silent)) {
	exit
}

if (-not (Test-WinGetDependency)) {
	Clear-Lock
	exit 1
}

try {
	$updates = Get-WinGetUpdate

	$blocklist = [System.Collections.ArrayList]::new()
	if ($null -ne $data -and $data.Blocklist) {
		$blocklist.AddRange(@($data.Blocklist))
	}

	$forcelist = [System.Collections.ArrayList]::new()
	if ($null -ne $data -and $data.Forcelist) {
		$forcelist.AddRange(@($data.Forcelist))
	}

	$actionableUpdates = $updates | Where-Object {
		$_.Id -and ($blocklist -notcontains $_.Id)
	}

	if ($actionableUpdates.Count -eq 0) {
		Write-UpdaterLog "Scheduled check found no actionable updates. Updating LastRun."

		$whitelist = if ($data.Whitelist) {
			$data.Whitelist
		}
		else {
			@()
		}

		$dataToSave = @{
			Whitelist = $whitelist
			Blocklist = $data.Blocklist
			Forcelist = $data.Forcelist
			LastRun   = (Get-Date).ToString("o")
		}
		if ($data.PackageOptions) {
			$dataToSave["PackageOptions"] = $data.PackageOptions
		}
		Save-Data -DataToSave $dataToSave -FilePath $DataFile
		Clear-Lock
		exit
	}

	$tempCache = [System.IO.Path]::GetTempFileName()
	$updates | ConvertTo-Json -Depth 5 | Out-File -FilePath $tempCache -Encoding utf8

	$keepLock = $false

	if ($Silent) {
		Write-UpdaterLog "Scheduled check found $($actionableUpdates.Count) actionable updates. Launching in Silent Mode."
		Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\winget-updater.ps1`" -Minimal -Forced -Silent -CachePath `"$tempCache`"" -WindowStyle Hidden -ErrorAction Stop
		$keepLock = $true
	}
	else {
		Write-UpdaterLog "Scheduled check found $($actionableUpdates.Count) actionable updates. Launching UI."

		if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
			Start-Process "wt.exe" -ArgumentList "-w new powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\winget-updater.ps1`" -Minimal -Forced -CachePath `"$tempCache`"" -WindowStyle Normal -ErrorAction Stop
			$keepLock = $true
		}
		else {
			Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\winget-updater.ps1`" -Minimal -Forced -CachePath `"$tempCache`"" -WindowStyle Normal -ErrorAction Stop
			$keepLock = $true
		}
	}

}
catch {
	Write-UpdaterLog "Error during scheduled update check or handoff: $($_.Exception.Message)"
}
finally {
	# Only clear the lock if the handoff did not successfully complete
	if (-not $keepLock) {
		Clear-Lock
	}
}
