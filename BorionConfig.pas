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
            "decorations": true, "alwaysOnTop": false, "fullscreen": false,
            "devTools": true }
        ],
        "security": { "csp": "default-src 'self'" }
      },
      "bundle": {
        "icon": ["icons/32x32.png", "icons/icon.icns", "icons/icon.ico"]
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

  { Uma janela (app.windows[I]); a primeira é a principal }
  TBorionWindowConfig = record
    WindowLabel: string;            { 'main' na primeira, se não informado }
    Url: string;                    { caminho no app: '/', '/config.html' }
    Visible: Boolean;
    CreateAtStart: Boolean;         { "create": False só define (abra com BorionWindows.Open) }
    Title: string;                  { '' = o productName }
    Width, Height: Integer;
    MinWidth, MinHeight: Integer;   { 0 = sem limite }
    MaxWidth, MaxHeight: Integer;
    Resizable: Boolean;
    Center: Boolean;
    Maximized: Boolean;
    Decorations: Boolean;           { False: sem borda nem barra de título }
    AlwaysOnTop: Boolean;
    Fullscreen: Boolean;            { abre em tela cheia (precisa do plugin window) }
    DevTools: Boolean;              { False: sem DevTools (F12, Ctrl+Shift+I) }
  end;

  TBorionConfig = class
  private
    FIdentifier: string;
    FProductName: string;
    FVersion: string;
    FFrontendDist: string;
    FDevUrl: string;
    FCsp: string;
    FIcons: TStringList;
    FBundleActive: Boolean;
    FWindows: array of TBorionWindowConfig;
    FWarnings: TStringList;
    FLoaded: Boolean;
    procedure Ler(Raiz: TJsonObject);
    procedure LerJanela(O: TJsonObject; const Caminho: string; var W: TBorionWindowConfig);
    function GetWindow: TBorionWindowConfig;
    procedure SetWindow(const Value: TBorionWindowConfig);
    function GetWindows(Index: Integer): TBorionWindowConfig;
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
    { bundle.icon: os ícones do app, relativos à pasta do app.json, como no
      tauri.conf.json. O Windows só usa o .ico (os .png e .icns são aceitos e
      ignorados) }
    property Icons: TStringList read FIcons;
    { O primeiro .ico de Icons, o que o borion build grava no exe ('' = nenhum) }
    function IconFile: string;
    { bundle.active: aceito, como no Tauri; o instalador é da Fase 7 }
    property BundleActive: Boolean read FBundleActive write FBundleActive;
    { A janela principal (Windows[0]) }
    property Window: TBorionWindowConfig read GetWindow write SetWindow;
    { Todas as janelas de app.windows (sempre pelo menos a principal) }
    function WindowCount: Integer;
    property Windows[Index: Integer]: TBorionWindowConfig read GetWindows;
    { A janela com esse rótulo; False se não houver }
    function FindWindow(const WindowLabel: string; out Config: TBorionWindowConfig): Boolean;
    { Avisos da última leitura (chaves desconhecidas...) }
    property Warnings: TStringList read FWarnings;
    { Um app.json foi lido }
    property Loaded: Boolean read FLoaded;
  end;

{ A janela sem configuração: 'main', '/', 1000x700, redimensionável, centralizada, com borda }
function BorionDefaultWindow: TBorionWindowConfig;
{ Rótulo de janela: letras, dígitos, '-' e '_' }
function BorionIsValidWindowLabel(const WindowLabel: string): Boolean;
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
  Finalize(Result);
  FillChar(Result, SizeOf(Result), 0);
  Result.WindowLabel := 'main';
  Result.Url := '/';
  Result.Visible := True;
  Result.CreateAtStart := True;
  Result.Width := 1000;
  Result.Height := 700;
  Result.Resizable := True;
  Result.Center := True;
  Result.Decorations := True;
  Result.DevTools := True;
end;

function BorionIsValidWindowLabel(const WindowLabel: string): Boolean;
var
  I: Integer;
begin
  Result := WindowLabel <> '';
  for I := 1 to Length(WindowLabel) do
    if not (WindowLabel[I] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then
    begin
      Result := False;
      Exit;
    end;
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
  FIcons := TStringList.Create;
  Clear;
end;

destructor TBorionConfig.Destroy;
begin
  FIcons.Free;
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
  FIcons.Clear;
  FBundleActive := False;
  SetLength(FWindows, 1);
  FWindows[0] := BorionDefaultWindow;
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

procedure TBorionConfig.LerJanela(O: TJsonObject; const Caminho: string; var W: TBorionWindowConfig);
begin
  Avisar(O, Caminho, 'label|url|visible|create|title|width|height|minWidth|minHeight|maxWidth|' +
    'maxHeight|resizable|center|maximized|decorations|alwaysOnTop|fullscreen|devTools');
  LerTexto(O, Caminho, 'label', W.WindowLabel);
  if not BorionIsValidWindowLabel(W.WindowLabel) then
    raise EBorionConfig.CreateFmt('app.json: "%s.label" inválido: "%s" (use letras, dígitos, "-" e "_")',
      [Caminho, W.WindowLabel]);
  LerTexto(O, Caminho, 'url', W.Url);
  if (Copy(W.Url, 1, 1) <> '/') or (Copy(W.Url, 1, 2) = '//') then
    Falhar(Juntar(Caminho, 'url'), 'um caminho do app começando com "/" (ex.: "/config.html")');
  LerLogico(O, Caminho, 'visible', W.Visible);
  LerLogico(O, Caminho, 'create', W.CreateAtStart);
  LerTexto(O, Caminho, 'title', W.Title);
  LerInteiro(O, Caminho, 'width', 1, W.Width);
  LerInteiro(O, Caminho, 'height', 1, W.Height);
  LerInteiro(O, Caminho, 'minWidth', 0, W.MinWidth);
  LerInteiro(O, Caminho, 'minHeight', 0, W.MinHeight);
  LerInteiro(O, Caminho, 'maxWidth', 0, W.MaxWidth);
  LerInteiro(O, Caminho, 'maxHeight', 0, W.MaxHeight);
  LerLogico(O, Caminho, 'resizable', W.Resizable);
  LerLogico(O, Caminho, 'center', W.Center);
  LerLogico(O, Caminho, 'maximized', W.Maximized);
  LerLogico(O, Caminho, 'decorations', W.Decorations);
  LerLogico(O, Caminho, 'alwaysOnTop', W.AlwaysOnTop);
  LerLogico(O, Caminho, 'fullscreen', W.Fullscreen);
  LerLogico(O, Caminho, 'devTools', W.DevTools);
  if (W.MaxWidth > 0) and (W.MaxWidth < W.MinWidth) then
    raise EBorionConfig.CreateFmt('app.json: "%s.maxWidth" é menor que o minWidth', [Caminho]);
  if (W.MaxHeight > 0) and (W.MaxHeight < W.MinHeight) then
    raise EBorionConfig.CreateFmt('app.json: "%s.maxHeight" é menor que o minHeight', [Caminho]);
end;

function TBorionConfig.GetWindow: TBorionWindowConfig;
begin
  Result := FWindows[0];
end;

procedure TBorionConfig.SetWindow(const Value: TBorionWindowConfig);
begin
  FWindows[0] := Value;
end;

function TBorionConfig.WindowCount: Integer;
begin
  Result := Length(FWindows);
end;

function TBorionConfig.GetWindows(Index: Integer): TBorionWindowConfig;
begin
  Result := FWindows[Index];
end;

function TBorionConfig.IconFile: string;
var
  I: Integer;
begin
  for I := 0 to FIcons.Count - 1 do
    if SameText(ExtractFileExt(FIcons[I]), '.ico') then
    begin
      Result := FIcons[I];
      Exit;
    end;
  Result := '';
end;

function TBorionConfig.FindWindow(const WindowLabel: string; out Config: TBorionWindowConfig): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FWindows) do
    if FWindows[I].WindowLabel = WindowLabel then
    begin
      Config := FWindows[I];
      Result := True;
      Exit;
    end;
  Result := False;
end;

procedure TBorionConfig.Ler(Raiz: TJsonObject);
var
  Build, App, Security, Bundle: TJsonObject;
  V: TJsonValue;
  Janelas, Icones: TJsonArray;
  I, J: Integer;
  Caminho: string;
begin
  Avisar(Raiz, '', '$schema|productName|version|identifier|build|app|bundle');
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

  Bundle := LerObjeto(Raiz, '', 'bundle');
  if Bundle <> nil then
  begin
    Avisar(Bundle, 'bundle', 'active|icon');
    LerLogico(Bundle, 'bundle', 'active', FBundleActive);
    V := Membro(Bundle, 'icon');
    if V <> nil then
    begin
      if V.ValueType <> jvArray then
        Falhar('bundle.icon', 'uma lista de arquivos (ex.: ["icons/icon.ico"])');
      Icones := V.AsArray;
      for I := 0 to Icones.Count - 1 do
      begin
        if (Icones[I].ValueType <> jvString) or (Trim(Icones[I].AsString) = '') then
          Falhar(Format('bundle.icon[%d]', [I]), 'o caminho de um arquivo');
        FIcons.Add(Icones[I].AsString);
      end;
      if (FIcons.Count > 0) and (IconFile = '') then
        raise EBorionConfig.Create('app.json: "bundle.icon" precisa de um arquivo .ico: é o ' +
          'ícone do exe no Windows (os .png e .icns ficam para outras plataformas)');
    end;
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
      SetLength(FWindows, Janelas.Count);
    for I := 0 to Janelas.Count - 1 do
    begin
      Caminho := Format('app.windows[%d]', [I]);
      FWindows[I] := BorionDefaultWindow;
      if I > 0 then
      begin
        FWindows[I].WindowLabel := '';
        if Janelas[I].AsObject.Find('label') < 0 then
          raise EBorionConfig.CreateFmt('app.json: "%s.label" é obrigatório (só a primeira janela ' +
            'pode ficar sem, e vira "main")', [Caminho]);
      end;
      LerJanela(Janelas[I].AsObject, Caminho, FWindows[I]);
      for J := 0 to I - 1 do
        if FWindows[J].WindowLabel = FWindows[I].WindowLabel then
          raise EBorionConfig.CreateFmt('app.json: "%s.label" repetido: "%s"', [Caminho, FWindows[I].WindowLabel]);
    end;
    if not FWindows[0].CreateAtStart then
      raise EBorionConfig.Create('app.json: a janela principal ("app.windows[0]") é sempre criada: ' +
        'tire o "create": false dela');
    if not FWindows[0].Visible then
      FWarnings.Add('app.json: a janela principal começa escondida ("visible": false); mostre-a ' +
        'pelo JS (window.show) ou pelo Delphi');
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
