<#
.SYNOPSIS
	WinGet Updater - Scheduled Task Runner
	Copyright 2025 Eric Lowry
	Licensed under the MIT License.
#>
param()

. "$PSScriptRoot\utils.ps1"

$data = $null
if (Test-Path $DataFile) {
	try {
		$fileContent = Get-Content $DataFile -Raw -Encoding utf8
		if (-not [string]::IsNullOrWhiteSpace($fileContent)) {
			$data = $fileContent | ConvertFrom-Json
		}
	}
	catch {
		Write-Log "Warning: Failed to load data file. Starting fresh. Error: $($_.Exception.Message)"
	}
}

$lastRunDate = Get-LastRunDate -Data $data

if ($lastRunDate.Date -eq (Get-Date).Date) {
	exit
}

if (-not (Request-Lock -Silent)) {
	exit
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
		Write-Log "Scheduled check found no actionable updates. Updating LastRun."

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

	Write-Log "Scheduled check found $($actionableUpdates.Count) actionable updates. Launching UI."

	if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
		Start-Process "wt.exe" -ArgumentList "-w new powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\winget-updater.ps1`" -Minimal -Forced -CachePath `"$tempCache`"" -WindowStyle Normal
	}
	else {
		Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\winget-updater.ps1`" -Minimal -Forced -CachePath `"$tempCache`"" -WindowStyle Normal
	}

}
catch {
	Write-Log "Error during scheduled update check: $($_.Exception.Message)"
}
finally {
	# Only clear if we didn't hand off to the UI (indicated by actionableUpdates count)
	if ($null -ne $actionableUpdates -and $actionableUpdates.Count -eq 0) {
		Clear-Lock
	}
	elseif ($null -eq $actionableUpdates) {
		# If we crashed before even defining the variable
		Clear-Lock
	}
}
