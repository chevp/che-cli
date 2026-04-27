; ============================================================================
;  che-cli — Inno Setup installer
;
;  Builds a Windows installer that:
;    • Copies bin\che + the lib\che tree into the install folder
;    • Drops che.bat / che.ps1 wrappers next to bin\che
;    • Bundles installer\lib\install-deps.ps1 (the dep bootstrapper)
;    • Adds <install>\bin to PATH (user or system, matching install mode)
;    • Optionally installs Git, Python, Ollama and pulls the default model
;      via install-deps.ps1
;    • Cleans up PATH on uninstall
;
;  Build with:   .\build.ps1     (or ISCC.exe che-cli.iss)
;  Output:       installer\Output\che-cli-<version>-setup.exe
; ============================================================================

#define MyAppName       "che-cli"
#define MyAppVersion    "0.2.0"
#define MyAppPublisher  "chevp"
#define MyAppURL        "https://chevp.github.io/che-cli/"
#define MyAppExeName    "che.bat"

[Setup]
AppId={{4E5C8D71-3B2A-4F8E-9C12-CHE01F7A4B11}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\che
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
DisableDirPage=no
OutputDir=Output
OutputBaseFilename=che-cli-{#MyAppVersion}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ChangesEnvironment=yes
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\bin\che.bat

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "modifypath";  Description: "Add che to PATH (recommended)"; GroupDescription: "Environment:"
Name: "installdeps"; Description: "Install missing dependencies (Git for Windows, Python 3, Ollama)"; GroupDescription: "Dependencies:"
Name: "installdeps\pullmodel"; Description: "Also pull the default Ollama model (llama3.2 — several GB)"; GroupDescription: "Dependencies:"; Flags: unchecked

[Files]
; Dispatcher and library tree
Source: "..\bin\che";              DestDir: "{app}\bin"; Flags: ignoreversion
Source: "..\lib\che\*";            DestDir: "{app}\lib\che"; Flags: ignoreversion recursesubdirs createallsubdirs

; Windows wrappers
Source: "wrappers\che.bat";        DestDir: "{app}\bin"; Flags: ignoreversion
Source: "wrappers\che.ps1";        DestDir: "{app}\bin"; Flags: ignoreversion

; Dependency bootstrapper (used by post-install [Run] step)
Source: "lib\install-deps.ps1";    DestDir: "{app}\installer\lib"; Flags: ignoreversion

; Helpful extras
Source: "..\README.md";            DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\{#MyAppName} (cmd)";    Filename: "{cmd}"; Parameters: "/k ""{app}\bin\che.bat"" doctor"; WorkingDir: "{app}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"

[Run]
; Install missing deps in a VISIBLE console so the user can see winget /
; ollama progress. {code:GetDepsArgs} adds -NoModel unless the "pullmodel"
; sub-task is checked. We deliberately do NOT use 'runhidden' here -- winget
; and 'ollama pull' both print non-newline progress that blocks any pipe;
; letting the console show through is the most reliable UX.
Filename: "powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\lib\install-deps.ps1"" {code:GetDepsArgs}"; \
  StatusMsg: "Installing dependencies (Git, Python, Ollama) -- see console window..."; \
  Flags: waituntilterminated; \
  Tasks: installdeps

; Final visible verification step.
Filename: "{cmd}"; Parameters: "/c ""{app}\bin\che.bat"" doctor & pause"; \
  Description: "Run che doctor now"; \
  Flags: postinstall skipifsilent shellexec runasoriginaluser

[Code]
const
  EnvUserKey   = 'Environment';
  EnvSystemKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';

function IsSystemInstall(): Boolean;
begin
  Result := IsAdminInstallMode();
end;

function GetEnvHive(): Integer;
begin
  if IsSystemInstall() then
    Result := HKEY_LOCAL_MACHINE
  else
    Result := HKEY_CURRENT_USER;
end;

function GetEnvKey(): String;
begin
  if IsSystemInstall() then
    Result := EnvSystemKey
  else
    Result := EnvUserKey;
end;

function ReadEnvPath(): String;
var
  S: String;
begin
  S := '';
  if not RegQueryStringValue(GetEnvHive(), GetEnvKey(), 'Path', S) then
    S := '';
  Result := S;
end;

function WriteEnvPath(const NewValue: String): Boolean;
begin
  Result := RegWriteExpandStringValue(GetEnvHive(), GetEnvKey(), 'Path', NewValue);
end;

function PathContainsDir(const PathStr, Dir: String): Boolean;
var
  Padded, NeedlePadded: String;
begin
  Padded       := ';' + Lowercase(PathStr) + ';';
  NeedlePadded := ';' + Lowercase(Dir) + ';';
  Result := Pos(NeedlePadded, Padded) > 0;
end;

procedure AddBinToPath();
var
  BinDir, Cur, NewVal: String;
begin
  BinDir := ExpandConstant('{app}\bin');
  Cur    := ReadEnvPath();
  if PathContainsDir(Cur, BinDir) then
    Exit;
  if (Length(Cur) > 0) and (Cur[Length(Cur)] <> ';') then
    NewVal := Cur + ';' + BinDir
  else
    NewVal := Cur + BinDir;
  if not WriteEnvPath(NewVal) then
    MsgBox('Failed to update PATH. You may need to add ' + BinDir + ' manually.',
           mbInformation, MB_OK);
end;

procedure RemoveBinFromPath();
var
  BinDir, Cur, NewVal, Token: String;
  Padded, LowerPadded: String;
  P: Integer;
begin
  BinDir := ExpandConstant('{app}\bin');
  Cur    := ReadEnvPath();
  if Cur = '' then
    Exit;

  Padded      := ';' + Cur + ';';
  LowerPadded := ';' + Lowercase(Cur) + ';';
  Token       := ';' + Lowercase(BinDir) + ';';

  P := Pos(Token, LowerPadded);
  if P = 0 then
    Exit;

  Delete(Padded, P, Length(Token) - 1);

  NewVal := Padded;
  if (Length(NewVal) > 0) and (NewVal[1] = ';') then
    Delete(NewVal, 1, 1);
  if (Length(NewVal) > 0) and (NewVal[Length(NewVal)] = ';') then
    Delete(NewVal, Length(NewVal), 1);

  WriteEnvPath(NewVal);
end;

function GetDepsArgs(Param: String): String;
begin
  // install-deps.ps1 args: always -AssumeYes (silent install context);
  // add -NoModel unless the "pullmodel" sub-task is checked.
  Result := '-AssumeYes';
  if not WizardIsTaskSelected('installdeps\pullmodel') then
    Result := Result + ' -NoModel';
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if WizardIsTaskSelected('modifypath') then
      AddBinToPath();
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    RemoveBinFromPath();
end;
