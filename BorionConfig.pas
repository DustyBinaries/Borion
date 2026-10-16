unit BorionConfig;

(*
  Borion — Native Application Engine
  O app.json: a configuração do app (como o tauri.conf.json), lida pela CLI no
  build e embutida no exe (recurso BORION_CONFIG, no mesmo .res dos assets).

    {
      "productName": "Meu App",
      "version": "0.1.0",
      "identifier": "com.exemplo.meu-app",
      "build": {
        "frontendDist": "frontend/dist",
        "devUrl": "http://localhost:5173"
      },
      "app": {
        "windows": [
          { "title": "Meu App", "width": 1000, "height": 700, "minWidth": 600,
            "resizable": true, "center": true, "maximized": false,
            "decorations": true, "alwaysOnTop": false }
        ],
        "security": { "csp": "default-src 'self'" }
      }
    }

  Tudo é opcional. Tipo errado ou valor inválido é erro (EBorionConfig); chave
  desconhecida (um "widht") vira aviso em Warnings.
*)

interface

uses
  Windows, SysUtils, Classes, Jsons;

const
  BORION_CONFIG_RESOURCE = 'BORION_CONFIG';
  BORION_CONFIG_FILE = 'app.json';

type
  EBorionConfig = class(Exception);

  { A janela principal (app.windows[0]) }
  TBorionWindowConfig = record
    Title: string;                  { '' = o productName }
    Width, Height: Integer;
    MinWidth, MinHeight: Integer;   { 0 = sem limite }
    MaxWidth, MaxHeight: Integer;
    Resizable: Boolean;
    Center: Boolean;
    Maximized: Boolean;
    Decorations: Boolean;           { False: sem borda nem barra de título }
    AlwaysOnTop: Boolean;
  end;

  TBorionConfig = class
  private
    FIdentifier: string;
    FProductName: string;
    FVersion: string;
    FFrontendDist: string;
    FDevUrl: string;
    FCsp: string;
    FWindow: TBorionWindowConfig;
    FWarnings: TStringList;
    FLoaded: Boolean;
    procedure Ler(Raiz: TJsonObject);
    procedure LerJanela(O: TJsonObject; const Caminho: string);
    procedure Avisar(O: TJsonObject; const Caminho, Conhecidas: string);
  public
    constructor Create;
    destructor Destroy; override;
    { Volta aos padrões (o app sem app.json) }
    procedure Clear;
    { Json: o conteúdo do arquivo, em UTF-8 (com ou sem BOM). Levanta EBorionConfig. }
    procedure LoadFromJson(const Json: string);
    procedure LoadFromFile(const FileName: string);
    { O recurso BORION_CONFIG do módulo; False (e os padrões) se não houver }
    function LoadFromResource(Instance: HMODULE): Boolean;
    { Porta do devUrl (0 se não houver devUrl) }
    function DevPort: Integer;
    property Identifier: string read FIdentifier write FIdentifier;
    property ProductName: string read FProductName write FProductName;
    property Version: string read FVersion write FVersion;
    { Relativo à pasta do app.json }
    property FrontendDist: string read FFrontendDist write FFrontendDist;
    property DevUrl: string read FDevUrl write FDevUrl;
    { app.security.csp: o header Content-Security-Policy dos assets ('' = nenhum) }
    property Csp: string read FCsp write FCsp;
    property Window: TBorionWindowConfig read FWindow write FWindow;
    { Avisos da última leitura (chaves desconhecidas...) }
    property Warnings: TStringList read FWarnings;
    { Um app.json foi lido }
    property Loaded: Boolean read FLoaded;
  end;

{ A janela sem configuração: 1000x700, redimensionável, centralizada, com borda }
function BorionDefaultWindow: TBorionWindowConfig;
{ A configuração do app: o app.json embutido no exe, lido na primeira chamada.
  Sem recurso, ou com erro nele, os padrões (o erro fica em BorionAppConfigError). }
function BorionAppConfig: TBorionConfig;
function BorionAppConfigError: string;
{ '1.2.3', '1.2.3-beta.1', '1.0.0.42': até 4 números de 0 a 65535 e um sufixo
  opcional depois de '-' ou '+' }
function BorionIsValidVersion(const Version: string): Boolean;
{ 'com.exemplo.meu-app': letras, dígitos, '-' e '_', em pelo menos duas partes separadas por '.' }
function BorionIsValidIdentifier(const Identifier: string): Boolean;

implementation

uses
  BorionJson;

var
  GConfig: TBorionConfig;
  GConfigError: string;

function BorionDefaultWindow: TBorionWindowConfig;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Width := 1000;
  Result.Height := 700;
  Result.Resizable := True;
  Result.Center := True;
  Result.Decorations := True;
end;

function BorionAppConfig: TBorionConfig;
begin
  if GConfig = nil then
  begin
    GConfig := TBorionConfig.Create;
    try
      GConfig.LoadFromResource(HInstance);
    except
      on E: Exception do
      begin
        GConfig.Clear;
        GConfigError := E.Message;
      end;
    end;
  end;
  Result := GConfig;
end;

function BorionAppConfigError: string;
begin
  BorionAppConfig;
  Result := GConfigError;
end;

function BorionIsValidVersion(const Version: string): Boolean;
var
  Numeros: string;
  I, Partes, Digitos, Valor: Integer;
begin
  Result := False;
  Numeros := Version;
  I := 1;
  while I <= Length(Numeros) do
  begin
    if Numeros[I] in ['-', '+'] then
    begin
      if I = Length(Numeros) then
        Exit;  { sufixo vazio }
      Numeros := Copy(Numeros, 1, I - 1);
      Break;
    end;
    Inc(I);
  end;
  Partes := 1;
  Digitos := 0;
  Valor := 0;
  for I := 1 to Length(Numeros) do
    case Numeros[I] of
      '0'..'9':
        begin
          Inc(Digitos);
          Valor := Valor * 10 + Ord(Numeros[I]) - Ord('0');
          if (Digitos > 5) or (Valor > 65535) then
            Exit;
        end;
      '.':
        begin
          if Digitos = 0 then
            Exit;
          Inc(Partes);
          Digitos := 0;
          Valor := 0;
        end;
    else
      Exit;
    end;
  Result := (Digitos > 0) and (Partes <= 4);
end;

function BorionIsValidIdentifier(const Identifier: string): Boolean;
var
  I, Partes, Tamanho: Integer;
begin
  Result := False;
  Partes := 1;
  Tamanho := 0;
  for I := 1 to Length(Identifier) do
    case Identifier[I] of
      'A'..'Z', 'a'..'z', '0'..'9', '-', '_':
        Inc(Tamanho);
      '.':
        begin
          if Tamanho = 0 then
            Exit;
          Inc(Partes);
          Tamanho := 0;
        end;
    else
      Exit;
    end;
  Result := (Tamanho > 0) and (Partes >= 2);
end;

{ --- leitura tipada ----------------------------------------------------------- }

function Membro(O: TJsonObject; const Nome: string): TJsonValue;
var
  I: Integer;
begin
  I := O.Find(Nome);
  if I < 0 then
    Result := nil
  else
  begin
    Result := O.Items[I].Value;
    if Result.ValueType = jvNull then
      Result := nil;  { null = ausente }
  end;
end;

procedure Falhar(const Caminho, Esperado: string);
begin
  raise EBorionConfig.CreateFmt('app.json: "%s" deve ser %s', [Caminho, Esperado]);
end;

function Juntar(const Caminho, Nome: string): string;
begin
  if Caminho = '' then
    Result := Nome
  else
    Result := Caminho + '.' + Nome;
end;

procedure LerTexto(O: TJsonObject; const Caminho, Nome: string; var Destino: string);
var
  V: TJsonValue;
begin
  V := Membro(O, Nome);
  if V = nil then
    Exit;
  if V.ValueType <> jvString then
    Falhar(Juntar(Caminho, Nome), 'um texto');
  Destino := V.AsString;
end;

procedure LerInteiro(O: TJsonObject; const Caminho, Nome: string; Minimo: Integer; var Destino: Integer);
var
  V: TJsonValue;
begin
  V := Membro(O, Nome);
  if V = nil then
    Exit;
  if (V.ValueType <> jvNumber) or (Frac(V.AsNumber) <> 0) or (V.AsNumber < Minimo) or
    (V.AsNumber > 32767) then
    Falhar(Juntar(Caminho, Nome), Format('um número inteiro de %d a 32767', [Minimo]));
  Destino := Trunc(V.AsNumber);
end;

procedure LerLogico(O: TJsonObject; const Caminho, Nome: string; var Destino: Boolean);
var
  V: TJsonValue;
begin
  V := Membro(O, Nome);
  if V = nil then
    Exit;
  if V.ValueType <> jvBoolean then
    Falhar(Juntar(Caminho, Nome), 'true ou false');
  Destino := V.AsBoolean;
end;

{ O objeto Nome dentro de O; nil se ausente }
function LerObjeto(O: TJsonObject; const Caminho, Nome: string): TJsonObject;
var
  V: TJsonValue;
begin
  Result := nil;
  V := Membro(O, Nome);
  if V = nil then
    Exit;
  if V.ValueType <> jvObject then
    Falhar(Juntar(Caminho, Nome), 'um objeto');
  Result := V.AsObject;
end;

{ --- TBorionConfig ------------------------------------------------------------ }

constructor TBorionConfig.Create;
begin
  inherited Create;
  FWarnings := TStringList.Create;
  Clear;
end;

destructor TBorionConfig.Destroy;
begin
  FWarnings.Free;
  inherited;
end;

procedure TBorionConfig.Clear;
begin
  FIdentifier := '';
  FProductName := '';
  FVersion := '';
  FFrontendDist := '';
  FDevUrl := '';
  FCsp := '';
  FWindow := BorionDefaultWindow;
  FWarnings.Clear;
  FLoaded := False;
end;

procedure TBorionConfig.Avisar(O: TJsonObject; const Caminho, Conhecidas: string);
var
  I: Integer;
begin
  for I := 0 to O.Count - 1 do
    if Pos('|' + O.Items[I].Name + '|', '|' + Conhecidas + '|') = 0 then
      FWarnings.Add(Format('app.json: chave desconhecida "%s"', [Juntar(Caminho, O.Items[I].Name)]));
end;

procedure TBorionConfig.LerJanela(O: TJsonObject; const Caminho: string);
begin
  Avisar(O, Caminho, 'title|width|height|minWidth|minHeight|maxWidth|maxHeight|resizable|center|' +
    'maximized|decorations|alwaysOnTop');
  LerTexto(O, Caminho, 'title', FWindow.Title);
  LerInteiro(O, Caminho, 'width', 1, FWindow.Width);
  LerInteiro(O, Caminho, 'height', 1, FWindow.Height);
  LerInteiro(O, Caminho, 'minWidth', 0, FWindow.MinWidth);
  LerInteiro(O, Caminho, 'minHeight', 0, FWindow.MinHeight);
  LerInteiro(O, Caminho, 'maxWidth', 0, FWindow.MaxWidth);
  LerInteiro(O, Caminho, 'maxHeight', 0, FWindow.MaxHeight);
  LerLogico(O, Caminho, 'resizable', FWindow.Resizable);
  LerLogico(O, Caminho, 'center', FWindow.Center);
  LerLogico(O, Caminho, 'maximized', FWindow.Maximized);
  LerLogico(O, Caminho, 'decorations', FWindow.Decorations);
  LerLogico(O, Caminho, 'alwaysOnTop', FWindow.AlwaysOnTop);
  if (FWindow.MaxWidth > 0) and (FWindow.MaxWidth < FWindow.MinWidth) then
    raise EBorionConfig.CreateFmt('app.json: "%s.maxWidth" é menor que o minWidth', [Caminho]);
  if (FWindow.MaxHeight > 0) and (FWindow.MaxHeight < FWindow.MinHeight) then
    raise EBorionConfig.CreateFmt('app.json: "%s.maxHeight" é menor que o minHeight', [Caminho]);
end;

procedure TBorionConfig.Ler(Raiz: TJsonObject);
var
  Build, App, Security: TJsonObject;
  V: TJsonValue;
  Janelas: TJsonArray;
  I: Integer;
begin
  Avisar(Raiz, '', '$schema|productName|version|identifier|build|app');
  LerTexto(Raiz, '', 'productName', FProductName);
  LerTexto(Raiz, '', 'version', FVersion);
  if (FVersion <> '') and not BorionIsValidVersion(FVersion) then
    raise EBorionConfig.CreateFmt('app.json: "version" inválida: "%s" (use o formato 1.2.3)', [FVersion]);
  LerTexto(Raiz, '', 'identifier', FIdentifier);
  if (FIdentifier <> '') and not BorionIsValidIdentifier(FIdentifier) then
    raise EBorionConfig.CreateFmt('app.json: "identifier" inválido: "%s" (use o formato ' +
      'com.empresa.app, só com letras, dígitos, "-" e "_")', [FIdentifier]);

  Build := LerObjeto(Raiz, '', 'build');
  if Build <> nil then
  begin
    Avisar(Build, 'build', 'frontendDist|devUrl');
    LerTexto(Build, 'build', 'frontendDist', FFrontendDist);
    LerTexto(Build, 'build', 'devUrl', FDevUrl);
    if (FDevUrl <> '') and not (SameText(Copy(FDevUrl, 1, 7), 'http://') or
      SameText(Copy(FDevUrl, 1, 8), 'https://')) then
      Falhar('build.devUrl', 'uma URL http:// ou https://');
  end;

  App := LerObjeto(Raiz, '', 'app');
  if App = nil then
    Exit;
  Avisar(App, 'app', 'windows|security');
  V := Membro(App, 'windows');
  if V <> nil then
  begin
    if V.ValueType <> jvArray then
      Falhar('app.windows', 'uma lista de janelas');
    Janelas := V.AsArray;
    for I := 0 to Janelas.Count - 1 do
      if Janelas[I].ValueType <> jvObject then
        Falhar(Format('app.windows[%d]', [I]), 'um objeto');
    if Janelas.Count > 0 then
      LerJanela(Janelas[0].AsObject, 'app.windows[0]');
    if Janelas.Count > 1 then
      FWarnings.Add('app.json: só a primeira janela de "app.windows" é usada por enquanto');
  end;
  Security := LerObjeto(App, 'app', 'security');
  if Security <> nil then
  begin
    Avisar(Security, 'app.security', 'csp');
    LerTexto(Security, 'app.security', 'csp', FCsp);
  end;
end;

procedure TBorionConfig.LoadFromJson(const Json: string);
var
  S: string;
  W: WideString;
  I: Integer;
  Raiz: TJsonObject;
begin
  Clear;
  S := Json;
  if Copy(S, 1, 3) = #$EF#$BB#$BF then
    Delete(S, 1, 3);
  W := UTF8Decode(S);
  if (W = '') and (S <> '') then
    raise EBorionConfig.Create('app.json: o arquivo não está em UTF-8');
  I := 1;
  while (I <= Length(W)) and ((W[I] = ' ') or (W[I] = #9) or (W[I] = #13) or (W[I] = #10)) do
    Inc(I);
  if (I > Length(W)) or (W[I] <> '{') then
    raise EBorionConfig.Create('app.json: o conteúdo deve ser um objeto JSON ({ ... })');
  Raiz := TJsonObject.Create;
  try
    try
      Raiz.Parse(WideJsonToAnsi(W));
    except
      on E: Exception do
        raise EBorionConfig.Create('app.json: JSON inválido: ' + E.Message);
    end;
    Ler(Raiz);
  finally
    Raiz.Free;
  end;
  FLoaded := True;
end;

procedure TBorionConfig.LoadFromFile(const FileName: string);
var
  F: TFileStream;
  S: string;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(S, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(S[1], F.Size);
  finally
    F.Free;
  end;
  LoadFromJson(S);
end;

function TBorionConfig.LoadFromResource(Instance: HMODULE): Boolean;
var
  R: TResourceStream;
  S: string;
begin
  Clear;
  Result := FindResource(Instance, BORION_CONFIG_RESOURCE, RT_RCDATA) <> 0;
  if not Result then
    Exit;
  R := TResourceStream.Create(Instance, BORION_CONFIG_RESOURCE, RT_RCDATA);
  try
    SetLength(S, R.Size);
    if R.Size > 0 then
      R.ReadBuffer(S[1], R.Size);
  finally
    R.Free;
  end;
  LoadFromJson(S);
end;

function TBorionConfig.DevPort: Integer;
var
  S: string;
  P: Integer;
begin
  Result := 0;
  if FDevUrl = '' then
    Exit;
  S := Copy(FDevUrl, Pos('://', FDevUrl) + 3, MaxInt);
  P := Pos('/', S);
  if P > 0 then
    S := Copy(S, 1, P - 1);
  P := Pos(':', S);
  if P > 0 then
    Result := StrToIntDef(Copy(S, P + 1, MaxInt), 0)
  else if SameText(Copy(FDevUrl, 1, 8), 'https://') then
    Result := 443
  else
    Result := 80;
end;

initialization

finalization
  GConfig.Free;

end.
