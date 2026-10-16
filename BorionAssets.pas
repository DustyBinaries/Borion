unit BorionAssets;

(*
  Borion — Native Application Engine
  Servidor de assets do frontend: serve o pacote BORION_ASSETS (gerado por
  "borion pack") num host virtual, com fallback de SPA, headers padrão e modo dev.

    Assets := TBorionAssets.Create(Self, Browser);       // pacote do exe
    Ipc.AllowOrigin(BorionOriginOf(Assets.StartUrl));
    Browser.CreateWebView;
    Browser.Navigate(Assets.StartUrl);

  Modo dev: com --dev-url=http://localhost:5173 na linha de comando (ou a
  variável BORION_DEV_URL), StartUrl aponta para o servidor do Vite e o
  hot-reload funciona; o pacote embutido nem precisa existir.

  Modo dev sem servidor: com --dev-dir=<pasta> (ou BORION_DEV_DIR), os arquivos
  são servidos direto da pasta (ex.: web\), sem cache, e a página recarrega
  sozinha quando um arquivo da pasta muda (LiveReload). É o que o
  "borion dev" usa nos projetos sem Node.

  Requisições da API do app (ex.: /api/...) podem ser tratadas no OnRequest,
  que roda antes dos assets. Com TBorionAssets, use o OnRequest em vez do
  Browser.OnWebResourceRequested (que passa a ser do TBorionAssets).
*)

interface

uses
  Windows, Messages, SysUtils, Classes, WebView2Browser, BorionPack;

const
  BORION_DEFAULT_HOST = 'app.local';

type
  TBorionAssets = class(TComponent)
  private
    FBrowser: TWebView2Browser;
    FHost: string;
    FPack: TBorionPack;
    FPackError: string;
    FIndexFile: string;
    FSpaFallback: Boolean;
    FCacheControl: string;
    FContentSecurityPolicy: string;
    FDevUrl: string;
    FDevDir: string;
    FLiveReload: Boolean;
    FVigia: TThread;
    FJanela: HWND;
    FOnLiveReload: TNotifyEvent;
    FOnRequest: TWV2WebResourceRequestedEvent;
    FPreviousHandler: TWV2WebResourceRequestedEvent;
    procedure WebResourceRequested(Sender: TObject; Request: TWV2WebResourceRequest;
      Response: TWV2WebResourceResponse; var Handled: Boolean);
    function GetOrigin: string;
    procedure WndProc(var Message: TMessage);
    function ServirDaPasta(const Path: string; Response: TWV2WebResourceResponse): Boolean;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    { ABrowser = nil: só o servidor (testes). Carrega o pacote BORION_ASSETS do
      exe se existir; sem pacote, toda requisição recebe 404 (útil no modo dev). }
    constructor Create(AOwner: TComponent; ABrowser: TWebView2Browser;
      const AHost: string = BORION_DEFAULT_HOST); reintroduce;
    destructor Destroy; override;

    { Troca o pacote (o TBorionAssets passa a ser o dono) }
    procedure SetPack(APack: TBorionPack);

    { Resposta para um caminho de URL (sem host e sem query, ainda codificado,
      ex.: 'img/a%C3%A7%C3%A3o.png'). Sempre preenche Response (200 ou 404). }
    procedure ServePath(const UrlPath: string; Response: TWV2WebResourceResponse);

    { https://<Host>/<Path> }
    function Url(const Path: string = ''): WideString;
    { DevUrl se estiver em modo dev com servidor; senão a raiz do host (https://<Host>/) }
    function StartUrl: WideString;
    { Modo dev: DevUrl ou DevDir }
    function IsDev: Boolean;
    { Começa a acompanhar o DevDir (o Create já chama, se houver DevDir) }
    procedure StartLiveReload;

    property Browser: TWebView2Browser read FBrowser;
    property Pack: TBorionPack read FPack;
    { Motivo de não haver pacote (ex.: recurso ausente), para diagnóstico }
    property PackError: string read FPackError;
    property Host: string read FHost;
    { https://<Host> }
    property Origin: string read GetOrigin;
    property IndexFile: string read FIndexFile write FIndexFile;
    { Caminho sem extensão que não existe no pacote -> IndexFile (roteamento de SPA) }
    property SpaFallback: Boolean read FSpaFallback write FSpaFallback;
    { Padrão 'no-cache': o WebView2 guarda cache entre versões do exe }
    property CacheControl: string read FCacheControl write FCacheControl;
    { Vazio = sem o header }
    property ContentSecurityPolicy: string read FContentSecurityPolicy write FContentSecurityPolicy;
    { Lido de --dev-url / BORION_DEV_URL na criação; pode ser trocado antes de navegar }
    property DevUrl: string read FDevUrl write FDevUrl;
    { Lido de --dev-dir / BORION_DEV_DIR: serve os arquivos desta pasta, no lugar do pacote }
    property DevDir: string read FDevDir write FDevDir;
    { Com DevDir: recarregar a página quando um arquivo da pasta muda (padrão: True) }
    property LiveReload: Boolean read FLiveReload write FLiveReload;
    { Um arquivo do DevDir mudou (antes do reload da página) }
    property OnLiveReload: TNotifyEvent read FOnLiveReload write FOnLiveReload;
    { Requisições filtradas, antes dos assets (ex.: uma API em /api/) }
    property OnRequest: TWV2WebResourceRequestedEvent read FOnRequest write FOnRequest;
  end;

{ URL do servidor de desenvolvimento: --dev-url=<url> ou --dev-url <url> nos
  parâmetros, ou EnvValue (BORION_DEV_URL). '' se não houver. }
function BorionDevUrlFrom(Params: TStrings; const EnvValue: string): string;
{ O mesmo, a partir da linha de comando e do ambiente do processo }
function BorionDevUrl: string;
{ Pasta do modo dev sem servidor: --dev-dir=<pasta> ou BORION_DEV_DIR; '' se não houver }
function BorionDevDir: string;
{ Valor de --chave=<valor> ou --chave <valor> em Params; EnvValue se não houver }
function BorionParamValue(Params: TStrings; const Key, EnvValue: string): string;

{ Content-Type pela extensão do caminho }
function BorionMimeType(const Path: string): string;

implementation

function BorionDevUrlFrom(Params: TStrings; const EnvValue: string): string;
begin
  Result := BorionParamValue(Params, '--dev-url', EnvValue);
end;

function BorionParamValue(Params: TStrings; const Key, EnvValue: string): string;
var
  I: Integer;
  P: string;
begin
  Result := '';
  for I := 0 to Params.Count - 1 do
  begin
    P := Params[I];
    if SameText(Copy(P, 1, Length(Key) + 1), Key + '=') then
    begin
      Result := Copy(P, Length(Key) + 2, MaxInt);
      Break;
    end;
    if SameText(P, Key) and (I < Params.Count - 1) then
    begin
      Result := Params[I + 1];
      Break;
    end;
  end;
  if Result = '' then
    Result := EnvValue;
  Result := Trim(Result);
end;

function BorionDevUrl: string;
var
  Params: TStringList;
  I: Integer;
begin
  Params := TStringList.Create;
  try
    for I := 1 to ParamCount do
      Params.Add(ParamStr(I));
    Result := BorionDevUrlFrom(Params, GetEnvironmentVariable('BORION_DEV_URL'));
  finally
    Params.Free;
  end;
end;

function BorionDevDir: string;
var
  Params: TStringList;
  I: Integer;
begin
  Params := TStringList.Create;
  try
    for I := 1 to ParamCount do
      Params.Add(ParamStr(I));
    Result := BorionParamValue(Params, '--dev-dir', GetEnvironmentVariable('BORION_DEV_DIR'));
    if Result <> '' then
      Result := ExcludeTrailingPathDelimiter(ExpandFileName(Result));
  finally
    Params.Free;
  end;
end;

const
  WM_BORION_RELOAD = WM_USER + 60;

type
  { Acompanha a pasta do DevDir e avisa a janela do TBorionAssets }
  TVigiaDePasta = class(TThread)
  private
    FPasta: string;
    FJanela: HWND;
    FParar: THandle;
  protected
    procedure Execute; override;
  public
    constructor Create(const Pasta: string; Janela: HWND);
    destructor Destroy; override;
    procedure Parar;
  end;

constructor TVigiaDePasta.Create(const Pasta: string; Janela: HWND);
begin
  FPasta := Pasta;
  FJanela := Janela;
  FParar := CreateEvent(nil, True, False, nil);
  inherited Create(False);
end;

destructor TVigiaDePasta.Destroy;
begin
  Parar;
  inherited;  { espera o Execute terminar }
  CloseHandle(FParar);
end;

procedure TVigiaDePasta.Parar;
begin
  Terminate;
  SetEvent(FParar);
end;

procedure TVigiaDePasta.Execute;
var
  Mudanca: THandle;
  Esperar: array[0..1] of THandle;
begin
  Mudanca := FindFirstChangeNotification(PChar(FPasta), True,
    FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME or FILE_NOTIFY_CHANGE_LAST_WRITE);
  if Mudanca = INVALID_HANDLE_VALUE then
    Exit;
  try
    Esperar[0] := FParar;
    Esperar[1] := Mudanca;
    while not Terminated do
    begin
      if WaitForMultipleObjects(2, @Esperar, False, INFINITE) <> WAIT_OBJECT_0 + 1 then
        Break;
      { um salvar no editor gera vários avisos seguidos: junta todos num reload só }
      repeat
        FindNextChangeNotification(Mudanca);
      until WaitForMultipleObjects(2, @Esperar, False, 200) <> WAIT_OBJECT_0 + 1;
      if Terminated then
        Break;
      PostMessage(FJanela, WM_BORION_RELOAD, 0, 0);
    end;
  finally
    FindCloseChangeNotification(Mudanca);
  end;
end;

function BorionMimeType(const Path: string): string;
const
  Tabela: array[0..39] of array[0..1] of string = (
    ('.html', 'text/html; charset=utf-8'),
    ('.htm', 'text/html; charset=utf-8'),
    ('.css', 'text/css; charset=utf-8'),
    ('.js', 'text/javascript; charset=utf-8'),
    ('.mjs', 'text/javascript; charset=utf-8'),
    ('.cjs', 'text/javascript; charset=utf-8'),
    ('.json', 'application/json; charset=utf-8'),
    ('.map', 'application/json; charset=utf-8'),
    ('.webmanifest', 'application/manifest+json; charset=utf-8'),
    ('.txt', 'text/plain; charset=utf-8'),
    ('.md', 'text/markdown; charset=utf-8'),
    ('.csv', 'text/csv; charset=utf-8'),
    ('.xml', 'application/xml; charset=utf-8'),
    ('.svg', 'image/svg+xml'),
    ('.png', 'image/png'),
    ('.jpg', 'image/jpeg'),
    ('.jpeg', 'image/jpeg'),
    ('.gif', 'image/gif'),
    ('.webp', 'image/webp'),
    ('.avif', 'image/avif'),
    ('.ico', 'image/x-icon'),
    ('.bmp', 'image/bmp'),
    ('.woff', 'font/woff'),
    ('.woff2', 'font/woff2'),
    ('.ttf', 'font/ttf'),
    ('.otf', 'font/otf'),
    ('.eot', 'application/vnd.ms-fontobject'),
    ('.wasm', 'application/wasm'),
    ('.mp3', 'audio/mpeg'),
    ('.wav', 'audio/wav'),
    ('.ogg', 'audio/ogg'),
    ('.m4a', 'audio/mp4'),
    ('.mp4', 'video/mp4'),
    ('.webm', 'video/webm'),
    ('.ogv', 'video/ogg'),
    ('.pdf', 'application/pdf'),
    ('.zip', 'application/zip'),
    ('.gz', 'application/gzip'),
    ('.vtt', 'text/vtt; charset=utf-8'),
    ('.glb', 'model/gltf-binary'));
var
  Ext: string;
  I: Integer;
begin
  Ext := LowerCase(ExtractFileExt(StringReplace(Path, '/', '\', [rfReplaceAll])));
  for I := Low(Tabela) to High(Tabela) do
    if Tabela[I][0] = Ext then
    begin
      Result := Tabela[I][1];
      Exit;
    end;
  Result := 'application/octet-stream';
end;

{ último segmento do caminho tem extensão? ('a/b.js' sim; 'clientes/7' não) }
function TemExtensao(const Path: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Length(Path) downto 1 do
    case Path[I] of
      '.': begin Result := True; Exit; end;
      '/': Exit;
    end;
end;

{ TBorionAssets }

constructor TBorionAssets.Create(AOwner: TComponent; ABrowser: TWebView2Browser;
  const AHost: string);
begin
  inherited Create(AOwner);
  FHost := LowerCase(AHost);
  FIndexFile := 'index.html';
  FSpaFallback := True;
  FCacheControl := 'no-cache';
  FDevUrl := BorionDevUrl;
  FDevDir := BorionDevDir;
  FLiveReload := True;
  try
    FPack := TBorionPack.FromResource(HInstance);
  except
    on E: Exception do
    begin
      FPack := nil;
      FPackError := E.Message;
    end;
  end;
  FBrowser := ABrowser;
  if FBrowser <> nil then
  begin
    FBrowser.FreeNotification(Self);
    FPreviousHandler := FBrowser.OnWebResourceRequested;
    FBrowser.OnWebResourceRequested := WebResourceRequested;
    FBrowser.AddWebResourceRequestedFilter('https://' + FHost + '/*');
  end;
  if (FDevDir <> '') and (FDevUrl = '') then
    StartLiveReload;
end;

procedure TBorionAssets.StartLiveReload;
begin
  if (FVigia <> nil) or (FDevDir = '') or not FLiveReload or
    ((FBrowser = nil) and not Assigned(FOnLiveReload)) or not DirectoryExists(FDevDir) then
    Exit;
  FJanela := Classes.AllocateHWnd(WndProc);
  FVigia := TVigiaDePasta.Create(FDevDir, FJanela);
end;

procedure TBorionAssets.WndProc(var Message: TMessage);
begin
  if Message.Msg = WM_BORION_RELOAD then
  begin
    if Assigned(FOnLiveReload) then
      FOnLiveReload(Self);
    if FLiveReload and (FBrowser <> nil) and (FBrowser.WebView <> nil) then
      FBrowser.Reload;
  end
  else
    Message.Result := DefWindowProc(FJanela, Message.Msg, Message.WParam, Message.LParam);
end;

destructor TBorionAssets.Destroy;
begin
  if FBrowser <> nil then
  begin
    FBrowser.OnWebResourceRequested := FPreviousHandler;
    FBrowser.RemoveFreeNotification(Self);
  end;
  FVigia.Free;
  if FJanela <> 0 then
    Classes.DeallocateHWnd(FJanela);
  FPack.Free;
  inherited Destroy;
end;

procedure TBorionAssets.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FBrowser) then
    FBrowser := nil;
end;

procedure TBorionAssets.SetPack(APack: TBorionPack);
begin
  if APack <> FPack then
    FPack.Free;
  FPack := APack;
  FPackError := '';
end;

function TBorionAssets.GetOrigin: string;
begin
  Result := 'https://' + FHost;
end;

function TBorionAssets.Url(const Path: string): WideString;
begin
  Result := Origin + '/' + Path;
end;

function TBorionAssets.IsDev: Boolean;
begin
  Result := (FDevUrl <> '') or (FDevDir <> '');
end;

function TBorionAssets.StartUrl: WideString;
begin
  if FDevUrl <> '' then
    Result := FDevUrl
  else
    Result := Url('');  { a raiz serve o IndexFile; '/index.html' seria uma rota desconhecida para SPAs }
end;

procedure TBorionAssets.ServePath(const UrlPath: string; Response: TWV2WebResourceResponse);
var
  Path: string;
  I: Integer;
begin
  Path := BorionUrlDecode(UrlPath);
  while (Path <> '') and (Path[1] = '/') do
    Delete(Path, 1, 1);
  if (Path = '') or (Path[Length(Path)] = '/') then
    Path := Path + FIndexFile;

  if (FDevDir <> '') and ServirDaPasta(Path, Response) then
    Exit;

  I := -1;
  if FPack <> nil then
  begin
    I := FPack.Find(Path);
    if (I < 0) and FSpaFallback and not TemExtensao(Path) then
    begin
      Path := FIndexFile;  { rota do app (ex.: /clientes/7): quem resolve é o JS }
      I := FPack.Find(Path);
    end;
  end;

  Response.Headers.Clear;
  Response.Content.Clear;
  if I < 0 then
  begin
    Response.StatusCode := 404;
    Response.ReasonPhrase := 'Not Found';
    if FPack = nil then
      Response.SetText('404 - pacote de assets ausente: ' + FPackError)
    else
      Response.SetText('404 - não encontrado: ' + UrlPath);
  end
  else
  begin
    Response.StatusCode := 200;
    Response.ReasonPhrase := 'OK';
    FPack.ExtractTo(I, Response.Content);
    Response.SetHeader('Content-Type', BorionMimeType(Path));
  end;
  Response.SetHeader('X-Content-Type-Options', 'nosniff');
  if FCacheControl <> '' then
    Response.SetHeader('Cache-Control', FCacheControl);
  if FContentSecurityPolicy <> '' then
    Response.SetHeader('Content-Security-Policy', FContentSecurityPolicy);
end;

{ Modo dev sem servidor: o arquivo vem da pasta, sem cache }
function TBorionAssets.ServirDaPasta(const Path: string; Response: TWV2WebResourceResponse): Boolean;
var
  Rel, Arquivo: string;
begin
  Rel := StringReplace(Path, '/', '\', [rfReplaceAll]);
  { nada de sair da pasta: ..\ , caminhos absolutos ou de dispositivo }
  Result := (Pos('..', Rel) = 0) and (Pos(':', Rel) = 0) and (Copy(Rel, 1, 1) <> '\');
  if not Result then
  begin
    Response.Headers.Clear;
    Response.Content.Clear;
    Response.StatusCode := 404;
    Response.ReasonPhrase := 'Not Found';
    Response.SetText('404 - caminho inválido: ' + Path);
    Result := True;
    Exit;
  end;
  Arquivo := FDevDir + '\' + Rel;
  if not FileExists(Arquivo) and FSpaFallback and not TemExtensao(Path) then
  begin
    Arquivo := FDevDir + '\' + FIndexFile;
    Rel := FIndexFile;
  end;
  Response.Headers.Clear;
  Response.Content.Clear;
  if FileExists(Arquivo) then
  begin
    Response.StatusCode := 200;
    Response.ReasonPhrase := 'OK';
    try
      Response.Content.LoadFromFile(Arquivo);
    except
      { o editor ainda está gravando: o próximo reload pega o arquivo inteiro }
      Response.StatusCode := 503;
      Response.ReasonPhrase := 'Service Unavailable';
    end;
    Response.SetHeader('Content-Type', BorionMimeType(Rel));
  end
  else
  begin
    Response.StatusCode := 404;
    Response.ReasonPhrase := 'Not Found';
    Response.SetText('404 - não encontrado em ' + FDevDir + ': ' + Path);
  end;
  Response.SetHeader('X-Content-Type-Options', 'nosniff');
  Response.SetHeader('Cache-Control', 'no-store');
  if FContentSecurityPolicy <> '' then
    Response.SetHeader('Content-Security-Policy', FContentSecurityPolicy);
end;

procedure TBorionAssets.WebResourceRequested(Sender: TObject; Request: TWV2WebResourceRequest;
  Response: TWV2WebResourceResponse; var Handled: Boolean);
var
  Prefixo: string;
begin
  if Assigned(FPreviousHandler) then
    FPreviousHandler(Sender, Request, Response, Handled);
  if not Handled and Assigned(FOnRequest) then
    FOnRequest(Sender, Request, Response, Handled);
  if Handled then
    Exit;
  Prefixo := Origin + '/';
  if SameText(Copy(Request.Uri, 1, Length(Prefixo)), Prefixo) then
  begin
    ServePath(Request.RawPath, Response);  { ServePath decodifica (bytes UTF-8 do pacote) }
    Handled := True;
  end;
end;

end.
