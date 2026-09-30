; Windows installer. Built by .github/workflows/release.yml after
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

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName "Meow Chess"
#define AppExe "meow_chess.exe"
#define BundleDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{CD658FF7-A9DD-4ECA-9E13-9E8F07BABCEF}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Meow Chess
AppPublisherURL=https://github.com/Zinkelburger/Meow-Chess
AppSupportURL=https://github.com/Zinkelburger/Meow-Chess/issues
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=meow-chess-{#AppVersion}-windows-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ChangesAssociations=yes
CloseApplications=yes

[Tasks]
Name: "meow"; Description: "Open .meow tournament files with {#AppName}"; GroupDescription: "File associations:"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
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
Root: HKCU; Subkey: "Software\Classes\.meow"; ValueType: string; ValueData: "MeowChess.Tournament"; Tasks: meow; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\.meow\OpenWithProgids"; ValueType: string; ValueName: "MeowChess.Tournament"; ValueData: ""; Tasks: meow; Flags: uninsdeletevalue

; Lets Windows list the app by name in "Open with" and Default apps.
Root: HKCU; Subkey: "Software\Classes\Applications\{#AppExe}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "{#AppName}"; Tasks: meow; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Applications\{#AppExe}\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: meow
Root: HKCU; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".meow"; ValueData: ""; Tasks: meow

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
