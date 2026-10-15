unit BorionPack;

(*
  Borion — Native Application Engine
  Pacote de assets: todos os arquivos do frontend (ex.: o dist/ do Vite) num
  único blob, embutido no exe como o recurso RCDATA "BORION_ASSETS".

  Formato (little-endian):
    'BORP'                 assinatura
    Word     versão (1)
    Cardinal quantidade de entradas
    entradas:
      Word     tamanho do caminho
      bytes    caminho em UTF-8, separado por '/', sem '/' inicial
      Byte     flags (1 = comprimido com zlib)
      Cardinal tamanho original
      Cardinal tamanho armazenado
      Cardinal posição dos dados (relativa ao início da área de dados)
    área de dados

  Gerado pela CLI (borion pack) e lido pelo TBorionAssets em tempo de execução.
  Também escreve e lê arquivos .res (formato de recursos Win32) direto, sem
  precisar de .rc nem do brcc32.
*)

interface

uses
  Windows, SysUtils, Classes;

const
  BORION_PACK_RESOURCE = 'BORION_ASSETS';
  BORION_PACK_FLAG_ZLIB = 1;

type
  EBorionPack = class(Exception);

  TBorionPackEntry = record
    Path: string;            { UTF-8 }
    Flags: Byte;
    OriginalSize: Cardinal;
    StoredSize: Cardinal;
    Offset: Cardinal;
  end;

  { Leitura de um pacote. Não copia os dados: a memória deve viver enquanto o
    pacote existir (um recurso do exe vive o processo todo). }
  TBorionPack = class
  private
    FData: PChar;
    FSize: Cardinal;
    FDataStart: Cardinal;
    FEntries: array of TBorionPackEntry;
    FIndex: TStringList;       { caminho exato -> entrada }
    FIndexLower: TStringList;  { caminho em minúsculas -> entrada }
    FOwned: TMemoryStream;
    procedure Parse;
    function GetCount: Integer;
    function GetEntry(Index: Integer): TBorionPackEntry;
  public
    constructor Create(Data: Pointer; Size: Cardinal);
    destructor Destroy; override;
    class function FromResource(Instance: HMODULE; const ResName: string = BORION_PACK_RESOURCE): TBorionPack;
    class function FromStream(Stream: TStream): TBorionPack;
    class function FromFile(const FileName: string): TBorionPack;
    { Caminho UTF-8 sem '/' inicial; tenta o exato e depois sem diferenciar maiúsculas.
      -1 se não existir. }
    function Find(const Path: string): Integer;
    procedure ExtractTo(Index: Integer; Dest: TStream);
    property Count: Integer read GetCount;
    property Entries[Index: Integer]: TBorionPackEntry read GetEntry; default;
  end;

  TBorionPackOptions = record
    Compress: Boolean;
  end;

{ Empacota todos os arquivos de Folder (recursivo). Log recebe uma linha por
  arquivo (opcional). Devolve a quantidade de arquivos. }
function BorionPackFolder(const Folder: string; Dest: TStream; const Options: TBorionPackOptions;
  Log: TStrings = nil): Integer;

{ .res com um único recurso RCDATA }
procedure BorionWriteRes(const FileName, ResName: string; Data: TStream);
{ Lê o recurso RCDATA ResName de um .res; False se não existir }
function BorionReadRes(const FileName, ResName: string; Dest: TStream): Boolean;

{ 'a%C3%A7%C3%A3o.png' -> bytes UTF-8 de 'ação.png'. Sequências inválidas ficam como estão. }
function BorionUrlDecode(const S: string): string;

implementation

uses
  ZLib;

const
  PACK_MAGIC: array[0..3] of Char = 'BORP';
  PACK_VERSION = 1;
  RT_RCDATA_ID = 10;

{ --- utilitários ----------------------------------------------------------- }

function HexValue(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function BorionUrlDecode(const S: string): string;
var
  I, J, Hi, Lo: Integer;
begin
  SetLength(Result, Length(S));
  I := 1;
  J := 0;
  while I <= Length(S) do
  begin
    if (S[I] = '%') and (I + 2 <= Length(S)) then
    begin
      Hi := HexValue(S[I + 1]);
      Lo := HexValue(S[I + 2]);
      if (Hi >= 0) and (Lo >= 0) then
      begin
        Inc(J);
        Result[J] := Chr(Hi * 16 + Lo);
        Inc(I, 3);
        Continue;
      end;
    end;
    Inc(J);
    Result[J] := S[I];
    Inc(I);
  end;
  SetLength(Result, J);
end;

procedure WriteWord(S: TStream; V: Word);
begin
  S.WriteBuffer(V, 2);
end;

procedure WriteCard(S: TStream; V: Cardinal);
begin
  S.WriteBuffer(V, 4);
end;

procedure WritePad(S: TStream);
const
  Zeros: Cardinal = 0;
begin
  if S.Position mod 4 <> 0 then
    S.WriteBuffer(Zeros, 4 - S.Position mod 4);
end;

{ --- TBorionPack ----------------------------------------------------------- }

constructor TBorionPack.Create(Data: Pointer; Size: Cardinal);
begin
  inherited Create;
  FData := Data;
  FSize := Size;
  FIndex := TStringList.Create;
  FIndex.CaseSensitive := True;
  FIndexLower := TStringList.Create;
  FIndexLower.CaseSensitive := True;
  Parse;
  FIndex.Sorted := True;
  FIndexLower.Sorted := True;
end;

destructor TBorionPack.Destroy;
begin
  FIndexLower.Free;
  FIndex.Free;
  FOwned.Free;
  inherited Destroy;
end;

class function TBorionPack.FromResource(Instance: HMODULE; const ResName: string): TBorionPack;
var
  Res: HRSRC;
begin
  Res := FindResource(Instance, PChar(ResName), RT_RCDATA);
  if Res = 0 then
    raise EBorionPack.CreateFmt('recurso %s não encontrado no executável', [ResName]);
  Result := TBorionPack.Create(LockResource(LoadResource(Instance, Res)), SizeofResource(Instance, Res));
end;

class function TBorionPack.FromStream(Stream: TStream): TBorionPack;
var
  M: TMemoryStream;
begin
  M := TMemoryStream.Create;
  try
    M.CopyFrom(Stream, 0);
    Result := TBorionPack.Create(M.Memory, M.Size);
    Result.FOwned := M;
  except
    M.Free;
    raise;
  end;
end;

class function TBorionPack.FromFile(const FileName: string): TBorionPack;
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := FromStream(F);
  finally
    F.Free;
  end;
end;

procedure TBorionPack.Parse;
var
  P: Cardinal;
  N, I: Integer;
  Len: Word;

  procedure Need(Bytes: Cardinal);
  begin
    if P + Bytes > FSize then
      raise EBorionPack.Create('pacote de assets truncado ou corrompido');
  end;

  function ReadWord: Word;
  begin
    Need(2);
    Move(FData[P], Result, 2);
    Inc(P, 2);
  end;

  function ReadCard: Cardinal;
  begin
    Need(4);
    Move(FData[P], Result, 4);
    Inc(P, 4);
  end;

begin
  P := 0;
  Need(4);
  if not CompareMem(FData, @PACK_MAGIC, 4) then
    raise EBorionPack.Create('não é um pacote de assets do Borion');
  Inc(P, 4);
  if ReadWord <> PACK_VERSION then
    raise EBorionPack.Create('versão do pacote de assets não suportada');
  N := ReadCard;
  SetLength(FEntries, N);
  for I := 0 to N - 1 do
  begin
    Len := ReadWord;
    Need(Len);
    SetString(FEntries[I].Path, FData + P, Len);
    Inc(P, Len);
    Need(1);
    FEntries[I].Flags := Byte(FData[P]);
    Inc(P);
    FEntries[I].OriginalSize := ReadCard;
    FEntries[I].StoredSize := ReadCard;
    FEntries[I].Offset := ReadCard;
    FIndex.AddObject(FEntries[I].Path, TObject(I));
    FIndexLower.AddObject(LowerCase(FEntries[I].Path), TObject(I));
  end;
  FDataStart := P;
  for I := 0 to N - 1 do
    if FDataStart + FEntries[I].Offset + FEntries[I].StoredSize > FSize then
      raise EBorionPack.CreateFmt('dados de "%s" fora do pacote', [FEntries[I].Path]);
end;

function TBorionPack.GetCount: Integer;
begin
  Result := Length(FEntries);
end;

function TBorionPack.GetEntry(Index: Integer): TBorionPackEntry;
begin
  Result := FEntries[Index];
end;

function TBorionPack.Find(const Path: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  if FIndex.Find(Path, I) then
    Result := Integer(FIndex.Objects[I])
  else if FIndexLower.Find(LowerCase(Path), I) then
    Result := Integer(FIndexLower.Objects[I]);
end;

procedure TBorionPack.ExtractTo(Index: Integer; Dest: TStream);
var
  E: TBorionPackEntry;
  Src, OutBuf: Pointer;
  OutBytes: Integer;
begin
  E := FEntries[Index];
  Src := FData + FDataStart + E.Offset;
  if E.Flags and BORION_PACK_FLAG_ZLIB = 0 then
  begin
    if E.StoredSize > 0 then
      Dest.WriteBuffer(Src^, E.StoredSize);
    Exit;
  end;
  { folga na estimativa: o DecompressBuf do Delphi 7 realoca se faltar espaço }
  DecompressBuf(Src, E.StoredSize, E.OriginalSize + 64, OutBuf, OutBytes);
  try
    if Cardinal(OutBytes) <> E.OriginalSize then
      raise EBorionPack.CreateFmt('tamanho descomprimido inesperado em "%s"', [E.Path]);
    Dest.WriteBuffer(OutBuf^, OutBytes);
  finally
    FreeMem(OutBuf);
  end;
end;

{ --- empacotamento --------------------------------------------------------- }

const
  { formatos que já são comprimidos: não vale a pena passar pelo zlib }
  JA_COMPRIMIDOS: array[0..14] of string = ('.png', '.jpg', '.jpeg', '.gif', '.webp', '.avif',
    '.ico', '.woff', '.woff2', '.mp3', '.mp4', '.webm', '.ogg', '.zip', '.gz');

function DeveComprimir(const FileName: string): Boolean;
var
  Ext: string;
  I: Integer;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  for I := Low(JA_COMPRIMIDOS) to High(JA_COMPRIMIDOS) do
    if Ext = JA_COMPRIMIDOS[I] then
    begin
      Result := False;
      Exit;
    end;
  Result := True;
end;

procedure ListarArquivos(const Base, Relativo: string; Lista: TStrings);
var
  SR: TSearchRec;
  Pasta: string;
begin
  Pasta := IncludeTrailingPathDelimiter(Base) + Relativo;
  if FindFirst(Pasta + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      if SR.Attr and faDirectory <> 0 then
        ListarArquivos(Base, Relativo + SR.Name + '\', Lista)
      else
        Lista.Add(Relativo + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

function BorionPackFolder(const Folder: string; Dest: TStream; const Options: TBorionPackOptions;
  Log: TStrings): Integer;
var
  Arquivos: TStringList;
  Dados: TMemoryStream;
  Entradas: array of TBorionPackEntry;
  I: Integer;
  F: TMemoryStream;
  OutBuf: Pointer;
  OutBytes: Integer;
  Caminho: string;
begin
  Result := 0;
  if not DirectoryExists(Folder) then
    raise EBorionPack.CreateFmt('pasta não encontrada: %s', [Folder]);
  Arquivos := TStringList.Create;
  Dados := TMemoryStream.Create;
  F := TMemoryStream.Create;
  try
    ListarArquivos(Folder, '', Arquivos);
    Arquivos.Sort;  { pacote determinístico }
    SetLength(Entradas, Arquivos.Count);
    for I := 0 to Arquivos.Count - 1 do
    begin
      F.LoadFromFile(IncludeTrailingPathDelimiter(Folder) + Arquivos[I]);
      Caminho := UTF8Encode(WideString(StringReplace(Arquivos[I], '\', '/', [rfReplaceAll])));
      if Length(Caminho) > High(Word) then
        raise EBorionPack.CreateFmt('caminho longo demais: %s', [Arquivos[I]]);
      Entradas[I].Path := Caminho;
      Entradas[I].OriginalSize := F.Size;
      Entradas[I].Offset := Dados.Size;
      Entradas[I].Flags := 0;
      OutBuf := nil;
      if Options.Compress and (F.Size > 0) and DeveComprimir(Arquivos[I]) then
        CompressBuf(F.Memory, F.Size, OutBuf, OutBytes);
      try
        { só guarda comprimido se ganhar pelo menos 10% }
        if (OutBuf <> nil) and (OutBytes < F.Size * 9 div 10) then
        begin
          Entradas[I].Flags := BORION_PACK_FLAG_ZLIB;
          Entradas[I].StoredSize := OutBytes;
          Dados.WriteBuffer(OutBuf^, OutBytes);
        end
        else
        begin
          Entradas[I].StoredSize := F.Size;
          if F.Size > 0 then
            Dados.WriteBuffer(F.Memory^, F.Size);
        end;
      finally
        if OutBuf <> nil then
          FreeMem(OutBuf);
      end;
      if Log <> nil then
        Log.Add(Format('%-50s %9d -> %9d%s', [StringReplace(Arquivos[I], '\', '/', [rfReplaceAll]), Entradas[I].OriginalSize,
          Entradas[I].StoredSize, Copy(' zlib', 1, 5 * Ord(Entradas[I].Flags <> 0))]));

    end;

    Dest.WriteBuffer(PACK_MAGIC, 4);
    WriteWord(Dest, PACK_VERSION);
    WriteCard(Dest, Length(Entradas));
    for I := 0 to High(Entradas) do
    begin
      WriteWord(Dest, Length(Entradas[I].Path));
      if Entradas[I].Path <> '' then
        Dest.WriteBuffer(Entradas[I].Path[1], Length(Entradas[I].Path));
      Dest.WriteBuffer(Entradas[I].Flags, 1);
      WriteCard(Dest, Entradas[I].OriginalSize);
      WriteCard(Dest, Entradas[I].StoredSize);
      WriteCard(Dest, Entradas[I].Offset);
    end;
    if Dados.Size > 0 then
      Dest.CopyFrom(Dados, 0);
    Result := Arquivos.Count;
  finally
    F.Free;
    Dados.Free;
    Arquivos.Free;
  end;
end;

{ --- arquivos .res --------------------------------------------------------- }

{ Cada recurso num .res: DataSize, HeaderSize, TYPE, NAME, DataVersion,
  MemoryFlags, LanguageId, Version, Characteristics, dados (alinhados a 4). }

procedure BorionWriteRes(const FileName, ResName: string; Data: TStream);
var
  S: TFileStream;
  Nome: WideString;
  NomeBytes, HeaderSize: Cardinal;
begin
  Nome := WideString(UpperCase(ResName));
  NomeBytes := (Length(Nome) + 1) * 2;
  HeaderSize := 8 + 4 + NomeBytes;
  if HeaderSize mod 4 <> 0 then
    Inc(HeaderSize, 4 - HeaderSize mod 4);
  Inc(HeaderSize, 16);
  S := TFileStream.Create(FileName, fmCreate);
  try
    { entrada vazia obrigatória no início do arquivo }
    WriteCard(S, 0); WriteCard(S, $20);
    WriteWord(S, $FFFF); WriteWord(S, 0);
    WriteWord(S, $FFFF); WriteWord(S, 0);
    WriteCard(S, 0); WriteCard(S, 0); WriteCard(S, 0); WriteCard(S, 0);
    { o recurso }
    WriteCard(S, Data.Size);
    WriteCard(S, HeaderSize);
    WriteWord(S, $FFFF); WriteWord(S, RT_RCDATA_ID);
    S.WriteBuffer(Nome[1], NomeBytes);  { inclui o #0 final }
    WritePad(S);
    WriteCard(S, 0);         { DataVersion }
    WriteWord(S, $0030);     { MemoryFlags: MOVEABLE | PURE }
    WriteWord(S, 0);         { LanguageId: neutro }
    WriteCard(S, 0);         { Version }
    WriteCard(S, 0);         { Characteristics }
    if Data.Size > 0 then
      S.CopyFrom(Data, 0);
    WritePad(S);
  finally
    S.Free;
  end;
end;

function BorionReadRes(const FileName, ResName: string; Dest: TStream): Boolean;
var
  S: TFileStream;
  Inicio: Int64;
  DataSize, HeaderSize: Cardinal;
  TipoMarca, TipoId: Word;
  Nome: WideString;
  C: WideChar;
begin
  Result := False;
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    while S.Position + 8 <= S.Size do
    begin
      Inicio := S.Position;
      S.ReadBuffer(DataSize, 4);
      S.ReadBuffer(HeaderSize, 4);
      S.ReadBuffer(TipoMarca, 2);
      TipoId := 0;
      if TipoMarca = $FFFF then
        S.ReadBuffer(TipoId, 2);
      { nome: ordinal ou texto Unicode terminado em #0 }
      Nome := '';
      S.ReadBuffer(C, 2);
      if Word(C) <> $FFFF then
        while C <> #0 do
        begin
          Nome := Nome + C;
          S.ReadBuffer(C, 2);
        end;
      if (TipoMarca = $FFFF) and (TipoId = RT_RCDATA_ID) and
        SameText(string(Nome), ResName) then
      begin
        S.Position := Inicio + HeaderSize;
        if DataSize > 0 then
          Dest.CopyFrom(S, DataSize);
        Result := True;
        Exit;
      end;
      S.Position := Inicio + HeaderSize + DataSize;
      if S.Position mod 4 <> 0 then
        S.Position := S.Position + 4 - S.Position mod 4;
    end;
  finally
    S.Free;
  end;
end;

end.
