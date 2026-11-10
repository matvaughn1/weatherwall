; Inno Setup script for Live Weather on Windows (built by .github/workflows/release.yml).
;   iscc /DSrcDir=path\to\deployed\app /DAppVersion=1.1.4 installer.iss
#ifndef AppVersion
  #define AppVersion "1.1.4"
#endif

[Setup]
AppId={{6A3C0F5E-2B7D-4C1E-9F43-7E0B5D8A1C2F}
AppName=Live Weather
AppVersion={#AppVersion}
AppPublisher=Mat Vaughn
AppPublisherURL=https://github.com/matvaughn1/weatherwall
DefaultDirName={localappdata}\Programs\Live Weather
DefaultGroupName=Live Weather
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=LiveWeather-{#AppVersion}-Windows-Setup
SetupIconFile=..\icons\app.ico
UninstallDisplayIcon={app}\Live Weather.exe
Compression=lzma2/fast
SolidCompression=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern

[Tasks]
Name: "autostart"; Description: "Start Live Weather when I log in"; Flags: checkedonce

[Files]
Source: "{#SrcDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\Live Weather"; Filename: "{app}\Live Weather.exe"
Name: "{group}\Uninstall Live Weather"; Filename: "{uninstallexe}"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Live Weather"; \
    ValueData: """{app}\Live Weather.exe"""; Tasks: autostart; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "Live Weather"; \
    Flags: uninsdeletevalue dontcreatekey

[Run]
Filename: "{app}\Live Weather.exe"; Description: "Start Live Weather now"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "taskkill"; Parameters: "/im ""Live Weather.exe"" /f"; Flags: runhidden; RunOnceId: "StopApp"
