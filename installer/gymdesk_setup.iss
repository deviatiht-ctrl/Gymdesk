; GymDesk V3 Inno Setup Script
; Pwodui enstalatè Windows GymDesk pou PC resepsyon / laptop

#define MyAppName "GymDesk"
#define MyAppVersion "3.0.0"
#define MyAppPublisher "GymDesk Systems"
#define MyAppURL "https://gymdesk.ht"
#define MyAppExeName "gym_desk.exe"

[Setup]
AppId={{C78DF6B1-3A58-45F2-9214-E48A96213D71}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=
OutputDir=Output
OutputBaseFilename=GymDesk-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Access agent and helper scripts
Source: "..\build\windows\x64\runner\Release\access_agent.exe"; DestDir: "{app}"; Flags: ignoreversion; Tasks: 
Source: "..\build\windows\x64\runner\Release\start_gymdesk.bat"; DestDir: "{app}"; Flags: ignoreversion; Tasks: 

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\GymDesk Access Agent"; Filename: "{app}\access_agent.exe"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\start_gymdesk.bat"; Description: "Demare GymDesk ak Sèvis Anprent la"; Flags: nowait postinstall skipifsilent
