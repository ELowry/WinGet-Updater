[Setup]
AppName=WinGet Updater
AppVersion=1.1.3
DefaultDirName={tmp}\WingetUpdaterInstaller
UsePreviousAppDir=no
PrivilegesRequired=admin
OutputBaseFilename=WingetUpdaterSetup
Compression=lzma
SolidCompression=yes
Uninstallable=no
CreateUninstallRegKey=no
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableWelcomePage=yes
DisableReadyPage=yes
DisableFinishedPage=yes

[Files]
Source: "..\winget-updater-core\winget-updater.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\configure.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\uninstall.ps1"; DestDir: "{tmp}"; Flags: ignoreversion
Source: "..\winget-updater-core\launcher.bat"; DestDir: "{tmp}"; Flags: ignoreversion

[Tasks]
Name: "startup"; Description: "Run automatically at system startup"; GroupDescription: "Automation:"; Flags: unchecked
Name: "wake"; Description: "Run automatically when system wakes or unlocks"; GroupDescription: "Automation:"; Flags: unchecked

[Run]
[Code]
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
    Params := '-ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\configure.ps1') + '" ' + GetParams('');
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
