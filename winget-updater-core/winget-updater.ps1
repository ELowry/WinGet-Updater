<#
.SYNOPSIS
	Winget Updater
	Copyright 2025 Eric Lowry
	Licensed under the MIT License.
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
param(
	[switch]$NoClear,
	[switch]$Forced,
	[switch]$Silent,
	[switch]$Minimal,
	[switch]$NoDelay
)

$DataFile = Join-Path $PSScriptRoot "winget-updater-data.json"
$LogFile = Join-Path $PSScriptRoot "winget-updater-log.txt"

Function Show-Header {
	if (-not $Silent) {
		Write-Host "============================" -ForegroundColor Cyan
		Write-Host "       WINGET UPDATER       " -ForegroundColor White
		Write-Host "============================" -ForegroundColor Cyan
		Write-Host ""
	}
}

Function Write-Status {
	param(
		[string]$Message,
		[ConsoleColor]$ForegroundColor = "White",
		[switch]$NoNewline,
		[string]$Type = "Info" # 'Info' or 'Error'
	)

	$Show = $true

	if ($Silent) {
		$Show = $false
	}
	elseif ($Minimal -and $Type -eq "Info") {
		$Show = $false
	}

	if ($Show) {
		if ($NoNewline) {
			Write-Host $Message -ForegroundColor $ForegroundColor -NoNewline
		}
		else {
			Write-Host $Message -ForegroundColor $ForegroundColor
		}
	}
}

Function Write-Log {
	param(
		[string]$Message
	)
	$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	"[$Timestamp] $Message" | Out-File -FilePath $LogFile -Append
}

Function Save-Data {
	param(
		[psobject]$DataToSave,
		[string]$FilePath
	)
	$TempFile = [System.IO.Path]::GetTempFileName()
	try {
		$DataToSave | ConvertTo-Json -Depth 5 | Out-File -FilePath $TempFile -Encoding utf8
		Move-Item -Path $TempFile -Destination $FilePath -Force
		Write-Status "Data saved successfully." -Type Info
	}
	catch {
		Write-Log "Failed to save data: $($_.Exception.Message)"
		Write-Status "Error saving data file." -ForegroundColor Red -Type Error
	}
	finally {
		if (Test-Path $TempFile) {
			Remove-Item $TempFile -Force
		}
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
			
			if ($Forcelist.Contains($id)) { $status = "ALWAYS RUN"; $color = "Magenta" }
			elseif ($Blocklist.Contains($id)) { $status = "BLOCKED"; $color = "Red" }
			elseif ($Whitelist.Contains($id)) { $status = "Run (Default)"; $color = "Cyan" }

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

			if ($Whitelist.Contains($selectedId)) { $Whitelist.Remove($selectedId) }
			if ($Blocklist.Contains($selectedId)) { $Blocklist.Remove($selectedId) }
			if ($Forcelist.Contains($selectedId)) { $Forcelist.Remove($selectedId) }

			switch ($action) {
				"f" { $Forcelist.Add($selectedId) | Out-Null; Write-Host "Set to Always Run." }
				"b" { $Blocklist.Add($selectedId) | Out-Null; Write-Host "Set to Blocked." }
				"w" { $Whitelist.Add($selectedId) | Out-Null; Write-Host "Set to Whitelist." }
				"r" { 
					Write-Host "Removed from tracking." 
					$allIds = @($Whitelist + $Blocklist + $Forcelist) | Select-Object -Unique | Sort-Object
				}
			}
		}
	}
}

Function Get-WingetUpdates {
	Write-Status "Checking for available updates..." -Type Info
	Write-Log "Checking for winget updates."
	try {
		Write-Log "Updating winget sources..."
		Write-Status "Updating winget sources... (This may take a moment)" -Type Info
		winget source update
		if ($LASTEXITCODE -ne 0) {
			throw "winget source update failed with exit code $LASTEXITCODE."
		}
		Write-Log "Winget sources updated."

		Write-Log "Running 'winget upgrade' to find available updates."
		Write-Status "Querying for available package updates..." -Type Info
		[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8
		$wingetOutput = winget upgrade | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
		
		$updates = @()
		
		$headerLine = $wingetOutput | Where-Object { $_ -like 'Name*Id*Version*' } | Select-Object -First 1
		$separatorLineIndex = -1
		for ($i = 0; $i -lt $wingetOutput.Count; $i++) {
			if ($wingetOutput[$i] -like '---*') {
				$separatorLineIndex = $i
				break
			}
		}

		if (-not $headerLine -or $separatorLineIndex -eq -1) {
			Write-Log "Could not find header or separator line in winget output. Assuming no updates."
			return @()
		}

		$idIndex = $headerLine.IndexOf('Id')
		$versionIndex = $headerLine.IndexOf('Version')
		$availableIndex = $headerLine.IndexOf('Available')
		$sourceIndex = $headerLine.IndexOf('Source')

		for ($i = $separatorLineIndex + 1; $i -lt $wingetOutput.Count; $i++) {
			$line = $wingetOutput[$i]
			if ($line.Length -lt $sourceIndex -or $line -like '*upgrades available*' -or $line -like '*cannot be determined*') { continue }

			try {
				$name = $line.Substring(0, $idIndex).Trim()
				$id = ($line.Substring($idIndex, $versionIndex - $idIndex).Trim() -replace '\p{C}')
				$version = $line.Substring($versionIndex, $availableIndex - $versionIndex).Trim()
				$available = $line.Substring($availableIndex, $sourceIndex - $availableIndex).Trim()

				if (-not ([string]::IsNullOrWhiteSpace($id))) {
					$updates += [PSCustomObject]@{
						Name             = $name
						Id               = $id
						Version          = $version
						AvailableVersion = $available
					}
				}
			}
			catch {
				Write-Log "Failed to parse line: '$line'. Error: $($_.Exception.Message)"
			}
		}

		Write-Log "Found $($updates.Count) valid updates."
		return $updates
	}
	catch {
		$errorMessage = $_.Exception.Message
		Write-Log "Error getting winget updates: $errorMessage"
		Write-Status "An error occurred while fetching updates. Check the log file for details." -ForegroundColor Red -Type Error
		return @()
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
		
		if ($null -eq $update -or [string]::IsNullOrWhiteSpace($update.Id)) { continue }

		$defaultChar = if ($Whitelist.Contains($update.Id)) { "r" } else { "s" }
		$defaultWord = switch ($defaultChar) {
			"r" { "Run" }
			"s" { "Skip" }
		}

		Write-Host "[$($i+1)/$($Updates.Count)] " -NoNewline
		Write-Host $update.Name -ForegroundColor White
		Write-Host "  $($update.Version) -> $($update.AvailableVersion)" -ForegroundColor DarkGray
		
		$prompt = "  Choose action: [R]un, [A]lways run, [S]kip, [B]lock (Default is '$defaultWord')"
		
		do {
			$response = Read-Host -Prompt $prompt
			if ([string]::IsNullOrWhiteSpace($response)) { $response = $defaultChar }
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
	if ($data.Whitelist -is [string]) { $whitelist.Add($data.Whitelist) } else { $whitelist.AddRange($data.Whitelist) }
}

$blocklist = [System.Collections.ArrayList]::new()
if ($null -ne $data -and $data.Blocklist) {
	if ($data.Blocklist -is [string]) { $blocklist.Add($data.Blocklist) } else { $blocklist.AddRange($data.Blocklist) }
}

$forcelist = [System.Collections.ArrayList]::new()
if ($null -ne $data -and $data.Forcelist) {
	if ($data.Forcelist -is [string]) { $forcelist.Add($data.Forcelist) } else { $forcelist.AddRange($data.Forcelist) }
}

$hasValidData = ($whitelist.Count + $blocklist.Count + $forcelist.Count) -gt 0

if (-not $Silent -and -not $Minimal -and $hasValidData) {
	Write-Host "Starting in 2 seconds... (Press any key to edit list)" -NoNewline -ForegroundColor Yellow
	$timeout = [DateTime]::Now.AddSeconds(2)
	$interrupted = $false
	while ([DateTime]::Now -lt $timeout) {
		if ($Host.UI.RawUI.KeyAvailable) {
			$interrupted = $true
			$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
			break
		}
		Start-Sleep -Milliseconds 50
	}
	Write-Host ""

	if ($interrupted) {
		Clear-Host
		Write-Host "--- PAUSED ---" -ForegroundColor Cyan
		Write-Host "[Enter] Continue to Update"
		if ($hasValidData) { Write-Host "[E]     Edit Existing List" }
		Write-Host "[Q]     Quit"
		
		while ($true) {
			$k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
			$ch = $k.Character.ToString().ToLower()
			
			if ($k.VirtualKeyCode -eq 13) { break } # Enter
			if ($ch -eq 'q') { exit }
			if ($hasValidData -and $ch -eq 'e') {
				Show-EditMode -Whitelist $whitelist -Blocklist $blocklist -Forcelist $forcelist
				$savedLastRun = if ($data -and $data.LastRun) { $data.LastRun } else { [DateTime]::MinValue.ToString("o") }
				$dataToSave = @{ Whitelist = @($whitelist); Blocklist = @($blocklist); Forcelist = @($forcelist); LastRun = $savedLastRun }
				Save-Data -DataToSave $dataToSave -FilePath $DataFile
				Write-Host "`nConfiguration saved. Continuing to update..." -ForegroundColor Green
				break
			}
		}
	}
}

$lastRunDate = [DateTime]::MinValue
if ($null -ne $data -and $data.PSObject.Properties.Name -contains 'LastRun') {
	try {
		if ($data.LastRun -is [string]) {
			$lastRunDate = [DateTime]::Parse($data.LastRun, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
		}
		elseif ($data.LastRun.DateTime) {
			$lastRunDate = [datetime]$data.LastRun.DateTime
		}
	}
	catch {
		Write-Log "Could not parse LastRun date: '$($data.LastRun)'. Resetting."
	}
}

if (-not $Forced -and ($lastRunDate.Date -eq (Get-Date).Date)) {
	Write-Log "Script has already run today. Exiting."
	if (-not $Silent) {
		Write-Host "This script has already been run successfully today." -ForegroundColor Red
		Write-Host "Use -Forced to bypass this check." -ForegroundColor DarkGray
		if (-not $NoDelay) { Start-Sleep -Seconds 3 }
	}
	exit
}


if (-not $NoClear -and -not $Silent -and -not $Minimal) { Clear-Host }

Show-Header

$allUpdates = Get-WingetUpdates

$updatesToForce = @($allUpdates | Where-Object { $_.Id -and $forcelist -contains $_.Id })
$blockedUpdates = @($allUpdates | Where-Object { $_.Id -and $blocklist -contains $_.Id })
$updatesToProcess = @($allUpdates | Where-Object { $_.Id -and ($blocklist -notcontains $_.Id) -and ($forcelist -notcontains $_.Id) })

if ($updatesToForce.Count -gt 0) {
	Write-Status "--- Automatically updating packages from forcelist ---" -ForegroundColor Magenta -Type Info
	foreach ($update in $updatesToForce) {
		Write-Status "Updating $($update.Name)..." -ForegroundColor Yellow -Type Info
		try {
			winget upgrade --id $update.Id --accept-source-agreements --accept-package-agreements
			if ($LASTEXITCODE -ne 0) {
				throw "Winget failed to update $($update.Name) (ID: $($update.Id))"
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
		$blockedUpdates.Name | ForEach-Object { Write-Host " - $_" }
	}
}

if ($updatesToProcess.Count -eq 0) {
	Write-Log "No updates to process after filtering."
	Write-Status "`nNo new updates to review." -Type Info
}
else {
	# Get user choices (Interaction required, so this bypasses Silent/Minimal logic)
	$userChoices = Show-UpdateMenu -Updates $updatesToProcess -Whitelist $whitelist

	if ($userChoices.Count -gt 0) {
		Write-Status "`n--- Processing Selections ---" -ForegroundColor Cyan -Type Info
		foreach ($id in $userChoices.Keys) {
			$choice = $userChoices[$id]
			$update = $updatesToProcess | Where-Object { $_.Id -eq $id } | Select-Object -First 1
			$updateName = if ($update) { $update.Name } else { $id }

			switch ($choice) {
				"Run" {
					if (-not $whitelist.Contains($id)) { $whitelist.Add($id) | Out-Null }
					if ($blocklist.Contains($id)) { $blocklist.Remove($id) }
					if ($forcelist.Contains($id)) { $forcelist.Remove($id) }
					try {
						Write-Status "Updating $updateName..." -ForegroundColor Yellow -Type Info
						Write-Log "Attempting to update $id."
						winget upgrade --id $id --accept-source-agreements --accept-package-agreements
						if ($LASTEXITCODE -ne 0) { throw "Winget failed to update $updateName (ID: $id)" }
					}
					catch {
						$errorMessage = $_.Exception.Message
						Write-Log "Error updating ${id}: $errorMessage"
						Write-Status "  -> FAILED to update $updateName." -ForegroundColor Red -Type Error
					}
				}
				"Always" {
					if (-not $forcelist.Contains($id)) { $forcelist.Add($id) | Out-Null }
					if ($whitelist.Contains($id)) { $whitelist.Remove($id) }
					if ($blocklist.Contains($id)) { $blocklist.Remove($id) }
					try {
						Write-Status "Updating $updateName..." -ForegroundColor Yellow -Type Info
						Write-Log "Attempting to update $id (and adding to forcelist)."
						winget upgrade --id $id --accept-source-agreements --accept-package-agreements
						if ($LASTEXITCODE -ne 0) { throw "Winget failed to update $updateName (ID: $id)" }
					}
					catch {
						$errorMessage = $_.Exception.Message
						Write-Log "Error updating ${id}: $errorMessage"
						Write-Status "  -> FAILED to update $updateName." -ForegroundColor Red -Type Error
					}
				}
				"Skip" {
					if ($whitelist.Contains($id)) { $whitelist.Remove($id) }
				}
				"Block" {
					if (-not $blocklist.Contains($id)) { $blocklist.Add($id) | Out-Null }
					if ($whitelist.Contains($id)) { $whitelist.Remove($id) }
					if ($forcelist.Contains($id)) { $forcelist.Remove($id) }
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

Write-Status "`nUpdate complete." -Type Info -ForegroundColor Green

$hasValidData = ($whitelist.Count + $blocklist.Count + $forcelist.Count) -gt 0

if (-not $Silent -and -not $Minimal -and $hasValidData) {
	Write-Host "Press 'E' to edit list, or Enter to exit..." -ForegroundColor Yellow
	
	# Wait up to 5 seconds for input
	$timeout = [DateTime]::Now.AddSeconds(5)
	while ([DateTime]::Now -lt $timeout) {
		if ($Host.UI.RawUI.KeyAvailable) {
			$k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
			
			if ($k.Character.ToString().ToLower() -eq 'e') {
				Show-EditMode -Whitelist $whitelist -Blocklist $blocklist -Forcelist $forcelist
				$dataToSave = @{ Whitelist = @($whitelist); Blocklist = @($blocklist); Forcelist = @($forcelist); LastRun = (Get-Date).ToString("o") }
				Save-Data -DataToSave $dataToSave -FilePath $DataFile
				Write-Host "`nConfiguration saved." -ForegroundColor Green
				Start-Sleep -Seconds 1
				break
			}
			if ($k.VirtualKeyCode -eq 13) { break }
		}
		Start-Sleep -Milliseconds 50
	}
}
elseif (-not $Silent -and -not $NoDelay) {
	Start-Sleep -Seconds 3
}