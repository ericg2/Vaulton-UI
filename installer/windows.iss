#ifndef AppVersion
#define AppVersion "1.0.0"
#endif

[Setup]
AppId={{F3E56C20-1F43-4B63-9E8A-3D0C1B25C6E2}
AppName=Vaulton
AppVersion={#AppVersion}
AppPublisher=Eric E. Gold
AppPublisherURL=https://github.com/ericg2/Vaulton-UI
AppContact=97804381+ericg2@users.noreply.github.com
AppSupportURL=https://github.com/ericg2/Vaulton-UI/issues
AppUpdatesURL=https://github.com/ericg2/Vaulton-UI/releases
AppCopyright=Copyright (C) 2026 Eric E. Gold
VersionInfoCompany=Eric E. Gold
VersionInfoCopyright=Copyright (C) 2026 Eric E. Gold
VersionInfoDescription=Vaulton installer
VersionInfoVersion={#AppVersion}.0
VersionInfoProductName=Vaulton
VersionInfoProductVersion={#AppVersion}
VersionInfoProductTextVersion={#AppVersion}
VersionInfoTextVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\Vaulton
DefaultGroupName=Vaulton
UninstallDisplayIcon={app}\vaulton.exe
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
OutputDir=..\build\release-assets
OutputBaseFilename=vaulton-{#AppVersion}-windows-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Vaulton"; Filename: "{app}\vaulton.exe"
Name: "{autodesktop}\Vaulton"; Filename: "{app}\vaulton.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\vaulton.exe"; Description: "Launch Vaulton"; Flags: postinstall nowait skipifsilent
