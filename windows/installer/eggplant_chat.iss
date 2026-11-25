#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef BuildRevision
  #define BuildRevision "local"
#endif

[Setup]
AppId={{7BD3D219-9148-476C-81E0-B53152B544E4}
AppName=EggplantChat
AppVersion={#AppVersion}
AppPublisher=uniquejava
AppPublisherURL=https://github.com/uniquejava/EggplantChat
DefaultDirName={localappdata}\Programs\EggplantChat
DefaultGroupName=EggplantChat
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=EggplantChat-{#AppVersion}-{#BuildRevision}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\eggplant_chat.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\EggplantChat"; Filename: "{app}\eggplant_chat.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\EggplantChat"; Filename: "{app}\eggplant_chat.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\eggplant_chat.exe"; Description: "Launch EggplantChat"; Flags: nowait postinstall skipifsilent
