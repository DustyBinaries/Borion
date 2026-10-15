unit BorionNotification;

(*
  Borion — Native Application Engine
  Plugin "notification": notificações nativas do Windows (toast, WinRT).

    Ipc.AddPlugin(TBorionNotificationPlugin.Create);            // AppId: 'Borion.<título do app>'
    Ipc.AddPlugin(TBorionNotificationPlugin.Create('Empresa.MeuApp'));

  Comandos:
    notification:send {id?, title, body?, silent?, actions?: [{id, title}]}  -> id
    notification:hide {id}                tira da tela uma notificação mostrada
    notification:permission               -> 'granted' | 'denied'
  Eventos:
    notification:click     {id, action}   clique na notificação (action null) ou num botão
    notification:dismissed {id, reason}   'user' | 'hidden' | 'timeout'
    notification:failed    {id, error}

  title, body e o title dos botões são literais JSON só com ASCII (Unicode
  completo; o @borion/api/notification gera). id e o id dos botões são texto
  simples: letras, números, '.', '_', ':' e '-', até 64 caracteres.

  Um app desktop sem pacote precisa de um AppUserModelID registrado para mostrar
  toasts. O plugin registra em HKCU\Software\Classes\AppUserModelId\<AppId>
  (DisplayName e IconUri) e o define no processo, como o Windows Community
  Toolkit faz; não precisa de atalho no Menu Iniciar. Para tirar o registro (no
  desinstalador), use BorionNotificationUnregister.

  Sem WinRT (Windows 7) a notificação vira um balão do plugin tray, se houver.
  Os eventos só chegam enquanto o app está aberto: clicar numa notificação na
  Central de Ações depois de fechar o app não o abre de novo.
*)

interface

uses
  Windows, Messages, SysUtils, Classes, Forms, Registry, ActiveX, Jsons, BorionIpc;

type
  TBorionNotificationAction = record
    Id: string;
    Title: WideString;
  end;
  TBorionNotificationActions = array of TBorionNotificationAction;

  TBorionNotificationClick = procedure(Sender: TObject; const Id, Action: string) of object;

  TBorionNotificationPlugin = class(TBorionPlugin)
  private
    FAppId: string;
    FDisplayName: string;
    FIconPath: string;
    FFocusOnClick: Boolean;
    FWindow: HWND;
    FToasts: TStringList;  { id -> TObject com a notificação (mantém viva até sair da tela) }
    FSeq: Integer;
    FRegistrado: Boolean;
    FComIniciado: Boolean;
    FOnClick: TBorionNotificationClick;
    procedure Registrar;
    procedure WndProc(var Message: TMessage);
    procedure Esquecer(const Id: string);
    procedure CmdSend(Call: TBorionCall);
    procedure CmdHide(Call: TBorionCall);
    procedure CmdPermission(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    { AppId vazio: 'Borion.' + Application.Title (só letras e números) }
    constructor Create(const AppId: string = '');
    destructor Destroy; override;
    function Name: string; override;
    { Mostra uma notificação; Id vazio gera um. Devolve o id. }
    function Send(const Id: string; const Title, Body: WideString; Silent: Boolean = False;
      const Actions: TBorionNotificationActions = nil): string;
    procedure Hide(const Id: string);
    { Eventos de uma notificação (chamados na thread da interface; públicos para testes) }
    procedure Activated(const Id: string; const Arguments: WideString);
    procedure Dismissed(const Id: string; Reason: Integer);
    procedure NotificationFailed(const Id: string; ErrorCode: Integer);
    { Notificações mostradas que ainda podem gerar eventos }
    function ActiveCount: Integer;
    function PermissionGranted: Boolean;
    { True se o WinRT (Windows 8+) está disponível }
    function ToastsAvailable: Boolean;
    property AppId: string read FAppId;
    { Nome mostrado na notificação (padrão: Application.Title) }
    property DisplayName: string read FDisplayName write FDisplayName;
    { Imagem (.png/.jpg) do app na notificação e nas configurações do Windows }
    property IconPath: string read FIconPath write FIconPath;
    { Clicar na notificação traz a janela para frente (padrão: True) }
    property FocusOnClick: Boolean read FFocusOnClick write FFocusOnClick;
    property OnClick: TBorionNotificationClick read FOnClick write FOnClick;
  end;

{ XML do toast (ToastGeneric) }
function BorionToastXml(const Id: string; const Title, Body: WideString; Silent: Boolean;
  const Actions: TBorionNotificationActions; const IconPath: string): WideString;
{ 'Meu App 2!' -> 'Borion.MeuApp2' }
function BorionDefaultAppId(const Title: string): string;
{ Tira o registro do AppUserModelID (para desinstaladores) }
procedure BorionNotificationUnregister(const AppId: string);
{ True se Id serve como id de notificação ou de botão }
function BorionValidNotificationId(const Id: string): Boolean;

implementation

uses
  BorionJson, BorionTray, BorionApp;

{ --- WinRT ------------------------------------------------------------------ }

type
  HSTRING = type THandle;

  IInspectable = interface(IUnknown)
    ['{AF86E2E0-B12D-4C6A-9C5A-D7AA65101E90}']
    function GetIids(out IidCount: Cardinal; out Iids: PGUID): HResult; stdcall;
    function GetRuntimeClassName(out ClassName: HSTRING): HResult; stdcall;
    function GetTrustLevel(out TrustLevel: Integer): HResult; stdcall;
  end;

  IXmlDocument = interface(IInspectable)
    ['{F7F3A506-1E87-42D6-BCFB-B8C809FA5494}']
  end;

  IXmlDocumentIO = interface(IInspectable)
    ['{6CD0E74E-EE65-4489-9EBF-CA43E87BA637}']
    function LoadXml(Xml: HSTRING): HResult; stdcall;
  end;

  IToastNotification = interface;

  IToastActivatedEventArgs = interface(IInspectable)
    ['{E3BF92F3-C197-436F-8265-0625824F8DAC}']
    function get_Arguments(out Value: HSTRING): HResult; stdcall;
  end;

  IToastDismissedEventArgs = interface(IInspectable)
    ['{3F89D935-D9CB-4538-A0F0-FFE7659938F8}']
    function get_Reason(out Value: Integer): HResult; stdcall;
  end;

  IToastFailedEventArgs = interface(IInspectable)
    ['{35176862-CFD4-44F8-AD64-F500FD896C3B}']
    function get_ErrorCode(out Value: HResult): HResult; stdcall;
  end;

  { TypedEventHandler<ToastNotification, ...>: delegates, IUnknown + Invoke }
  IActivatedHandler = interface(IUnknown)
    ['{AB54DE2D-97D9-5528-B6AD-105AFE156530}']
    function Invoke(const Sender: IToastNotification; const Args: IInspectable): HResult; stdcall;
  end;

  IDismissedHandler = interface(IUnknown)
    ['{61C2402F-0ED0-5A18-AB69-59F4AA99A368}']
    function Invoke(const Sender: IToastNotification; const Args: IToastDismissedEventArgs): HResult; stdcall;
  end;

  IFailedHandler = interface(IUnknown)
    ['{95E3E803-C969-5E3A-9753-EA2AD22A9A33}']
    function Invoke(const Sender: IToastNotification; const Args: IToastFailedEventArgs): HResult; stdcall;
  end;

  IToastNotification = interface(IInspectable)
    ['{997E2675-059E-4E60-8B06-1760917C8B80}']
    function get_Content(out Value: IXmlDocument): HResult; stdcall;
    function put_ExpirationTime(Value: Pointer): HResult; stdcall;
    function get_ExpirationTime(out Value: Pointer): HResult; stdcall;
    function add_Dismissed(const Handler: IDismissedHandler; out Token: Int64): HResult; stdcall;
    function remove_Dismissed(Token: Int64): HResult; stdcall;
    function add_Activated(const Handler: IActivatedHandler; out Token: Int64): HResult; stdcall;
    function remove_Activated(Token: Int64): HResult; stdcall;
    function add_Failed(const Handler: IFailedHandler; out Token: Int64): HResult; stdcall;
    function remove_Failed(Token: Int64): HResult; stdcall;
  end;

  IToastNotifier = interface(IInspectable)
    ['{75927B93-03F3-41EC-91D3-6E5BAC1B38E7}']
    function Show(const Notification: IToastNotification): HResult; stdcall;
    function Hide(const Notification: IToastNotification): HResult; stdcall;
    function get_Setting(out Value: Integer): HResult; stdcall;
  end;

  IToastNotificationFactory = interface(IInspectable)
    ['{04124B20-82C6-4229-B109-FD9ED4662B53}']
    function CreateToastNotification(const Content: IXmlDocument; out Value: IToastNotification): HResult; stdcall;
  end;

  IToastNotificationManagerStatics = interface(IInspectable)
    ['{50AC103F-D235-4598-BBEF-98FE4D1A3AD4}']
    function CreateToastNotifier(out Value: IToastNotifier): HResult; stdcall;
    function CreateToastNotifierWithId(AppId: HSTRING; out Value: IToastNotifier): HResult; stdcall;
  end;

  { marca o delegate como livre de thread: o WinRT chama de outra thread }
  IAgileObject = interface(IUnknown)
    ['{94EA2B94-E9CC-49E0-C0FF-EE64CA8F5B90}']
  end;

  TWindowsCreateString = function(Src: PWideChar; Len: Cardinal; out Str: HSTRING): HResult; stdcall;
  TWindowsDeleteString = function(Str: HSTRING): HResult; stdcall;
  TWindowsGetStringRawBuffer = function(Str: HSTRING; Len: PCardinal): PWideChar; stdcall;
  TRoGetActivationFactory = function(ClassId: HSTRING; const Iid: TGUID; out Factory): HResult; stdcall;
  TRoActivateInstance = function(ClassId: HSTRING; out Instance: IInspectable): HResult; stdcall;
  TSetAppId = function(AppId: PWideChar): HResult; stdcall;

var
  WinRTCarregado: Boolean;
  WindowsCreateString: TWindowsCreateString;
  WindowsDeleteString: TWindowsDeleteString;
  WindowsGetStringRawBuffer: TWindowsGetStringRawBuffer;
  RoGetActivationFactory: TRoGetActivationFactory;
  RoActivateInstance: TRoActivateInstance;

function WinRT: Boolean;
var
  M: HMODULE;
begin
  if not WinRTCarregado then
  begin
    WinRTCarregado := True;
    M := LoadLibrary('combase.dll');  { Windows 8+ }
    if M <> 0 then
    begin
      @WindowsCreateString := GetProcAddress(M, 'WindowsCreateString');
      @WindowsDeleteString := GetProcAddress(M, 'WindowsDeleteString');
      @WindowsGetStringRawBuffer := GetProcAddress(M, 'WindowsGetStringRawBuffer');
      @RoGetActivationFactory := GetProcAddress(M, 'RoGetActivationFactory');
      @RoActivateInstance := GetProcAddress(M, 'RoActivateInstance');
    end;
  end;
  Result := Assigned(WindowsCreateString) and Assigned(WindowsDeleteString) and
    Assigned(WindowsGetStringRawBuffer) and Assigned(RoGetActivationFactory) and
    Assigned(RoActivateInstance);
end;

type
  { HSTRING que se apaga sozinho }
  THString = class
  private
    FValue: HSTRING;
  public
    constructor Create(const S: WideString);
    destructor Destroy; override;
    property Value: HSTRING read FValue;
  end;

constructor THString.Create(const S: WideString);
begin
  inherited Create;
  if Failed(WindowsCreateString(PWideChar(S), Length(S), FValue)) then
    raise EBorionError.Create('NOTIFICATION_FAILED', 'WindowsCreateString falhou');
end;

destructor THString.Destroy;
begin
  if FValue <> 0 then
    WindowsDeleteString(FValue);
  inherited;
end;

function LerHString(S: HSTRING): WideString;
var
  N: Cardinal;
  P: PWideChar;
begin
  Result := '';
  if S = 0 then
    Exit;
  P := WindowsGetStringRawBuffer(S, @N);
  SetString(Result, P, N);
end;

procedure Checar(R: HResult; const Etapa: string);
begin
  if Failed(R) then
    raise EBorionError.Create('NOTIFICATION_FAILED',
      Format('%s falhou: %s ($%.8x)', [Etapa, SysErrorMessage(R), R]));
end;

function Fabrica(const Classe: WideString; const Iid: TGUID; out Fab): HResult;
var
  H: THString;
begin
  H := THString.Create(Classe);
  try
    Result := RoGetActivationFactory(H.Value, Iid, Fab);
  finally
    H.Free;
  end;
end;

function Notificador(const AppId: string; out N: IToastNotifier): HResult;
var
  Statics: IToastNotificationManagerStatics;
  H: THString;
begin
  Result := Fabrica('Windows.UI.Notifications.ToastNotificationManager',
    IToastNotificationManagerStatics, Statics);
  if Failed(Result) then
    Exit;
  H := THString.Create(AppId);
  try
    Result := Statics.CreateToastNotifierWithId(H.Value, N);
  finally
    H.Free;
  end;
end;

{ --- eventos: chegam numa thread do WinRT e vão para a janela do plugin --- }

const
  WM_BORION_NOTIFICATION = WM_USER + 40;

type
  TTipoEvento = (teClique, teDispensa, teFalha);

  PEvento = ^TEvento;
  TEvento = record
    Tipo: TTipoEvento;
    Id: string;
    Argumentos: WideString;
    Motivo: Integer;
  end;

  TOuvinte = class(TInterfacedObject, IActivatedHandler, IDismissedHandler, IFailedHandler, IAgileObject)
  private
    FJanela: HWND;
    FId: string;
    procedure Postar(Tipo: TTipoEvento; const Argumentos: WideString; Motivo: Integer);
    function Ativado(const Sender: IToastNotification; const Args: IInspectable): HResult; stdcall;
    function Dispensado(const Sender: IToastNotification; const Args: IToastDismissedEventArgs): HResult; stdcall;
    function Falhou(const Sender: IToastNotification; const Args: IToastFailedEventArgs): HResult; stdcall;
    function IActivatedHandler.Invoke = Ativado;
    function IDismissedHandler.Invoke = Dispensado;
    function IFailedHandler.Invoke = Falhou;
  public
    constructor Create(Janela: HWND; const Id: string);
  end;

  { uma notificação mostrada: mantém o objeto WinRT vivo e os registros dos eventos }
  TToast = class
  public
    Toast: IToastNotification;
    Ouvinte: TOuvinte;
    TokenAtivado, TokenDispensado, TokenFalha: Int64;
    destructor Destroy; override;
  end;

constructor TOuvinte.Create(Janela: HWND; const Id: string);
begin
  inherited Create;
  FJanela := Janela;
  FId := Id;
end;

procedure TOuvinte.Postar(Tipo: TTipoEvento; const Argumentos: WideString; Motivo: Integer);
var
  E: PEvento;
begin
  New(E);
  E.Tipo := Tipo;
  E.Id := FId;
  E.Argumentos := Argumentos;
  E.Motivo := Motivo;
  if not PostMessage(FJanela, WM_BORION_NOTIFICATION, 0, LPARAM(E)) then
    Dispose(E);  { o plugin já foi destruído }
end;

function TOuvinte.Ativado(const Sender: IToastNotification; const Args: IInspectable): HResult;
var
  A: IToastActivatedEventArgs;
  S: HSTRING;
  Texto: WideString;
begin
  Texto := '';
  if (Args <> nil) and Succeeded(Args.QueryInterface(IToastActivatedEventArgs, A)) and
    Succeeded(A.get_Arguments(S)) then
  begin
    Texto := LerHString(S);
    WindowsDeleteString(S);
  end;
  Postar(teClique, Texto, 0);
  Result := S_OK;
end;

function TOuvinte.Dispensado(const Sender: IToastNotification; const Args: IToastDismissedEventArgs): HResult;
var
  Motivo: Integer;
begin
  Motivo := 0;
  if Args <> nil then
    Args.get_Reason(Motivo);
  Postar(teDispensa, '', Motivo);
  Result := S_OK;
end;

function TOuvinte.Falhou(const Sender: IToastNotification; const Args: IToastFailedEventArgs): HResult;
var
  Erro: HResult;
begin
  Erro := E_FAIL;
  if Args <> nil then
    Args.get_ErrorCode(Erro);
  Postar(teFalha, '', Erro);
  Result := S_OK;
end;

destructor TToast.Destroy;
begin
  if Toast <> nil then
  begin
    Toast.remove_Activated(TokenAtivado);
    Toast.remove_Dismissed(TokenDispensado);
    Toast.remove_Failed(TokenFalha);
  end;
  Toast := nil;
  if Ouvinte <> nil then
    Ouvinte._Release;
  inherited;
end;

{ --- funções ----------------------------------------------------------------- }

function BorionValidNotificationId(const Id: string): Boolean;
var
  I: Integer;
begin
  Result := (Id <> '') and (Length(Id) <= 64);
  if Result then
    for I := 1 to Length(Id) do
      if not (Id[I] in ['A'..'Z', 'a'..'z', '0'..'9', '.', '_', ':', '-']) then
      begin
        Result := False;
        Exit;
      end;
end;

function BorionDefaultAppId(const Title: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(Title) do
    if Title[I] in ['A'..'Z', 'a'..'z', '0'..'9'] then
      Result := Result + Title[I];
  if Result = '' then
    Result := 'App';
  Result := 'Borion.' + Result;
end;

function Xml(const S: WideString): WideString;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    case S[I] of
      '&': Result := Result + '&amp;';
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '"': Result := Result + '&quot;';
      '''': Result := Result + '&apos;';
    else
      Result := Result + S[I];
    end;
end;

function BorionToastXml(const Id: string; const Title, Body: WideString; Silent: Boolean;
  const Actions: TBorionNotificationActions; const IconPath: string): WideString;
var
  I: Integer;
begin
  { launch/arguments voltam no clique: 'borion|<id>|<botão>' }
  Result := '<toast launch="' + Xml('borion|' + Id + '|') + '">' +
    '<visual><binding template="ToastGeneric">' +
    '<text>' + Xml(Title) + '</text>';
  if Body <> '' then
    Result := Result + '<text>' + Xml(Body) + '</text>';
  if IconPath <> '' then
    Result := Result + '<image placement="appLogoOverride" src="' +
      Xml('file:///' + StringReplace(IconPath, '\', '/', [rfReplaceAll])) + '"/>';
  Result := Result + '</binding></visual>';
  if Length(Actions) > 0 then
  begin
    Result := Result + '<actions>';
    for I := 0 to High(Actions) do
      Result := Result + '<action content="' + Xml(Actions[I].Title) + '" arguments="' +
        Xml('borion|' + Id + '|' + Actions[I].Id) + '" activationType="foreground"/>';
    Result := Result + '</actions>';
  end;
  if Silent then
    Result := Result + '<audio silent="true"/>';
  Result := Result + '</toast>';
end;

procedure BorionNotificationUnregister(const AppId: string);
var
  R: TRegistry;
begin
  R := TRegistry.Create;
  try
    R.RootKey := HKEY_CURRENT_USER;
    R.DeleteKey('Software\Classes\AppUserModelId\' + AppId);
  finally
    R.Free;
  end;
end;

{ TBorionNotificationPlugin }

constructor TBorionNotificationPlugin.Create(const AppId: string);
begin
  inherited Create;
  if AppId <> '' then
    FAppId := AppId
  else
    FAppId := BorionDefaultAppId(Application.Title);
  FDisplayName := Application.Title;
  FFocusOnClick := True;
  FToasts := TStringList.Create;
  FWindow := Classes.AllocateHWnd(WndProc);
  FComIniciado := CoInitialize(nil) = S_OK;  { o WinRT precisa de COM na thread }
end;

destructor TBorionNotificationPlugin.Destroy;
var
  I: Integer;
begin
  for I := 0 to FToasts.Count - 1 do
    FToasts.Objects[I].Free;
  FToasts.Free;
  Classes.DeallocateHWnd(FWindow);
  if FComIniciado then
    CoUninitialize;
  inherited;
end;

function TBorionNotificationPlugin.Name: string;
begin
  Result := 'notification';
end;

procedure TBorionNotificationPlugin.Install;
begin
  Command('send', CmdSend);
  Command('hide', CmdHide);
  Command('permission', CmdPermission);
end;

function TBorionNotificationPlugin.ToastsAvailable: Boolean;
begin
  Result := WinRT;
end;

procedure TBorionNotificationPlugin.Registrar;
var
  R: TRegistry;
  SetAppId: TSetAppId;
begin
  if FRegistrado then
    Exit;
  R := TRegistry.Create;
  try
    R.RootKey := HKEY_CURRENT_USER;
    if R.OpenKey('Software\Classes\AppUserModelId\' + FAppId, True) then
    begin
      R.WriteString('DisplayName', FDisplayName);
      if FIconPath <> '' then
        R.WriteString('IconUri', FIconPath)
      else if R.ValueExists('IconUri') then
        R.DeleteValue('IconUri');
    end;
  finally
    R.Free;
  end;
  @SetAppId := GetProcAddress(GetModuleHandle('shell32.dll'), 'SetCurrentProcessExplicitAppUserModelID');
  if Assigned(SetAppId) then
    SetAppId(PWideChar(WideString(FAppId)));
  FRegistrado := True;
end;

function TBorionNotificationPlugin.PermissionGranted: Boolean;
var
  N: IToastNotifier;
  Ajuste: Integer;
begin
  if not WinRT then
  begin
    Result := (Ipc <> nil) and (Ipc.FindPlugin('tray') <> nil);
    Exit;
  end;
  Registrar;
  if Failed(Notificador(FAppId, N)) then
    Result := False
  else if Failed(N.get_Setting(Ajuste)) then
    Result := True  { app que ainda não notificou: o Windows ainda não o conhece, e o padrão é permitir }
  else
    Result := Ajuste = 0;  { 0 = Enabled }
end;

function TBorionNotificationPlugin.Send(const Id: string; const Title, Body: WideString;
  Silent: Boolean; const Actions: TBorionNotificationActions): string;
var
  Classe: THString;
  Inst: IInspectable;
  Io: IXmlDocumentIO;
  Doc: IXmlDocument;
  Fab: IToastNotificationFactory;
  N: IToastNotifier;
  T: TToast;
  H: THString;
  Tray: TBorionPlugin;
  I: Integer;
begin
  if Id = '' then
  begin
    Inc(FSeq);
    Result := Format('n%d-%d', [GetCurrentProcessId, FSeq]);
  end
  else
    Result := Id;
  if not BorionValidNotificationId(Result) then
    raise EBorionError.Create('INVALID_ARGS', 'id de notificação inválido: ' + Result);
  for I := 0 to High(Actions) do
    if not BorionValidNotificationId(Actions[I].Id) then
      raise EBorionError.Create('INVALID_ARGS', 'id de botão inválido: ' + Actions[I].Id);

  if not WinRT then
  begin
    { Windows 7: balão do tray, se houver }
    Tray := nil;
    if Ipc <> nil then
      Tray := Ipc.FindPlugin('tray');
    if Tray = nil then
      raise EBorionError.Create('UNSUPPORTED', 'notificações exigem o Windows 8+ ou o plugin tray');
    TBorionTrayPlugin(Tray).Notify(Title, Body);
    Exit;
  end;

  Registrar;
  Esquecer(Result);  { mesmo id: a nova substitui a anterior }
  Classe := THString.Create('Windows.Data.Xml.Dom.XmlDocument');
  try
    Checar(RoActivateInstance(Classe.Value, Inst), 'XmlDocument');
  finally
    Classe.Free;
  end;
  Checar(Inst.QueryInterface(IXmlDocumentIO, Io), 'IXmlDocumentIO');
  H := THString.Create(BorionToastXml(Result, Title, Body, Silent, Actions, FIconPath));
  try
    Checar(Io.LoadXml(H.Value), 'XML da notificação');
  finally
    H.Free;
  end;
  Checar(Inst.QueryInterface(IXmlDocument, Doc), 'IXmlDocument');
  Checar(Fabrica('Windows.UI.Notifications.ToastNotification', IToastNotificationFactory, Fab),
    'ToastNotification');
  T := TToast.Create;
  try
    Checar(Fab.CreateToastNotification(Doc, T.Toast), 'CreateToastNotification');
    T.Ouvinte := TOuvinte.Create(FWindow, Result);
    T.Ouvinte._AddRef;
    T.Toast.add_Activated(T.Ouvinte, T.TokenAtivado);
    T.Toast.add_Dismissed(T.Ouvinte, T.TokenDispensado);
    T.Toast.add_Failed(T.Ouvinte, T.TokenFalha);
    Checar(Notificador(FAppId, N), 'CreateToastNotifierWithId');
    Checar(N.Show(T.Toast), 'Show');
  except
    T.Free;
    raise;
  end;
  FToasts.AddObject(Result, T);
end;

procedure TBorionNotificationPlugin.Hide(const Id: string);
var
  I: Integer;
  N: IToastNotifier;
begin
  I := FToasts.IndexOf(Id);
  if (I < 0) or not WinRT then
    Exit;
  if Succeeded(Notificador(FAppId, N)) then
    N.Hide(TToast(FToasts.Objects[I]).Toast);
end;

function TBorionNotificationPlugin.ActiveCount: Integer;
begin
  Result := FToasts.Count;
end;

procedure TBorionNotificationPlugin.Esquecer(const Id: string);
var
  I: Integer;
begin
  I := FToasts.IndexOf(Id);
  if I >= 0 then
  begin
    FToasts.Objects[I].Free;
    FToasts.Delete(I);
  end;
end;

procedure TBorionNotificationPlugin.WndProc(var Message: TMessage);
var
  E: PEvento;
begin
  if Message.Msg <> WM_BORION_NOTIFICATION then
  begin
    Message.Result := DefWindowProc(FWindow, Message.Msg, Message.WParam, Message.LParam);
    Exit;
  end;
  E := PEvento(Message.LParam);
  try
    case E.Tipo of
      teClique: Activated(E.Id, E.Argumentos);
      teDispensa: Dismissed(E.Id, E.Motivo);
      teFalha: NotificationFailed(E.Id, E.Motivo);
    end;
  finally
    Dispose(E);
  end;
end;

procedure TBorionNotificationPlugin.Activated(const Id: string; const Arguments: WideString);
var
  Acao: string;
  P: Integer;
begin
  { 'borion|<id>|<botão>' }
  Acao := Arguments;
  P := Pos('|', Acao);
  if P > 0 then
    Delete(Acao, 1, P);
  P := Pos('|', Acao);
  if P > 0 then
    Acao := Copy(Acao, P + 1, MaxInt)
  else
    Acao := '';
  Esquecer(Id);
  if Ipc <> nil then
  begin
    if Acao = '' then
      Ipc.EmitJson('notification:click', '{"id":' + JsonQuote(Id) + ',"action":null}')
    else
      Ipc.EmitJson('notification:click', '{"id":' + JsonQuote(Id) + ',"action":' + JsonQuote(Acao) + '}');
    if FFocusOnClick then
      BorionShowMainWindow(Ipc);
  end;
  if Assigned(FOnClick) then
    FOnClick(Self, Id, Acao);
end;

procedure TBorionNotificationPlugin.Dismissed(const Id: string; Reason: Integer);
const
  MOTIVOS: array[0..2] of string = ('user', 'hidden', 'timeout');
var
  Motivo: string;
begin
  if (Reason >= 0) and (Reason <= 2) then
    Motivo := MOTIVOS[Reason]
  else
    Motivo := 'user';
  { 'timeout': a notificação foi para a Central de Ações e ainda pode ser clicada }
  if Motivo <> 'timeout' then
    Esquecer(Id);
  if Ipc <> nil then
    Ipc.EmitJson('notification:dismissed', '{"id":' + JsonQuote(Id) + ',"reason":' + JsonQuote(Motivo) + '}');
end;

procedure TBorionNotificationPlugin.NotificationFailed(const Id: string; ErrorCode: Integer);
begin
  Esquecer(Id);
  if Ipc <> nil then
    Ipc.EmitJson('notification:failed', '{"id":' + JsonQuote(Id) + ',"error":' +
      JsonQuote(Format('$%.8x', [ErrorCode])) + '}');
end;

{ --- comandos --- }

function Texto(Call: TBorionCall; V: TJsonValue; const Nome: string): WideString;
begin
  if (V = nil) or (V.ValueType <> jvString) or not JsonLiteralToWide(V.AsString, Result) then
    raise EBorionError.Create('INVALID_ARGS',
      Nome + ' deve ser um literal JSON só com ASCII (o @borion/api/notification gera)');
end;

procedure TBorionNotificationPlugin.CmdSend(Call: TBorionCall);
var
  Titulo, Corpo: WideString;
  Acoes: TBorionNotificationActions;
  Lista: TJsonValue;
  O: TJsonObject;
  I: Integer;
begin
  Titulo := Texto(Call, Call.Arg('title'), 'title');
  Corpo := '';
  if Call.HasArg('body') and (Call.Arg('body').ValueType <> jvNull) then
    Corpo := Texto(Call, Call.Arg('body'), 'body');
  Lista := Call.Arg('actions');
  if (Lista <> nil) and (Lista.ValueType = jvArray) then
  begin
    if Lista.AsArray.Count > 5 then
      raise EBorionError.Create('INVALID_ARGS', 'no máximo 5 botões');
    SetLength(Acoes, Lista.AsArray.Count);
    for I := 0 to Lista.AsArray.Count - 1 do
    begin
      if Lista.AsArray[I].ValueType <> jvObject then
        raise EBorionError.Create('INVALID_ARGS', 'actions deve ser uma lista de {id, title}');
      O := Lista.AsArray[I].AsObject;
      if (O.Find('id') < 0) or (O.Find('title') < 0) then
        raise EBorionError.Create('INVALID_ARGS', 'botão sem id ou title');
      Acoes[I].Id := O['id'].AsString;
      Acoes[I].Title := Texto(Call, O['title'], 'title do botão');
    end;
  end;
  Call.Result.AsString := Send(Call.ArgStr('id'), Titulo, Corpo, Call.ArgBool('silent'), Acoes);
end;

procedure TBorionNotificationPlugin.CmdHide(Call: TBorionCall);
begin
  Hide(Call.ArgStr('id'));
end;

procedure TBorionNotificationPlugin.CmdPermission(Call: TBorionCall);
begin
  if PermissionGranted then
    Call.Result.AsString := 'granted'
  else
    Call.Result.AsString := 'denied';
end;

end.
