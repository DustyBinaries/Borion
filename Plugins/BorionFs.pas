unit BorionFs;

{$WARN SYMBOL_PLATFORM OFF}  { TSearchRec.FindData: o Borion é só Windows }

(*
  Borion — Native Application Engine
  Plugin "fs": arquivos e pastas, sempre dentro do escopo (TBorionScope).

    Scope := TBorionScope.Create('MeuApp');
    Scope.AllowDir('$APPDATA');
    Ipc.AddPlugin(TBorionFsPlugin.Create(Scope));   // o plugin vira dono do escopo

  Comandos (todo caminho aceita "baseDir": 'appData', 'document', 'temp'...):
    fs:readTextFile  {path, encoding?}            -> string
    fs:writeTextFile {path, contents, append?, encoding?}
    fs:readFile      {path}                       -> base64
    fs:writeFile     {path, data (base64), append?}
    fs:exists        {path}                       -> boolean
    fs:stat          {path}                       -> {isFile, isDirectory, size, modified, readonly}
    fs:readDir       {path}                       -> [{name, isFile, isDirectory, size, modified}]
    fs:mkdir         {path, recursive?}
    fs:remove        {path, recursive?}
    fs:rename        {from, to}
    fs:copyFile      {from, to}

  encoding: 'utf8' (padrão; lê com ou sem BOM, grava sem BOM) ou 'ansi'.
  Erros: FORBIDDEN_PATH, INVALID_PATH, NOT_FOUND, ALREADY_EXISTS, IO_ERROR.
*)

interface

uses
  Windows, SysUtils, Classes, Jsons, BorionIpc, BorionScope;

type
  TBorionFsPlugin = class(TBorionPlugin)
  private
    FScope: TBorionScope;
    FOwnsScope: Boolean;
    function Caminho(Call: TBorionCall; const Arg: string = 'path'): string;
    procedure CmdReadTextFile(Call: TBorionCall);
    procedure CmdWriteTextFile(Call: TBorionCall);
    procedure CmdReadFile(Call: TBorionCall);
    procedure CmdWriteFile(Call: TBorionCall);
    procedure CmdExists(Call: TBorionCall);
    procedure CmdStat(Call: TBorionCall);
    procedure CmdReadDir(Call: TBorionCall);
    procedure CmdMkdir(Call: TBorionCall);
    procedure CmdRemove(Call: TBorionCall);
    procedure CmdRename(Call: TBorionCall);
    procedure CmdCopyFile(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    constructor Create(AScope: TBorionScope; OwnsScope: Boolean = True);
    destructor Destroy; override;
    function Name: string; override;
    property Scope: TBorionScope read FScope;
  end;

function BorionBase64Encode(const Data: string): string;
{ Levanta EBorionError('INVALID_BASE64') se a entrada não for base64 }
function BorionBase64Decode(const Text: string): string;

implementation

const
  FILE_ATTRIBUTE_REPARSE_POINT = $400;  { ausente no Windows.pas do Delphi 7 }
  B64: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function BorionBase64Encode(const Data: string): string;
var
  I, J, N: Integer;
  V: Cardinal;
begin
  N := Length(Data);
  SetLength(Result, ((N + 2) div 3) * 4);
  I := 1;
  J := 1;
  while I <= N do
  begin
    V := Ord(Data[I]) shl 16;
    if I + 1 <= N then
      V := V or (Ord(Data[I + 1]) shl 8);
    if I + 2 <= N then
      V := V or Ord(Data[I + 2]);
    Result[J] := B64[(V shr 18) and 63 + 1];
    Result[J + 1] := B64[(V shr 12) and 63 + 1];
    if I + 1 <= N then
      Result[J + 2] := B64[(V shr 6) and 63 + 1]
    else
      Result[J + 2] := '=';
    if I + 2 <= N then
      Result[J + 3] := B64[V and 63 + 1]
    else
      Result[J + 3] := '=';
    Inc(I, 3);
    Inc(J, 4);
  end;
end;

function BorionBase64Decode(const Text: string): string;
var
  I, J, Bits, Valor, D: Integer;
  C: Char;
begin
  SetLength(Result, Length(Text) * 3 div 4 + 3);
  J := 0;
  Bits := 0;
  Valor := 0;
  for I := 1 to Length(Text) do
  begin
    C := Text[I];
    if C in ['=', #13, #10, ' '] then
      Continue;
    case C of
      'A'..'Z': D := Ord(C) - Ord('A');
      'a'..'z': D := Ord(C) - Ord('a') + 26;
      '0'..'9': D := Ord(C) - Ord('0') + 52;
      '+', '-': D := 62;
      '/', '_': D := 63;
    else
      raise EBorionError.Create('INVALID_BASE64', 'dado base64 inválido');
    end;
    Valor := ((Valor shl 6) or D) and $FFFFFF;  { só os últimos bits importam }
    Inc(Bits, 6);
    if Bits >= 8 then
    begin
      Dec(Bits, 8);
      Inc(J);
      Result[J] := Chr((Valor shr Bits) and $FF);
    end;
  end;
  SetLength(Result, J);
end;

{ --- utilitários de arquivo ------------------------------------------------ }

function ErroIo(const Acao, Path: string): EBorionError;
var
  Codigo: Integer;
begin
  Codigo := GetLastError;
  if (Codigo = ERROR_FILE_NOT_FOUND) or (Codigo = ERROR_PATH_NOT_FOUND) then
    Result := EBorionError.Create('NOT_FOUND', 'não encontrado: ' + Path)
  else if (Codigo = ERROR_ALREADY_EXISTS) or (Codigo = ERROR_FILE_EXISTS) then
    Result := EBorionError.Create('ALREADY_EXISTS', 'já existe: ' + Path)
  else
    Result := EBorionError.Create('IO_ERROR', Format('%s "%s": %s', [Acao, Path, SysErrorMessage(Codigo)]));
end;

function LerArquivo(const Path: string): string;
var
  F: TFileStream;
begin
  if not FileExists(Path) then
    raise EBorionError.Create('NOT_FOUND', 'arquivo não encontrado: ' + Path);
  try
    F := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  except
    on E: EFOpenError do
      raise EBorionError.Create('IO_ERROR', E.Message);
  end;
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

procedure GravarArquivo(const Path, Dados: string; Anexar: Boolean);
var
  F: TFileStream;
begin
  if DirectoryExists(Path) then
    raise EBorionError.Create('IO_ERROR', 'é uma pasta: ' + Path);
  try
    if Anexar and FileExists(Path) then
    begin
      F := TFileStream.Create(Path, fmOpenWrite or fmShareDenyWrite);
      F.Seek(0, soFromEnd);
    end
    else
      F := TFileStream.Create(Path, fmCreate);
  except
    on E: EFCreateError do
      raise EBorionError.Create('IO_ERROR', E.Message);
    on E: EFOpenError do
      raise EBorionError.Create('IO_ERROR', E.Message);
  end;
  try
    if Dados <> '' then
      F.WriteBuffer(Dados[1], Length(Dados));
  finally
    F.Free;
  end;
end;

function DataIso(const FT: TFileTime): string;
var
  Local: TFileTime;
  ST: TSystemTime;
begin
  FileTimeToLocalFileTime(FT, Local);
  FileTimeToSystemTime(Local, ST);
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', SystemTimeToDateTime(ST));
end;

function Atributos(const Path: string; var Dados: TWin32FileAttributeData): Boolean;
begin
  FillChar(Dados, SizeOf(Dados), 0);
  Result := GetFileAttributesEx(PChar(Path), GetFileExInfoStandard, @Dados);
end;

procedure PreencherStat(O: TJsonObject; const D: TWin32FileAttributeData);
var
  Pasta: Boolean;
begin
  Pasta := D.dwFileAttributes and FILE_ATTRIBUTE_DIRECTORY <> 0;
  O.Put('isFile', not Pasta);
  O.Put('isDirectory', Pasta);
  O.Put('size', Int64(D.nFileSizeHigh) shl 32 or D.nFileSizeLow);
  O.Put('modified', DataIso(D.ftLastWriteTime));
  O.Put('readonly', D.dwFileAttributes and FILE_ATTRIBUTE_READONLY <> 0);
end;

{ Apaga uma pasta e o conteúdo. Não entra em junções/links simbólicos: remove
  só o link, para nunca apagar algo fora da pasta pedida. }
procedure ApagarPasta(const Pasta: string);
var
  SR: TSearchRec;
  Item: string;
begin
  if FindFirst(Pasta + '\*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      Item := Pasta + '\' + SR.Name;
      if SR.FindData.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT <> 0 then
      begin
        if SR.Attr and faDirectory <> 0 then
          RemoveDirectory(PChar(Item))
        else
          Windows.DeleteFile(PChar(Item));
      end
      else if SR.Attr and faDirectory <> 0 then
        ApagarPasta(Item)
      else
      begin
        SetFileAttributes(PChar(Item), FILE_ATTRIBUTE_NORMAL);
        if not Windows.DeleteFile(PChar(Item)) then
          raise ErroIo('apagar', Item);
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  if not RemoveDirectory(PChar(Pasta)) then
    raise ErroIo('apagar', Pasta);
end;

{ TBorionFsPlugin }

constructor TBorionFsPlugin.Create(AScope: TBorionScope; OwnsScope: Boolean);
begin
  inherited Create;
  FScope := AScope;
  FOwnsScope := OwnsScope;
end;

destructor TBorionFsPlugin.Destroy;
begin
  if FOwnsScope then
    FScope.Free;
  inherited Destroy;
end;

function TBorionFsPlugin.Name: string;
begin
  Result := 'fs';
end;

procedure TBorionFsPlugin.Install;
begin
  Command('readTextFile', CmdReadTextFile);
  Command('writeTextFile', CmdWriteTextFile);
  Command('readFile', CmdReadFile);
  Command('writeFile', CmdWriteFile);
  Command('exists', CmdExists);
  Command('stat', CmdStat);
  Command('readDir', CmdReadDir);
  Command('mkdir', CmdMkdir);
  Command('remove', CmdRemove);
  Command('rename', CmdRename);
  Command('copyFile', CmdCopyFile);
end;

function TBorionFsPlugin.Caminho(Call: TBorionCall; const Arg: string): string;
begin
  if not Call.HasArg(Arg) then
    raise EBorionError.Create('INVALID_ARGS', 'argumento obrigatório: ' + Arg);
  Result := FScope.Check(Call.ArgStr(Arg), Call.ArgStr('baseDir'));
end;

function Utf8(Call: TBorionCall): Boolean;
var
  E: string;
begin
  E := LowerCase(Call.ArgStr('encoding', 'utf8'));
  if (E = 'utf8') or (E = 'utf-8') then
    Result := True
  else if E = 'ansi' then
    Result := False
  else
    raise EBorionError.Create('INVALID_ARGS', 'encoding desconhecido: ' + E);
end;

procedure TBorionFsPlugin.CmdReadTextFile(Call: TBorionCall);
var
  Path, Dados: string;
begin
  Path := Caminho(Call);
  Dados := LerArquivo(Path);
  if Utf8(Call) then
  begin
    if Copy(Dados, 1, 3) = #$EF#$BB#$BF then
      Delete(Dados, 1, 3);
    Dados := Utf8ToAnsi(Dados);
  end;
  Call.Result.AsString := Dados;
end;

procedure TBorionFsPlugin.CmdWriteTextFile(Call: TBorionCall);
var
  Path, Dados: string;
begin
  Path := Caminho(Call);
  Dados := Call.ArgStr('contents');
  if Utf8(Call) then
    Dados := AnsiToUtf8(Dados);
  GravarArquivo(Path, Dados, Call.ArgBool('append'));
end;

procedure TBorionFsPlugin.CmdReadFile(Call: TBorionCall);
begin
  Call.Result.AsString := BorionBase64Encode(LerArquivo(Caminho(Call)));
end;

procedure TBorionFsPlugin.CmdWriteFile(Call: TBorionCall);
var
  Path: string;
begin
  Path := Caminho(Call);
  GravarArquivo(Path, BorionBase64Decode(Call.ArgStr('data')), Call.ArgBool('append'));
end;

procedure TBorionFsPlugin.CmdExists(Call: TBorionCall);
var
  D: TWin32FileAttributeData;
begin
  Call.Result.AsBoolean := Atributos(Caminho(Call), D);
end;

procedure TBorionFsPlugin.CmdStat(Call: TBorionCall);
var
  Path: string;
  D: TWin32FileAttributeData;
begin
  Path := Caminho(Call);
  if not Atributos(Path, D) then
    raise ErroIo('stat', Path);
  PreencherStat(Call.Result.AsObject, D);
end;

procedure TBorionFsPlugin.CmdReadDir(Call: TBorionCall);
var
  Path: string;
  SR: TSearchRec;
  Lista: TJsonArray;
  Item: TJsonObject;
  D: TWin32FileAttributeData;
begin
  Path := Caminho(Call);
  if not DirectoryExists(Path) then
    raise EBorionError.Create('NOT_FOUND', 'pasta não encontrada: ' + Path);
  Lista := Call.Result.AsArray;
  if FindFirst(IncludeTrailingPathDelimiter(Path) + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      Item := Lista.Add.AsObject;
      Item.Put('name', SR.Name);
      D.dwFileAttributes := SR.FindData.dwFileAttributes;
      D.nFileSizeHigh := SR.FindData.nFileSizeHigh;
      D.nFileSizeLow := SR.FindData.nFileSizeLow;
      D.ftLastWriteTime := SR.FindData.ftLastWriteTime;
      PreencherStat(Item, D);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

procedure TBorionFsPlugin.CmdMkdir(Call: TBorionCall);
var
  Path: string;
begin
  Path := Caminho(Call);
  if Call.ArgBool('recursive') then
  begin
    if not ForceDirectories(Path) then
      raise ErroIo('criar a pasta', Path);
  end
  else if not CreateDirectory(PChar(Path), nil) then
    raise ErroIo('criar a pasta', Path);
end;

procedure TBorionFsPlugin.CmdRemove(Call: TBorionCall);
var
  Path: string;
begin
  Path := Caminho(Call);
  if DirectoryExists(Path) then
  begin
    if Call.ArgBool('recursive') then
      ApagarPasta(Path)
    else if not RemoveDirectory(PChar(Path)) then
      raise ErroIo('apagar a pasta', Path);
  end
  else if not Windows.DeleteFile(PChar(Path)) then
    raise ErroIo('apagar', Path);
end;

procedure TBorionFsPlugin.CmdRename(Call: TBorionCall);
var
  De, Para: string;
begin
  De := Caminho(Call, 'from');
  Para := Caminho(Call, 'to');
  if not MoveFile(PChar(De), PChar(Para)) then
    raise ErroIo('renomear', De);
end;

procedure TBorionFsPlugin.CmdCopyFile(Call: TBorionCall);
var
  De, Para: string;
begin
  De := Caminho(Call, 'from');
  Para := Caminho(Call, 'to');
  if not CopyFile(PChar(De), PChar(Para), False) then
    raise ErroIo('copiar', De);
end;

end.
