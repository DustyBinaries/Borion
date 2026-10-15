unit BorionOs;

(*
  Borion — Native Application Engine
  Plugin "os": informações do sistema operacional (como o plugin os do Tauri).

    Ipc.AddPlugin(TBorionOsPlugin.Create);

  Comando:
    os:info -> {platform, family, type, arch, processArch, version, build,
                displayVersion, name, locale, hostname, eol, exeExtension}

    platform/family/type  'windows'
    arch                  arquitetura do Windows: 'x86_64', 'aarch64', 'x86', 'arm'
    processArch           a do processo: 'x86' (o Delphi 7 só gera 32 bits)
    version / build       '10.0.22631' / 22631 (a versão real, sem o "modo de
                          compatibilidade" do GetVersionEx)
    displayVersion        '23H2' ('' em versões antigas)
    name                  'Windows 11 Pro'
    locale                'pt-BR' (BCP 47), ou null
    hostname              nome DNS do computador
    eol / exeExtension    #13#10 / 'exe'
*)

interface

uses
  Windows, SysUtils, Classes, Registry, Jsons, BorionIpc;

type
  TBorionOsInfo = record
    Arch: string;
    ProcessArch: string;
    Version: string;
    Build: Integer;
    DisplayVersion: string;
    Name: string;
    Locale: string;
    Hostname: string;
  end;

  TBorionOsPlugin = class(TBorionPlugin)
  private
    procedure CmdInfo(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    function Name: string; override;
  end;

function BorionOsInfo: TBorionOsInfo;

implementation

type
  TRtlOsVersionInfo = record
    dwOSVersionInfoSize: DWORD;
    dwMajorVersion: DWORD;
    dwMinorVersion: DWORD;
    dwBuildNumber: DWORD;
    dwPlatformId: DWORD;
    szCSDVersion: array[0..127] of WideChar;
  end;

  TRtlGetVersion = function(var Info: TRtlOsVersionInfo): Longint; stdcall;
  TIsWow64Process2 = function(Process: THandle; var ProcessMachine, NativeMachine: Word): BOOL; stdcall;
  TGetNativeSystemInfo = procedure(var Info: TSystemInfo); stdcall;
  TGetUserDefaultLocaleName = function(Name: PWideChar; Size: Integer): Integer; stdcall;
  TGetComputerNameEx = function(NameType: Integer; Buffer: PChar; var Size: DWORD): BOOL; stdcall;

const
  IMAGE_FILE_MACHINE_I386 = $014C;
  IMAGE_FILE_MACHINE_AMD64 = $8664;
  IMAGE_FILE_MACHINE_ARM64 = $AA64;
  IMAGE_FILE_MACHINE_ARMNT = $01C4;
  PROCESSOR_ARCHITECTURE_AMD64 = 9;
  PROCESSOR_ARCHITECTURE_ARM64 = 12;
  PROCESSOR_ARCHITECTURE_ARM_ = 5;
  PROCESSOR_ARCHITECTURE_INTEL = 0;
  ComputerNameDnsHostname = 1;
  LOCALE_NAME_MAX_LENGTH = 85;
  KEY_WOW64_64KEY = $0100;

function Proc(const Dll, Nome: string): Pointer;
begin
  Result := GetProcAddress(GetModuleHandle(PChar(Dll)), PChar(Nome));
end;

function Arquitetura: string;
var
  IsWow64Process2: TIsWow64Process2;
  GetNativeSystemInfo: TGetNativeSystemInfo;
  DoProcesso, Nativa: Word;
  Info: TSystemInfo;
begin
  { IsWow64Process2 (Windows 10 1511+) é o único que não mente num Windows ARM64 }
  @IsWow64Process2 := Proc(kernel32, 'IsWow64Process2');
  if Assigned(IsWow64Process2) and IsWow64Process2(GetCurrentProcess, DoProcesso, Nativa) then
    case Nativa of
      IMAGE_FILE_MACHINE_AMD64: Result := 'x86_64';
      IMAGE_FILE_MACHINE_ARM64: Result := 'aarch64';
      IMAGE_FILE_MACHINE_ARMNT: Result := 'arm';
      IMAGE_FILE_MACHINE_I386: Result := 'x86';
    else
      Result := 'unknown';
    end
  else
  begin
    @GetNativeSystemInfo := Proc(kernel32, 'GetNativeSystemInfo');
    if Assigned(GetNativeSystemInfo) then
      GetNativeSystemInfo(Info)
    else
      GetSystemInfo(Info);
    case Info.wProcessorArchitecture of
      PROCESSOR_ARCHITECTURE_AMD64: Result := 'x86_64';
      PROCESSOR_ARCHITECTURE_ARM64: Result := 'aarch64';
      PROCESSOR_ARCHITECTURE_ARM_: Result := 'arm';
      PROCESSOR_ARCHITECTURE_INTEL: Result := 'x86';
    else
      Result := 'unknown';
    end;
  end;
end;

function Idioma: string;
var
  GetUserDefaultLocaleName: TGetUserDefaultLocaleName;
  Buf: array[0..LOCALE_NAME_MAX_LENGTH] of WideChar;
begin
  Result := '';
  @GetUserDefaultLocaleName := Proc(kernel32, 'GetUserDefaultLocaleName');  { Vista+ }
  if Assigned(GetUserDefaultLocaleName) and (GetUserDefaultLocaleName(Buf, Length(Buf)) > 0) then
    Result := WideCharToString(Buf);
end;

function NomeDoComputador: string;
var
  GetComputerNameEx: TGetComputerNameEx;
  Buf: array[0..255] of Char;
  N: DWORD;
begin
  N := SizeOf(Buf);
  @GetComputerNameEx := Proc(kernel32, 'GetComputerNameExA');
  if Assigned(GetComputerNameEx) and GetComputerNameEx(ComputerNameDnsHostname, Buf, N) then
    Result := Buf
  else
  begin
    N := SizeOf(Buf);
    if GetComputerName(Buf, N) then
      Result := Buf
    else
      Result := '';
  end;
end;

function BorionOsInfo: TBorionOsInfo;
var
  RtlGetVersion: TRtlGetVersion;
  V: TRtlOsVersionInfo;
  R: TRegistry;
begin
  FillChar(V, SizeOf(V), 0);
  V.dwOSVersionInfoSize := SizeOf(V);
  @RtlGetVersion := Proc('ntdll.dll', 'RtlGetVersion');
  if not (Assigned(RtlGetVersion) and (RtlGetVersion(V) = 0)) then
  begin
    V.dwMajorVersion := Win32MajorVersion;
    V.dwMinorVersion := Win32MinorVersion;
    V.dwBuildNumber := Win32BuildNumber;
  end;
  Result.Version := Format('%d.%d.%d', [V.dwMajorVersion, V.dwMinorVersion, V.dwBuildNumber]);
  Result.Build := V.dwBuildNumber;
  Result.Arch := Arquitetura;
  Result.ProcessArch := 'x86';
  Result.Locale := Idioma;
  Result.Hostname := NomeDoComputador;
  Result.Name := 'Windows';
  Result.DisplayVersion := '';
  { o processo é 32 bits: sem KEY_WOW64_64KEY, o Windows lê o WOW6432Node, que
    pode ter um ProductName desatualizado (de antes de um upgrade de edição) }
  R := TRegistry.Create(KEY_READ or KEY_WOW64_64KEY);
  try
    R.RootKey := HKEY_LOCAL_MACHINE;
    if R.OpenKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion', False) then
    begin
      if R.ValueExists('ProductName') then
        Result.Name := R.ReadString('ProductName');
      if R.ValueExists('DisplayVersion') then  { 20H2+ }
        Result.DisplayVersion := R.ReadString('DisplayVersion')
      else if R.ValueExists('ReleaseId') then
        Result.DisplayVersion := R.ReadString('ReleaseId');
    end;
  finally
    R.Free;
  end;
  { o ProductName do Windows 11 continua dizendo "Windows 10" }
  if (V.dwMajorVersion = 10) and (V.dwBuildNumber >= 22000) and (Pos('Windows 10', Result.Name) = 1) then
    Result.Name := 'Windows 11' + Copy(Result.Name, 11, MaxInt);
end;

{ TBorionOsPlugin }

function TBorionOsPlugin.Name: string;
begin
  Result := 'os';
end;

procedure TBorionOsPlugin.Install;
begin
  Command('info', CmdInfo);
end;

procedure TBorionOsPlugin.CmdInfo(Call: TBorionCall);
var
  Info: TBorionOsInfo;
  O: TJsonObject;
begin
  Info := BorionOsInfo;
  O := Call.Result.AsObject;
  O.Put('platform', 'windows');
  O.Put('family', 'windows');
  O.Put('type', 'windows');
  O.Put('arch', Info.Arch);
  O.Put('processArch', Info.ProcessArch);
  O.Put('version', Info.Version);
  O.Put('build', Info.Build);
  O.Put('displayVersion', Info.DisplayVersion);
  O.Put('name', Info.Name);
  if Info.Locale <> '' then
    O.Put('locale', Info.Locale)
  else
    O.Put('locale', null);
  O.Put('hostname', Info.Hostname);
  O.Put('eol', #13#10);
  O.Put('exeExtension', 'exe');
end;

end.
