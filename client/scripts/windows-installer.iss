; Inno Setup 6. AppVersion, AppArch, BundleDir and OutputDir are provided by package-windows.ps1.
[Setup]
AppId={{A0D8675F-6BE2-49A8-80CF-7C1C5CE1DA0F}
AppName=未来画布
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\未来画布
DefaultGroupName=未来画布
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=huabu-{#AppVersion}-windows-{#AppArch}-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\huabu_app.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
#if AppArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\未来画布"; Filename: "{app}\huabu_app.exe"

[Run]
Filename: "{app}\huabu_app.exe"; Description: "启动未来画布"; Flags: nowait postinstall skipifsilent
