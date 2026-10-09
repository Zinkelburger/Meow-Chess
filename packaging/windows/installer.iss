; Windows installer. Built by .github/workflows/windows-build.yml after
; `flutter build windows --release`:
;
;   ISCC.exe /DAppVersion=0.2.0 packaging\windows\installer.iss
;
; Per-user install under %LocalAppData%\Programs, so Setup never asks for an
; administrator password. The Visual C++ runtime is already beside the exe
; (windows/CMakeLists.txt deploys it app-locally), so there is no
; prerequisite to install.
;
; Adds a Start Menu entry, an uninstaller in Settings > Apps, and (on by
; default) the .meow association. The association keys are the same ones the
; app writes for itself when run from the zip
; (windows/runner/desktop_integration.cpp); the choice recorded here is what
; stops the installed app from asking again.
;
; Tournament data lives in %APPDATA%\org.meowchess\Meow Chess, outside {app},
; so upgrading or uninstalling never touches a TD's events.
; scripts/test_windows_installer.ps1 checks the upgrade and uninstall paths.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName "Meow Chess"
#define AppExe "meow_chess.exe"
#define BundleDir "..\..\build\windows\x64\runner\Release"
; Running is held by every running copy (windows/runner/single_instance.cpp),
; Instance by the one that owns the session, which is all older builds hold.
#define InstanceMutex "Local\MeowChess.Instance,Local\MeowChess.Running"

; File version resources take numbers only: 1.2.0-rc1 is 1.2.0 there, as in
; the app's own --build-name.
#define DashPos Pos("-", AppVersion)
#if DashPos > 0
  #define NumericVersion Copy(AppVersion, 1, DashPos - 1)
#else
  #define NumericVersion AppVersion
#endif

[Setup]
AppId={{CD658FF7-A9DD-4ECA-9E13-9E8F07BABCEF}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Meow Chess
AppPublisherURL=https://github.com/Zinkelburger/Meow-Chess
AppSupportURL=https://github.com/Zinkelburger/Meow-Chess/issues
AppCopyright=Copyright (C) 2026 Meow Chess contributors. Licensed under the GNU AGPLv3.
VersionInfoVersion={#NumericVersion}
VersionInfoProductTextVersion={#AppVersion}
VersionInfoDescription={#AppName} Setup
; Flutter supports Windows 10 and later; refuse older systems up front rather
; than install an app that cannot start.
MinVersion=10.0
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=meow-chess-{#AppVersion}-windows-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
; Settings > Apps shows the version in its own column.
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ChangesAssociations=yes
; An upgrade closes a running copy through Restart Manager; the uninstaller
; has no such step, so InitializeUninstall below waits for the TD instead.
CloseApplications=yes
; One Setup at a time, so a double-clicked download cannot race itself.
SetupMutex=MeowChessSetup,Global\MeowChessSetup

[Tasks]
Name: "meow"; Description: "Open .meow tournament files with {#AppName}"; GroupDescription: "File associations:"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Start every upgrade from a clean bundle, so a plugin DLL or asset that a
; newer release no longer ships cannot linger beside the new files.
Type: filesandordirs; Name: "{app}\data"
Type: files; Name: "{app}\*.dll"
; Releases through 1.2.2 put the shortcut in a Start menu folder of its own.
Type: filesandordirs; Name: "{autoprograms}\{#AppName}"

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; One app, one shortcut: straight in the Start menu's All list, no folder.
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; The app's own first-run offer reads this; the installer has already asked.
Root: HKCU; Subkey: "Software\MeowChess"; ValueType: string; ValueName: "FileAssociationChoice"; ValueData: "yes"; Tasks: meow; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\MeowChess"; ValueType: string; ValueName: "FileAssociationChoice"; ValueData: "no"; Tasks: not meow; Flags: uninsdeletekey

; ProgID for the type.
Root: HKCU; Subkey: "Software\Classes\MeowChess.Tournament"; ValueType: string; ValueData: "Meow Chess tournament"; Tasks: meow; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\MeowChess.Tournament\DefaultIcon"; ValueType: string; ValueData: """{app}\{#AppExe}"",0"; Tasks: meow
Root: HKCU; Subkey: "Software\Classes\MeowChess.Tournament\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: meow

; .meow is ours: make it the extension's default and list it under "Open
; with". Windows keeps a default the user picked themselves ahead of both.
; Uninstall removes only our values, then the keys once nothing else is left.
Root: HKCU; Subkey: "Software\Classes\.meow"; ValueType: string; ValueData: "MeowChess.Tournament"; Tasks: meow; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKCU; Subkey: "Software\Classes\.meow\OpenWithProgids"; ValueType: string; ValueName: "MeowChess.Tournament"; ValueData: ""; Tasks: meow; Flags: uninsdeletevalue uninsdeletekeyifempty

; Lets Windows list the app by name in "Open with" and Default apps.
Root: HKCU; Subkey: "Software\Classes\Applications\{#AppExe}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "{#AppName}"; Tasks: meow; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Applications\{#AppExe}\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: meow
Root: HKCU; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".meow"; ValueData: ""; Tasks: meow

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// A running copy holds meow_chess.exe open, and uninstalling around it
// leaves the exe and folder behind. Wait until the TD closes it; a silent
// uninstall (/SUPPRESSMSGBOXES) answers Cancel and stops cleanly instead.
function InitializeUninstall(): Boolean;
begin
  Result := True;
  while CheckForMutexes('{#InstanceMutex}') do
  begin
    if SuppressibleMsgBox('{#AppName} is still open. Close it, then click Retry to finish uninstalling.',
        mbError, MB_RETRYCANCEL, IDCANCEL) <> IDRETRY then
    begin
      Result := False;
      Exit;
    end;
  end;
end;
