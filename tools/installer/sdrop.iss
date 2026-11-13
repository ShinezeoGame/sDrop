; Installateur Windows de sDrop (Inno Setup 6).
;
; Compilé par .github/workflows/build-windows.yml une fois l'application assemblée dans
; build\windows\x64\runner\Release :
;
;     ISCC.exe /DAppVersion=1.0.12 tools\installer\sdrop.iss
;
; L'installation se fait dans le profil de l'utilisateur : aucun droit d'administrateur requis.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{3E8A6F52-91C7-4D0E-A2B4-6C5F0D7E1A93}
AppName=sDrop
AppVersion={#AppVersion}
AppPublisher=ShinezeoGame
AppPublisherURL=https://github.com/ShinezeoGame/sDrop
DefaultDirName={autopf}\sDrop
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..
OutputBaseFilename=sdrop-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\sdrop.exe
UninstallDisplayName=sDrop
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Une mise à jour ferme sDrop avant de remplacer les fichiers.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\sDrop"; Filename: "{app}\sdrop.exe"
Name: "{autodesktop}\sDrop"; Filename: "{app}\sdrop.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\sdrop.exe"; Description: "{cm:LaunchProgram,sDrop}"; Flags: nowait postinstall skipifsilent
