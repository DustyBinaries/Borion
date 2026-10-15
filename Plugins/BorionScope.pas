unit BorionScope;

(*
  Borion — Native Application Engine
  Escopo de arquivos: quais pastas e arquivos os plugins (fs, shell...) podem
  tocar. Tudo é negado por padrão.

    Scope := TBorionScope.Create('MeuApp');
    Scope.AllowDir('$APPDATA');              // %APPDATA%\MeuApp e subpastas
    Scope.AllowDir('$DOCUMENT\MeuApp');
    Scope.AllowFile('C:\dados\config.ini');

  Antes de comparar, o caminho é validado e normalizado: '..' e '.' resolvidos,
  '/' vira '\', e são recusados caminhos de dispositivo (\\?\, \\.\, CON, NUL...),
  alternate data streams ('arquivo:stream') e caracteres inválidos.

  Variáveis aceitas em AllowDir/AllowFile: $APPDATA, $APPLOCALDATA (as duas já
  com a subpasta do app), $DOCUMENT, $DESKTOP, $DOWNLOAD, $PICTURE, $HOME,
  $TEMP e $EXE (pasta do executável).
*)

interface

uses
  Windows, SysUtils, Classes;

type
  { Diretórios-base aceitos pelos comandos (argumento "baseDir" no JS) }
  TBorionBaseDir = (bdNone, bdAppData, bdAppLocalData, bdDocument, bdDesktop, bdDownload,
    bdPicture, bdHome, bdTemp, bdExe);

  TBorionScope = class
  private
    FAppName: string;
    FDirs: TStringList;   { pasta normalizada; Objects = 1 se recursiva }
    FFiles: TStringList;  { arquivo normalizado }
    function ExpandVars(const Path: string): string;
  public
    constructor Create(const AppName: string);
    destructor Destroy; override;
    { Libera uma pasta (e, se Recursive, tudo abaixo dela) }
    procedure AllowDir(const Dir: string; Recursive: Boolean = True);
    { Libera um único arquivo }
    procedure AllowFile(const FileName: string);
    procedure Clear;
    { Caminho absoluto e normalizado. Com Base <> bdNone, Path é relativo a ela.
      Levanta EBorionError('INVALID_PATH') para caminhos inválidos. }
    function Resolve(const Path: string; Base: TBorionBaseDir = bdNone): string;
    { Path já normalizado está liberado? }
    function IsAllowed(const NormalizedPath: string): Boolean;
    { Resolve + IsAllowed; levanta EBorionError('FORBIDDEN_PATH') se negado.
      BaseDirName como no JS ('appData', 'document'...; '' = nenhum). }
    function Check(const Path: string; const BaseDirName: string = ''): string;
    property AppName: string read FAppName;
    property Dirs: TStringList read FDirs;
    property Files: TStringList read FFiles;
  end;

{ Pasta de um diretório-base, sem barra final. AppData e AppLocalData incluem AppName. }
function BorionBaseDirPath(Base: TBorionBaseDir; const AppName: string): string;
{ 'appData' -> bdAppData; '' -> bdNone. Levanta EBorionError('INVALID_BASE_DIR') se desconhecido. }
function BorionBaseDirFromName(const Name: string): TBorionBaseDir;
{ Valida e normaliza um caminho absoluto (ver o cabeçalho). Levanta EBorionError('INVALID_PATH'). }
function BorionNormalizePath(const Path: string): string;

implementation

uses
  ActiveX, ShlObj, BorionIpc;

const
  NOMES_BASE: array[TBorionBaseDir] of string = ('', 'appData', 'appLocalData', 'document',
    'desktop', 'download', 'picture', 'home', 'temp', 'exe');
  VARS_BASE: array[TBorionBaseDir] of string = ('', '$APPDATA', '$APPLOCALDATA', '$DOCUMENT',
    '$DESKTOP', '$DOWNLOAD', '$PICTURE', '$HOME', '$TEMP', '$EXE');

  CSIDL_LOCAL_APPDATA_ = $001C;
  CSIDL_MYPICTURES_ = $0027;
  CSIDL_PROFILE_ = $0028;

function SemBarraFinal(const S: string): string;
begin
  Result := S;
  while (Length(Result) > 3) and (Result[Length(Result)] = '\') do
    Delete(Result, Length(Result), 1);
end;

function PastaEspecial(Csidl: Integer): string;
var
  Buf: array[0..MAX_PATH] of Char;
begin
  if SHGetSpecialFolderPath(0, Buf, Csidl, False) then
    Result := SemBarraFinal(Buf)
  else
    Result := '';
end;

function PastaDownloads: string;
const
  FOLDERID_Downloads: TGUID = '{374DE290-123F-4565-9164-39C4925E467B}';
type
  TSHGetKnownFolderPath = function(const rfid: TGUID; dwFlags: DWORD; hToken: THandle;
    var ppszPath: PWideChar): HResult; stdcall;
var
  Lib: HMODULE;
  Fn: TSHGetKnownFolderPath;
  P: PWideChar;
begin
  Result := '';
  Lib := GetModuleHandle('shell32.dll');
  if Lib <> 0 then
  begin
    @Fn := GetProcAddress(Lib, 'SHGetKnownFolderPath');  { Vista+ }
    if Assigned(Fn) and Succeeded(Fn(FOLDERID_Downloads, 0, 0, P)) then
    begin
      Result := SemBarraFinal(WideString(P));
      CoTaskMemFree(P);
    end;
  end;
  if Result = '' then
    Result := PastaEspecial(CSIDL_PROFILE_) + '\Downloads';
end;

function BorionBaseDirPath(Base: TBorionBaseDir; const AppName: string): string;
var
  Buf: array[0..MAX_PATH] of Char;
begin
  case Base of
    bdAppData: Result := PastaEspecial(CSIDL_APPDATA) + '\' + AppName;
    bdAppLocalData: Result := PastaEspecial(CSIDL_LOCAL_APPDATA_) + '\' + AppName;
    bdDocument: Result := PastaEspecial(CSIDL_PERSONAL);
    bdDesktop: Result := PastaEspecial(CSIDL_DESKTOPDIRECTORY);
    bdDownload: Result := PastaDownloads;
    bdPicture: Result := PastaEspecial(CSIDL_MYPICTURES_);
    bdHome: Result := PastaEspecial(CSIDL_PROFILE_);
    bdTemp:
      begin
        GetTempPath(SizeOf(Buf), Buf);
        Result := SemBarraFinal(Buf);
      end;
    bdExe: Result := SemBarraFinal(ExtractFilePath(ParamStr(0)));
  else
    Result := '';
  end;
end;

function BorionBaseDirFromName(const Name: string): TBorionBaseDir;
var
  B: TBorionBaseDir;
begin
  for B := Low(TBorionBaseDir) to High(TBorionBaseDir) do
    if SameText(NOMES_BASE[B], Name) then
    begin
      Result := B;
      Exit;
    end;
  raise EBorionError.Create('INVALID_BASE_DIR', 'baseDir desconhecido: ' + Name);
end;

function Invalido(const Path, Motivo: string): EBorionError;
begin
  Result := EBorionError.Create('INVALID_PATH', 'caminho inválido (' + Motivo + '): ' + Path);
end;

function NomeReservado(const Segmento: string): Boolean;
var
  S: string;
  I: Integer;
begin
  { CON, PRN, AUX, NUL, COM1..9, LPT1..9, inclusive com extensão (NUL.txt) }
  S := UpperCase(Segmento);
  I := Pos('.', S);
  if I > 0 then
    S := Copy(S, 1, I - 1);
  S := TrimRight(S);
  Result := (S = 'CON') or (S = 'PRN') or (S = 'AUX') or (S = 'NUL') or
    ((Length(S) = 4) and ((Copy(S, 1, 3) = 'COM') or (Copy(S, 1, 3) = 'LPT')) and (S[4] in ['1'..'9']));
end;

function BorionNormalizePath(const Path: string): string;
var
  S, Seg: string;
  I, Ini: Integer;
begin
  S := StringReplace(Trim(Path), '/', '\', [rfReplaceAll]);
  if S = '' then
    raise Invalido(Path, 'vazio');
  for I := 1 to Length(S) do
    if (S[I] < ' ') or (S[I] in ['<', '>', '"', '|', '?', '*']) then
      raise Invalido(Path, 'caractere não permitido');
  if Copy(S, 1, 2) = '\\' then
  begin
    if (Copy(S, 3, 2) = '?\') or (Copy(S, 3, 2) = '.\') then
      raise Invalido(Path, 'caminho de dispositivo');
  end
  else if not ((Length(S) >= 3) and (UpCase(S[1]) in ['A'..'Z']) and (S[2] = ':') and (S[3] = '\')) then
    raise Invalido(Path, 'não é absoluto');
  { ':' só depois da letra do drive: o resto seria um alternate data stream }
  if Pos(':', Copy(S, 3, MaxInt)) > 0 then
    raise Invalido(Path, 'alternate data stream');
  { nomes reservados em qualquer segmento }
  Ini := 1;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = '\') then
    begin
      Seg := Copy(S, Ini, I - Ini);
      if (Seg <> '') and NomeReservado(Seg) then
        raise Invalido(Path, 'nome reservado do Windows: ' + Seg);
      Ini := I + 1;
    end;
  Result := SemBarraFinal(ExpandFileName(S));
end;

{ TBorionScope }

constructor TBorionScope.Create(const AppName: string);
begin
  inherited Create;
  FAppName := AppName;
  FDirs := TStringList.Create;
  FFiles := TStringList.Create;
end;

destructor TBorionScope.Destroy;
begin
  FFiles.Free;
  FDirs.Free;
  inherited Destroy;
end;

function TBorionScope.ExpandVars(const Path: string): string;
var
  B: TBorionBaseDir;
  V: string;
begin
  Result := Path;
  if (Result = '') or (Result[1] <> '$') then
    Exit;
  for B := Succ(bdNone) to High(TBorionBaseDir) do
  begin
    V := VARS_BASE[B];
    if SameText(Copy(Result, 1, Length(V)), V) and
      ((Length(Result) = Length(V)) or (Result[Length(V) + 1] in ['\', '/'])) then
    begin
      Result := BorionBaseDirPath(B, FAppName) + Copy(Result, Length(V) + 1, MaxInt);
      Exit;
    end;
  end;
  raise EBorionError.Create('INVALID_PATH', 'variável desconhecida em ' + Path);
end;

procedure TBorionScope.AllowDir(const Dir: string; Recursive: Boolean);
begin
  FDirs.AddObject(BorionNormalizePath(ExpandVars(Dir)), TObject(Ord(Recursive)));
end;

procedure TBorionScope.AllowFile(const FileName: string);
begin
  FFiles.Add(BorionNormalizePath(ExpandVars(FileName)));
end;

procedure TBorionScope.Clear;
begin
  FDirs.Clear;
  FFiles.Clear;
end;

function TBorionScope.Resolve(const Path: string; Base: TBorionBaseDir): string;
var
  S: string;
begin
  S := StringReplace(Trim(Path), '/', '\', [rfReplaceAll]);
  if Base <> bdNone then
  begin
    if (Copy(S, 1, 1) = '\') or (Pos(':', S) > 0) then
      raise Invalido(Path, 'com baseDir, o caminho deve ser relativo');
    S := BorionBaseDirPath(Base, FAppName) + '\' + S;
  end;
  Result := BorionNormalizePath(S);
end;

function TBorionScope.IsAllowed(const NormalizedPath: string): Boolean;
var
  I: Integer;
  Dir, Pai, Prefixo: string;
begin
  Result := True;
  for I := 0 to FFiles.Count - 1 do
    if AnsiSameText(FFiles[I], NormalizedPath) then
      Exit;
  for I := 0 to FDirs.Count - 1 do
  begin
    Dir := FDirs[I];
    if AnsiSameText(Dir, NormalizedPath) then
      Exit;
    if Integer(FDirs.Objects[I]) = 1 then
    begin
      { prefixo com a barra: 'C:\app' não libera 'C:\app2' (e 'C:\' continua funcionando) }
      Prefixo := IncludeTrailingPathDelimiter(Dir);
      if AnsiSameText(Copy(NormalizedPath, 1, Length(Prefixo)), Prefixo) then
        Exit;
    end
    else
    begin
      Pai := SemBarraFinal(ExtractFilePath(NormalizedPath));
      if AnsiSameText(Pai, Dir) then
        Exit;
    end;
  end;
  Result := False;
end;

function TBorionScope.Check(const Path, BaseDirName: string): string;
begin
  Result := Resolve(Path, BorionBaseDirFromName(BaseDirName));
  if not IsAllowed(Result) then
    raise EBorionError.Create('FORBIDDEN_PATH', 'fora do escopo permitido: ' + Result);
end;

end.
