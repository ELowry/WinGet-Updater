#include "version.isi"

[Setup]
AppName=WinGet Updater
AppVersion={#AppVersion}
VersionInfoProductVersion={#AppVersion}
VersionInfoVersion={#AppVersion}
AppPublisher=Eric Lowry
AppPublisherURL=https://github.com/ELowry/WinGet-Updater
AppSupportURL=https://github.com/ELowry/WinGet-Updater/issues
AppUpdatesURL=https://github.com/ELowry/WinGet-Updater/releases
AppCopyright=Copyright 2025 Eric Lowry
VersionInfoCompany=Eric Lowry
VersionInfoDescription=WinGet Updater Installer
VersionInfoProductName=WinGet Updater
DefaultDirName={tmp}\WinGetUpdaterInstaller
UsePreviousAppDir=no
PrivilegesRequired=admin
OutputBaseFilename=WinGetUpdaterSetup
Compression=lzma
SolidCompression=yes
Uninstallable=no
CreateUninstallRegKey=no
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableWelcomePage=yes
DisableReadyPage=yes
DisableFinishedPage=yes
WizardStyle=modern
SetupIconFile=..\winget-updater-core\winget-updater.ico

[Files]
Source: "version.isi"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\winget-updater.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\scheduled-updater.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\utils.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\configure.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\uninstall.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\launcher.bat"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\silent.vbs"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\winget-updater.ico"; DestDir: "{tmp}"; Flags: ignoreversion

[Tasks]
Name: "startup"; Description: "Run automatically at system startup"; GroupDescription: "Automation:"
Name: "wake"; Description: "Run automatically when system wakes or unlocks"; GroupDescription: "Automation:"; Flags: unchecked
Name: "installonly"; Description: "Silent Mode (Only install [A]lways updates automatically)"; GroupDescription: "Automation:"; Flags: unchecked

[Run]
[Code]
function TryGetConfigValue(Name: String; var IsChecked: Boolean): Boolean;
var
	ValueData: Cardinal;
begin
	Result := False;
	if RegQueryDWordValue(HKEY_CURRENT_USER, 'Software\EricLowry\WingetUpdater\Config', Name, ValueData) then
	begin
		Result := True;
		IsChecked := (ValueData = 1);
	end;
end;

procedure TasksListClickCheck(Sender: TObject);
var
	I: Integer;
	StartupChecked, WakeChecked: Boolean;
	SilentIndex: Integer;
	Caption: String;
begin
	StartupChecked := False;
	WakeChecked := False;
	SilentIndex := -1;

	for I := 0 to WizardForm.TasksList.Items.Count - 1 do
	begin
		Caption := LowerCase(WizardForm.TasksList.ItemCaption[I]);
		if (Pos('system startup', Caption) > 0) then
		begin
			if WizardForm.TasksList.Checked[I] then StartupChecked := True;
		end
		else if (Pos('system wakes', Caption) > 0) then
		begin
			if WizardForm.TasksList.Checked[I] then WakeChecked := True;
		end
		else if (Pos('silent mode', Caption) > 0) then
		begin
			SilentIndex := I;
		end;
	end;

	if SilentIndex <> -1 then
	begin
		if (not StartupChecked) and (not WakeChecked) then
		begin
				WizardForm.TasksList.ItemEnabled[SilentIndex] := False;
				WizardForm.TasksList.Checked[SilentIndex] := False;
		end
		else
		begin
				WizardForm.TasksList.ItemEnabled[SilentIndex] := True;
		end;
	end;
end;

procedure InitializeWizard;
begin
	WizardForm.TasksList.OnClickCheck := @TasksListClickCheck;
end;

var
	TasksInitialized: Boolean;

procedure CurPageChanged(CurPageID: Integer);
var
	I: Integer;
	Caption: String;
	RegState: Boolean;
begin
	if (CurPageID = wpSelectTasks) and (not TasksInitialized) then
	begin
	for I := 0 to WizardForm.TasksList.Items.Count - 1 do
	begin
		Caption := LowerCase(WizardForm.TasksList.ItemCaption[I]);
		if (Pos('startup', Caption) > 0) then
		begin
			if TryGetConfigValue('AutoStartup', RegState) then
				WizardForm.TasksList.Checked[I] := RegState;
		end
		else if (Pos('wake', Caption) > 0) then
		begin
			if TryGetConfigValue('AutoWake', RegState) then
				WizardForm.TasksList.Checked[I] := RegState;
		end
		else if (Pos('silent', Caption) > 0) then
		begin
			if TryGetConfigValue('AutoInstallOnly', RegState) then
				WizardForm.TasksList.Checked[I] := RegState;
		end;
	end;
	TasksInitialized := True;
	TasksListClickCheck(WizardForm.TasksList);
end;
end;

function GetParams(Param: String): String;
begin
	Result := '-Unattended';
	if WizardIsTaskSelected('startup') then
		Result := Result + ' -EnableStartup';
	if WizardIsTaskSelected('wake') then
		Result := Result + ' -EnableWake';
	if WizardIsTaskSelected('installonly') then
		Result := Result + ' -InstallOnly';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
	ResultCode: Integer;
	Params: String;
begin
	if CurStep = ssPostInstall then
	begin
		Params := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\configure.ps1') + '" ' + GetParams('');
		if not Exec('powershell.exe', Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
		begin
			MsgBox('Failed to launch configuration script.', mbError, MB_OK);
		end
		else if ResultCode <> 0 then
		begin
			MsgBox('Configuration script failed with exit code: ' + IntToStr(ResultCode) + #13#10 + 'Please check the installation log.', mbError, MB_OK);
		end;
	end;
end;
