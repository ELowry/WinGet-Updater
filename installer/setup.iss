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

[Files]
Source: "version.isi"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\winget-updater.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\scheduled-updater.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\utils.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\configure.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\uninstall.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\launcher.bat"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\silent.vbs"; DestDir: "{tmp}"; Flags: ignoreversion

[Tasks]
Name: "startup"; Description: "Run automatically at system startup"; GroupDescription: "Automation:"
Name: "wake"; Description: "Run automatically when system wakes or unlocks"; GroupDescription: "Automation:"

[Run]
[Code]
function ShouldCheckStartup: Boolean;
var
  ValueData: Cardinal;
begin
  Result := True;
  if RegQueryDWordValue(HKEY_CURRENT_USER, 'Software\EricLowry\WingetUpdater\Config', 'AutoStartup', ValueData) then
  begin
    Result := (ValueData = 1);
  end;
end;

function ShouldCheckWake: Boolean;
var
  ValueData: Cardinal;
begin
  Result := False;
  if RegQueryDWordValue(HKEY_CURRENT_USER, 'Software\EricLowry\WingetUpdater\Config', 'AutoWake', ValueData) then
  begin
    Result := (ValueData = 1);
  end;
end;

procedure InitializeWizard;
var
  I: Integer;
begin
for I := 0 to WizardForm.TasksList.Items.Count - 1 do
  begin
    if Pos('startup', LowerCase(WizardForm.TasksList.ItemCaption[I])) > 0 then
      WizardForm.TasksList.Checked[I] := ShouldCheckStartup
    else if Pos('wake', LowerCase(WizardForm.TasksList.ItemCaption[I])) > 0 then
      WizardForm.TasksList.Checked[I] := ShouldCheckWake;
  end;
end;

function GetParams(Param: String): String;
begin
  Result := '-Unattended';
  if WizardIsTaskSelected('startup') then
    Result := Result + ' -EnableStartup';
  if WizardIsTaskSelected('wake') then
    Result := Result + ' -EnableWake';
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
