<#
.SYNOPSIS
	WinGet Updater
	Copyright 2025 Eric Lowry
	Licensed under the MIT License.
#>

[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
param(
	[switch]$NoClear,
	[switch]$Silent,
	[switch]$Minimal,
	[switch]$NoDelay,
	[string]$CachePath
)

. "$PSScriptRoot\utils.ps1"

Function Show-Header {
	if (-not $Silent) {
		Write-Host "============================" -ForegroundColor Cyan
		Write-Host "       WINGET UPDATER       " -ForegroundColor White
		Write-Host "============================" -ForegroundColor Cyan
		Write-Host ""
	}
}

Function Show-EditMode {
	param (
		[System.Collections.ArrayList]$Whitelist,
		[System.Collections.ArrayList]$Blocklist,
		[System.Collections.ArrayList]$Forcelist
	)

	Clear-Host
	Write-Host "--- EDIT MODE ---" -ForegroundColor Cyan
	Write-Host "Reviewing managed packages."
		
	$allIds = @($Whitelist + $Blocklist + $Forcelist) | Select-Object -Unique | Sort-Object

	if ($allIds.Count -eq 0) {
		Write-Host "No managed packages found in data file." -ForegroundColor Yellow
		return
	}

	$exitEdit = $false
	while (-not $exitEdit) {
		Write-Host "`nCurrent Managed Packages:" -ForegroundColor Cyan
		for ($i = 0; $i -lt $allIds.Count; $i++) {
			$id = $allIds[$i]
			$status = "Unknown"
			$color = "Gray"
				
			if ($Forcelist.Contains($id)) {
				$status = "ALWAYS RUN"; $color = "Magenta"
			}
			elseif ($Blocklist.Contains($id)) {
				$status = "BLOCKED"; $color = "Red"
			}
			elseif ($Whitelist.Contains($id)) {
				$status = "Run (Default)"; $color = "Cyan"
			}

			Write-Host "[$($i+1)] $id " -NoNewline
			Write-Host "[$status]" -ForegroundColor $color
		}

		Write-Host "`nEnter number to edit, or 'q' to save and exit."
		$choice = Read-Host "Selection"
			
		if ($choice -eq 'q') {
			$exitEdit = $true
		}
		elseif ($choice -match '^\d+$' -and [int]$choice -le $allIds.Count -and [int]$choice -gt 0) {
			$selectedIndex = [int]$choice - 1
			$selectedId = $allIds[$selectedIndex]
				
			Write-Host "`nEditing: $selectedId" -ForegroundColor Yellow
			Write-Host "[F]orce (Always Run)"
			Write-Host "[B]lock (Never Run)"
			Write-Host "[W]hitelist (Default to Run)"
			Write-Host "[R]emove (Forget setting)"
				
			$action = Read-Host "Set status"
			$action = $action.ToLower()

			if ($Whitelist.Contains($selectedId)) {
				$Whitelist.Remove($selectedId)
			}
			if ($Blocklist.Contains($selectedId)) {
				$Blocklist.Remove($selectedId)
			}
			if ($Forcelist.Contains($selectedId)) {
				$Forcelist.Remove($selectedId)
			}

			switch ($action) {
				"f" {
					$Forcelist.Add($selectedId) | Out-Null; Write-Host "Set to Always Run."
				}
				"b" {
					$Blocklist.Add($selectedId) | Out-Null; Write-Host "Set to Blocked."
				}
				"w" {
					$Whitelist.Add($selectedId) | Out-Null; Write-Host "Set to Whitelist."
				}
				"r" {
					Write-Host "Removed from tracking."
					$allIds = @($Whitelist + $Blocklist + $Forcelist) | Select-Object -Unique | Sort-Object
				}
			}
		}
	}
}

Function Show-UpdateMenu {
	param (
		[System.Collections.ArrayList]$Updates,
		[System.Collections.ArrayList]$Whitelist
	)

	$choices = @{}
	Write-Host "`n--- Choose actions for remaining updates ---`n" -ForegroundColor Cyan

	for ($i = 0; $i -lt $Updates.Count; $i++) {
		$update = $Updates[$i]
			
		if ($null -eq $update -or [string]::IsNullOrWhiteSpace($update.Id)) {
			continue
		}

		$defaultChar = if ($Whitelist.Contains($update.Id)) {
			"r"
		}
		else {
			"s"
		}
		$defaultWord = switch ($defaultChar) {
			"r" {
				"Run"
			}
			"s" {
				"Skip"
			}
		}

		Write-Host "[$($i+1)/$($Updates.Count)] " -NoNewline
		Write-Host $update.Name -ForegroundColor White
		Write-Host "  $($update.Version) -> $($update.AvailableVersion)" -ForegroundColor DarkGray
			
		$prompt = "  Choose action: [R]un, [A]lways run, [S]kip, [B]lock (Default is '$defaultWord')"
			
		do {
			$response = Read-Host -Prompt $prompt
			if ([string]::IsNullOrWhiteSpace($response)) {
				$response = $defaultChar
			}
			$response = $response.ToLower()
		} while ($response -notin @('r', 'a', 's', 'b'))

		switch ($response) {
			"r" {
				$choices[$update.Id] = "Run"
				Write-Host "  -> Marked to RUN." -ForegroundColor Green
			}
			"a" {
				$choices[$update.Id] = "Always"
				Write-Host "  -> Marked to ALWAYS RUN in the future." -ForegroundColor Magenta
			}
			"s" {
				$choices[$update.Id] = "Skip"
				Write-Host "  -> SKIPPED for this session." -ForegroundColor DarkGray
			}
			"b" {
				$choices[$update.Id] = "Block"
				Write-Host "  -> BLOCKED for future sessions." -ForegroundColor Red
			}
		}
		Write-Host ""
	}

	return $choices
}

Function Invoke-Countdown {
	param(
		[int]$Seconds,
		[string]$Message,
		[System.Collections.ArrayList]$Whitelist,
		[System.Collections.ArrayList]$Blocklist,
		[System.Collections.ArrayList]$Forcelist
	)

	Write-Host "$Message" -ForegroundColor Yellow
	
	$startTime = [DateTime]::Now
	$timeout = $startTime.AddSeconds($Seconds)

	while ([DateTime]::Now -lt $timeout) {
		if ($Host.UI.RawUI.KeyAvailable) {
			$k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown,IncludeKeyUp")
			
			if ($k.KeyDown) {
				if ($k.Character -and $k.Character.ToString().ToLower() -eq 'e') {
					Show-EditMode -Whitelist $Whitelist -Blocklist $Blocklist -Forcelist $Forcelist
				
					# Save immediately after editing
					$dataToSave = @{
						Whitelist = @($Whitelist)
						Blocklist = @($Blocklist)
						Forcelist = @($Forcelist)
						LastRun   = (Get-Date).ToString("o")
					}
					Save-Data -DataToSave $dataToSave -FilePath $DataFile
					Write-Host "`nConfiguration saved." -ForegroundColor Green
					Start-Sleep -Seconds 1
					return $true # Indicates an edit happened
				}
				if ($k.VirtualKeyCode -eq 13 -and ([DateTime]::Now - $startTime).TotalMilliseconds -lt 100) {
					return $false # Enter key pressed, skip delay
				}
			}
		}
		Start-Sleep -Milliseconds 50
	}
	return $false
}

if (-not $NoClear -and -not $Silent -and -not $Minimal) {
	Clear-Host
}

Show-Header

if (Test-Path $LogFile) {
	Clear-Content -Path $LogFile -ErrorAction SilentlyContinue
}

$data = $null
if (Test-Path $DataFile) {
	try {
		$fileContent = Get-Content $DataFile -Raw -Encoding utf8
		if (-not [string]::IsNullOrWhiteSpace($fileContent)) {
			$data = $fileContent | ConvertFrom-Json
		}
	}
	catch {
		$err = $_.Exception.Message
		Write-Log "Error reading or parsing data file $DataFile. A new one will be created. Error: $err"
		$data = $null
	}
}

$whitelist = [System.Collections.ArrayList]::new()
if ($null -ne $data -and $data.Whitelist) {
	$whitelist.AddRange(@($data.Whitelist))
}

$blocklist = [System.Collections.ArrayList]::new()
if ($null -ne $data -and $data.Blocklist) {
	$blocklist.AddRange(@($data.Blocklist))
}

$forcelist = [System.Collections.ArrayList]::new()
if ($null -ne $data -and $data.Forcelist) {
	$forcelist.AddRange(@($data.Forcelist))
}

$hasValidData = ($whitelist.Count + $blocklist.Count + $forcelist.Count) -gt 0

if (-not $Silent -and -not $Minimal -and $hasValidData) {
	Invoke-Countdown -Seconds 2 `
		-Message "Press 'E' to edit list, or Enter to run updater (auto-starts in 2s)..." `
		-Whitelist $whitelist -Blocklist $blocklist -Forcelist $forcelist | Out-Null
}

try {
	if ($CachePath -and (Test-Path $CachePath)) {
		Write-Status "Loading cached update data..." -Type Info
		$allUpdates = Get-Content $CachePath | ConvertFrom-Json
	}
	else {
		$allUpdates = Get-WinGetUpdate
	}
}
catch {
	Write-Status "Error loading update data." -Type Error
	$allUpdates = @()
}
finally {
	if ($CachePath -and (Test-Path $CachePath)) {
		Remove-Item $CachePath -Force -ErrorAction SilentlyContinue
	}
}

# Check for Self-Update
$SelfID = "EricLowry.WinGetUpdater"
$selfUpdate = $allUpdates | Where-Object { $_.Id -eq $SelfID } | Select-Object -First 1

if ($selfUpdate) {
	Write-Status "`n[!] Update available for Winget Updater (v$($selfUpdate.AvailableVersion))" -ForegroundColor Cyan -Important
	
	$doSelfUpdate = $false
	
	if (-not $Silent) {
		Write-Host "    Update and restart application now? [Y/n] " -NoNewline -ForegroundColor Yellow
		$response = Read-Host
		if ($response -eq '' -or $response.ToLower().StartsWith('y')) {
			$doSelfUpdate = $true
		}
	}

	if ($doSelfUpdate) {
		Write-Status "Spawning updater..." -Type Info
		
		$batchPath = [System.IO.Path]::GetTempFileName() + ".bat"
		$installDir = $PSScriptRoot
		
		$batchContent = @"
@echo off
cd /d "%TEMP%"

:RETRY_UPDATE
cls
echo Waiting for Winget Updater to close...
timeout /t 3 /nobreak > NUL

echo Updating Winget Updater...
winget upgrade $SelfID --accept-source-agreements --accept-package-agreements

if %errorlevel% equ 0 (
	echo Update successful. Restarting...
	
	where wt >nul 2>&1
	if %errorlevel% equ 0 (
		start "" wt -w new powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$installDir\winget-updater.ps1"
	) else (
		start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$installDir\winget-updater.ps1"
	)
	
	(goto) 2>nul & del "%~f0"
) else (
	echo.
	echo [!] Update failed.
	echo This usually happens if the application folder is open in another console window.
	echo.
	echo Please close any open Explorer, Terminal, or PowerShell windows operating on:
	echo "$installDir"
	echo.
	echo Press any key to try again...
	pause >nul
	goto RETRY_UPDATE
)
"@
		Set-Content -Path $batchPath -Value $batchContent -Encoding Ascii
		Start-Process "cmd.exe" -ArgumentList "/c `"$batchPath`"" -WindowStyle Normal -WorkingDirectory $env:TEMP
		exit
	}
	
	$allUpdates = @($allUpdates | Where-Object { $_.Id -ne $SelfID })
}

$updatesToForce = @(
	$allUpdates | Where-Object {
		$_.Id -and $forcelist -contains $_.Id -and $_.Id -ne $SelfID
	}
)
$blockedUpdates = @(
	$allUpdates | Where-Object {
		$_.Id -and $blocklist -contains $_.Id -and $_.Id -ne $SelfID
	}
)
$updatesToProcess = @(
	$allUpdates | Where-Object {
		$_.Id -and ($blocklist -notcontains $_.Id) -and ($forcelist -notcontains $_.Id) -and $_.Id -ne $SelfID
	}
)

if ($updatesToForce.Count -gt 0) {
	Write-Status "--- Automatically updating packages from forcelist ---" -ForegroundColor Magenta -Type Info -Important
	foreach ($update in $updatesToForce) {
		Write-Status "Updating $($update.Name)..." -ForegroundColor Yellow -Type Info -Important
		try {
			if ($Minimal) {
				winget upgrade --id $update.Id --accept-source-agreements --accept-package-agreements | Out-Null
			}
			else {
				winget upgrade --id $update.Id --accept-source-agreements --accept-package-agreements
			}
			if ($LASTEXITCODE -ne 0) {
				throw "WinGet failed to update $($update.Name) (ID: $($update.Id))"
			}
		}
		catch {
			Write-Status "  -> FAILED to update $($update.Name)." -ForegroundColor Red -Type Error
			Write-Log "Error updating $($update.Id): $($_.Exception.Message)"
		}
	}
}

if ($blockedUpdates.Count -gt 0) {
	Write-Status "`n--- Skipping blocked packages ---" -ForegroundColor Red -Type Info
	if (-not $Silent -and -not $Minimal) {
		$blockedUpdates.Name | ForEach-Object {
			Write-Host " - $_"
		}
	}
}

if ($updatesToProcess.Count -eq 0) {
	Write-Log "No updates to process after filtering."
	Write-Status "`nNo new updates to review." -Type Info
}
else {
	$userChoices = Show-UpdateMenu -Updates $updatesToProcess -Whitelist $whitelist

	if ($userChoices.Count -gt 0) {
		Write-Status "`n--- Processing Selections ---" -ForegroundColor Cyan -Type Info
		foreach ($id in $userChoices.Keys) {
			$choice = $userChoices[$id]
			$update = $updatesToProcess | Where-Object {
				$_.Id -eq $id
			} | Select-Object -First 1
			$updateName = if ($update) {
				$update.Name
			}
			else {
				$id
			}

			switch ($choice) {
				"Run" {
					if (-not $whitelist.Contains($id)) {
						$whitelist.Add($id) | Out-Null
					}
					if ($blocklist.Contains($id)) {
						$blocklist.Remove($id)
					}
					if ($forcelist.Contains($id)) {
						$forcelist.Remove($id)
					}
					try {
						Write-Status "Updating $updateName..." -ForegroundColor Yellow -Type Info -Important
						Write-Log "Attempting to update $id."
						if ($Minimal) {
							winget upgrade --id $id --accept-source-agreements --accept-package-agreements | Out-Null
						}
						else {
							winget upgrade --id $id --accept-source-agreements --accept-package-agreements
						}
						if ($LASTEXITCODE -ne 0) {
							throw "WinGet failed to update $updateName (ID: $id)"
						}
					}
					catch {
						$errorMessage = $_.Exception.Message
						Write-Log "Error updating ${id}: $errorMessage"
						Write-Status "  -> FAILED to update $updateName." -ForegroundColor Red -Type Error
					}
				}
				"Always" {
					if (-not $forcelist.Contains($id)) {
						$forcelist.Add($id) | Out-Null
					}
					if ($whitelist.Contains($id)) {
						$whitelist.Remove($id)
					}
					if ($blocklist.Contains($id)) {
						$blocklist.Remove($id)
					}
					try {
						Write-Status "Updating $updateName..." -ForegroundColor Yellow -Type Info -Important
						Write-Log "Attempting to update $id (and adding to forcelist)."
						if ($Minimal) {
							winget upgrade --id $id --accept-source-agreements --accept-package-agreements | Out-Null
						}
						else {
							winget upgrade --id $id --accept-source-agreements --accept-package-agreements
						}
						if ($LASTEXITCODE -ne 0) {
							throw "WinGet failed to update $updateName (ID: $id)"
						}
					}
					catch {
						$errorMessage = $_.Exception.Message
						Write-Log "Error updating ${id}: $errorMessage"
						Write-Status "  -> FAILED to update $updateName." -ForegroundColor Red -Type Error
					}
				}
				"Skip" {
					if ($whitelist.Contains($id)) {
						$whitelist.Remove($id)
					}
				}
				"Block" {
					if (-not $blocklist.Contains($id)) {
						$blocklist.Add($id) | Out-Null
					}
					if ($whitelist.Contains($id)) {
						$whitelist.Remove($id)
					}
					if ($forcelist.Contains($id)) {
						$forcelist.Remove($id)
					}
				}
			}
		}
	}
	else {
		Write-Status "`nNo selections were made." -ForegroundColor Yellow -Type Info
	}
}

$dataToSave = @{
	Whitelist = @($whitelist)
	Blocklist = @($blocklist)
	Forcelist = @($forcelist)
	LastRun   = (Get-Date).ToString("o")
}
Save-Data -DataToSave $dataToSave -FilePath $DataFile

Write-Status "`nUpdate complete." -Type Info -ForegroundColor Green -Important

$hasValidData = ($whitelist.Count + $blocklist.Count + $forcelist.Count) -gt 0

if (-not $Silent -and -not $Minimal -and $hasValidData) {
	Invoke-Countdown -Seconds 5 `
		-Message "Press 'E' to edit list, or Enter to exit (auto-exits in 5s)..." `
		-Whitelist $whitelist -Blocklist $blocklist -Forcelist $forcelist | Out-Null
}
elseif (-not $Silent -and -not $NoDelay -and -not $Minimal) {
	Start-Sleep -Seconds 3
}