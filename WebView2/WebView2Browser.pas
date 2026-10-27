unit WebView2Browser;

{
  TWebView2Browser: controle VCL (Delphi 7) que hospeda o Microsoft Edge WebView2.

  Uso básico:
    Browser := TWebView2Browser.Create(Self);
    Browser.Parent := Self;
    Browser.Align := alClient;
    Browser.OnInitialized := ...;
    Browser.CreateWebView;            // assíncrono; dispara OnInitialized
    Browser.Navigate('https://...');  // pode ser chamado antes: fica pendente

  Como o Delphi 7 não tem métodos anônimos, cada callback do WebView2 é uma
  pequena classe (TInterfacedObject) que apenas repassa a chamada ao controle.

  Robustez:
    - Nenhuma exceção escapa de um callback para o WebView2: vai para o
      OnCallbackError (ou para o tratador padrão da aplicação).
    - Se o processo do WebView2 cair, OnProcessFailed decide o que fazer; o
      padrão é recarregar (renderer) ou recriar o WebView (browser).
    - Se o handle do controle for recriado (troca de Parent, BorderStyle do
      form...), o WebView é levado para o novo handle.
}

interface

uses
  Windows, Messages, SysUtils, Classes, Controls, ActiveX,
  ComObj, { ComObj faz o Application.Initialize chamar CoInitialize (STA), exigido pelo WebView2 }
  WebView2;

type
  TWebView2Browser = class;

  TWV2InitializedEvent = procedure(Sender: TObject; ErrorCode: HResult) of object;
  TWV2NavigationStartingEvent = procedure(Sender: TObject; const Uri: WideString;
    IsUserInitiated, IsRedirected: Boolean; var Cancel: Boolean) of object;
  { O que fazer quando a página pede uma nova janela (target="_blank", window.open):
      nwaPopup      - comportamento padrão: o WebView2 abre a própria janela popup
      nwaSameWindow - navega para a URL neste mesmo controle
      nwaCancel     - não abre nada (ex.: o próprio handler abre no navegador padrão) }
  TWV2NewWindowAction = (nwaPopup, nwaSameWindow, nwaCancel);
  TWV2NewWindowRequestedEvent = procedure(Sender: TObject; const Uri: WideString;
    IsUserInitiated: Boolean; var Action: TWV2NewWindowAction) of object;
  TWV2NavigationCompletedEvent = procedure(Sender: TObject; Success: Boolean; WebErrorStatus: Integer) of object;
  TWV2StringEvent = procedure(Sender: TObject; const Value: WideString) of object;
  { Json: a mensagem como JSON (postMessage('x') chega como '"x"'); Source: URL do documento }
  TWV2WebMessageJsonEvent = procedure(Sender: TObject; const Json, Source: WideString;
    var Handled: Boolean) of object;
  TWV2ScriptResultEvent = procedure(Sender: TObject; ErrorCode: HResult; const ResultJson: WideString) of object;
  { Exceção levantada dentro de um callback do WebView2 (um evento do controle) }
  TWV2CallbackErrorEvent = procedure(Sender: TObject; E: Exception) of object;
  { O que fazer quando um processo do WebView2 cai:
      pfaNone     - nada (o app trata)
      pfaReload   - recarrega a página (renderer caiu ou travou)
      pfaRecreate - recria o WebView e volta à última URL (o browser caiu: tudo morreu) }
  TWV2ProcessFailedAction = (pfaNone, pfaReload, pfaRecreate);
  { Tecla de atalho com o foco no WebView (Ctrl+..., Alt+..., F1..F12, Esc...).
    KeyEventKind: COREWEBVIEW2_KEY_EVENT_KIND_*. Handled := True: a página não recebe a tecla. }
  TWV2AcceleratorKeyEvent = procedure(Sender: TObject; KeyEventKind, VirtualKey: Integer;
    var Handled: Boolean) of object;
  { Kind: COREWEBVIEW2_PROCESS_FAILED_KIND_*; Action já vem com o padrão para o Kind }
  TWV2ProcessFailedEvent = procedure(Sender: TObject; Kind: Integer;
    var Action: TWV2ProcessFailedAction) of object;

  { Requisição interceptada (OnWebResourceRequested). Só é válida durante o evento. }
  TWV2WebResourceRequest = class
  private
    FRequest: ICoreWebView2WebResourceRequest;
    FUri: WideString;
    FMethod: WideString;
    FResourceContext: Integer;
    FContent: string;
    FContentLoaded: Boolean;
    function GetContent: string;
    function GetContentText: WideString;
  public
    constructor Create(const ARequest: ICoreWebView2WebResourceRequest; AResourceContext: Integer);
    { Caminho sem esquema, host, query e fragmento, ainda codificado:
      'https://app.localhost/a%20b/x.js?q=1' -> 'a%20b/x.js' }
    function RawPath: WideString;
    { O mesmo, decodificado (%XX em UTF-8): 'a b/x.js' }
    function Path: WideString;
    { Parte depois do '?', sem o '?', ainda codificada (decodificar tudo de uma vez
      quebraria valores com '&' ou '=' codificados; use QueryParam) }
    function Query: WideString;
    { Valor decodificado de um parâmetro da query ('+' vira espaço); '' se não houver }
    function QueryParam(const Name: WideString): WideString;
    function HasQueryParam(const Name: WideString): Boolean;
    function GetHeader(const Name: WideString): WideString;
    { Alteram a requisição que segue para a rede (quando o evento não a trata) }
    procedure SetHeader(const Name, Value: WideString);
    procedure RemoveHeader(const Name: WideString);
    property Uri: WideString read FUri;
    property Method: WideString read FMethod;
    { COREWEBVIEW2_WEB_RESOURCE_CONTEXT_* (documento, script, imagem, fetch...) }
    property ResourceContext: Integer read FResourceContext;
    { Corpo da requisição (POST/PUT): bytes brutos / decodificado de UTF-8 }
    property Content: string read GetContent;
    property ContentText: WideString read GetContentText;
    property Native: ICoreWebView2WebResourceRequest read FRequest;
  end;

  { Resposta montada em Delphi. Começa como 200 OK, sem conteúdo. }
  TWV2WebResourceResponse = class
  private
    FStatusCode: Integer;
    FReasonPhrase: WideString;
    FHeaders: TStringList;
    FContent: TMemoryStream;
    FBrowser: TWebView2Browser;
    FArgs: ICoreWebView2WebResourceRequestedEventArgs;
    FDeferral: ICoreWebView2Deferral;
    FDeferred: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetHeader(const Name, Value: string);
    { Grava o texto em UTF-8 e define Content-Type (com charset=utf-8) }
    procedure SetText(const Text: WideString; const ContentType: string = 'text/plain');
    procedure SetJson(const Json: WideString);
    procedure SetData(Data: Pointer; Size: Integer; const ContentType: string);
    procedure LoadFromStream(Stream: TStream; const ContentType: string);
    { ContentType vazio: deduz pela extensão }
    procedure LoadFromFile(const FileName: string; const ContentType: string = '');
    function HeadersText: WideString;
    { Responder depois: chame Defer no OnWebResourceRequested (com Handled := True),
      guarde a resposta e chame Complete mais tarde, NA THREAD DA INTERFACE. Depois
      do Complete o objeto é liberado. O Request não vive além do evento: copie
      o que precisar dele antes. }
    procedure Defer;
    procedure Complete;
    property Deferred: Boolean read FDeferred;
    property StatusCode: Integer read FStatusCode write FStatusCode;
    property ReasonPhrase: WideString read FReasonPhrase write FReasonPhrase;
    { formato Nome=Valor }
    property Headers: TStringList read FHeaders;
    property Content: TMemoryStream read FContent;
  end;

  { Handled := True envia Response; senão a requisição segue normalmente }
  TWV2WebResourceRequestedEvent = procedure(Sender: TObject; Request: TWV2WebResourceRequest;
    Response: TWV2WebResourceResponse; var Handled: Boolean) of object;

  TWV2ResourceFilter = record
    Pattern: WideString;
    Context: Integer;
  end;

  { Opções do ambiente (ICoreWebView2EnvironmentOptions) }
  TWV2EnvironmentOptions = class(TInterfacedObject, ICoreWebView2EnvironmentOptions)
  private
    FAdditionalBrowserArguments: WideString;
    FLanguage: WideString;
    FTargetCompatibleBrowserVersion: WideString;
    FAllowSingleSignOn: Boolean;
  public
    constructor Create;
    function get_AdditionalBrowserArguments(out Value: PWideChar): HResult; stdcall;
    function put_AdditionalBrowserArguments(Value: PWideChar): HResult; stdcall;
    function get_Language(out Value: PWideChar): HResult; stdcall;
    function put_Language(Value: PWideChar): HResult; stdcall;
    function get_TargetCompatibleBrowserVersion(out Value: PWideChar): HResult; stdcall;
    function put_TargetCompatibleBrowserVersion(Value: PWideChar): HResult; stdcall;
    function get_AllowSingleSignOnUsingOSPrimaryAccount(out Allow: BOOL): HResult; stdcall;
    function put_AllowSingleSignOnUsingOSPrimaryAccount(Allow: WV2BOOL): HResult; stdcall;
  end;

  TWV2EventKind = (ekNavigationStarting, ekNavigationCompleted, ekNewWindowRequested,
    ekSourceChanged, ekTitleChanged, ekWebMessageReceived, ekWebResourceRequested, ekProcessFailed,
    ekAcceleratorKeyPressed);

  TWebView2Browser = class(TWinControl)
  private
    FEnvironment: ICoreWebView2Environment;
    FController: ICoreWebView2Controller;
    FWebView: ICoreWebView2;
    FHandlers: TList;
    FDeferredResponses: TList;
    FTokens: array[TWV2EventKind] of EventRegistrationToken;
    FTokenActive: array[TWV2EventKind] of Boolean;
    FCreating: Boolean;
    FDevToolsEnabled: Boolean;
    FContextMenusEnabled: Boolean;
    FZoomControlEnabled: Boolean;
    FPendingUrl: WideString;
    FLastUrl: WideString;
    FParkingWindow: HWND;
    FUserDataFolder: WideString;
    FLanguage: WideString;
    FAdditionalBrowserArguments: WideString;
    FResourceHost: WideString;
    FResourceFilters: array of TWV2ResourceFilter;
    FResourceFiltersApplied: Integer;
    FDocumentScripts: array of WideString;
    FDocumentScriptsApplied: Integer;
    FOnWebMessageJson: TWV2WebMessageJsonEvent;
    FOnWebResourceRequested: TWV2WebResourceRequestedEvent;
    FOnInitialized: TWV2InitializedEvent;
    FOnNavigationStarting: TWV2NavigationStartingEvent;
    FOnNavigationCompleted: TWV2NavigationCompletedEvent;
    FOnNewWindowRequested: TWV2NewWindowRequestedEvent;
    FOnSourceChanged: TWV2StringEvent;
    FOnTitleChanged: TWV2StringEvent;
    FOnWebMessageReceived: TWV2StringEvent;
    FOnScriptResult: TWV2ScriptResultEvent;
    FOnCallbackError: TWV2CallbackErrorEvent;
    FOnProcessFailed: TWV2ProcessFailedEvent;
    FOnAcceleratorKeyPressed: TWV2AcceleratorKeyEvent;
    procedure DetachHandlers;
    procedure ReleaseWebView;
    procedure AddToken(Kind: TWV2EventKind; Token: EventRegistrationToken);
    procedure ApplyResourceFilters;
    procedure ApplyDocumentScripts;
    function IsEmbeddedUri(const Uri: WideString): Boolean;
    procedure ServeEmbedded(const Path: string; Response: TWV2WebResourceResponse);
    procedure SendResponse(const Args: ICoreWebView2WebResourceRequestedEventArgs;
      Response: TWV2WebResourceResponse);
    procedure UpdateBounds;
    procedure ParkingWndProc(var Message: TMessage);
    procedure WMSize(var Message: TWMSize); message WM_SIZE;
    procedure WMSetFocus(var Message: TWMSetFocus); message WM_SETFOCUS;
    procedure CMShowingChanged(var Message: TMessage); message CM_SHOWINGCHANGED;
    procedure WMRecreate(var Message: TMessage); message WM_USER + $57;
    procedure Fail(ErrorCode: HResult);
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
    { chamado por todo callback que levantou exceção }
    procedure CallbackFailed;
    { chamados pelas classes de callback }
    procedure EnvironmentCreated(ErrorCode: HResult; const Env: ICoreWebView2Environment);
    procedure ControllerCreated(ErrorCode: HResult; const Controller: ICoreWebView2Controller);
    procedure NavigationStarting(const Args: ICoreWebView2NavigationStartingEventArgs);
    procedure NavigationCompleted(const Args: ICoreWebView2NavigationCompletedEventArgs);
    procedure NewWindowRequested(const Args: ICoreWebView2NewWindowRequestedEventArgs);
    procedure SourceChanged;
    procedure TitleChanged;
    procedure WebMessageReceived(const Args: ICoreWebView2WebMessageReceivedEventArgs);
    procedure ScriptCompleted(ErrorCode: HResult; ResultJson: PWideChar);
    procedure WebResourceRequested(const Args: ICoreWebView2WebResourceRequestedEventArgs);
    procedure ProcessFailed(const Args: ICoreWebView2ProcessFailedEventArgs);
    procedure AcceleratorKeyPressed(const Args: ICoreWebView2AcceleratorKeyPressedEventArgs);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure CreateWebView;
    function Ready: Boolean;
    { Fecha o WebView atual e cria outro, voltando à última URL. Usado depois de
      uma queda do processo do browser; seguro de chamar a qualquer momento. }
    procedure Recreate;

    procedure Navigate(const Url: WideString);
    procedure NavigateToString(const Html: WideString);
    procedure GoBack;
    procedure GoForward;
    procedure Reload;
    procedure Stop;
    procedure OpenDevTools;
    function CanGoBack: Boolean;
    function CanGoForward: Boolean;
    function Source: WideString;

    { Delphi -> JS: chega em window.chrome.webview 'message' (event.data) }
    procedure PostWebMessage(const Msg: WideString);
    procedure PostWebMessageAsJson(const Json: WideString);
    { Executa JS; o resultado (JSON) chega em OnScriptResult }
    procedure ExecuteScript(const Script: WideString);
    { Script que roda em todo documento novo, antes dos scripts da página.
      Pode ser chamado antes do CreateWebView. }
    procedure AddScriptOnDocumentCreated(const Script: WideString);

    { Chamar no WM_MOVE do formulário para posicionar popups/dropdowns corretamente }
    procedure NotifyParentWindowPositionChanged;

    { Serve os recursos RCDATA do executável em https://<HostName>/.
      O caminho da URL vira o nome do recurso: maiúsculas e tudo que não for
      letra/dígito vira "_" (ex.: /js/app.js -> JS_APP_JS). '/' serve INDEX_HTML.
      Pode ser chamado antes do CreateWebView. }
    procedure ServeEmbeddedResources(const HostName: WideString = 'app.localhost');
    function EmbeddedUrl(const Path: WideString): WideString;

    { Passa a disparar OnWebResourceRequested para as URLs que casam com o padrão
      (curinga '*', ex.: 'https://api.exemplo.com/*'). Pode ser chamado antes do
      CreateWebView. O host do ServeEmbeddedResources já é filtrado. }
    procedure AddWebResourceRequestedFilter(const UriPattern: WideString;
      ResourceContext: Integer = COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
    procedure RemoveWebResourceRequestedFilter(const UriPattern: WideString;
      ResourceContext: Integer = COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
    function ResourceFilterCount: Integer;

    property Controller: ICoreWebView2Controller read FController;
    property WebView: ICoreWebView2 read FWebView;
    { Pasta de cache/cookies. Padrão: %LOCALAPPDATA%\<nome do exe>\WebView2 }
    property UserDataFolder: WideString read FUserDataFolder write FUserDataFolder;
    { Falso: sem DevTools (F12, Ctrl+Shift+I, "Inspecionar"); antes de CreateWebView }
    property DevToolsEnabled: Boolean read FDevToolsEnabled write FDevToolsEnabled;
    { Menu de contexto padrão do WebView2 (padrão True); antes do CreateWebView }
    property ContextMenusEnabled: Boolean read FContextMenusEnabled write FContextMenusEnabled;
    { Zoom pelo usuário (Ctrl+roda, Ctrl+ +/-) (padrão True); antes do CreateWebView }
    property ZoomControlEnabled: Boolean read FZoomControlEnabled write FZoomControlEnabled;
    { Idioma da interface do WebView2 e do Accept-Language, ex.: 'pt-BR'. Antes do CreateWebView. }
    property Language: WideString read FLanguage write FLanguage;
    { Argumentos de linha de comando do Chromium, ex.: '--disable-gpu'. Antes do CreateWebView. }
    property AdditionalBrowserArguments: WideString read FAdditionalBrowserArguments write FAdditionalBrowserArguments;
  published
    property Align;
    property Anchors;
    property Visible;
    property TabStop default True;
    property OnInitialized: TWV2InitializedEvent read FOnInitialized write FOnInitialized;
    { Antes de cada navegação; Cancel := True impede o carregamento }
    property OnNavigationStarting: TWV2NavigationStartingEvent read FOnNavigationStarting write FOnNavigationStarting;
    property OnNavigationCompleted: TWV2NavigationCompletedEvent read FOnNavigationCompleted write FOnNavigationCompleted;
    { A página pediu uma nova janela; Action decide o que acontece (padrão: nwaPopup) }
    property OnNewWindowRequested: TWV2NewWindowRequestedEvent read FOnNewWindowRequested write FOnNewWindowRequested;
    property OnSourceChanged: TWV2StringEvent read FOnSourceChanged write FOnSourceChanged;
    property OnTitleChanged: TWV2StringEvent read FOnTitleChanged write FOnTitleChanged;
    property OnWebMessageReceived: TWV2StringEvent read FOnWebMessageReceived write FOnWebMessageReceived;
    { Disparado antes do OnWebMessageReceived; Handled := True o suprime }
    property OnWebMessageJson: TWV2WebMessageJsonEvent read FOnWebMessageJson write FOnWebMessageJson;
    property OnScriptResult: TWV2ScriptResultEvent read FOnScriptResult write FOnScriptResult;
    { Requisição que casa com um filtro (AddWebResourceRequestedFilter/ServeEmbeddedResources).
      Roda antes do servidor de recursos embutidos, então pode sobrepor caminhos dele. }
    property OnWebResourceRequested: TWV2WebResourceRequestedEvent read FOnWebResourceRequested write FOnWebResourceRequested;
    { Exceção num evento do controle. Sem handler: vai para o tratador padrão da
      aplicação (o diálogo de erro da VCL). Nunca escapa para o WebView2. }
    property OnCallbackError: TWV2CallbackErrorEvent read FOnCallbackError write FOnCallbackError;
    { Um processo do WebView2 caiu ou travou }
    property OnProcessFailed: TWV2ProcessFailedEvent read FOnProcessFailed write FOnProcessFailed;
    { Teclas de atalho com o foco na página: o teclado vai direto para o processo do
      WebView2, então os atalhos da VCL (TMainMenu, TActionList) não os veem. }
    property OnAcceleratorKeyPressed: TWV2AcceleratorKeyEvent read FOnAcceleratorKeyPressed write FOnAcceleratorKeyPressed;
  end;

  EWebView2Error = class(Exception);

{ Content-Type pela extensão (tabela básica do servidor de recursos embutidos) }
function WV2MimeType(const Path: string): string;
{ Nome do recurso RCDATA para um caminho: 'js/app.js' -> 'JS_APP_JS' }
function WV2ResourceName(const Path: string): string;
{ Decodifica %XX (bytes UTF-8). PlusAsSpace: '+' vira espaço (query string).
  Sequências inválidas ficam como estão; UTF-8 inválido é lido como ANSI. }
function WV2UrlDecode(const S: WideString; PlusAsSpace: Boolean = False): WideString;
{ Ação padrão do OnProcessFailed para um Kind }
function WV2DefaultProcessFailedAction(Kind: Integer): TWV2ProcessFailedAction;

implementation

const
  WM_WV2_RECREATE = WM_USER + $57;

{ ------------------------------------------------------------------------ }
{ Callbacks                                                                }
{ ------------------------------------------------------------------------ }

type
  { Base: guarda o dono e é "desligada" quando o controle é destruído,
    para que um callback tardio não acesse um objeto já liberado. }
  TWV2Handler = class(TInterfacedObject)
  protected
    FOwner: TWebView2Browser;
  public
    constructor Create(AOwner: TWebView2Browser);
    destructor Destroy; override;
  end;

  TEnvironmentCompletedHandler = class(TWV2Handler, ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler)
    function Invoke(ErrorCode: HResult; const CreatedEnvironment: ICoreWebView2Environment): HResult; stdcall;
  end;

  TControllerCompletedHandler = class(TWV2Handler, ICoreWebView2CreateCoreWebView2ControllerCompletedHandler)
    function Invoke(ErrorCode: HResult; const CreatedController: ICoreWebView2Controller): HResult; stdcall;
  end;

  TNavigationStartingHandler = class(TWV2Handler, ICoreWebView2NavigationStartingEventHandler)
    function Invoke(const Sender: ICoreWebView2; const Args: ICoreWebView2NavigationStartingEventArgs): HResult; stdcall;
  end;

  TNavigationCompletedHandler = class(TWV2Handler, ICoreWebView2NavigationCompletedEventHandler)
    function Invoke(const Sender: ICoreWebView2; const Args: ICoreWebView2NavigationCompletedEventArgs): HResult; stdcall;
  end;

  TNewWindowRequestedHandler = class(TWV2Handler, ICoreWebView2NewWindowRequestedEventHandler)
    function Invoke(const Sender: ICoreWebView2; const Args: ICoreWebView2NewWindowRequestedEventArgs): HResult; stdcall;
  end;

  TSourceChangedHandler = class(TWV2Handler, ICoreWebView2SourceChangedEventHandler)
    function Invoke(const Sender: ICoreWebView2; const Args: IUnknown): HResult; stdcall;
  end;

  TTitleChangedHandler = class(TWV2Handler, ICoreWebView2DocumentTitleChangedEventHandler)
    function Invoke(const Sender: ICoreWebView2; const Args: IUnknown): HResult; stdcall;
  end;

  TWebMessageReceivedHandler = class(TWV2Handler, ICoreWebView2WebMessageReceivedEventHandler)
    function Invoke(const Sender: ICoreWebView2; const Args: ICoreWebView2WebMessageReceivedEventArgs): HResult; stdcall;
  end;

  TWebResourceRequestedHandler = class(TWV2Handler, ICoreWebView2WebResourceRequestedEventHandler)
    function Invoke(const Sender: ICoreWebView2; const Args: ICoreWebView2WebResourceRequestedEventArgs): HResult; stdcall;
  end;

  TProcessFailedHandler = class(TWV2Handler, ICoreWebView2ProcessFailedEventHandler)
    function Invoke(const Sender: ICoreWebView2; const Args: ICoreWebView2ProcessFailedEventArgs): HResult; stdcall;
  end;

  TAcceleratorKeyHandler = class(TWV2Handler, ICoreWebView2AcceleratorKeyPressedEventHandler)
    function Invoke(const Sender: ICoreWebView2Controller;
      const Args: ICoreWebView2AcceleratorKeyPressedEventArgs): HResult; stdcall;
  end;

  TAddScriptCompletedHandler = class(TWV2Handler, ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler)
    function Invoke(ErrorCode: HResult; Id: PWideChar): HResult; stdcall;
  end;

  TExecuteScriptCompletedHandler = class(TWV2Handler, ICoreWebView2ExecuteScriptCompletedHandler)
    function Invoke(ErrorCode: HResult; ResultObjectAsJson: PWideChar): HResult; stdcall;
  end;

constructor TWV2Handler.Create(AOwner: TWebView2Browser);
begin
  inherited Create;
  FOwner := AOwner;
  FOwner.FHandlers.Add(Self);
end;

destructor TWV2Handler.Destroy;
begin
  if FOwner <> nil then
    FOwner.FHandlers.Remove(Self);
  inherited;
end;

{ Todos os Invoke seguem o mesmo padrão: sempre S_OK para o WebView2, e
  qualquer exceção vai para o CallbackFailed do controle. }

function TEnvironmentCompletedHandler.Invoke(ErrorCode: HResult;
  const CreatedEnvironment: ICoreWebView2Environment): HResult;
begin
  Result := S_OK;
  if FOwner <> nil then
  try
    FOwner.EnvironmentCreated(ErrorCode, CreatedEnvironment);
  except
    FOwner.CallbackFailed;
  end;
end;

function TControllerCompletedHandler.Invoke(ErrorCode: HResult;
  const CreatedController: ICoreWebView2Controller): HResult;
begin
  Result := S_OK;
  if FOwner <> nil then
  try
    FOwner.ControllerCreated(ErrorCode, CreatedController);
  except
    FOwner.CallbackFailed;
  end;
end;

function TNavigationStartingHandler.Invoke(const Sender: ICoreWebView2;
  const Args: ICoreWebView2NavigationStartingEventArgs): HResult;
begin
  Result := S_OK;
  if FOwner <> nil then
  try
    FOwner.NavigationStarting(Args);
  except
    FOwner.CallbackFailed;
  end;
end;

function TNavigationCompletedHandler.Invoke(const Sender: ICoreWebView2;
  const Args: ICoreWebView2NavigationCompletedEventArgs): HResult;
begin
  Result := S_OK;
  if FOwner <> nil then
  try
    FOwner.NavigationCompleted(Args);
  except
    FOwner.CallbackFailed;
  end;
end;

function TNewWindowRequestedHandler.Invoke(const Sender: ICoreWebView2;
  const Args: ICoreWebView2NewWindowRequestedEventArgs): HResult;
begin
  Result := S_OK;
  if FOwner <> nil then
  try
    FOwner.NewWindowRequested(Args);
  except
    FOwner.CallbackFailed;
  end;
end;

function TSourceChangedHandler.Invoke(const Sender: ICoreWebView2; const Args: IUnknown): HResult;
begin
  Result := S_OK;
  if FOwner <> nil then
  try
    FOwner.SourceChanged;
  except
    FOwner.CallbackFailed;
  end;
end;

function TTitleChangedHandler.Invoke(const Sender: ICoreWebView2; const Args: IUnknown): HResult;
begin
  Result := S_OK;
  if FOwner <> nil then
  try
    FOwner.TitleChanged;
  except
    FOwner.CallbackFailed;
  end;
end;

function TWebMessageReceivedHandler.Invoke(const Sender: ICoreWebView2;
  const Args: ICoreWebView2WebMessageReceivedEventArgs): HResult;
begin
  Result := S_OK;
  if FOwner <> nil then
  try
    FOwner.WebMessageReceived(Args);
  except
    FOwner.CallbackFailed;
  end;
end;

function TWebResourceRequestedHandler.Invoke(const Sender: ICoreWebView2;
  const Args: ICoreWebView2WebResourceRequestedEventArgs): HResult;
begin
  Result := S_OK;
  if FOwner <> nil then
  try
    FOwner.WebResourceRequested(Args);
  except
    FOwner.CallbackFailed;
  end;
end;

function TProcessFailedHandler.Invoke(const Sender: ICoreWebView2;
  const Args: ICoreWebView2ProcessFailedEventArgs): HResult;
begin
  Result := S_OK;
  if FOwner <> nil then
  try
    FOwner.ProcessFailed(Args);
  except
    FOwner.CallbackFailed;
  end;
end;

function TAcceleratorKeyHandler.Invoke(const Sender: ICoreWebView2Controller;
  const Args: ICoreWebView2AcceleratorKeyPressedEventArgs): HResult;
begin
  Result := S_OK;
  if FOwner <> nil then
  try
    FOwner.AcceleratorKeyPressed(Args);
  except
    FOwner.CallbackFailed;
  end;
end;

function TAddScriptCompletedHandler.Invoke(ErrorCode: HResult; Id: PWideChar): HResult;
begin
  { o id serviria para RemoveScriptToExecuteOnDocumentCreated; não é usado por enquanto }
  Result := S_OK;
end;

function TExecuteScriptCompletedHandler.Invoke(ErrorCode: HResult; ResultObjectAsJson: PWideChar): HResult;
begin
  Result := S_OK;
  if FOwner <> nil then
  try
    FOwner.ScriptCompleted(ErrorCode, ResultObjectAsJson);
  except
    FOwner.CallbackFailed;
  end;
end;

{ ------------------------------------------------------------------------ }
{ Funções utilitárias                                                      }
{ ------------------------------------------------------------------------ }

function WV2MimeType(const Path: string): string;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(StringReplace(Path, '/', '\', [rfReplaceAll])));
  if (Ext = '.html') or (Ext = '.htm') then Result := 'text/html; charset=utf-8'
  else if Ext = '.css' then Result := 'text/css; charset=utf-8'
  else if (Ext = '.js') or (Ext = '.mjs') then Result := 'text/javascript; charset=utf-8'
  else if Ext = '.json' then Result := 'application/json; charset=utf-8'
  else if Ext = '.txt' then Result := 'text/plain; charset=utf-8'
  else if Ext = '.svg' then Result := 'image/svg+xml'
  else if Ext = '.png' then Result := 'image/png'
  else if (Ext = '.jpg') or (Ext = '.jpeg') then Result := 'image/jpeg'
  else if Ext = '.gif' then Result := 'image/gif'
  else if Ext = '.webp' then Result := 'image/webp'
  else if Ext = '.ico' then Result := 'image/x-icon'
  else if Ext = '.woff2' then Result := 'font/woff2'
  else if Ext = '.woff' then Result := 'font/woff'
  else if Ext = '.wasm' then Result := 'application/wasm'
  else Result := 'application/octet-stream';
end;

function WV2ResourceName(const Path: string): string;
var
  I: Integer;
begin
  Result := UpperCase(Path);
  for I := 1 to Length(Result) do
    if not (Result[I] in ['A'..'Z', '0'..'9']) then
      Result[I] := '_';
end;

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

function WV2UrlDecode(const S: WideString; PlusAsSpace: Boolean): WideString;
var
  Bytes, Saida: string;
  I, J, Hi, Lo: Integer;
begin
  Bytes := UTF8Encode(S);  { a URL deveria ser ASCII; se não for, mantém os caracteres }
  SetLength(Saida, Length(Bytes));
  I := 1;
  J := 0;
  while I <= Length(Bytes) do
  begin
    if (Bytes[I] = '%') and (I + 2 <= Length(Bytes)) then
    begin
      Hi := HexValue(Bytes[I + 1]);
      Lo := HexValue(Bytes[I + 2]);
      if (Hi >= 0) and (Lo >= 0) then
      begin
        Inc(J);
        Saida[J] := Chr(Hi * 16 + Lo);
        Inc(I, 3);
        Continue;
      end;
    end;
    Inc(J);
    if PlusAsSpace and (Bytes[I] = '+') then
      Saida[J] := ' '
    else
      Saida[J] := Bytes[I];
    Inc(I);
  end;
  SetLength(Saida, J);
  Result := UTF8Decode(Saida);
  if (Result = '') and (Saida <> '') then
    Result := Saida;  { UTF-8 inválido: lê os bytes como ANSI }
end;

function WV2DefaultProcessFailedAction(Kind: Integer): TWV2ProcessFailedAction;
begin
  case Kind of
    COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED: Result := pfaRecreate;
    COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED: Result := pfaReload;
  else
    Result := pfaNone;  { travamento, frames, GPU, utilitários: o WebView2 se recupera sozinho }
  end;
end;

{ Cópia de uma WideString em memória do CoTaskMem (para devolver ao WebView2) }
function CoTaskString(const S: WideString): PWideChar;
var
  Bytes: Integer;
begin
  Bytes := (Length(S) + 1) * SizeOf(WideChar);
  Result := CoTaskMemAlloc(Bytes);
  if Result <> nil then
    Move(PWideChar(S)^, Result^, Bytes);
end;

{ ------------------------------------------------------------------------ }
{ TWV2EnvironmentOptions                                                   }
{ ------------------------------------------------------------------------ }

constructor TWV2EnvironmentOptions.Create;
begin
  inherited Create;
  FTargetCompatibleBrowserVersion := WV2_TARGET_COMPATIBLE_BROWSER_VERSION;
end;

function TWV2EnvironmentOptions.get_AdditionalBrowserArguments(out Value: PWideChar): HResult;
begin
  Value := CoTaskString(FAdditionalBrowserArguments);
  Result := S_OK;
end;

function TWV2EnvironmentOptions.put_AdditionalBrowserArguments(Value: PWideChar): HResult;
begin
  FAdditionalBrowserArguments := Value;
  Result := S_OK;
end;

function TWV2EnvironmentOptions.get_Language(out Value: PWideChar): HResult;
begin
  Value := CoTaskString(FLanguage);
  Result := S_OK;
end;

function TWV2EnvironmentOptions.put_Language(Value: PWideChar): HResult;
begin
  FLanguage := Value;
  Result := S_OK;
end;

function TWV2EnvironmentOptions.get_TargetCompatibleBrowserVersion(out Value: PWideChar): HResult;
begin
  Value := CoTaskString(FTargetCompatibleBrowserVersion);
  Result := S_OK;
end;

function TWV2EnvironmentOptions.put_TargetCompatibleBrowserVersion(Value: PWideChar): HResult;
begin
  FTargetCompatibleBrowserVersion := Value;
  Result := S_OK;
end;

function TWV2EnvironmentOptions.get_AllowSingleSignOnUsingOSPrimaryAccount(out Allow: BOOL): HResult;
begin
  Allow := FAllowSingleSignOn;
  Result := S_OK;
end;

function TWV2EnvironmentOptions.put_AllowSingleSignOnUsingOSPrimaryAccount(Allow: WV2BOOL): HResult;
begin
  FAllowSingleSignOn := Allow <> 0;
  Result := S_OK;
end;

{ ------------------------------------------------------------------------ }
{ TWebView2Browser                                                         }
{ ------------------------------------------------------------------------ }

constructor TWebView2Browser.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHandlers := TList.Create;
  FDeferredResponses := TList.Create;
  FDevToolsEnabled := True;
  FContextMenusEnabled := True;
  FZoomControlEnabled := True;
  TabStop := True;
  Width := 300;
  Height := 200;
end;

destructor TWebView2Browser.Destroy;
begin
  ReleaseWebView;
  if FParkingWindow <> 0 then
    DeallocateHWnd(FParkingWindow);
  FDeferredResponses.Free;
  FHandlers.Free;
  inherited Destroy;
end;

procedure TWebView2Browser.DetachHandlers;
var
  I: Integer;
begin
  for I := 0 to FHandlers.Count - 1 do
    TWV2Handler(FHandlers[I]).FOwner := nil;
  FHandlers.Clear;
end;

procedure TWebView2Browser.AddToken(Kind: TWV2EventKind; Token: EventRegistrationToken);
begin
  FTokens[Kind] := Token;
  FTokenActive[Kind] := True;
end;

{ Remove os handlers, fecha o controller e volta ao estado de "não criado".
  Os filtros e scripts registrados continuam guardados e são reaplicados no
  próximo CreateWebView. }
procedure TWebView2Browser.ReleaseWebView;
var
  K: TWV2EventKind;
  I: Integer;
  R: TWV2WebResourceResponse;
begin
  { respostas adiadas pendentes: os objetos COM vão morrer; só libera }
  for I := FDeferredResponses.Count - 1 downto 0 do
  begin
    R := TWV2WebResourceResponse(FDeferredResponses[I]);
    R.FBrowser := nil;
    R.FArgs := nil;
    R.FDeferral := nil;
    R.Free;
  end;
  FDeferredResponses.Clear;

  if FWebView <> nil then
    for K := Low(TWV2EventKind) to High(TWV2EventKind) do
      if FTokenActive[K] then
      try
        case K of
          ekNavigationStarting: FWebView.remove_NavigationStarting(FTokens[K]);
          ekNavigationCompleted: FWebView.remove_NavigationCompleted(FTokens[K]);
          ekNewWindowRequested: FWebView.remove_NewWindowRequested(FTokens[K]);
          ekSourceChanged: FWebView.remove_SourceChanged(FTokens[K]);
          ekTitleChanged: FWebView.remove_DocumentTitleChanged(FTokens[K]);
          ekWebMessageReceived: FWebView.remove_WebMessageReceived(FTokens[K]);
          ekWebResourceRequested: FWebView.remove_WebResourceRequested(FTokens[K]);
          ekProcessFailed: FWebView.remove_ProcessFailed(FTokens[K]);
          ekAcceleratorKeyPressed:
            if FController <> nil then
              FController.remove_AcceleratorKeyPressed(FTokens[K]);
        end;
      except
        { o processo pode já ter morrido: as chamadas falham, mas não importa }
      end;
  FillChar(FTokenActive, SizeOf(FTokenActive), 0);

  if FController <> nil then
  try
    FController.Close;
  except
  end;
  DetachHandlers;  { callbacks tardios do WebView antigo são ignorados }
  FWebView := nil;
  FController := nil;
  FEnvironment := nil;
  FCreating := False;
  FResourceFiltersApplied := 0;
  FDocumentScriptsApplied := 0;
end;

procedure TWebView2Browser.CallbackFailed;
var
  E: TObject;
begin
  E := ExceptObject;
  try
    if Assigned(FOnCallbackError) and (E is Exception) then
      FOnCallbackError(Self, Exception(E))
    else if Assigned(ApplicationHandleException) then
      ApplicationHandleException(Self);
  except
    { o próprio tratador falhou: mesmo assim nada pode escapar para o WebView2 }
  end;
end;

procedure TWebView2Browser.Fail(ErrorCode: HResult);
begin
  FCreating := False;
  if Assigned(FOnInitialized) then
    FOnInitialized(Self, ErrorCode);
end;

procedure TWebView2Browser.CreateWebView;
var
  Handler: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler;
  Options: ICoreWebView2EnvironmentOptions;
  Opcoes: TWV2EnvironmentOptions;
  Hr: HResult;
  Folder: string;
begin
  if FCreating or (FController <> nil) then
    Exit;

  if not LoadWebView2Loader then
    raise EWebView2Error.Create('Não foi possível carregar o WebView2Loader.dll (x86). ' +
      'Copie-o para a pasta do executável.');

  if GetWebView2RuntimeVersion = '' then
    raise EWebView2Error.Create('O WebView2 Runtime não está instalado. ' +
      'Baixe em https://developer.microsoft.com/microsoft-edge/webview2/');

  { Pasta de dados do usuário (cache, cookies...). Precisa ser gravável. }
  if FUserDataFolder = '' then
  begin
    Folder := GetEnvironmentVariable('LOCALAPPDATA');
    if Folder = '' then
      Folder := ExtractFilePath(ParamStr(0))
    else
      Folder := IncludeTrailingPathDelimiter(Folder);
    FUserDataFolder := Folder + ChangeFileExt(ExtractFileName(ParamStr(0)), '') + '\WebView2';
  end;

  { opções só quando configuradas: sem elas o comportamento é o padrão do runtime }
  Options := nil;
  if (FLanguage <> '') or (FAdditionalBrowserArguments <> '') then
  begin
    Opcoes := TWV2EnvironmentOptions.Create;
    Opcoes.FLanguage := FLanguage;
    Opcoes.FAdditionalBrowserArguments := FAdditionalBrowserArguments;
    Options := Opcoes;
  end;

  HandleNeeded;
  FCreating := True;
  { variável local: garante a contagem de referência do objeto recém-criado }
  Handler := TEnvironmentCompletedHandler.Create(Self);
  Hr := CreateCoreWebView2EnvironmentWithOptions(nil, PWideChar(FUserDataFolder), Options, Handler);
  if Failed(Hr) then
    Fail(Hr);
end;

procedure TWebView2Browser.Recreate;
var
  Atual: WideString;
begin
  { depois de uma queda do browser, Source falha e volta vazio: mantém a última conhecida }
  Atual := Source;
  if Atual <> '' then
    FLastUrl := Atual;
  ReleaseWebView;
  if FPendingUrl = '' then
    FPendingUrl := FLastUrl;
  CreateWebView;
end;

procedure TWebView2Browser.WMRecreate(var Message: TMessage);
begin
  try
    Recreate;
  except
    CallbackFailed;
  end;
end;

procedure TWebView2Browser.EnvironmentCreated(ErrorCode: HResult; const Env: ICoreWebView2Environment);
var
  Handler: ICoreWebView2CreateCoreWebView2ControllerCompletedHandler;
  Hr: HResult;
begin
  if Failed(ErrorCode) or (Env = nil) then
  begin
    Fail(ErrorCode);
    Exit;
  end;
  FEnvironment := Env;  { usado para criar as respostas dos recursos embutidos }
  Handler := TControllerCompletedHandler.Create(Self);
  Hr := Env.CreateCoreWebView2Controller(Handle, Handler);
  if Failed(Hr) then
    Fail(Hr);
end;

procedure TWebView2Browser.ControllerCreated(ErrorCode: HResult; const Controller: ICoreWebView2Controller);
var
  Settings: ICoreWebView2Settings;
  Token: EventRegistrationToken;
  StartHandler: ICoreWebView2NavigationStartingEventHandler;
  NavHandler: ICoreWebView2NavigationCompletedEventHandler;
  NewWinHandler: ICoreWebView2NewWindowRequestedEventHandler;
  SrcHandler: ICoreWebView2SourceChangedEventHandler;
  TitleHandler: ICoreWebView2DocumentTitleChangedEventHandler;
  MsgHandler: ICoreWebView2WebMessageReceivedEventHandler;
  FailHandler: ICoreWebView2ProcessFailedEventHandler;
  KeyHandler: ICoreWebView2AcceleratorKeyPressedEventHandler;
  Url: WideString;
begin
  FCreating := False;
  if Failed(ErrorCode) or (Controller = nil) then
  begin
    Fail(ErrorCode);
    Exit;
  end;

  FController := Controller;
  FController.get_CoreWebView2(FWebView);

  if Succeeded(FWebView.get_Settings(Settings)) then
  begin
    Settings.put_IsScriptEnabled(BoolToWV2(True));
    Settings.put_IsWebMessageEnabled(BoolToWV2(True));
    Settings.put_AreDevToolsEnabled(BoolToWV2(FDevToolsEnabled));
    Settings.put_AreDefaultContextMenusEnabled(BoolToWV2(FContextMenusEnabled));
    Settings.put_IsZoomControlEnabled(BoolToWV2(FZoomControlEnabled));
    Settings.put_IsStatusBarEnabled(BoolToWV2(True));
  end;

  StartHandler := TNavigationStartingHandler.Create(Self);
  if Succeeded(FWebView.add_NavigationStarting(StartHandler, Token)) then
    AddToken(ekNavigationStarting, Token);
  NavHandler := TNavigationCompletedHandler.Create(Self);
  if Succeeded(FWebView.add_NavigationCompleted(NavHandler, Token)) then
    AddToken(ekNavigationCompleted, Token);
  NewWinHandler := TNewWindowRequestedHandler.Create(Self);
  if Succeeded(FWebView.add_NewWindowRequested(NewWinHandler, Token)) then
    AddToken(ekNewWindowRequested, Token);
  SrcHandler := TSourceChangedHandler.Create(Self);
  if Succeeded(FWebView.add_SourceChanged(SrcHandler, Token)) then
    AddToken(ekSourceChanged, Token);
  TitleHandler := TTitleChangedHandler.Create(Self);
  if Succeeded(FWebView.add_DocumentTitleChanged(TitleHandler, Token)) then
    AddToken(ekTitleChanged, Token);
  MsgHandler := TWebMessageReceivedHandler.Create(Self);
  if Succeeded(FWebView.add_WebMessageReceived(MsgHandler, Token)) then
    AddToken(ekWebMessageReceived, Token);
  FailHandler := TProcessFailedHandler.Create(Self);
  if Succeeded(FWebView.add_ProcessFailed(FailHandler, Token)) then
    AddToken(ekProcessFailed, Token);
  KeyHandler := TAcceleratorKeyHandler.Create(Self);
  if Succeeded(FController.add_AcceleratorKeyPressed(KeyHandler, Token)) then
    AddToken(ekAcceleratorKeyPressed, Token);
  ApplyResourceFilters;
  ApplyDocumentScripts;  { antes da primeira navegação (FPendingUrl, mais abaixo) }

  UpdateBounds;
  FController.put_IsVisible(BoolToWV2(Showing));

  if Assigned(FOnInitialized) then
    FOnInitialized(Self, S_OK);

  if FPendingUrl <> '' then
  begin
    Url := FPendingUrl;
    FPendingUrl := '';
    FWebView.Navigate(PWideChar(Url));
  end;
end;

procedure TWebView2Browser.NavigationStarting(const Args: ICoreWebView2NavigationStartingEventArgs);
var
  P: PWideChar;
  Uri: WideString;
  UserInitiated, Redirected: BOOL;
  Cancel: Boolean;
begin
  P := nil;
  Args.get_Uri(P);
  Uri := TakeCoTaskString(P);
  UserInitiated := False;
  Redirected := False;
  Args.get_IsUserInitiated(UserInitiated);
  Args.get_IsRedirected(Redirected);
  Cancel := False;
  if Assigned(FOnNavigationStarting) then
    FOnNavigationStarting(Self, Uri, UserInitiated, Redirected, Cancel);
  if Cancel then
    Args.put_Cancel(BoolToWV2(True));
end;

procedure TWebView2Browser.NavigationCompleted(const Args: ICoreWebView2NavigationCompletedEventArgs);
var
  Success: BOOL;
  Status: Integer;
begin
  Success := False;
  Status := 0;
  Args.get_IsSuccess(Success);
  Args.get_WebErrorStatus(Status);
  if Assigned(FOnNavigationCompleted) then
    FOnNavigationCompleted(Self, Success, Status);
end;

procedure TWebView2Browser.NewWindowRequested(const Args: ICoreWebView2NewWindowRequestedEventArgs);
var
  P: PWideChar;
  Uri: WideString;
  UserInitiated: BOOL;
  Action: TWV2NewWindowAction;
begin
  P := nil;
  Args.get_Uri(P);
  Uri := TakeCoTaskString(P);
  UserInitiated := False;
  Args.get_IsUserInitiated(UserInitiated);
  Action := nwaPopup;
  if Assigned(FOnNewWindowRequested) then
    FOnNewWindowRequested(Self, Uri, UserInitiated, Action);
  case Action of
    nwaSameWindow:
      begin
        Args.put_Handled(BoolToWV2(True));
        FWebView.Navigate(PWideChar(Uri));
      end;
    nwaCancel:
      Args.put_Handled(BoolToWV2(True));
  end;
end;

procedure TWebView2Browser.SourceChanged;
var
  Url: WideString;
begin
  Url := Source;
  if Url <> '' then
    FLastUrl := Url;  { para voltar a ela se o browser cair }
  if Assigned(FOnSourceChanged) then
    FOnSourceChanged(Self, Url);
end;

procedure TWebView2Browser.TitleChanged;
var
  P: PWideChar;
  Titulo: WideString;
begin
  P := nil;
  FWebView.get_DocumentTitle(P);
  Titulo := TakeCoTaskString(P);
  if Assigned(FOnTitleChanged) then
    FOnTitleChanged(Self, Titulo);
end;

procedure TWebView2Browser.WebMessageReceived(const Args: ICoreWebView2WebMessageReceivedEventArgs);
var
  P: PWideChar;
  Msg, Json, Source: WideString;
  Handled: Boolean;
begin
  { 1) mensagem crua (sempre JSON) + origem, para quem precisa do protocolo }
  if Assigned(FOnWebMessageJson) then
  begin
    P := nil;
    Args.get_WebMessageAsJson(P);
    Json := TakeCoTaskString(P);
    P := nil;
    Args.get_Source(P);
    Source := TakeCoTaskString(P);
    Handled := False;
    FOnWebMessageJson(Self, Json, Source, Handled);
    if Handled then
      Exit;
  end;

  { 2) postMessage('texto') chega como string; objetos chegam como JSON }
  P := nil;
  if Succeeded(Args.TryGetWebMessageAsString(P)) then
    Msg := TakeCoTaskString(P)
  else
  begin
    P := nil;
    Args.get_WebMessageAsJson(P);
    Msg := TakeCoTaskString(P);
  end;
  if Assigned(FOnWebMessageReceived) then
    FOnWebMessageReceived(Self, Msg);
end;

procedure TWebView2Browser.ProcessFailed(const Args: ICoreWebView2ProcessFailedEventArgs);
var
  Kind: Integer;
  Action: TWV2ProcessFailedAction;
begin
  Kind := COREWEBVIEW2_PROCESS_FAILED_KIND_UNKNOWN_PROCESS_EXITED;
  Args.get_ProcessFailedKind(Kind);
  Action := WV2DefaultProcessFailedAction(Kind);
  if Assigned(FOnProcessFailed) then
    FOnProcessFailed(Self, Kind, Action);
  case Action of
    pfaReload:
      if FWebView <> nil then
        FWebView.Reload;
    pfaRecreate:
      { fora do callback: fechar o controller dentro do próprio evento não é seguro }
      if HandleAllocated then
        PostMessage(Handle, WM_WV2_RECREATE, 0, 0);
  end;
end;

procedure TWebView2Browser.AcceleratorKeyPressed(const Args: ICoreWebView2AcceleratorKeyPressedEventArgs);
var
  Kind: Integer;
  Tecla: Cardinal;
  Handled: Boolean;
begin
  if not Assigned(FOnAcceleratorKeyPressed) then
    Exit;
  Kind := 0;
  Tecla := 0;
  Args.get_KeyEventKind(Kind);
  Args.get_VirtualKey(Tecla);
  Handled := False;
  FOnAcceleratorKeyPressed(Self, Kind, Tecla, Handled);
  if Handled then
    Args.put_Handled(BoolToWV2(True));
end;

procedure TWebView2Browser.AddScriptOnDocumentCreated(const Script: WideString);
var
  N: Integer;
begin
  N := Length(FDocumentScripts);
  SetLength(FDocumentScripts, N + 1);
  FDocumentScripts[N] := Script;
  ApplyDocumentScripts;
end;

procedure TWebView2Browser.ApplyDocumentScripts;
var
  Handler: ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler;
  I: Integer;
begin
  if FWebView = nil then
    Exit;  { ficam pendentes até o ControllerCreated }
  for I := FDocumentScriptsApplied to High(FDocumentScripts) do
  begin
    Handler := TAddScriptCompletedHandler.Create(Self);
    FWebView.AddScriptToExecuteOnDocumentCreated(PWideChar(FDocumentScripts[I]), Handler);
  end;
  FDocumentScriptsApplied := Length(FDocumentScripts);
end;

procedure TWebView2Browser.ScriptCompleted(ErrorCode: HResult; ResultJson: PWideChar);
var
  S: WideString;
begin
  { este LPCWSTR pertence ao WebView2: copiar, não liberar }
  S := ResultJson;
  if Assigned(FOnScriptResult) then
    FOnScriptResult(Self, ErrorCode, S);
end;

{ --- recursos embutidos -------------------------------------------------- }

{ Interfaces não podem ser devolvidas por funções externas no Delphi (ele usa
  um parâmetro oculto), então o resultado é lido como Pointer. }
function SHCreateMemStream(pInit: Pointer; cbInit: UINT): Pointer; stdcall;
  external 'shlwapi.dll';

function CreateMemStream(Data: Pointer; Size: Cardinal): IStream;
begin
  Result := nil;
  { atribuição "crua": assume a referência devolvida, sem AddRef extra }
  Pointer(Result) := SHCreateMemStream(Data, Size);
end;

{ --- TWV2WebResourceRequest ---------------------------------------------- }

constructor TWV2WebResourceRequest.Create(const ARequest: ICoreWebView2WebResourceRequest;
  AResourceContext: Integer);
var
  P: PWideChar;
begin
  inherited Create;
  FRequest := ARequest;
  FResourceContext := AResourceContext;
  P := nil;
  FRequest.get_Uri(P);
  FUri := TakeCoTaskString(P);
  P := nil;
  FRequest.get_Method(P);
  FMethod := TakeCoTaskString(P);
end;

function TWV2WebResourceRequest.RawPath: WideString;
var
  I: Integer;
begin
  Result := FUri;
  I := Pos('://', Result);
  if I > 0 then
  begin
    Delete(Result, 1, I + 2);           { tira "https://" }
    I := Pos('/', Result);
    if I > 0 then
      Delete(Result, 1, I)              { tira "host/" }
    else
      Result := '';
  end;
  I := Pos('#', Result);
  if I > 0 then
    Result := Copy(Result, 1, I - 1);
  I := Pos('?', Result);
  if I > 0 then
    Result := Copy(Result, 1, I - 1);
end;

function TWV2WebResourceRequest.Path: WideString;
begin
  Result := WV2UrlDecode(RawPath);
end;

function TWV2WebResourceRequest.Query: WideString;
var
  I: Integer;
begin
  Result := FUri;
  I := Pos('#', Result);
  if I > 0 then
    Result := Copy(Result, 1, I - 1);
  I := Pos('?', Result);
  if I > 0 then
    Result := Copy(Result, I + 1, MaxInt)
  else
    Result := '';
end;

{ Procura Name entre os pares da query; Found indica se existe (mesmo vazio) }
function BuscarParam(const Query, Name: WideString; out Found: Boolean): WideString;
var
  Resto, Par, Chave: WideString;
  I: Integer;
begin
  Result := '';
  Found := False;
  Resto := Query;
  while Resto <> '' do
  begin
    I := Pos('&', Resto);
    if I > 0 then
    begin
      Par := Copy(Resto, 1, I - 1);
      Delete(Resto, 1, I);
    end
    else
    begin
      Par := Resto;
      Resto := '';
    end;
    if Par = '' then
      Continue;
    I := Pos('=', Par);
    if I > 0 then
      Chave := WV2UrlDecode(Copy(Par, 1, I - 1), True)
    else
      Chave := WV2UrlDecode(Par, True);
    if Chave = Name then
    begin
      Found := True;
      if I > 0 then
        Result := WV2UrlDecode(Copy(Par, I + 1, MaxInt), True);
      Exit;
    end;
  end;
end;

function TWV2WebResourceRequest.QueryParam(const Name: WideString): WideString;
var
  Found: Boolean;
begin
  Result := BuscarParam(Query, Name, Found);
end;

function TWV2WebResourceRequest.HasQueryParam(const Name: WideString): Boolean;
begin
  BuscarParam(Query, Name, Result);
end;

function TWV2WebResourceRequest.GetHeader(const Name: WideString): WideString;
var
  Headers: ICoreWebView2HttpRequestHeaders;
  P: PWideChar;
begin
  Result := '';
  P := nil;
  if Succeeded(FRequest.get_Headers(Headers)) and (Headers <> nil) and
    Succeeded(Headers.GetHeader(PWideChar(Name), P)) then
    Result := TakeCoTaskString(P);
end;

procedure TWV2WebResourceRequest.SetHeader(const Name, Value: WideString);
var
  Headers: ICoreWebView2HttpRequestHeaders;
begin
  if Succeeded(FRequest.get_Headers(Headers)) and (Headers <> nil) then
    Headers.SetHeader(PWideChar(Name), PWideChar(Value));
end;

procedure TWV2WebResourceRequest.RemoveHeader(const Name: WideString);
var
  Headers: ICoreWebView2HttpRequestHeaders;
begin
  if Succeeded(FRequest.get_Headers(Headers)) and (Headers <> nil) then
    Headers.RemoveHeader(PWideChar(Name));
end;

function TWV2WebResourceRequest.GetContent: string;
var
  Stream: IStream;
  Buffer: array[0..8191] of Byte;
  BytesRead: Longint;
  NewPos: Largeint;
  Len: Integer;
begin
  if not FContentLoaded then
  begin
    FContentLoaded := True;
    FContent := '';
    if Succeeded(FRequest.get_Content(Stream)) and (Stream <> nil) then
    begin
      Stream.Seek(0, STREAM_SEEK_SET, NewPos);
      repeat
        BytesRead := 0;
        if Failed(Stream.Read(@Buffer, SizeOf(Buffer), @BytesRead)) then
          Break;
        if BytesRead > 0 then
        begin
          Len := Length(FContent);
          SetLength(FContent, Len + BytesRead);
          Move(Buffer, FContent[Len + 1], BytesRead);
        end;
      until BytesRead < SizeOf(Buffer);
    end;
  end;
  Result := FContent;
end;

function TWV2WebResourceRequest.GetContentText: WideString;
begin
  Result := UTF8Decode(GetContent);
end;

{ --- TWV2WebResourceResponse --------------------------------------------- }

constructor TWV2WebResourceResponse.Create;
begin
  inherited Create;
  FStatusCode := 200;
  FReasonPhrase := 'OK';
  FHeaders := TStringList.Create;
  FContent := TMemoryStream.Create;
end;

destructor TWV2WebResourceResponse.Destroy;
begin
  if FBrowser <> nil then
    FBrowser.FDeferredResponses.Remove(Self);
  FContent.Free;
  FHeaders.Free;
  inherited Destroy;
end;

procedure TWV2WebResourceResponse.SetHeader(const Name, Value: string);
begin
  FHeaders.Values[Name] := Value;
end;

procedure TWV2WebResourceResponse.SetData(Data: Pointer; Size: Integer; const ContentType: string);
begin
  FContent.Clear;
  if Size > 0 then
    FContent.WriteBuffer(Data^, Size);
  if ContentType <> '' then
    SetHeader('Content-Type', ContentType);
end;

procedure TWV2WebResourceResponse.SetText(const Text: WideString; const ContentType: string);
var
  Utf8: string;
begin
  Utf8 := UTF8Encode(Text);
  SetData(PChar(Utf8), Length(Utf8), ContentType + '; charset=utf-8');
end;

procedure TWV2WebResourceResponse.SetJson(const Json: WideString);
begin
  SetText(Json, 'application/json');
end;

procedure TWV2WebResourceResponse.LoadFromStream(Stream: TStream; const ContentType: string);
begin
  FContent.Clear;
  FContent.CopyFrom(Stream, 0);
  if ContentType <> '' then
    SetHeader('Content-Type', ContentType);
end;

procedure TWV2WebResourceResponse.LoadFromFile(const FileName: string; const ContentType: string);
begin
  FContent.LoadFromFile(FileName);
  if ContentType <> '' then
    SetHeader('Content-Type', ContentType)
  else
    SetHeader('Content-Type', WV2MimeType(FileName));
end;

function TWV2WebResourceResponse.HeadersText: WideString;
var
  I: Integer;
  Name: string;
begin
  { formato esperado pelo WebView2: "Nome: Valor" separados por CRLF }
  Result := '';
  for I := 0 to FHeaders.Count - 1 do
  begin
    Name := FHeaders.Names[I];
    if Result <> '' then
      Result := Result + #13#10;
    Result := Result + Name + ': ' + Copy(FHeaders[I], Length(Name) + 2, MaxInt);
  end;
end;

procedure TWV2WebResourceResponse.Defer;
begin
  if FDeferred then
    Exit;
  if FArgs = nil then
    raise EWebView2Error.Create('Defer só pode ser chamado dentro do OnWebResourceRequested');
  if Failed(FArgs.GetDeferral(FDeferral)) or (FDeferral = nil) then
    raise EWebView2Error.Create('o WebView2 não concedeu o adiamento da resposta');
  FDeferred := True;
end;

procedure TWV2WebResourceResponse.Complete;
begin
  if not FDeferred then
    raise EWebView2Error.Create('Complete só vale para respostas adiadas com Defer');
  try
    if (FBrowser <> nil) and (FArgs <> nil) then
      FBrowser.SendResponse(FArgs, Self);
  finally
    if FDeferral <> nil then
      FDeferral.Complete;
    FDeferral := nil;
    FArgs := nil;
    Free;
  end;
end;

{ --- interceptação de requisições ---------------------------------------- }

procedure TWebView2Browser.ServeEmbeddedResources(const HostName: WideString);
begin
  FResourceHost := HostName;
  AddWebResourceRequestedFilter('https://' + HostName + '/*');
end;

function TWebView2Browser.EmbeddedUrl(const Path: WideString): WideString;
begin
  Result := 'https://' + FResourceHost + '/' + Path;
end;

procedure TWebView2Browser.AddWebResourceRequestedFilter(const UriPattern: WideString;
  ResourceContext: Integer);
var
  N: Integer;
begin
  N := Length(FResourceFilters);
  SetLength(FResourceFilters, N + 1);
  FResourceFilters[N].Pattern := UriPattern;
  FResourceFilters[N].Context := ResourceContext;
  ApplyResourceFilters;
end;

procedure TWebView2Browser.RemoveWebResourceRequestedFilter(const UriPattern: WideString;
  ResourceContext: Integer);
var
  I, J: Integer;
begin
  for I := High(FResourceFilters) downto 0 do
    if (FResourceFilters[I].Pattern = UriPattern) and (FResourceFilters[I].Context = ResourceContext) then
    begin
      if (I < FResourceFiltersApplied) and (FWebView <> nil) then
      begin
        FWebView.RemoveWebResourceRequestedFilter(PWideChar(UriPattern), ResourceContext);
        Dec(FResourceFiltersApplied);
      end;
      for J := I to High(FResourceFilters) - 1 do
        FResourceFilters[J] := FResourceFilters[J + 1];
      SetLength(FResourceFilters, Length(FResourceFilters) - 1);
    end;
end;

function TWebView2Browser.ResourceFilterCount: Integer;
begin
  Result := Length(FResourceFilters);
end;

procedure TWebView2Browser.ApplyResourceFilters;
var
  Handler: ICoreWebView2WebResourceRequestedEventHandler;
  Token: EventRegistrationToken;
  I: Integer;
begin
  if FWebView = nil then
    Exit;  { filtros ficam pendentes até o ControllerCreated }
  if not FTokenActive[ekWebResourceRequested] then
  begin
    Handler := TWebResourceRequestedHandler.Create(Self);
    if Succeeded(FWebView.add_WebResourceRequested(Handler, Token)) then
      AddToken(ekWebResourceRequested, Token);
  end;
  for I := FResourceFiltersApplied to High(FResourceFilters) do
    FWebView.AddWebResourceRequestedFilter(PWideChar(FResourceFilters[I].Pattern),
      FResourceFilters[I].Context);
  FResourceFiltersApplied := Length(FResourceFilters);
end;

function TWebView2Browser.IsEmbeddedUri(const Uri: WideString): Boolean;
var
  Prefix: WideString;
begin
  Prefix := 'https://' + FResourceHost + '/';
  Result := (FResourceHost <> '') and SameText(Copy(Uri, 1, Length(Prefix)), Prefix);
end;

procedure TWebView2Browser.ServeEmbedded(const Path: string; Response: TWV2WebResourceResponse);
var
  FilePath: string;
  ResInfo: HRSRC;
begin
  FilePath := Path;
  if FilePath = '' then
    FilePath := 'index.html';
  ResInfo := FindResource(HInstance, PChar(WV2ResourceName(FilePath)), RT_RCDATA);
  if ResInfo <> 0 then
    Response.SetData(LockResource(LoadResource(HInstance, ResInfo)),
      SizeofResource(HInstance, ResInfo), WV2MimeType(FilePath))
  else
  begin
    Response.StatusCode := 404;
    Response.ReasonPhrase := 'Not Found';
    Response.SetText('404 - recurso não embutido: ' + FilePath +
      ' (' + WV2ResourceName(FilePath) + ')');
  end;
end;

procedure TWebView2Browser.SendResponse(const Args: ICoreWebView2WebResourceRequestedEventArgs;
  Response: TWV2WebResourceResponse);
var
  Stream: IStream;
  NativeResponse: ICoreWebView2WebResourceResponse;
  Headers: WideString;
begin
  if FEnvironment = nil then
    Exit;
  { SHCreateMemStream copia os bytes: o stream não depende do TMemoryStream }
  Stream := CreateMemStream(Response.Content.Memory, Response.Content.Size);
  Headers := Response.HeadersText;
  if Succeeded(FEnvironment.CreateWebResourceResponse(Stream, Response.StatusCode,
    PWideChar(Response.ReasonPhrase), PWideChar(Headers), NativeResponse)) then
    Args.put_Response(NativeResponse);
end;

procedure TWebView2Browser.WebResourceRequested(const Args: ICoreWebView2WebResourceRequestedEventArgs);
var
  NativeRequest: ICoreWebView2WebResourceRequest;
  Context: Integer;
  Request: TWV2WebResourceRequest;
  Response: TWV2WebResourceResponse;
  Handled: Boolean;
begin
  if (FEnvironment = nil) or Failed(Args.get_Request(NativeRequest)) then
    Exit;
  Context := COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL;
  Args.get_ResourceContext(Context);

  Request := TWV2WebResourceRequest.Create(NativeRequest, Context);
  Response := TWV2WebResourceResponse.Create;
  Response.FBrowser := Self;
  Response.FArgs := Args;  { para um eventual Defer }
  try
    Handled := False;
    try
      { 1) o evento do usuário tem prioridade (ex.: uma API local em /api/...) }
      if Assigned(FOnWebResourceRequested) then
        FOnWebResourceRequested(Self, Request, Response, Handled);
      { 2) senão, se for do host embutido, serve o recurso RCDATA }
      if not Handled and IsEmbeddedUri(Request.Uri) then
      begin
        ServeEmbedded(Request.Path, Response);
        Handled := True;
      end;
    except
      { estamos dentro de um callback COM: a exceção não pode escapar para o WebView2 }
      on E: Exception do
      begin
        Response.Headers.Clear;
        Response.StatusCode := 500;
        Response.ReasonPhrase := 'Internal Server Error';
        Response.SetText('500 - ' + E.ClassName + ': ' + E.Message);
        Handled := True;
        if Response.FDeferred then
          Response.FDeferred := False;  { responde agora; o adiamento é concluído abaixo }
      end;
    end;

    if Response.FDeferred and Handled then
    begin
      { a resposta sai no Response.Complete }
      FDeferredResponses.Add(Response);
      Response := nil;
    end
    else
    begin
      if Handled then
        SendResponse(Args, Response);
      { se não tratou, a requisição segue normalmente para a rede }
      if Response.FDeferral <> nil then
        Response.FDeferral.Complete;  { Defer sem Handled, ou exceção depois do Defer }
    end;
  finally
    if Response <> nil then
    begin
      Response.FBrowser := nil;
      Response.FArgs := nil;
      Response.FDeferral := nil;
      Response.Free;
    end;
    Request.Free;
  end;
end;

function TWebView2Browser.Ready: Boolean;
begin
  Result := FWebView <> nil;
end;

procedure TWebView2Browser.UpdateBounds;
begin
  if FController <> nil then
    FController.put_Bounds(ClientRect);
end;

{ --- ciclo de vida do handle ---------------------------------------------- }

procedure TWebView2Browser.ParkingWndProc(var Message: TMessage);
begin
  Message.Result := DefWindowProc(FParkingWindow, Message.Msg, Message.WParam, Message.LParam);
end;

procedure TWebView2Browser.DestroyWnd;
begin
  { O handle vai ser recriado (troca de Parent, BorderStyle do form...): a janela
    do WebView2 é filha deste handle e morreria junto. Ela fica "estacionada"
    numa janela oculta até o CreateWnd. Na destruição do controle, não. }
  if (FController <> nil) and not (csDestroying in ComponentState) then
  begin
    if FParkingWindow = 0 then
      FParkingWindow := AllocateHWnd(ParkingWndProc);
    FController.put_IsVisible(BoolToWV2(False));
    FController.put_ParentWindow(FParkingWindow);
  end;
  inherited DestroyWnd;
end;

procedure TWebView2Browser.CreateWnd;
begin
  inherited CreateWnd;
  if FController <> nil then
  begin
    FController.put_ParentWindow(Handle);
    UpdateBounds;
    FController.put_IsVisible(BoolToWV2(Showing));
    FController.NotifyParentWindowPositionChanged;
  end;
end;

procedure TWebView2Browser.WMSize(var Message: TWMSize);
begin
  inherited;
  UpdateBounds;
end;

procedure TWebView2Browser.WMSetFocus(var Message: TWMSetFocus);
begin
  inherited;
  if FController <> nil then
    FController.MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
end;

procedure TWebView2Browser.CMShowingChanged(var Message: TMessage);
begin
  inherited;
  if FController <> nil then
    FController.put_IsVisible(BoolToWV2(Showing));
end;

procedure TWebView2Browser.NotifyParentWindowPositionChanged;
begin
  if FController <> nil then
    FController.NotifyParentWindowPositionChanged;
end;

{ --- navegação e scripts --------------------------------------------------- }

procedure TWebView2Browser.Navigate(const Url: WideString);
begin
  if FWebView <> nil then
    FWebView.Navigate(PWideChar(Url))
  else
    FPendingUrl := Url;
end;

procedure TWebView2Browser.NavigateToString(const Html: WideString);
begin
  if FWebView <> nil then
    FWebView.NavigateToString(PWideChar(Html));
end;

procedure TWebView2Browser.GoBack;
begin
  if FWebView <> nil then
    FWebView.GoBack;
end;

procedure TWebView2Browser.GoForward;
begin
  if FWebView <> nil then
    FWebView.GoForward;
end;

procedure TWebView2Browser.Reload;
begin
  if FWebView <> nil then
    FWebView.Reload;
end;

procedure TWebView2Browser.Stop;
begin
  if FWebView <> nil then
    FWebView.Stop;
end;

procedure TWebView2Browser.OpenDevTools;
begin
  if FWebView <> nil then
    FWebView.OpenDevToolsWindow;
end;

function TWebView2Browser.CanGoBack: Boolean;
var
  B: BOOL;
begin
  B := False;
  if FWebView <> nil then
    FWebView.get_CanGoBack(B);
  Result := B;
end;

function TWebView2Browser.CanGoForward: Boolean;
var
  B: BOOL;
begin
  B := False;
  if FWebView <> nil then
    FWebView.get_CanGoForward(B);
  Result := B;
end;

function TWebView2Browser.Source: WideString;
var
  P: PWideChar;
begin
  Result := '';
  if FWebView = nil then
    Exit;
  P := nil;
  if Succeeded(FWebView.get_Source(P)) then
    Result := TakeCoTaskString(P);
end;

procedure TWebView2Browser.PostWebMessage(const Msg: WideString);
begin
  if FWebView <> nil then
    FWebView.PostWebMessageAsString(PWideChar(Msg));
end;

procedure TWebView2Browser.PostWebMessageAsJson(const Json: WideString);
begin
  if FWebView <> nil then
    FWebView.PostWebMessageAsJson(PWideChar(Json));
end;

procedure TWebView2Browser.ExecuteScript(const Script: WideString);
var
  Handler: ICoreWebView2ExecuteScriptCompletedHandler;
begin
  if FWebView = nil then
    Exit;
  Handler := TExecuteScriptCompletedHandler.Create(Self);
  FWebView.ExecuteScript(PWideChar(Script), Handler);
end;

initialization
  { O Chromium/Edge espera exceções de ponto flutuante mascaradas (padrão do C/C++).
    O Delphi 7 as deixa habilitadas, o que pode causar "Floating point" / "Invalid
    floating point operation" aleatórios dentro do WebView2. }
  Set8087CW($133F);

end.
