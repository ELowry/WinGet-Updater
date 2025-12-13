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

Function Get-WinGetUpdate {
	Write-Status "Checking for available updates..." -Type Info
	Write-Log "Checking for WinGet updates."
	try {
		Write-Log "Updating WinGet sources..."
		Write-Status "Updating WinGet sources... (This may take a moment)" -Type Info
		
		$proc = Start-Process winget -ArgumentList "source update" -NoNewWindow -PassThru -Wait
		if ($proc.ExitCode -ne 0) {
			Write-Log "WinGet source update returned exit code $($proc.ExitCode)."
		}
		Write-Log "WinGet sources updated."

		Write-Log "Running 'winget upgrade' to find available updates."
		Write-Status "Querying for available package updates..." -Type Info
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
		Write-Log "Error getting WinGet updates: $errorMessage"
		Write-Status "An error occurred while fetching updates. Check the log file for details." -ForegroundColor Red -Type Error
		return @()
	}
}