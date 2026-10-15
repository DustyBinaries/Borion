unit BorionStore;

(*
  Borion — Native Application Engine
  Plugin "store": chave-valor persistido em arquivos JSON, um por store.

    Ipc.AddPlugin(TBorionStorePlugin.Create('Meu App'));  // em %APPDATA%\Meu App

  Comandos (store = nome do arquivo, ex.: 'settings.json'; '.json' é opcional):
    store:load    {store}               abre (lê o arquivo, se existir) -> número de chaves
    store:get     {store, key}          -> valor, ou null se a chave não existir
    store:set     {store, key, value}
    store:has     {store, key}          -> boolean
    store:delete  {store, key}          -> boolean (se existia)
    store:clear   {store}
    store:entries {store}               -> [[key, value], ...] na ordem de inserção
    store:save    {store}               grava agora (com AutoSave, já foi gravado)
    store:reload  {store}               descarta o que não foi gravado e relê o arquivo
  Evento:
    store:change  {store, key, value}   a cada set/delete/clear, vindo da página
                                        ou do Delphi; value null = chave apagada

  Unicode completo: key é um literal JSON de string e value um texto JSON, ambos
  só com ASCII (o resto como \uXXXX), gerados e lidos pelo @borion/api/store. O
  Delphi valida e guarda esse texto como está, sem interpretar, então nada
  passa pela página de código. O arquivo gravado é JSON comum (UTF-8).

  Arquivo corrompido: é renomeado para <nome>.json.corrupt e o store recomeça
  vazio (o app não fica travado e os dados antigos não são perdidos).
*)

interface

uses
  Windows, SysUtils, Classes, Jsons, BorionIpc;

type
  { Um arquivo: chaves (literais canônicos) e valores (texto JSON), na ordem }
  TBorionStoreData = class
  private
    FFileName: string;
    FKeys: TStringList;
    FValues: TStringList;
    FDirty: Boolean;
  public
    constructor Create(const AFileName: string);
    destructor Destroy; override;
    procedure Load;
    procedure Save;
    function IndexOf(const KeyLiteral: string): Integer;
    property FileName: string read FFileName;
    property Keys: TStringList read FKeys;
    property Values: TStringList read FValues;
    property Dirty: Boolean read FDirty;
  end;

  TBorionStorePlugin = class(TBorionPlugin)
  private
    FDir: string;
    FAutoSave: Boolean;
    FStores: TStringList;  { nome normalizado -> TBorionStoreData }
    function Abrir(const Nome: string): TBorionStoreData;
    function DoCall(Call: TBorionCall): TBorionStoreData;
    function ChaveDoCall(Call: TBorionCall): string;
    procedure Mudou(Store: TBorionStoreData; const Chave: string; const Valor: string; Apagada: Boolean);
    procedure Gravar(Store: TBorionStoreData);
    procedure PorValor(Store: TBorionStoreData; const Chave, Valor: string);
    function Apagar(Store: TBorionStoreData; const Chave: string): Boolean;
    procedure CmdLoad(Call: TBorionCall);
    procedure CmdGet(Call: TBorionCall);
    procedure CmdSet(Call: TBorionCall);
    procedure CmdHas(Call: TBorionCall);
    procedure CmdDelete(Call: TBorionCall);
    procedure CmdClear(Call: TBorionCall);
    procedure CmdEntries(Call: TBorionCall);
    procedure CmdSave(Call: TBorionCall);
    procedure CmdReload(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    { Pasta dos arquivos: %APPDATA%\AppName (troque pela propriedade Dir) }
    constructor Create(const AppName: string);
    { Grava os stores com alterações pendentes (AutoSave desligado) }
    destructor Destroy; override;
    function Name: string; override;

    { Uso pelo Delphi. Key é texto comum; os valores são JSON (como no JS).
      Alterações feitas aqui também emitem store:change para a página. }
    function ReadJson(const Store, Key: string; out Json: string): Boolean;
    procedure WriteJson(const Store, Key, Json: string);
    function ReadString(const Store, Key: string; const Default: WideString = ''): WideString;
    procedure WriteString(const Store, Key: string; const Value: WideString);
    function Delete(const Store, Key: string): Boolean;
    procedure Save(const Store: string);

    property Dir: string read FDir write FDir;
    { True (padrão): cada alteração grava o arquivo na hora. False: só no
      store:save, no Save e ao destruir o plugin. }
    property AutoSave: Boolean read FAutoSave write FAutoSave;
  end;

{ 'settings' / 'Settings.JSON' -> 'settings.json'. Levanta EBorionError('INVALID_STORE')
  se o nome não for um nome de arquivo simples: letras, números, '.', '_' e '-'. }
function BorionStoreFileName(const Name: string): string;

implementation

uses
  BorionJson, BorionScope;

function BorionStoreFileName(const Name: string): string;
var
  I: Integer;
begin
  Result := LowerCase(Name);
  if (Result = '') or (Length(Result) > 64) or (Result[1] = '.') or (Pos('..', Result) > 0) then
    raise EBorionError.Create('INVALID_STORE', 'nome de store inválido: "' + Name + '"');
  for I := 1 to Length(Result) do
    if not (Result[I] in ['a'..'z', '0'..'9', '.', '_', '-']) then
      raise EBorionError.Create('INVALID_STORE',
        'nome de store inválido: "' + Name + '" (use letras, números, ".", "_" e "-")');
  if Copy(Result, Length(Result) - 4, 5) <> '.json' then
    Result := Result + '.json';
end;

{ Chave canônica: o mesmo texto vira sempre o mesmo literal ('"é"' e '"é"') }
function ChaveCanonica(const Literal: string; out Chave: string): Boolean;
var
  W: WideString;
begin
  Result := JsonLiteralToWide(Literal, W);
  if Result then
    Chave := WideToJsonLiteral(W);
end;

function LerArquivo(const FileName: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

{ Conteúdo UTF-8 (com ou sem BOM) -> JSON só com ASCII: o arquivo que o plugin
  grava já é ASCII, mas um editado à mão pode ter acentos crus. }
function ParaAscii(const Utf8: string): string;
var
  S: string;
  W: WideString;
  N, I: Integer;
begin
  S := Utf8;
  if Copy(S, 1, 3) = #$EF#$BB#$BF then
    Delete(S, 1, 3);
  for I := 1 to Length(S) do
    if Ord(S[I]) > 126 then
    begin
      N := MultiByteToWideChar(CP_UTF8, 0, PChar(S), Length(S), nil, 0);
      SetLength(W, N);
      MultiByteToWideChar(CP_UTF8, 0, PChar(S), Length(S), PWideChar(W), N);
      Result := '';
      for N := 1 to Length(W) do
        if Ord(W[N]) > 126 then
          Result := Result + '\u' + LowerCase(IntToHex(Ord(W[N]), 4))
        else
          Result := Result + Char(Ord(W[N]));
      Exit;
    end;
  Result := S;
end;

{ TBorionStoreData }

constructor TBorionStoreData.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
  FKeys := TStringList.Create;
  FKeys.CaseSensitive := True;
  FValues := TStringList.Create;
end;

destructor TBorionStoreData.Destroy;
begin
  FKeys.Free;
  FValues.Free;
  inherited;
end;

function TBorionStoreData.IndexOf(const KeyLiteral: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FKeys.Count - 1 do
    if FKeys[I] = KeyLiteral then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

procedure TBorionStoreData.Load;
var
  S, Chave: string;
  I, Fim, Idx: Integer;

  procedure Corrompido;
  begin
    FKeys.Clear;
    FValues.Clear;
    MoveFileEx(PChar(FFileName), PChar(FFileName + '.corrupt'),
      MOVEFILE_REPLACE_EXISTING or MOVEFILE_COPY_ALLOWED);
  end;

begin
  FKeys.Clear;
  FValues.Clear;
  FDirty := False;
  if not FileExists(FFileName) then
    Exit;
  try
    S := ParaAscii(LerArquivo(FFileName));
  except
    on E: Exception do
      raise EBorionError.Create('IO_ERROR', 'não foi possível ler ' + FFileName + ': ' + E.Message);
  end;
  if Trim(S) = '' then
    Exit;  { arquivo vazio: store vazio }
  { objeto no topo; cada valor é guardado como texto, sem interpretar }
  I := SkipJsonSpace(S, 1);
  if (I > Length(S)) or (S[I] <> '{') then
  begin
    Corrompido;
    Exit;
  end;
  I := SkipJsonSpace(S, I + 1);
  if (I <= Length(S)) and (S[I] = '}') then
    Inc(I)
  else
    while True do
    begin
      Fim := ScanJsonString(S, I);
      if (Fim = 0) or not ChaveCanonica(Copy(S, I, Fim - I), Chave) then
      begin
        Corrompido;
        Exit;
      end;
      I := SkipJsonSpace(S, Fim);
      if (I > Length(S)) or (S[I] <> ':') then
      begin
        Corrompido;
        Exit;
      end;
      I := SkipJsonSpace(S, I + 1);
      Fim := ScanJsonValue(S, I);
      if Fim = 0 then
      begin
        Corrompido;
        Exit;
      end;
      Idx := IndexOf(Chave);  { chave repetida: vale a última }
      if Idx >= 0 then
        FValues[Idx] := Copy(S, I, Fim - I)
      else
      begin
        FKeys.Add(Chave);
        FValues.Add(Copy(S, I, Fim - I));
      end;
      I := SkipJsonSpace(S, Fim);
      if (I <= Length(S)) and (S[I] = ',') then
      begin
        I := SkipJsonSpace(S, I + 1);
        Continue;
      end;
      if (I <= Length(S)) and (S[I] = '}') then
      begin
        Inc(I);
        Break;
      end;
      Corrompido;
      Exit;
    end;
  if SkipJsonSpace(S, I) <= Length(S) then
    Corrompido;  { lixo depois do objeto }
end;

procedure TBorionStoreData.Save;
var
  S, Temp: string;
  I: Integer;
  F: TFileStream;
begin
  if FKeys.Count = 0 then
    S := '{}'#13#10
  else
  begin
    S := '{'#13#10;
    for I := 0 to FKeys.Count - 1 do
    begin
      S := S + '  ' + FKeys[I] + ': ' + FValues[I];
      if I < FKeys.Count - 1 then
        S := S + ',';
      S := S + #13#10;
    end;
    S := S + '}'#13#10;
  end;
  { grava num temporário e troca: uma queda no meio não deixa o arquivo pela metade }
  Temp := FFileName + '.tmp';
  try
    ForceDirectories(ExtractFileDir(FFileName));
    F := TFileStream.Create(Temp, fmCreate);
    try
      F.WriteBuffer(S[1], Length(S));
    finally
      F.Free;
    end;
    if not MoveFileEx(PChar(Temp), PChar(FFileName), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
      RaiseLastOSError;
  except
    on E: Exception do
    begin
      DeleteFile(Temp);
      raise EBorionError.Create('IO_ERROR', 'não foi possível gravar ' + FFileName + ': ' + E.Message);
    end;
  end;
  FDirty := False;
end;

{ TBorionStorePlugin }

constructor TBorionStorePlugin.Create(const AppName: string);
begin
  inherited Create;
  FDir := BorionBaseDirPath(bdAppData, AppName);
  FAutoSave := True;
  FStores := TStringList.Create;
  FStores.Sorted := True;
end;

destructor TBorionStorePlugin.Destroy;
var
  I: Integer;
  Store: TBorionStoreData;
begin
  for I := 0 to FStores.Count - 1 do
  begin
    Store := TBorionStoreData(FStores.Objects[I]);
    if Store.Dirty then
      try
        Store.Save;
      except
        { fechando: não há a quem avisar }
      end;
    Store.Free;
  end;
  FStores.Free;
  inherited;
end;

function TBorionStorePlugin.Name: string;
begin
  Result := 'store';
end;

procedure TBorionStorePlugin.Install;
begin
  Command('load', CmdLoad);
  Command('get', CmdGet);
  Command('set', CmdSet);
  Command('has', CmdHas);
  Command('delete', CmdDelete);
  Command('clear', CmdClear);
  Command('entries', CmdEntries);
  Command('save', CmdSave);
  Command('reload', CmdReload);
end;

function TBorionStorePlugin.Abrir(const Nome: string): TBorionStoreData;
var
  Arquivo: string;
  I: Integer;
begin
  Arquivo := BorionStoreFileName(Nome);
  I := FStores.IndexOf(Arquivo);
  if I >= 0 then
  begin
    Result := TBorionStoreData(FStores.Objects[I]);
    Exit;
  end;
  Result := TBorionStoreData.Create(IncludeTrailingPathDelimiter(FDir) + Arquivo);
  try
    Result.Load;
  except
    Result.Free;
    raise;
  end;
  FStores.AddObject(Arquivo, Result);
end;

function TBorionStorePlugin.DoCall(Call: TBorionCall): TBorionStoreData;
begin
  if Call.ArgStr('store') = '' then
    raise EBorionError.Create('INVALID_STORE', 'store é obrigatório');
  Result := Abrir(Call.ArgStr('store'));
end;

function TBorionStorePlugin.ChaveDoCall(Call: TBorionCall): string;
begin
  if not ChaveCanonica(Call.ArgStr('key'), Result) then
    raise EBorionError.Create('INVALID_ARGS',
      'key deve ser um literal JSON de string só com ASCII (o @borion/api/store gera)');
end;

procedure TBorionStorePlugin.Mudou(Store: TBorionStoreData; const Chave, Valor: string;
  Apagada: Boolean);
var
  V: string;
begin
  if Ipc = nil then
    Exit;
  if Apagada then
    V := 'null'
  else
    V := JsonQuote(Valor);
  Ipc.EmitJson('store:change', '{"store":' + JsonQuote(ExtractFileName(Store.FileName)) +
    ',"key":' + JsonQuote(Chave) + ',"value":' + V + '}');
end;

procedure TBorionStorePlugin.Gravar(Store: TBorionStoreData);
begin
  Store.FDirty := True;
  if FAutoSave then
    Store.Save;
end;

procedure TBorionStorePlugin.PorValor(Store: TBorionStoreData; const Chave, Valor: string);
var
  I: Integer;
  Texto: string;
begin
  Texto := Trim(Valor);
  if not IsAsciiJson(Texto) then
    raise EBorionError.Create('INVALID_ARGS',
      'value deve ser um texto JSON válido só com ASCII (o @borion/api/store gera)');
  I := Store.IndexOf(Chave);
  if I >= 0 then
    Store.Values[I] := Texto
  else
  begin
    Store.Keys.Add(Chave);
    Store.Values.Add(Texto);
  end;
  Gravar(Store);
  Mudou(Store, Chave, Texto, False);
end;

function TBorionStorePlugin.Apagar(Store: TBorionStoreData; const Chave: string): Boolean;
var
  I: Integer;
begin
  I := Store.IndexOf(Chave);
  Result := I >= 0;
  if not Result then
    Exit;
  Store.Keys.Delete(I);
  Store.Values.Delete(I);
  Gravar(Store);
  Mudou(Store, Chave, '', True);
end;

procedure TBorionStorePlugin.CmdLoad(Call: TBorionCall);
begin
  Call.Result.AsInteger := DoCall(Call).Keys.Count;
end;

procedure TBorionStorePlugin.CmdGet(Call: TBorionCall);
var
  Store: TBorionStoreData;
  I: Integer;
begin
  Store := DoCall(Call);
  I := Store.IndexOf(ChaveDoCall(Call));
  if I >= 0 then
    Call.Result.AsString := Store.Values[I];  { senão: null }
end;

procedure TBorionStorePlugin.CmdSet(Call: TBorionCall);
var
  Store: TBorionStoreData;
  Chave: string;
begin
  Store := DoCall(Call);
  Chave := ChaveDoCall(Call);
  if (Call.Arg('value') = nil) or (Call.Arg('value').ValueType <> jvString) then
    raise EBorionError.Create('INVALID_ARGS', 'value deve ser o texto JSON do valor');
  PorValor(Store, Chave, Call.ArgStr('value'));
end;

procedure TBorionStorePlugin.CmdHas(Call: TBorionCall);
var
  Store: TBorionStoreData;
begin
  Store := DoCall(Call);
  Call.Result.AsBoolean := Store.IndexOf(ChaveDoCall(Call)) >= 0;
end;

procedure TBorionStorePlugin.CmdDelete(Call: TBorionCall);
var
  Store: TBorionStoreData;
begin
  Store := DoCall(Call);
  Call.Result.AsBoolean := Apagar(Store, ChaveDoCall(Call));
end;

procedure TBorionStorePlugin.CmdClear(Call: TBorionCall);
var
  Store: TBorionStoreData;
  Antes: TStringList;
  I: Integer;
begin
  Store := DoCall(Call);
  if Store.Keys.Count = 0 then
    Exit;
  Antes := TStringList.Create;
  try
    Antes.Assign(Store.Keys);
    Store.Keys.Clear;
    Store.Values.Clear;
    Gravar(Store);
    for I := 0 to Antes.Count - 1 do
      Mudou(Store, Antes[I], '', True);
  finally
    Antes.Free;
  end;
end;

procedure TBorionStorePlugin.CmdEntries(Call: TBorionCall);
var
  Store: TBorionStoreData;
  Lista, Par: TJsonArray;
  I: Integer;
begin
  Store := DoCall(Call);
  Lista := Call.Result.AsArray;
  for I := 0 to Store.Keys.Count - 1 do
  begin
    Par := Lista.Add.AsArray;
    Par.Put(Store.Keys[I]);
    Par.Put(Store.Values[I]);
  end;
end;

procedure TBorionStorePlugin.CmdSave(Call: TBorionCall);
begin
  DoCall(Call).Save;
end;

procedure TBorionStorePlugin.CmdReload(Call: TBorionCall);
var
  Store: TBorionStoreData;
begin
  Store := DoCall(Call);
  Store.Load;
  Call.Result.AsInteger := Store.Keys.Count;
end;

{ --- uso pelo Delphi --- }

function TBorionStorePlugin.ReadJson(const Store, Key: string; out Json: string): Boolean;
var
  Data: TBorionStoreData;
  I: Integer;
begin
  Data := Abrir(Store);
  I := Data.IndexOf(WideToJsonLiteral(Key));
  Result := I >= 0;
  if Result then
    Json := Data.Values[I]
  else
    Json := '';
end;

procedure TBorionStorePlugin.WriteJson(const Store, Key, Json: string);
begin
  PorValor(Abrir(Store), WideToJsonLiteral(Key), Json);
end;

function TBorionStorePlugin.ReadString(const Store, Key: string; const Default: WideString): WideString;
var
  Json: string;
begin
  if not (ReadJson(Store, Key, Json) and JsonLiteralToWide(Json, Result)) then
    Result := Default;
end;

procedure TBorionStorePlugin.WriteString(const Store, Key: string; const Value: WideString);
begin
  WriteJson(Store, Key, WideToJsonLiteral(Value));
end;

function TBorionStorePlugin.Delete(const Store, Key: string): Boolean;
begin
  Result := Apagar(Abrir(Store), WideToJsonLiteral(Key));
end;

procedure TBorionStorePlugin.Save(const Store: string);
begin
  Abrir(Store).Save;
end;

end.
