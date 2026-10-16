unit BorionLog;

(*
  Borion — Native Application Engine
  Plugin "log": log em arquivo (UTF-8) com níveis e rotação, o mesmo para o
  Delphi e para a página (como o plugin log do Tauri).

    Log := TBorionLogPlugin(Ipc.AddPlugin(TBorionLogPlugin.Create('Meu App')));
    Log.Info('iniciando');   // do Delphi, de qualquer thread

  Arquivo: %LOCALAPPDATA%\<app>\logs\<app>.log. Ao passar de MaxFileSize
  (1 MB), o arquivo vira <app>.log.1, o .1 vira .2... até KeepFiles (5).

  Linha: 2026-10-15 10:30:00.123 [INFO ] [js] mensagem

  Comandos:
    log:write  {level, message, target?}   level: trace|debug|info|warn|error;
                                           message: literal JSON só com ASCII
    log:attach                             manda cada linha para a página (log:entry)
    log:detach
    log:path   -> literal JSON do caminho do arquivo
  Evento:
    log:entry  {level, message, target, time}   (só com log:attach)
*)

interface

uses
  Windows, SysUtils, Classes, Jsons, BorionIpc;

type
  TBorionLogLevel = (llTrace, llDebug, llInfo, llWarn, llError);

  TBorionLogPlugin = class(TBorionPlugin)
  private
    FLock: TRTLCriticalSection;
    FAppName: string;
    FDir: WideString;
    FArquivo: THandle;
    FTamanho: Int64;
    FMinLevel: TBorionLogLevel;
    FMaxFileSize: Int64;
    FKeepFiles: Integer;
    FAnexado: Integer;
    FEchoToDebugger: Boolean;
    function Caminho: WideString;
    procedure Abrir;
    procedure Fechar;
    procedure Girar;
    procedure SetDir(const Value: WideString);
    procedure CmdWrite(Call: TBorionCall);
    procedure CmdAttach(Call: TBorionCall);
    procedure CmdDetach(Call: TBorionCall);
    procedure CmdPath(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    constructor Create(const AppName: string);
    destructor Destroy; override;
    function Name: string; override;
    { Escreve uma linha (thread-safe); abaixo de MinLevel, ignora }
    procedure Write(Level: TBorionLogLevel; const Msg: WideString; const Target: string = 'delphi');
    procedure Trace(const Msg: WideString);
    procedure Debug(const Msg: WideString);
    procedure Info(const Msg: WideString);
    procedure Warn(const Msg: WideString);
    procedure Error(const Msg: WideString);
    { Caminho completo do arquivo atual }
    property FileName: WideString read Caminho;
    { Pasta dos arquivos (padrão: %LOCALAPPDATA%\<app>\logs) }
    property Dir: WideString read FDir write SetDir;
    { Nível mínimo gravado (padrão: llInfo) }
    property MinLevel: TBorionLogLevel read FMinLevel write FMinLevel;
    property MaxFileSize: Int64 read FMaxFileSize write FMaxFileSize;
    property KeepFiles: Integer read FKeepFiles write FKeepFiles;
    { Também manda para o OutputDebugString (DebugView, IDE) }
    property EchoToDebugger: Boolean read FEchoToDebugger write FEchoToDebugger;
  end;

{ 'info' -> llInfo; False se desconhecido }
function BorionLogLevelFromName(const Name: string; out Level: TBorionLogLevel): Boolean;
function BorionLogLevelName(Level: TBorionLogLevel): string;

implementation

uses
  BorionJson;

const
  NOMES: array[TBorionLogLevel] of string = ('trace', 'debug', 'info', 'warn', 'error');
  CSIDL_LOCAL_APPDATA = $001C;
  FILE_SHARE_DELETE_ = $00000004;

function SHGetFolderPathW(Wnd: HWND; Csidl: Integer; Token: THandle; Flags: DWORD;
  Path: PWideChar): HResult; stdcall; external 'shell32.dll';

function BorionLogLevelFromName(const Name: string; out Level: TBorionLogLevel): Boolean;
var
  L: TBorionLogLevel;
begin
  for L := Low(TBorionLogLevel) to High(TBorionLogLevel) do
    if SameText(Name, NOMES[L]) then
    begin
      Level := L;
      Result := True;
      Exit;
    end;
  Result := False;
end;

function BorionLogLevelName(Level: TBorionLogLevel): string;
begin
  Result := NOMES[Level];
end;

function NomeDeArquivo(const S: string): string;
var
  I: Integer;
begin
  Result := Trim(S);
  for I := 1 to Length(Result) do
    if Result[I] in ['\', '/', ':', '*', '?', '"', '<', '>', '|'] then
      Result[I] := '_';
  if Result = '' then
    Result := 'app';
end;

function Utf8(const W: WideString): string;
var
  N: Integer;
begin
  Result := '';
  if W = '' then
    Exit;
  N := WideCharToMultiByte(CP_UTF8, 0, PWideChar(W), Length(W), nil, 0, nil, nil);
  SetLength(Result, N);
  WideCharToMultiByte(CP_UTF8, 0, PWideChar(W), Length(W), PChar(Result), N, nil, nil);
end;

procedure CriarPastas(const Dir: WideString);
var
  I: Integer;
begin
  { cria cada nível (CreateDirectoryW não cria os intermediários) }
  for I := 4 to Length(Dir) do
    if (Dir[I] = '\') and (Dir[I - 1] <> ':') then
      CreateDirectoryW(PWideChar(Copy(Dir, 1, I - 1)), nil);
  CreateDirectoryW(PWideChar(Dir), nil);
end;

{ TBorionLogPlugin }

constructor TBorionLogPlugin.Create(const AppName: string);
var
  Buf: array[0..MAX_PATH] of WideChar;
begin
  inherited Create;
  InitializeCriticalSection(FLock);
  FAppName := NomeDeArquivo(AppName);
  FArquivo := INVALID_HANDLE_VALUE;
  FMinLevel := llInfo;
  FMaxFileSize := 1024 * 1024;
  FKeepFiles := 5;
  if SHGetFolderPathW(0, CSIDL_LOCAL_APPDATA, 0, 0, Buf) = S_OK then
    FDir := WideString(Buf) + '\' + FAppName + '\logs'
  else
    FDir := WideString(ExtractFilePath(ParamStr(0))) + 'logs';
end;

destructor TBorionLogPlugin.Destroy;
begin
  Fechar;
  DeleteCriticalSection(FLock);
  inherited;
end;

function TBorionLogPlugin.Name: string;
begin
  Result := 'log';
end;

procedure TBorionLogPlugin.Install;
begin
  Command('write', CmdWrite);
  Command('attach', CmdAttach);
  Command('detach', CmdDetach);
  Command('path', CmdPath);
end;

function TBorionLogPlugin.Caminho: WideString;
begin
  Result := FDir + '\' + FAppName + '.log';
end;

procedure TBorionLogPlugin.SetDir(const Value: WideString);
begin
  EnterCriticalSection(FLock);
  try
    Fechar;
    FDir := Value;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TBorionLogPlugin.Abrir;
var
  Alto: DWORD;
begin
  if FArquivo <> INVALID_HANDLE_VALUE then
    Exit;
  CriarPastas(FDir);
  { compartilhado: dá para acompanhar o arquivo (tail) com o app rodando }
  FArquivo := CreateFileW(PWideChar(Caminho), GENERIC_WRITE,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE_, nil, OPEN_ALWAYS,
    FILE_ATTRIBUTE_NORMAL, 0);
  if FArquivo = INVALID_HANDLE_VALUE then
    Exit;
  FTamanho := GetFileSize(FArquivo, @Alto);
  FTamanho := FTamanho or (Int64(Alto) shl 32);
  SetFilePointer(FArquivo, 0, nil, FILE_END);
end;

procedure TBorionLogPlugin.Fechar;
begin
  if FArquivo <> INVALID_HANDLE_VALUE then
  begin
    CloseHandle(FArquivo);
    FArquivo := INVALID_HANDLE_VALUE;
  end;
end;

procedure TBorionLogPlugin.Girar;
var
  I: Integer;
  Base: WideString;
begin
  Fechar;
  Base := Caminho;
  DeleteFileW(PWideChar(Base + '.' + IntToStr(FKeepFiles)));
  for I := FKeepFiles - 1 downto 1 do
    MoveFileExW(PWideChar(Base + '.' + IntToStr(I)), PWideChar(Base + '.' + IntToStr(I + 1)),
      MOVEFILE_REPLACE_EXISTING);
  if FKeepFiles > 0 then
    MoveFileExW(PWideChar(Base), PWideChar(Base + '.1'), MOVEFILE_REPLACE_EXISTING)
  else
    DeleteFileW(PWideChar(Base));
  Abrir;
end;

procedure TBorionLogPlugin.Write(Level: TBorionLogLevel; const Msg: WideString; const Target: string);
var
  Agora, Rotulo, Linha: string;
  Escritos: DWORD;
begin
  if Level < FMinLevel then
    Exit;
  Agora := FormatDateTime('yyyy"-"mm"-"dd hh":"nn":"ss"."zzz', Now);
  Rotulo := UpperCase(NOMES[Level]);
  Linha := Agora + ' [' + Rotulo + StringOfChar(' ', 5 - Length(Rotulo)) + '] [' + Target + '] ' +
    Utf8(Msg) + #13#10;
  EnterCriticalSection(FLock);
  try
    Abrir;
    if (FArquivo <> INVALID_HANDLE_VALUE) and (FTamanho > 0) and
      (FTamanho + Length(Linha) > FMaxFileSize) then
      Girar;
    if FArquivo <> INVALID_HANDLE_VALUE then
    begin
      WriteFile(FArquivo, Linha[1], Length(Linha), Escritos, nil);
      Inc(FTamanho, Escritos);
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
  if FEchoToDebugger then
    OutputDebugStringW(PWideChar(WideString('[' + Target + '] ') + Msg));
  if (FAnexado > 0) and (Ipc <> nil) then
    Ipc.EmitJson('log:entry', '{"level":' + JsonQuote(NOMES[Level]) + ',"message":' +
      JsonQuote(WideToJsonLiteral(Msg)) + ',"target":' + JsonQuote(Target) + ',"time":' +
      JsonQuote(Agora) + '}');
end;

procedure TBorionLogPlugin.Trace(const Msg: WideString);
begin
  Write(llTrace, Msg);
end;

procedure TBorionLogPlugin.Debug(const Msg: WideString);
begin
  Write(llDebug, Msg);
end;

procedure TBorionLogPlugin.Info(const Msg: WideString);
begin
  Write(llInfo, Msg);
end;

procedure TBorionLogPlugin.Warn(const Msg: WideString);
begin
  Write(llWarn, Msg);
end;

procedure TBorionLogPlugin.Error(const Msg: WideString);
begin
  Write(llError, Msg);
end;

procedure TBorionLogPlugin.CmdWrite(Call: TBorionCall);
var
  Nivel: TBorionLogLevel;
  Msg: WideString;
  Alvo: string;
  I: Integer;
begin
  if not BorionLogLevelFromName(Call.ArgStr('level'), Nivel) then
    raise EBorionError.Create('INVALID_ARGS', 'nível de log inválido: ' + Call.ArgStr('level'));
  if not JsonLiteralToWide(Call.ArgStr('message'), Msg) then
    raise EBorionError.Create('INVALID_ARGS', 'message deve ser um literal JSON só com ASCII (o @borion/api/log gera)');
  Alvo := Call.ArgStr('target', 'js');
  for I := 1 to Length(Alvo) do
    if Alvo[I] < ' ' then
      Alvo[I] := ' ';  { sem quebras de linha no rótulo }
  Write(Nivel, Msg, Copy(Alvo, 1, 64));
end;

procedure TBorionLogPlugin.CmdAttach(Call: TBorionCall);
begin
  InterlockedIncrement(FAnexado);
end;

procedure TBorionLogPlugin.CmdDetach(Call: TBorionCall);
begin
  if FAnexado > 0 then
    InterlockedDecrement(FAnexado);
end;

procedure TBorionLogPlugin.CmdPath(Call: TBorionCall);
begin
  Call.Result.AsString := WideToJsonLiteral(Caminho);
end;

end.
