unit WebView2;

{
  Declarações mínimas da API COM do Microsoft Edge WebView2 para Delphi 7.

  O Delphi 7 não tem TEdgeBrowser (que só surgiu no 10.4), então as interfaces
  são declaradas manualmente a partir do WebView2.h do pacote NuGet
  Microsoft.Web.WebView2. A ORDEM DOS MÉTODOS É A ORDEM DA VTABLE: não remova
  nem reordene métodos, mesmo os que não são usados. Métodos que não usamos
  aparecem com parâmetros genéricos (Pointer/IUnknown) apenas para ocupar o slot.

  Strings: LPCWSTR = PWideChar. Strings devolvidas (LPWSTR*) são alocadas pelo
  WebView2 e devem ser liberadas com CoTaskMemFree (veja TakeCoTaskString).
}

interface

uses
  Windows, ActiveX;

type
  EventRegistrationToken = Int64;

  { BOOL de entrada: o WebView2 espera exatamente TRUE (1). O BOOL do Delphi (LongBool)
    vale -1 para True, o que faz o runtime tratar o valor como FALSE. Use BoolToWV2(). }
  WV2BOOL = Integer;

const
  COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC = 0;
  COREWEBVIEW2_MOVE_FOCUS_REASON_NEXT         = 1;
  COREWEBVIEW2_MOVE_FOCUS_REASON_PREVIOUS     = 2;

  { COREWEBVIEW2_WEB_ERROR_STATUS (parcial) }
  COREWEBVIEW2_WEB_ERROR_STATUS_OPERATION_CANCELED = 14;

  COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL = 0;

  { COREWEBVIEW2_PROCESS_FAILED_KIND }
  COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED = 0;
  COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED = 1;
  COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_UNRESPONSIVE = 2;
  COREWEBVIEW2_PROCESS_FAILED_KIND_FRAME_RENDER_PROCESS_EXITED = 3;
  COREWEBVIEW2_PROCESS_FAILED_KIND_UTILITY_PROCESS_EXITED = 4;
  COREWEBVIEW2_PROCESS_FAILED_KIND_SANDBOX_HELPER_PROCESS_EXITED = 5;
  COREWEBVIEW2_PROCESS_FAILED_KIND_GPU_PROCESS_EXITED = 6;
  COREWEBVIEW2_PROCESS_FAILED_KIND_PPAPI_PLUGIN_PROCESS_EXITED = 7;
  COREWEBVIEW2_PROCESS_FAILED_KIND_PPAPI_BROKER_PROCESS_EXITED = 8;
  COREWEBVIEW2_PROCESS_FAILED_KIND_UNKNOWN_PROCESS_EXITED = 9;

  { COREWEBVIEW2_KEY_EVENT_KIND }
  COREWEBVIEW2_KEY_EVENT_KIND_KEY_DOWN = 0;
  COREWEBVIEW2_KEY_EVENT_KIND_KEY_UP = 1;
  COREWEBVIEW2_KEY_EVENT_KIND_SYSTEM_KEY_DOWN = 2;
  COREWEBVIEW2_KEY_EVENT_KIND_SYSTEM_KEY_UP = 3;

  { Versão mínima do runtime para as interfaces declaradas nesta unit (WebView2 1.0) }
  WV2_TARGET_COMPATIBLE_BROWSER_VERSION = '86.0.616.0';

  IID_ICoreWebView2Environment: TGUID = '{B96D755E-0319-4E92-A296-23436F46A1FC}';
  IID_ICoreWebView2Controller: TGUID = '{4D00C0D1-9434-4EB6-8078-8697A560334F}';
  IID_ICoreWebView2: TGUID = '{76ECEACB-0462-4D94-AC83-423A6793775E}';

type
  ICoreWebView2 = interface;
  ICoreWebView2Controller = interface;
  ICoreWebView2Environment = interface;

  { ---------------------------------------------------------------------- }
  { Handlers (implementados pelo nosso lado)                                }
  { ---------------------------------------------------------------------- }

  ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler = interface(IUnknown)
    ['{4E8A3389-C9D8-4BD2-B6B5-124FEE6CC14D}']
    function Invoke(ErrorCode: HResult; const CreatedEnvironment: ICoreWebView2Environment): HResult; stdcall;
  end;

  ICoreWebView2CreateCoreWebView2ControllerCompletedHandler = interface(IUnknown)
    ['{6C4819F3-C9B7-4260-8127-C9F5BDE7F68C}']
    function Invoke(ErrorCode: HResult; const CreatedController: ICoreWebView2Controller): HResult; stdcall;
  end;

  ICoreWebView2NavigationStartingEventArgs = interface(IUnknown)
    ['{5B495469-E119-438A-9B18-7604F25F2E49}']
    function get_Uri(out Uri: PWideChar): HResult; stdcall;
    function get_IsUserInitiated(out IsUserInitiated: BOOL): HResult; stdcall;
    function get_IsRedirected(out IsRedirected: BOOL): HResult; stdcall;
    function get_RequestHeaders(out RequestHeaders: IUnknown): HResult; stdcall; { ICoreWebView2HttpRequestHeaders }
    function get_Cancel(out Cancel: BOOL): HResult; stdcall;
    function put_Cancel(Cancel: WV2BOOL): HResult; stdcall;
    function get_NavigationId(out NavigationId: Int64): HResult; stdcall;
  end;

  ICoreWebView2NavigationStartingEventHandler = interface(IUnknown)
    ['{9ADBE429-F36D-432B-9DDC-F8881FBD76E3}']
    function Invoke(const Sender: ICoreWebView2; const Args: ICoreWebView2NavigationStartingEventArgs): HResult; stdcall;
  end;

  ICoreWebView2NewWindowRequestedEventArgs = interface(IUnknown)
    ['{34ACB11C-FC37-4418-9132-F9C21D1EAFB9}']
    function get_Uri(out Uri: PWideChar): HResult; stdcall;
    function put_NewWindow(const NewWindow: ICoreWebView2): HResult; stdcall;
    function get_NewWindow(out NewWindow: ICoreWebView2): HResult; stdcall;
    function put_Handled(Handled: WV2BOOL): HResult; stdcall;
    function get_Handled(out Handled: BOOL): HResult; stdcall;
    function get_IsUserInitiated(out IsUserInitiated: BOOL): HResult; stdcall;
    function GetDeferral(out Deferral: IUnknown): HResult; stdcall;           { ICoreWebView2Deferral }
    function get_WindowFeatures(out Value: IUnknown): HResult; stdcall;       { ICoreWebView2WindowFeatures }
  end;

  ICoreWebView2NewWindowRequestedEventHandler = interface(IUnknown)
    ['{D4C185FE-C81C-4989-97AF-2D3FA7AB5651}']
    function Invoke(const Sender: ICoreWebView2; const Args: ICoreWebView2NewWindowRequestedEventArgs): HResult; stdcall;
  end;

  ICoreWebView2NavigationCompletedEventArgs = interface(IUnknown)
    ['{30D68B7D-20D9-4752-A9CA-EC8448FBB5C1}']
    function get_IsSuccess(out IsSuccess: BOOL): HResult; stdcall;
    function get_WebErrorStatus(out WebErrorStatus: Integer): HResult; stdcall;
    function get_NavigationId(out NavigationId: Int64): HResult; stdcall;
  end;

  ICoreWebView2NavigationCompletedEventHandler = interface(IUnknown)
    ['{D33A35BF-1C49-4F98-93AB-006E0533FE1C}']
    function Invoke(const Sender: ICoreWebView2; const Args: ICoreWebView2NavigationCompletedEventArgs): HResult; stdcall;
  end;

  ICoreWebView2SourceChangedEventHandler = interface(IUnknown)
    ['{3C067F9F-5388-4772-8B48-79F7EF1AB37C}']
    function Invoke(const Sender: ICoreWebView2; const Args: IUnknown): HResult; stdcall;
  end;

  ICoreWebView2DocumentTitleChangedEventHandler = interface(IUnknown)
    ['{F5F2B923-953E-4042-9F95-F3A118E1AFD4}']
    function Invoke(const Sender: ICoreWebView2; const Args: IUnknown): HResult; stdcall;
  end;

  ICoreWebView2WebMessageReceivedEventArgs = interface(IUnknown)
    ['{0F99A40C-E962-4207-9E92-E3D542EFF849}']
    function get_Source(out Source: PWideChar): HResult; stdcall;
    function get_WebMessageAsJson(out WebMessageAsJson: PWideChar): HResult; stdcall;
    function TryGetWebMessageAsString(out WebMessageAsString: PWideChar): HResult; stdcall;
  end;

  ICoreWebView2WebMessageReceivedEventHandler = interface(IUnknown)
    ['{57213F19-00E6-49FA-8E07-898EA01ECBD2}']
    function Invoke(const Sender: ICoreWebView2; const Args: ICoreWebView2WebMessageReceivedEventArgs): HResult; stdcall;
  end;

  ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler = interface(IUnknown)
    ['{B99369F3-9B11-47B5-BC6F-8E7895FCEA17}']
    function Invoke(ErrorCode: HResult; Id: PWideChar): HResult; stdcall;
  end;

  ICoreWebView2ExecuteScriptCompletedHandler = interface(IUnknown)
    ['{49511172-CC67-4BCA-9923-137112F4C4CC}']
    function Invoke(ErrorCode: HResult; ResultObjectAsJson: PWideChar): HResult; stdcall;
  end;

  { ---------------------------------------------------------------------- }
  { Objetos do WebView2 (implementados pelo runtime)                        }
  { ---------------------------------------------------------------------- }

  ICoreWebView2HttpRequestHeaders = interface(IUnknown)
    ['{E86CAC0E-5523-465C-B536-8FB9FC8C8C60}']
    function GetHeader(Name: PWideChar; out Value: PWideChar): HResult; stdcall;
    function GetHeaders(Name: PWideChar; out Iterator: IUnknown): HResult; stdcall;  { ICoreWebView2HttpHeadersCollectionIterator }
    function Contains(Name: PWideChar; out Value: BOOL): HResult; stdcall;
    function SetHeader(Name: PWideChar; Value: PWideChar): HResult; stdcall;
    function RemoveHeader(Name: PWideChar): HResult; stdcall;
    function GetIterator(out Iterator: IUnknown): HResult; stdcall;
  end;

  ICoreWebView2WebResourceRequest = interface(IUnknown)
    ['{97055CD4-512C-4264-8B5F-E3F446CEA6A5}']
    function get_Uri(out Uri: PWideChar): HResult; stdcall;
    function put_Uri(Uri: PWideChar): HResult; stdcall;
    function get_Method(out Method: PWideChar): HResult; stdcall;
    function put_Method(Method: PWideChar): HResult; stdcall;
    function get_Content(out Content: IStream): HResult; stdcall;
    function put_Content(const Content: IStream): HResult; stdcall;
    function get_Headers(out Headers: ICoreWebView2HttpRequestHeaders): HResult; stdcall;
  end;

  ICoreWebView2WebResourceResponse = interface(IUnknown)
    ['{AAFCC94F-FA27-48FD-97DF-830EF75AAEC9}']
    function get_Content(out Content: IStream): HResult; stdcall;
    function put_Content(const Content: IStream): HResult; stdcall;
    function get_Headers(out Headers: IUnknown): HResult; stdcall;  { ICoreWebView2HttpResponseHeaders }
    function get_StatusCode(out StatusCode: Integer): HResult; stdcall;
    function put_StatusCode(StatusCode: Integer): HResult; stdcall;
    function get_ReasonPhrase(out ReasonPhrase: PWideChar): HResult; stdcall;
    function put_ReasonPhrase(ReasonPhrase: PWideChar): HResult; stdcall;
  end;

  TCoreWebView2PhysicalKeyStatus = record
    RepeatCount: Cardinal;
    ScanCode: Cardinal;
    IsExtendedKey: BOOL;
    IsMenuKeyDown: BOOL;
    WasKeyDown: BOOL;
    IsKeyReleased: BOOL;
  end;

  ICoreWebView2AcceleratorKeyPressedEventArgs = interface(IUnknown)
    ['{9F760F8A-FB79-42BE-9990-7B56900FA9C7}']
    function get_KeyEventKind(out Kind: Integer): HResult; stdcall;
    function get_VirtualKey(out VirtualKey: Cardinal): HResult; stdcall;
    function get_KeyEventLParam(out LParam: Integer): HResult; stdcall;
    function get_PhysicalKeyStatus(out Status: TCoreWebView2PhysicalKeyStatus): HResult; stdcall;
    function get_Handled(out Handled: BOOL): HResult; stdcall;
    function put_Handled(Handled: WV2BOOL): HResult; stdcall;
  end;

  ICoreWebView2AcceleratorKeyPressedEventHandler = interface(IUnknown)
    ['{B29C7E28-FA79-41A8-8E44-65811C76DCB2}']
    function Invoke(const Sender: ICoreWebView2Controller;
      const Args: ICoreWebView2AcceleratorKeyPressedEventArgs): HResult; stdcall;
  end;

  ICoreWebView2Deferral = interface(IUnknown)
    ['{C10E7F7B-B585-46F0-A623-8BEFBF3E4EE0}']
    function Complete: HResult; stdcall;
  end;

  ICoreWebView2ProcessFailedEventArgs = interface(IUnknown)
    ['{8155A9A4-1474-4A86-8CAE-151B0FA6B8CA}']
    function get_ProcessFailedKind(out Kind: Integer): HResult; stdcall;
  end;

  ICoreWebView2ProcessFailedEventHandler = interface(IUnknown)
    ['{79E0AEA4-990B-42D9-AA1D-0FCC2E5BC7F1}']
    function Invoke(const Sender: ICoreWebView2; const Args: ICoreWebView2ProcessFailedEventArgs): HResult; stdcall;
  end;

  { Implementada pelo nosso lado e passada a CreateCoreWebView2EnvironmentWithOptions }
  ICoreWebView2EnvironmentOptions = interface(IUnknown)
    ['{2FDE08A8-1E9A-4766-8C05-95A9CEB9D1C5}']
    function get_AdditionalBrowserArguments(out Value: PWideChar): HResult; stdcall;
    function put_AdditionalBrowserArguments(Value: PWideChar): HResult; stdcall;
    function get_Language(out Value: PWideChar): HResult; stdcall;
    function put_Language(Value: PWideChar): HResult; stdcall;
    function get_TargetCompatibleBrowserVersion(out Value: PWideChar): HResult; stdcall;
    function put_TargetCompatibleBrowserVersion(Value: PWideChar): HResult; stdcall;
    function get_AllowSingleSignOnUsingOSPrimaryAccount(out Allow: BOOL): HResult; stdcall;
    function put_AllowSingleSignOnUsingOSPrimaryAccount(Allow: WV2BOOL): HResult; stdcall;
  end;

  ICoreWebView2WebResourceRequestedEventArgs = interface(IUnknown)
    ['{453E667F-12C7-49D4-BE6D-DDBE7956F57A}']
    function get_Request(out Request: ICoreWebView2WebResourceRequest): HResult; stdcall;
    function get_Response(out Response: ICoreWebView2WebResourceResponse): HResult; stdcall;
    function put_Response(const Response: ICoreWebView2WebResourceResponse): HResult; stdcall;
    function GetDeferral(out Deferral: ICoreWebView2Deferral): HResult; stdcall;
    function get_ResourceContext(out Context: Integer): HResult; stdcall;
  end;

  ICoreWebView2WebResourceRequestedEventHandler = interface(IUnknown)
    ['{AB00B74C-15F1-4646-80E8-E76341D25D71}']
    function Invoke(const Sender: ICoreWebView2; const Args: ICoreWebView2WebResourceRequestedEventArgs): HResult; stdcall;
  end;

  ICoreWebView2Environment = interface(IUnknown)
    ['{B96D755E-0319-4E92-A296-23436F46A1FC}']
    function CreateCoreWebView2Controller(ParentWindow: HWND;
      const Handler: ICoreWebView2CreateCoreWebView2ControllerCompletedHandler): HResult; stdcall;
    function CreateWebResourceResponse(const Content: IStream; StatusCode: Integer; ReasonPhrase: PWideChar;
      Headers: PWideChar; out Response: ICoreWebView2WebResourceResponse): HResult; stdcall;
    function get_BrowserVersionString(out VersionInfo: PWideChar): HResult; stdcall;
    function add_NewBrowserVersionAvailable(const Handler: IUnknown; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_NewBrowserVersionAvailable(Token: EventRegistrationToken): HResult; stdcall;
  end;

  ICoreWebView2Settings = interface(IUnknown)
    ['{E562E4F0-D7FA-43AC-8D71-C05150499F00}']
    function get_IsScriptEnabled(out Value: BOOL): HResult; stdcall;
    function put_IsScriptEnabled(Value: WV2BOOL): HResult; stdcall;
    function get_IsWebMessageEnabled(out Value: BOOL): HResult; stdcall;
    function put_IsWebMessageEnabled(Value: WV2BOOL): HResult; stdcall;
    function get_AreDefaultScriptDialogsEnabled(out Value: BOOL): HResult; stdcall;
    function put_AreDefaultScriptDialogsEnabled(Value: WV2BOOL): HResult; stdcall;
    function get_IsStatusBarEnabled(out Value: BOOL): HResult; stdcall;
    function put_IsStatusBarEnabled(Value: WV2BOOL): HResult; stdcall;
    function get_AreDevToolsEnabled(out Value: BOOL): HResult; stdcall;
    function put_AreDevToolsEnabled(Value: WV2BOOL): HResult; stdcall;
    function get_AreDefaultContextMenusEnabled(out Value: BOOL): HResult; stdcall;
    function put_AreDefaultContextMenusEnabled(Value: WV2BOOL): HResult; stdcall;
    function get_AreHostObjectsAllowed(out Value: BOOL): HResult; stdcall;
    function put_AreHostObjectsAllowed(Value: WV2BOOL): HResult; stdcall;
    function get_IsZoomControlEnabled(out Value: BOOL): HResult; stdcall;
    function put_IsZoomControlEnabled(Value: WV2BOOL): HResult; stdcall;
    function get_IsBuiltInErrorPageEnabled(out Value: BOOL): HResult; stdcall;
    function put_IsBuiltInErrorPageEnabled(Value: WV2BOOL): HResult; stdcall;
  end;

  ICoreWebView2Controller = interface(IUnknown)
    ['{4D00C0D1-9434-4EB6-8078-8697A560334F}']
    function get_IsVisible(out IsVisible: BOOL): HResult; stdcall;
    function put_IsVisible(IsVisible: WV2BOOL): HResult; stdcall;
    function get_Bounds(out Bounds: TRect): HResult; stdcall;
    function put_Bounds(Bounds: TRect): HResult; stdcall;
    function get_ZoomFactor(out ZoomFactor: Double): HResult; stdcall;
    function put_ZoomFactor(ZoomFactor: Double): HResult; stdcall;
    function add_ZoomFactorChanged(const Handler: IUnknown; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_ZoomFactorChanged(Token: EventRegistrationToken): HResult; stdcall;
    function SetBoundsAndZoomFactor(Bounds: TRect; ZoomFactor: Double): HResult; stdcall;
    function MoveFocus(Reason: Integer): HResult; stdcall;
    function add_MoveFocusRequested(const Handler: IUnknown; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_MoveFocusRequested(Token: EventRegistrationToken): HResult; stdcall;
    function add_GotFocus(const Handler: IUnknown; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_GotFocus(Token: EventRegistrationToken): HResult; stdcall;
    function add_LostFocus(const Handler: IUnknown; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_LostFocus(Token: EventRegistrationToken): HResult; stdcall;
    function add_AcceleratorKeyPressed(const Handler: ICoreWebView2AcceleratorKeyPressedEventHandler; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_AcceleratorKeyPressed(Token: EventRegistrationToken): HResult; stdcall;
    function get_ParentWindow(out ParentWindow: HWND): HResult; stdcall;
    function put_ParentWindow(ParentWindow: HWND): HResult; stdcall;
    function NotifyParentWindowPositionChanged: HResult; stdcall;
    function Close: HResult; stdcall;
    function get_CoreWebView2(out CoreWebView2: ICoreWebView2): HResult; stdcall;
  end;

  ICoreWebView2 = interface(IUnknown)
    ['{76ECEACB-0462-4D94-AC83-423A6793775E}']
    function get_Settings(out Settings: ICoreWebView2Settings): HResult; stdcall;
    function get_Source(out Uri: PWideChar): HResult; stdcall;
    function Navigate(Uri: PWideChar): HResult; stdcall;
    function NavigateToString(HtmlContent: PWideChar): HResult; stdcall;
    function add_NavigationStarting(const Handler: ICoreWebView2NavigationStartingEventHandler; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_NavigationStarting(Token: EventRegistrationToken): HResult; stdcall;
    function add_ContentLoading(const Handler: IUnknown; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_ContentLoading(Token: EventRegistrationToken): HResult; stdcall;
    function add_SourceChanged(const Handler: ICoreWebView2SourceChangedEventHandler; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_SourceChanged(Token: EventRegistrationToken): HResult; stdcall;
    function add_HistoryChanged(const Handler: IUnknown; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_HistoryChanged(Token: EventRegistrationToken): HResult; stdcall;
    function add_NavigationCompleted(const Handler: ICoreWebView2NavigationCompletedEventHandler; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_NavigationCompleted(Token: EventRegistrationToken): HResult; stdcall;
    function add_FrameNavigationStarting(const Handler: IUnknown; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_FrameNavigationStarting(Token: EventRegistrationToken): HResult; stdcall;
    function add_FrameNavigationCompleted(const Handler: IUnknown; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_FrameNavigationCompleted(Token: EventRegistrationToken): HResult; stdcall;
    function add_ScriptDialogOpening(const Handler: IUnknown; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_ScriptDialogOpening(Token: EventRegistrationToken): HResult; stdcall;
    function add_PermissionRequested(const Handler: IUnknown; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_PermissionRequested(Token: EventRegistrationToken): HResult; stdcall;
    function add_ProcessFailed(const Handler: ICoreWebView2ProcessFailedEventHandler; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_ProcessFailed(Token: EventRegistrationToken): HResult; stdcall;
    function AddScriptToExecuteOnDocumentCreated(JavaScript: PWideChar;
      const Handler: ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler): HResult; stdcall;
    function RemoveScriptToExecuteOnDocumentCreated(Id: PWideChar): HResult; stdcall;
    function ExecuteScript(JavaScript: PWideChar; const Handler: ICoreWebView2ExecuteScriptCompletedHandler): HResult; stdcall;
    function CapturePreview(ImageFormat: Integer; ImageStream: Pointer; const Handler: IUnknown): HResult; stdcall;
    function Reload: HResult; stdcall;
    function PostWebMessageAsJson(WebMessageAsJson: PWideChar): HResult; stdcall;
    function PostWebMessageAsString(WebMessageAsString: PWideChar): HResult; stdcall;
    function add_WebMessageReceived(const Handler: ICoreWebView2WebMessageReceivedEventHandler; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_WebMessageReceived(Token: EventRegistrationToken): HResult; stdcall;
    function CallDevToolsProtocolMethod(MethodName: PWideChar; ParametersAsJson: PWideChar; const Handler: IUnknown): HResult; stdcall;
    function get_BrowserProcessId(out Value: LongWord): HResult; stdcall;
    function get_CanGoBack(out CanGoBack: BOOL): HResult; stdcall;
    function get_CanGoForward(out CanGoForward: BOOL): HResult; stdcall;
    function GoBack: HResult; stdcall;
    function GoForward: HResult; stdcall;
    function GetDevToolsProtocolEventReceiver(EventName: PWideChar; out Receiver: IUnknown): HResult; stdcall;
    function Stop: HResult; stdcall;
    function add_NewWindowRequested(const Handler: ICoreWebView2NewWindowRequestedEventHandler; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_NewWindowRequested(Token: EventRegistrationToken): HResult; stdcall;
    function add_DocumentTitleChanged(const Handler: ICoreWebView2DocumentTitleChangedEventHandler; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_DocumentTitleChanged(Token: EventRegistrationToken): HResult; stdcall;
    function get_DocumentTitle(out Title: PWideChar): HResult; stdcall;
    function AddHostObjectToScript(Name: PWideChar; var AObject: OleVariant): HResult; stdcall;
    function RemoveHostObjectFromScript(Name: PWideChar): HResult; stdcall;
    function OpenDevToolsWindow: HResult; stdcall;
    function add_ContainsFullScreenElementChanged(const Handler: IUnknown; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_ContainsFullScreenElementChanged(Token: EventRegistrationToken): HResult; stdcall;
    function get_ContainsFullScreenElement(out Value: BOOL): HResult; stdcall;
    function add_WebResourceRequested(const Handler: ICoreWebView2WebResourceRequestedEventHandler; out Token: EventRegistrationToken): HResult; stdcall;
    function remove_WebResourceRequested(Token: EventRegistrationToken): HResult; stdcall;
    function AddWebResourceRequestedFilter(Uri: PWideChar; ResourceContext: Integer): HResult; stdcall;
    function RemoveWebResourceRequestedFilter(Uri: PWideChar; ResourceContext: Integer): HResult; stdcall;
    { (há mais métodos depois deste ponto na vtable; não são usados aqui) }
  end;

  TCreateCoreWebView2EnvironmentWithOptions = function(BrowserExecutableFolder: PWideChar;
    UserDataFolder: PWideChar; const EnvironmentOptions: ICoreWebView2EnvironmentOptions;
    const EnvironmentCreatedHandler: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler): HResult; stdcall;

  TGetAvailableCoreWebView2BrowserVersionString = function(BrowserExecutableFolder: PWideChar;
    out VersionInfo: PWideChar): HResult; stdcall;

var
  CreateCoreWebView2EnvironmentWithOptions: TCreateCoreWebView2EnvironmentWithOptions = nil;
  GetAvailableCoreWebView2BrowserVersionString: TGetAvailableCoreWebView2BrowserVersionString = nil;

{ Carrega o WebView2Loader.dll (versão x86, pois o Delphi 7 gera 32 bits). }
function LoadWebView2Loader(const DllPath: string = 'WebView2Loader.dll'): Boolean;

{ Versão do runtime Evergreen instalado, ou '' se não houver runtime. }
function GetWebView2RuntimeVersion: WideString;

{ Copia uma string alocada pelo WebView2 e libera a memória original. }
function TakeCoTaskString(P: PWideChar): WideString;

{ Converte Boolean para o BOOL esperado pelo WebView2 (1/0). }
function BoolToWV2(Value: Boolean): WV2BOOL;

implementation

var
  LoaderHandle: HMODULE = 0;

function LoadWebView2Loader(const DllPath: string): Boolean;
begin
  if LoaderHandle = 0 then
  begin
    LoaderHandle := LoadLibrary(PChar(DllPath));
    if LoaderHandle <> 0 then
    begin
      @CreateCoreWebView2EnvironmentWithOptions :=
        GetProcAddress(LoaderHandle, 'CreateCoreWebView2EnvironmentWithOptions');
      @GetAvailableCoreWebView2BrowserVersionString :=
        GetProcAddress(LoaderHandle, 'GetAvailableCoreWebView2BrowserVersionString');
    end;
  end;
  Result := (LoaderHandle <> 0) and Assigned(CreateCoreWebView2EnvironmentWithOptions);
end;

function GetWebView2RuntimeVersion: WideString;
var
  P: PWideChar;
begin
  Result := '';
  if not LoadWebView2Loader or not Assigned(GetAvailableCoreWebView2BrowserVersionString) then
    Exit;
  P := nil;
  if Succeeded(GetAvailableCoreWebView2BrowserVersionString(nil, P)) then
    Result := TakeCoTaskString(P);
end;

function TakeCoTaskString(P: PWideChar): WideString;
begin
  if P = nil then
    Result := ''
  else
  begin
    Result := P;
    CoTaskMemFree(P);
  end;
end;

function BoolToWV2(Value: Boolean): WV2BOOL;
begin
  if Value then
    Result := 1
  else
    Result := 0;
end;

initialization

finalization
  if LoaderHandle <> 0 then
    FreeLibrary(LoaderHandle);

end.
