; Inno Setup script for EditHub (Flutter Windows).
; Build: ISCC /DMyAppVersion=1.2.3 edithub.iss
; Bundles the entire Flutter Release folder (exe + DLLs + data) into one setup.

#define MyAppName "EditHub"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#define MyAppExe "edithub.exe"

[Setup]
; Keep AppId stable across versions so updates upgrade in place.
AppId={{7E5C1B9A-3D2F-4E8B-9C10-A1B2C3D4E5F6}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=EditHub
; Per-user install: no admin prompt, and WinSparkle can update without UAC.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\EditHub
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=EditHub-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExe}

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall
