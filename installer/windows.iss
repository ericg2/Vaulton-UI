#ifndef AppVersion
#define AppVersion "1.0.0"
#endif

[Setup]
AppId={{F3E56C20-1F43-4B63-9E8A-3D0C1B25C6E2}
AppName=Vaulton
AppVersion={#AppVersion}
AppPublisher=Eric G2
DefaultDirName={localappdata}\Programs\Vaulton
DefaultGroupName=Vaulton
UninstallDisplayIcon={app}\vaulton.exe
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
OutputDir=..\..\build\release-assets
OutputBaseFilename=Vaulton-Windows-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Vaulton"; Filename: "{app}\vaulton.exe"
Name: "{autodesktop}\Vaulton"; Filename: "{app}\vaulton.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\vaulton.exe"; Description: "Launch Vaulton"; Flags: postinstall nowait skipifsilent
