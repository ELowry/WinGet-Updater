<#
.SYNOPSIS
	WinGet Updater - Shared Utilities
	Copyright 2025 Eric Lowry
	Licensed under the MIT License.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "")]
param()

$DataFile = Join-Path $PSScriptRoot "winget-updater-data.json"
$LogFile = Join-Path $PSScriptRoot "winget-updater-log.txt"
$LockFile = Join-Path $PSScriptRoot "winget-updater.lock"

Function Get-AppVersion {
	$versionFilePath = if (Test-Path "$PSScriptRoot\version.isi") {
		"$PSScriptRoot\version.isi"
	}
	elseif (Test-Path "$PSScriptRoot\..\installer\version.isi") {
		"$PSScriptRoot\..\installer\version.isi"
	}
	else {
		return "Unknown"
	}
	
	try {
		$versionLine = Get-Content $versionFilePath -ErrorAction Stop | Select-String '#define AppVersion' | Select-Object -First 1
		if ($versionLine) {
			return ($versionLine.Line -replace '.*"(.*)".*', '$1')
		}
	}
	catch {
		return "Unknown"
	}
}

Function Get-LastRunDate {
	param([psobject]$Data)

	if ($null -eq $Data) {
		return [DateTime]::MinValue
	}

	if (-not ($Data.PSObject.Properties.Name -contains 'LastRun')) {
		return [DateTime]::MinValue
	}

	try {
		if ($Data.LastRun -is [string]) {
			return [DateTime]::Parse($Data.LastRun, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
		}
		elseif ($Data.LastRun.DateTime) {
			return [datetime]$Data.LastRun.DateTime
		}
		return [DateTime]::MinValue
	}
	catch {
		Write-Log "Could not parse LastRun date: '$($Data.LastRun)'. Error: $($_.Exception.Message)"
		return [DateTime]::MinValue
	}
}

Function Write-Status {
	param(
		[string]$Message,
		[ConsoleColor]$ForegroundColor = "White",
		[switch]$NoNewline,
		[string]$Type = "Info", # 'Info' or 'Error'
		[switch]$Important
	)

	$Show = $true

	if ($Silent) {
		$Show = $false
	}
	elseif ($Minimal -and $Type -eq "Info" -and -not $Important) {
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
	try {
		"[$Timestamp] $Message" | Out-File -FilePath $LogFile -Append -ErrorAction SilentlyContinue
	}
	catch {
		Write-Status "Error logging message: $Message" -ForegroundColor Red -Type Error
	}

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
		Write-Status "Data saved successfully." -Type Info -ForegroundColor Green
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

Function Split-ArgumentList {
	param([string]$InputString)
	if ([string]::IsNullOrWhiteSpace($InputString)) {
		return @()
	}

	# Matches quoted strings or non-whitespace sequences
	$regex = [regex] '([^\s"]+|"([^"]*)")'
	$matchCollection = $regex.Matches($InputString)
	$argsList = @()
	foreach ($m in $matchCollection) {
		$val = $m.Value
		if ($val.StartsWith('"') -and $val.EndsWith('"')) {
			$val = $val.Substring(1, $val.Length - 2)
		}
		$argsList += $val
	}
	return $argsList
}

Function Request-Lock {
	param(
		[switch]$Forced,
		[switch]$Silent
	)

	if (Test-Path $LockFile) {
		if (-not $Forced) {
			try {
				$lockContent = Get-Content $LockFile -Raw -ErrorAction Stop
				if ([string]::IsNullOrWhiteSpace($lockContent)) {
					throw "Lock file is empty."
				}
				$lockTime = [DateTime]::Parse($lockContent.Trim(), $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
				if ((Get-Date) -lt $lockTime.AddHours(2)) {
					if (-not $Silent) {
						Write-Host "Warning: Another instance of WinGet Updater is already running (locked since $($lockTime.ToString('HH:mm:ss')))." -ForegroundColor Yellow
						Write-Host "This usually happens if you've already opened the updater or if a previous instance crashed." -ForegroundColor Gray
						Write-Host ""
						Write-Host "Do you want to start anyway? (y/N): " -NoNewline -ForegroundColor Yellow
						$response = Read-Host
						if ($response -eq 'y') {
							Write-Log "Lock override bypassed via user prompt."
						}
						else {
							return $false
						}
					}
					else {
						return $false
					}
				}
				else {
					Write-Status "An old lock file was found (over 2 hours old). Proceeding..." -Type Info -ForegroundColor Gray
				}

			}
			catch {
				Write-Log "Error checking lock file: $($_.Exception.Message)"
				Write-Status "Error checking lock file: $($_.Exception.Message)" -ForegroundColor Red -Type Error
				return $false # Fail safe: if we can't check the lock, assume it's locked
			}
		}
		else {
			Write-Log "Lock override forced."
		}
	}

	try {
		Get-Date -Format "o" | Out-File -FilePath $LockFile -Encoding utf8 -ErrorAction Stop
		return $true
	}
	catch {
		Write-Log "Failed to create lock file: $($_.Exception.Message)"
		return $false
	}
}

Function Clear-Lock {
	if (Test-Path $LockFile) {
		Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
	}
}


Function Find-OnlineUpdate {
	param(
		[string]$CurrentVersion,
		[string]$RepoOwner = "ELowry",
		[string]$RepoName = "WinGet-Updater"
	)

	try {
		$apiUrl = "https://api.github.com/repos/$RepoOwner/$RepoName/releases/latest"
		$response = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 3 -ErrorAction Stop
		
		if ($null -eq $response -or $null -eq $response.tag_name) {
			return
		}

		$latestTag = $response.tag_name -replace "^v", ""
		$latestTagClean = $response.tag_name -replace "^v", ""
		if ($latestTagClean -notmatch "\.") { $latestTagClean += ".0" }

		$currentVerClean = $CurrentVersion -replace "^v", ""
		if ($currentVerClean -notmatch "\.") { $currentVerClean += ".0" }

		if ([System.Version]$latestTagClean -gt [System.Version]$currentVerClean) {
			Write-Status "`n[!] New version available: $($response.tag_name)" -ForegroundColor Yellow -Important
			Write-Status "    Download at: $($response.html_url)" -ForegroundColor Cyan -Important
			Write-Host ""
			Write-Host "Press Enter to continue..." -NoNewline -ForegroundColor Gray
			$null = Read-Host
			Write-Host ""
		}
	}
	catch {
		Write-Log "Failed to check for updates: $($_.Exception.Message)"
	}
}

Function Get-WinGetUpdate {
	Write-Status "Checking for available updates..." -Type Info -ForegroundColor Yellow
	Write-Log "Checking for WinGet updates."
	try {
		Write-Log "Updating WinGet sources..."
		Write-Status "Updating WinGet sources... (This may take a moment)" -Type Info -ForegroundColor Yellow

		$proc = Start-Process winget -ArgumentList "source update" -NoNewWindow -PassThru -Wait
		if ($proc.ExitCode -ne 0) {
			Write-Log "WinGet source update returned exit code $($proc.ExitCode)."
		}
		Write-Log "WinGet sources updated."

		Write-Log "Running 'winget upgrade' to find available updates."
		Write-Status "Querying for available package updates..." -Type Info -ForegroundColor Yellow
		[System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8
		$wingetOutput = winget upgrade | Where-Object {
			-not [string]::IsNullOrWhiteSpace($_)
		}

		$updates = @()

		$headerLine = $wingetOutput | Where-Object {
			$_ -like 'Name*Id*Version*'
		} | Select-Object -First 1
		$separatorLineIndex = -1
		for ($i = 0; $i -lt $wingetOutput.Count; $i++) {
			if ($wingetOutput[$i] -like '---*') {
				$separatorLineIndex = $i
				break
			}
		}

		if (-not $headerLine -or $separatorLineIndex -eq -1) {
			Write-Log "Could not find header or separator line in WinGet output. Assuming no updates."
			return @()
		}

		$idIndex = $headerLine.IndexOf('Id')
		$versionIndex = $headerLine.IndexOf('Version')
		$availableIndex = $headerLine.IndexOf('Available')
		$sourceIndex = $headerLine.IndexOf('Source')

		for ($i = $separatorLineIndex + 1; $i -lt $wingetOutput.Count; $i++) {
			$line = $wingetOutput[$i]
			if ($line.Length -lt $sourceIndex -or $line -like '*upgrades available*' -or $line -like '*cannot be determined*') {
				continue
			}

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
						AvailableVersion	= $available
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
		Write-Log "Error getting WinGet updates: $errorMessage"
		Write-Status "An error occurred while fetching updates. Check the log file for details." -ForegroundColor Red -Type Error
		return @()
	}
}