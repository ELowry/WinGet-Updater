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

$AppVersion = Get-AppVersion

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
		[System.Collections.ArrayList]$Forcelist,
		$PackageOptions
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
				$status = "Run (Default)"; $color = "Green"
			}

			Write-Host "[$($i+1)] $id " -NoNewline -ForegroundColor White
			Write-Host "[$status]" -ForegroundColor $color
		}

		Write-Host "`nEnter number to edit, or 'q' to save and exit."
		Write-Host "Selection: " -NoNewline -ForegroundColor Yellow
		$choice = Read-Host

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
			Write-Host "[O]ptions (Set custom arguments)"

			Write-Host "Set status: " -NoNewline -ForegroundColor Yellow
			$action = Read-Host
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
					$Forcelist.Add($selectedId) | Out-Null; Write-Host "Set to Always Run." -ForegroundColor Green
				}
				"b" {
					$Blocklist.Add($selectedId) | Out-Null; Write-Host "Set to Blocked." -ForegroundColor Green
				}
				"w" {
					$Whitelist.Add($selectedId) | Out-Null; Write-Host "Set to Whitelist." -ForegroundColor Green
				}
				"r" {
					Write-Host "Removed from tracking." -ForegroundColor Green
					$allIds = @($Whitelist + $Blocklist + $Forcelist) | Select-Object -Unique | Sort-Object
				}
				"o" {
					$current = if ($null -ne $PackageOptions -and $PackageOptions.Contains($selectedId)) {
						$PackageOptions[$selectedId]
					}
					else {
						""
					}
					if ($current -is [array]) {
						$current = $current -join " "
					}
					Write-Host "Current options: '$current'" -ForegroundColor DarkGray
					Write-Host "Note: --accept-source-agreements and --accept-package-agreements are always enabled." -ForegroundColor DarkGray
					Write-Host "New arguments (leave empty to clear): " -NoNewline -ForegroundColor Yellow
					$newOpts = Read-Host
					if ($null -eq $PackageOptions) {
						$PackageOptions = @{}
					}
					if ([string]::IsNullOrWhiteSpace($newOpts)) {
						$PackageOptions.Remove($selectedId)
						Write-Host "Options cleared." -ForegroundColor Green
					}
					else {
						$PackageOptions[$selectedId] = $newOpts
						Write-Host "Options updated." -ForegroundColor Green
					}
				}
			}
		}
	}
}

Function Show-UpdateMenu {
	param (
		[System.Collections.ArrayList]$Updates,
		[System.Collections.ArrayList]$Whitelist,
		$PackageOptions
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

		$prompt = "  Choose action: [R]un, [A]lways run, [S]kip, [B]lock, [O]ptions (Default is '$defaultWord')"

		$actionChoice = $null
		while ($null -eq $actionChoice) {
			do {
				Write-Host "${prompt}: " -NoNewline -ForegroundColor Yellow
				$response = Read-Host
				if ([string]::IsNullOrWhiteSpace($response)) {
					$response = $defaultChar
				}
				$response = $response.ToLower()
			} while ($response -notin @('r', 'a', 's', 'b', 'o'))

			if ($response -eq 'o') {
				$current = if ($null -ne $PackageOptions -and $PackageOptions.Contains($update.Id)) {
					$PackageOptions[$update.Id]
				}
				else {
					""
				}
				if ($current -is [array]) {
					$current = $current -join " "
				}
				Write-Host "  Current options: '$current'" -ForegroundColor DarkGray
				Write-Host "  Note: --accept-source-agreements and --accept-package-agreements are always enabled." -ForegroundColor DarkGray
				Write-Host "  New arguments (leave empty to clear): " -NoNewline -ForegroundColor Yellow
				$newOpts = Read-Host
				if ($null -eq $PackageOptions) {
					$PackageOptions = @{}
				}
				if ([string]::IsNullOrWhiteSpace($newOpts)) {
					$PackageOptions.Remove($update.Id)
					Write-Host "  Options cleared." -ForegroundColor Green
				}
				else {
					$PackageOptions[$update.Id] = $newOpts
					Write-Host "  Options updated." -ForegroundColor Green
				}
				# Loop again
			}
			else {
				$actionChoice = $response
			}
		}

		switch ($actionChoice) {
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
		[System.Collections.ArrayList]$Forcelist,
		$PackageOptions
	)

	Write-Host "$Message" -ForegroundColor Yellow

	$startTime = [DateTime]::Now
	$timeout = $startTime.AddSeconds($Seconds)

	while ([DateTime]::Now -lt $timeout) {
		if ($Host.UI.RawUI.KeyAvailable) {
			$k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown,IncludeKeyUp")

			if ($k.KeyDown) {
				if ($k.Character -and $k.Character.ToString().ToLower() -eq 'e') {
					Show-EditMode -Whitelist $Whitelist -Blocklist $Blocklist -Forcelist $Forcelist -PackageOptions $PackageOptions

					# Save immediately after editing
					$dataToSave = @{
						Whitelist = @($Whitelist)
						Blocklist = @($Blocklist)
						Forcelist = @($Forcelist)
						LastRun   = (Get-Date).ToString("o")
					}
					if ($PackageOptions) {
						$dataToSave["PackageOptions"] = $PackageOptions
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

$packageOptions = @{}
if ($null -ne $data -and $null -ne $data.PackageOptions) {
	if ($data.PackageOptions -is [System.Management.Automation.PSCustomObject]) {
		$data.PackageOptions.PSObject.Properties | ForEach-Object {
			$packageOptions[$_.Name] = $_.Value
		}
	}
	elseif ($data.PackageOptions -is [System.Collections.IDictionary]) {
		$packageOptions = $data.PackageOptions
	}
}

$hasValidData = ($whitelist.Count + $blocklist.Count + $forcelist.Count) -gt 0

if (-not $Silent -and -not $Minimal -and $hasValidData) {
	Invoke-Countdown -Seconds 2 `
		-Message "Press 'E' to edit list, or Enter to run updater (auto-starts in 2s)..." `
		-Whitelist $whitelist -Blocklist $blocklist -Forcelist $forcelist -PackageOptions $packageOptions | Out-Null
}

if (-not $Silent) {
	Find-OnlineUpdate -CurrentVersion $AppVersion
}

try {
	if ($CachePath -and (Test-Path $CachePath)) {
		Write-Status "Loading cached update data..." -Type Info -ForegroundColor Yellow
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

$updatesToForce = @(
	$allUpdates | Where-Object {
		$_.Id -and $forcelist -contains $_.Id
	}
)
$blockedUpdates = @(
	$allUpdates | Where-Object {
		$_.Id -and $blocklist -contains $_.Id
	}
)
$updatesToProcess = @(
	$allUpdates | Where-Object {
		$_.Id -and ($blocklist -notcontains $_.Id) -and ($forcelist -notcontains $_.Id)
	}
)

if ($updatesToForce.Count -gt 0) {
	Write-Status "--- Automatically updating packages from forcelist ---" -ForegroundColor Magenta -Type Info -Important
	foreach ($update in $updatesToForce) {
		Write-Status "Updating $($update.Name)..." -ForegroundColor Yellow -Type Info -Important
		try {
			$wingetArgs = @("upgrade", "--id", "$($update.Id)")
			if ($null -ne $packageOptions) {
				$val = $packageOptions.$($update.Id)
				if ($null -ne $val) {
					if ($val -is [array]) {
						$wingetArgs += $val
					}
					else {
						$wingetArgs += Split-ArgumentList $val
					}
				}
			}
			$wingetArgs += "--accept-source-agreements"
			$wingetArgs += "--accept-package-agreements"

			if ($Minimal) {
				& winget @wingetArgs | Out-Null
			}
			else {
				& winget @wingetArgs
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
	Write-Status "`nNo new updates to review." -Type Info -ForegroundColor Green
}
else {
	$userChoices = Show-UpdateMenu -Updates $updatesToProcess -Whitelist $whitelist -PackageOptions $packageOptions

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
						$wingetArgs = @("upgrade", "--id", "$($id)")
						if ($null -ne $packageOptions) {
							$val = $packageOptions.$($id)
							if ($null -ne $val) {
								if ($val -is [array]) {
									$wingetArgs += $val
								}
								else {
									$wingetArgs += Split-ArgumentList $val
								}
							}
						}
						$wingetArgs += "--accept-source-agreements"
						$wingetArgs += "--accept-package-agreements"

						if ($Minimal) {
							& winget @wingetArgs | Out-Null
						}
						else {
							& winget @wingetArgs
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
						$wingetArgs = @("upgrade", "--id", "$($id)")
						if ($null -ne $packageOptions) {
							$val = $packageOptions.$($id)
							if ($null -ne $val) {
								if ($val -is [array]) {
									$wingetArgs += $val
								}
								else {
									$wingetArgs += Split-ArgumentList $val
								}
							}
						}
						$wingetArgs += "--accept-source-agreements"
						$wingetArgs += "--accept-package-agreements"

						if ($Minimal) {
							& winget @wingetArgs | Out-Null
						}
						else {
							& winget @wingetArgs
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
		Write-Status "`nNo selections were made." -ForegroundColor Green -Type Info
	}
}

$dataToSave = @{
	Whitelist = @($whitelist)
	Blocklist = @($blocklist)
	Forcelist = @($forcelist)
	LastRun   = (Get-Date).ToString("o")
}
if ($null -ne $packageOptions -and $packageOptions.Count -gt 0) {
	$dataToSave["PackageOptions"] = $packageOptions
}
Save-Data -DataToSave $dataToSave -FilePath $DataFile

Write-Status "`nUpdate complete." -Type Info -ForegroundColor Green -Important

$hasValidData = ($whitelist.Count + $blocklist.Count + $forcelist.Count) -gt 0

if (-not $Silent -and -not $Minimal -and $hasValidData) {
	Invoke-Countdown -Seconds 5 `
		-Message "Press 'E' to edit list, or Enter to exit (auto-exits in 5s)..." `
		-Whitelist $whitelist -Blocklist $blocklist -Forcelist $forcelist -PackageOptions $packageOptions | Out-Null
}
elseif (-not $Silent -and -not $NoDelay -and -not $Minimal) {
	Start-Sleep -Seconds 3
}