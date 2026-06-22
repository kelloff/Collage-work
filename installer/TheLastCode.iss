; Inno Setup — The Last Code (Windows x64)
; Сборка: installer\build_release.ps1

#define MyAppName "The Last Code"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Collage Work"
#define MyAppExeName "TheLastCode.exe"
#define StagingDir "staging"
#define PythonVersion "3.12.10"
#define PythonInstallerFile "python-3.12.10-amd64.exe"

[Setup]
AppId={{A8F3C2E1-9B4D-4F6A-8E2C-1D5B7A9E3F40}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
DisableDirPage=no
AllowRootDirectory=yes
OutputDir=output
OutputBaseFilename=TheLastCode_Setup_{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
LicenseFile=LICENSE_RU.txt
InfoBeforeFile=SYSTEM_REQUIREMENTS_RU.txt
SetupIconFile=fav.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion=1.0.0.0
VersionInfoProductName={#MyAppName}
VersionInfoCompany={#MyAppPublisher}

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать значок на рабочем столе"; GroupDescription: "Дополнительно:"

[Files]
Source: "{#StagingDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "tools\{#PythonInstallerFile}"; DestDir: "{tmp}"; Flags: deleteafterinstall dontcopy

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Запустить {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Messages]
russian.WelcomeLabel2=Установка [name/ver] на ваш компьютер.%n%nСначала — лицензия и системные требования. Затем вы выберете папку установки и при необходимости — Python.
russian.LicenseLabel=Прочитайте лицензионное соглашение (русский и қазақша). Для продолжения нажмите «Принимаю».
russian.SelectDirLabel3=Выберите папку для установки игры. Нажмите «Обзор», чтобы указать другой диск или каталог (например, D:\Games).
russian.SelectDirBrowseLabel=Об&зор…

[Code]
var
  PythonPage: TWizardPage;
  PythonDescLabel: TNewStaticText;
  PythonInstallCheck: TNewCheckBox;
  PythonDetected: Boolean;
  PythonInstalledThisSession: Boolean;

function TryPythonCmd(const Args: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(ExpandConstant('{cmd}'), Args, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

function PythonExeOnDisk: Boolean;
var
  I: Integer;
  Paths: TArrayOfString;
begin
  SetArrayLength(Paths, 4);
  Paths[0] := ExpandConstant('{localappdata}\Programs\Python\Python312\python.exe');
  Paths[1] := ExpandConstant('{localappdata}\Programs\Python\Python311\python.exe');
  Paths[2] := ExpandConstant('{pf64}\Python312\python.exe');
  Paths[3] := ExpandConstant('{pf64}\Python311\python.exe');
  for I := 0 to GetArrayLength(Paths) - 1 do
  begin
    if FileExists(Paths[I]) then
    begin
      Result := True;
      Exit;
    end;
  end;
  Result := False;
end;

function DetectPython: Boolean;
begin
  Result := TryPythonCmd('/c py -3 --version') or
            TryPythonCmd('/c python --version') or
            PythonExeOnDisk;
end;

function ShouldInstallPython: Boolean;
begin
  Result := (not PythonDetected) and PythonInstallCheck.Checked;
end;

function InstallBundledPython: Boolean;
var
  ResultCode: Integer;
  InstallerPath: String;
begin
  ExtractTemporaryFile('{#PythonInstallerFile}');
  InstallerPath := ExpandConstant('{tmp}\{#PythonInstallerFile}');
  WizardForm.StatusLabel.Caption := 'Установка Python {#PythonVersion}...';
  WizardForm.ProgressGauge.Style := npbstMarquee;
  Result := Exec(
    InstallerPath,
    '/passive InstallAllUsers=0 PrependPath=1 Include_test=0 Include_pip=1',
    '',
    SW_SHOW,
    ewWaitUntilTerminated,
    ResultCode) and (ResultCode = 0);
  WizardForm.ProgressGauge.Style := npbstNormal;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  NeedsRestart := False;
  PythonInstalledThisSession := False;

  if not ShouldInstallPython then
    Exit;

  if not InstallBundledPython then
  begin
    Result :=
      'Не удалось установить Python {#PythonVersion}.' + #13#10#13#10 +
      'Скачайте Python 3.8+ с https://www.python.org/downloads/ ' +
      '(включите «Add python.exe to PATH») и повторите установку игры.';
    Exit;
  end;

  PythonInstalledThisSession := True;

  if not (DetectPython or PythonExeOnDisk) then
  begin
    Result :=
      'Python установлен, но ещё не виден в PATH в этой сессии.' + #13#10#13#10 +
      'Закройте установщик, перезапустите его (или перезагрузите ПК) и установите игру снова.';
    Exit;
  end;

  PythonDetected := True;
end;

procedure InitializeWizard;
begin
  PythonDetected := DetectPython;
  PythonInstalledThisSession := False;

  PythonPage := CreateCustomPage(
    wpSelectDir,
    'Python',
    'Проверка Python для терминала в игре');

  PythonDescLabel := TNewStaticText.Create(PythonPage);
  PythonDescLabel.Parent := PythonPage.Surface;
  PythonDescLabel.Left := 0;
  PythonDescLabel.Top := 0;
  PythonDescLabel.Width := PythonPage.SurfaceWidth;
  PythonDescLabel.AutoSize := False;
  PythonDescLabel.Height := 150;

  PythonInstallCheck := TNewCheckBox.Create(PythonPage);
  PythonInstallCheck.Parent := PythonPage.Surface;
  PythonInstallCheck.Left := 0;
  PythonInstallCheck.Top := 160;
  PythonInstallCheck.Width := PythonPage.SurfaceWidth;

  if PythonDetected then
  begin
    PythonDescLabel.Caption :=
      'Python обнаружен в системе (команда py -3, python или установка в стандартной папке).' + #13#10#13#10 +
      'Терминал в игре сможет запускать и проверять ваш код.' + #13#10#13#10 +
      'Дополнительная установка Python не требуется — далее будет установлена игра в выбранную папку.';
    PythonInstallCheck.Caption := 'Установить Python повторно (не нужно)';
    PythonInstallCheck.Checked := False;
    PythonInstallCheck.Enabled := False;
  end
  else
  begin
    PythonDescLabel.Caption :=
      'Python не найден.' + #13#10#13#10 +
      'Без Python терминал не сможет проверять код — кнопка «Проверить решение» работать не будет. ' +
      'Остальная игра (движение, сюжет, журнал) доступна.' + #13#10#13#10 +
      'Рекомендуем установить Python {#PythonVersion} с python.org (в PATH). ' +
      'Установщик Python встроен — он запустится до копирования файлов игры.';
    PythonInstallCheck.Caption :=
      'Установить Python {#PythonVersion} сейчас (рекомендуется, с python.org)';
    PythonInstallCheck.Checked := True;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (PythonPage <> nil) and (CurPageID = PythonPage.ID) then
  begin
    if (not PythonDetected) and (not PythonInstallCheck.Checked) then
    begin
      if MsgBox(
        'Без Python терминал в игре не сможет проверять ваш код.' + #13#10#13#10 +
        'Продолжить установку только игры, без Python?',
        mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDNO then
        Result := False;
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if PythonInstalledThisSession then
    begin
      MsgBox(
        'Python {#PythonVersion} установлен.' + #13#10#13#10 +
        'Если терминал в игре не увидит Python сразу — перезапустите игру или выйдите из Windows и войдите снова.',
        mbInformation, MB_OK);
    end;
  end;
end;
