unit Borion;

(*
  Borion — Native Application Engine
  TBorionBuilder: monta e roda um app inteiro a partir do .dpr, sem escrever
  form (como o tauri::Builder). A janela é um TBorionWindow: o browser ocupando
  tudo, o IPC e os assets do frontend embutidos no exe (ou o --dev-url).

    program MeuApp;

    uses
      Borion, BorionIpc, BorionFs, BorionDialog;

    {$R *.res}
    {$R web.res}

    procedure Saudar(Call: TBorionCall);
    begin
      Call.Result.AsString := 'Olá, ' + Call.ArgStr('nome');
    end;

    begin
      TBorionBuilder.Create  // título, janela e CSP do app.json embutido
        .AllowDir('$APPDATA')
        .Plugin(TBorionFsPlugin.Create)
        .Plugin(TBorionDialogPlugin.Create)
        .Command('saudar', Saudar)
        .Run;
    end.

  A configuração vem do app.json (BorionConfig), que o "borion build" embute
  no exe; sem ele, os padrões (1000x700, redimensionável, centralizada). Os
  métodos do builder vencem o app.json: .Size(800, 600) muda só o tamanho
  (da janela principal).

  Várias janelas: as de app.windows com "create" (o padrão) abrem junto com a
  principal; as outras, com BorionWindows.Open('rotulo') ou pelo JS. Todas
  usam o mesmo IPC: os plugins e comandos são registrados uma vez e servem
  todas as janelas. Fechar a principal fecha o app (e as outras); fechar uma
  secundária só libera ela.

  O Run inicializa a aplicação, cria a janela, instala os plugins e comandos,
  chama o Setup, abre a página e só volta quando o app fecha (liberando o
  builder). Se um plugin encerrar o app antes (o single-instance numa segunda
  execução), o Run não cria janela nenhuma.
*)

interface

uses
  Windows, Messages, ShellAPI, SysUtils, Classes, Controls, Forms, Dialogs,
  XPMan,  { visual do Windows nos diálogos e controles nativos }
  WebView2Browser, BorionIpc, BorionAssets, BorionScope, BorionConfig;

type
  TBorionWindow = class;

  { Ganchos em procedures comuns (no .dpr não há métodos de form) }
  TBorionSetupProc = procedure(Window: TBorionWindow);
  TBorionCloseQueryProc = procedure(Window: TBorionWindow; var CanClose: Boolean);
  TBorionCloseProc = procedure(Window: TBorionWindow);
  TBorionCommandsProc = procedure(Ipc: TBorionIpc);

  { A janela de um app Borion: um form só com o browser }
  TBorionWindow = class(TForm)
  private
    FBrowser: TWebView2Browser;
    FIpc: TBorionIpc;
    FWindowLabel: string;
    FAssets: TBorionAssets;
    FTitleFromPage: Boolean;
    FResizable: Boolean;
    FNormalBounds: TRect;
    FFullscreen: Boolean;
    FStartFullscreen: Boolean;
    FNavigation: TStringList;
    FOnCloseQuery: TBorionCloseQueryProc;
    FOnClose: TBorionCloseProc;
    procedure WMMove(var Message: TWMMove); message WM_MOVE;
    procedure WMSize(var Message: TWMSize); message WM_SIZE;
    procedure GuardarNormal;
    procedure Ligar(AIpc: TBorionIpc);
    procedure BrowserInitialized(Sender: TObject; ErrorCode: HResult);
    procedure BrowserTitleChanged(Sender: TObject; const Value: WideString);
    procedure FecharConsulta(Sender: TObject; var CanClose: Boolean);
    procedure Fechar(Sender: TObject; var Action: TCloseAction);
    procedure Preparar;
    function NavigationAllowed(const Uri: WideString): Boolean;
    procedure BrowserNavigating(Sender: TObject; const Uri: WideString;
      IsUserInitiated, IsRedirected: Boolean; var Cancel: Boolean);
    procedure BrowserNewWindow(Sender: TObject; const Uri: WideString;
      IsUserInitiated: Boolean; var Action: TWV2NewWindowAction);
    procedure BrowserKey(Sender: TObject; KeyEventKind, VirtualKey: Integer; var Handled: Boolean);
  public
    { A janela 'main', com um IPC próprio (o do app) }
    constructor Create(AOwner: TComponent); override;
    { Mais uma janela no IPC de outra (o do app), com esse rótulo. AIpc nil:
      entra no IPC depois (o TBorionWindows, já com a configuração aplicada). }
    constructor CreateWindow(AOwner: TComponent; AIpc: TBorionIpc; const AWindowLabel: string);
    destructor Destroy; override;
    property Browser: TWebView2Browser read FBrowser;
    { O IPC do app (o mesmo em todas as janelas) }
    property Ipc: TBorionIpc read FIpc;
    { 'main' na principal }
    property WindowLabel: string read FWindowLabel;
    { A janela principal: fechá-la fecha o app }
    function IsMain: Boolean;
    property Assets: TBorionAssets read FAssets;
    { Mais uma origem para onde esta janela pode navegar, além do app e das origens
      do IPC. Qualquer outra navegação é cancelada e, se foi um clique, abre no
      navegador do sistema (http, https e mailto); janelas novas (target="_blank",
      window.open) nunca abrem, só vão para o navegador. "*" libera tudo. }
    procedure AllowNavigation(const Origin: string);
    { O escopo de arquivos do app (o mesmo dos plugins fs, dialog e shell) }
    function Scope: TBorionScope;
    { Tamanho, limites, borda e estado da janela; o caption é Config.Title ou,
      se vazio, DefaultTitle. Antes de mostrar a janela. }
    procedure ApplyConfig(const Config: TBorionWindowConfig; const DefaultTitle: string);
    { O caption acompanha o document.title da página (padrão: True) }
    property TitleFromPage: Boolean read FTitleFromPage write FTitleFromPage;
    { Redimensionável pelo usuário. Sem decorations, pela borda da página
      (plugin window); com elas, pela borda da janela. }
    property Resizable: Boolean read FResizable write FResizable;
    { Tamanho e posição no estado normal: os atuais ou, maximizada ou
      minimizada, os de antes (o plugin window-state grava estes). Vazio até a
      janela ter um handle. }
    property NormalBounds: TRect read FNormalBounds write FNormalBounds;
    { Em tela cheia (o plugin window marca): o NormalBounds fica o de antes dela }
    property Fullscreen: Boolean read FFullscreen write FFullscreen;
    { O app.json pediu tela cheia: o plugin window entra nela quando acompanha a janela }
    property StartFullscreen: Boolean read FStartFullscreen;
  end;

  { As janelas do app (o global BorionWindows, criado pelo TBorionBuilder.Run) }
  TBorionWindows = class
  private
    FMain: TBorionWindow;
    FList: TList;
    FDefs: array of TBorionWindowConfig;
    FTitle: string;
    FCsp: string;
    FUrl: string;
    FUserDataFolder: string;
    FNavigation: TStringList;
    FOnCloseQuery: TBorionCloseQueryProc;
    FOnClose: TBorionCloseProc;
    function GetItem(Index: Integer): TBorionWindow;
    procedure Preparar(W: TBorionWindow; const Config: TBorionWindowConfig);
    procedure Abrir(W: TBorionWindow; const Config: TBorionWindowConfig);
    procedure Saiu(W: TBorionWindow);
  public
    constructor Create;
    destructor Destroy; override;
    function Count: Integer;
    property Items[Index: Integer]: TBorionWindow read GetItem; default;
    property Main: TBorionWindow read FMain;
    { nil se não estiver aberta }
    function Find(const WindowLabel: string): TBorionWindow;
    { A definição do app.json; False se não houver }
    function Definition(const WindowLabel: string; out Config: TBorionWindowConfig): Boolean;
    { Abre a janela do app.json com esse rótulo; se já estiver aberta, mostra e
      traz para frente. EBorionError WINDOW_NOT_FOUND se não houver a definição. }
    function Open(const WindowLabel: string): TBorionWindow;
    { Abre uma janela nova (Config.WindowLabel não pode estar aberto) }
    function CreateWindow(const Config: TBorionWindowConfig): TBorionWindow;
  end;

  TBorionBuilder = class
  private
    FTitle: string;
    FExplicitTitle: Boolean;
    FWindow: TBorionWindowConfig;
    FDefs: array of TBorionWindowConfig;
    FCsp: string;
    FTitleFromPage: Boolean;
    FUrl: string;
    FUserDataFolder: string;
    FScope: TBorionScope;
    FPlugins: TList;
    FCommands: TStringList;    { nome -> TBorionCommandProc (em Objects) }
    FCommandSets: TList;       { TBorionCommandsProc }
    FOrigins: TStringList;
    FNavigation: TStringList;
    FSetup: TBorionSetupProc;
    FOnCloseQuery: TBorionCloseQueryProc;
    FOnClose: TBorionCloseProc;
    procedure Montar(W: TBorionWindow; Janelas: TBorionWindows);
  public
    { Title: título do app e da janela (Application.Title, já definido aqui para
      os plugins que o usam como nome). '' = o productName do app.json (ou o
      nome do exe). Aplica o app.json embutido (BorionAppConfig). }
    constructor Create(const Title: string = '');
    destructor Destroy; override;

    { Aplica uma configuração no lugar da embutida (título, janela, CSP). Chame
      antes dos outros métodos: ela substitui o que eles definiram. Com
      app.windows[0].title, o caption fica fixo (como o FixedTitle). }
    function Config(AConfig: TBorionConfig): TBorionBuilder;

    { --- janela --- }
    function Size(Width, Height: Integer): TBorionBuilder;
    function MinSize(Width, Height: Integer): TBorionBuilder;
    function MaxSize(Width, Height: Integer): TBorionBuilder;
    function Maximized: TBorionBuilder;
    function Resizable(Value: Boolean = True): TBorionBuilder;
    function Centered(Value: Boolean = True): TBorionBuilder;
    { False: sem borda nem barra de título (feche pelo plugin app) }
    function Decorations(Value: Boolean = True): TBorionBuilder;
    function AlwaysOnTop(Value: Boolean = True): TBorionBuilder;
    { O caption fica sempre o Title, sem acompanhar o document.title }
    function FixedTitle: TBorionBuilder;

    { --- conteúdo --- }
    { Abre esta URL em vez do frontend embutido (pacote BORION_ASSETS) }
    function Url(const AUrl: string): TBorionBuilder;
    { Mais uma origem que pode usar o IPC (a do frontend já é liberada) }
    function AllowOrigin(const Origin: string): TBorionBuilder;
    { Mais uma origem para onde as janelas podem navegar (sem IPC); o resto
      abre no navegador do sistema. Soma-se ao app.security.allowNavigation. }
    function AllowNavigation(const Origin: string): TBorionBuilder;
    { Header Content-Security-Policy dos assets embutidos ('' = nenhum) }
    function Csp(const Policy: string): TBorionBuilder;
    { Pasta de dados do WebView2 (padrão: <exe>.WebView2 ao lado do exe) }
    function UserDataFolder(const Dir: string): TBorionBuilder;

    { --- escopo de arquivos do app (plugins fs, dialog e shell) --- }
    function AllowDir(const Dir: string; Recursive: Boolean = True): TBorionBuilder;
    function AllowFile(const FileName: string): TBorionBuilder;

    { --- plugins e comandos --- }
    function Plugin(APlugin: TBorionPlugin): TBorionBuilder;
    function Command(const Name: string; Handler: TBorionCommandProc): TBorionBuilder;
    { Uma procedure que registra vários comandos: procedure Registrar(Ipc: TBorionIpc) }
    function Commands(Register: TBorionCommandsProc): TBorionBuilder;

    { --- ganchos --- }
    { Depois de montar a janela principal e antes de abrir a página: acesso ao
      form, ao browser, ao IPC e aos plugins }
    function Setup(Proc: TBorionSetupProc): TBorionBuilder;
    { Valem para todas as janelas (veja Window.WindowLabel / Window.IsMain) }
    function OnCloseQuery(Proc: TBorionCloseQueryProc): TBorionBuilder;
    function OnClose(Proc: TBorionCloseProc): TBorionBuilder;

    { Roda o app e libera o builder }
    procedure Run;

    property Title: string read FTitle;
    property TitleFromPage: Boolean read FTitleFromPage;
    { A janela principal como vai ser criada (app.json + métodos do builder) }
    property Window: TBorionWindowConfig read FWindow;
    { Todas as janelas do app.json (a 0 é a principal, com os métodos do builder) }
    function WindowCount: Integer;
    function WindowConfig(Index: Integer): TBorionWindowConfig;
    property ContentSecurityPolicy: string read FCsp;
  end;

var
  { As janelas do app, durante o TBorionBuilder.Run (nil fora dele) }
  BorionWindows: TBorionWindows;

implementation

{ caminho do app ('/config.html') sobre a raiz da interface }
function UrlDaJanela(const Base, Caminho: string): string;
begin
  Result := Base;
  while (Result <> '') and (Result[Length(Result)] = '/') do
    SetLength(Result, Length(Result) - 1);
  Result := Result + Caminho;
end;

{ TBorionWindow }

constructor TBorionWindow.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);  { sem .dfm }
  FWindowLabel := 'main';
  Preparar;
  { o IPC antes do CreateWebView: a ponte JS entra já no primeiro documento }
  FIpc := TBorionIpc.Create(Self, FBrowser);
end;

constructor TBorionWindow.CreateWindow(AOwner: TComponent; AIpc: TBorionIpc; const AWindowLabel: string);
begin
  inherited CreateNew(AOwner);
  FWindowLabel := AWindowLabel;
  Preparar;
  if AIpc <> nil then
    Ligar(AIpc);
end;

procedure TBorionWindow.Ligar(AIpc: TBorionIpc);
begin
  AIpc.AddWindow(FWindowLabel, FBrowser);
  FIpc := AIpc;
end;

destructor TBorionWindow.Destroy;
begin
  if BorionWindows <> nil then
    BorionWindows.Saiu(Self);
  if (FIpc <> nil) and (FIpc.Owner <> Self) then
  begin
    FIpc.RemoveWindow(FWindowLabel);
    FIpc.EmitJson('window:destroyed', '{"label":' + '"' + FWindowLabel + '"}');
  end;
  inherited;
  FNavigation.Free;
end;

{ http, https e mailto vão para o navegador do sistema; nada mais é executado }
procedure AbrirNoNavegador(const Uri: WideString);
var
  S, L: string;
begin
  S := Uri;
  L := LowerCase(S);
  if (Pos('http://', L) = 1) or (Pos('https://', L) = 1) or (Pos('mailto:', L) = 1) then
    ShellExecute(0, 'open', PChar(S), nil, nil, SW_SHOWNORMAL);
end;

procedure TBorionWindow.AllowNavigation(const Origin: string);
var
  S: string;
begin
  S := LowerCase(Trim(Origin));
  while (S <> '') and (S[Length(S)] = '/') do
    Delete(S, Length(S), 1);
  if (S <> '') and (FNavigation.IndexOf(S) < 0) then
    FNavigation.Add(S);
end;

{ o app, as origens do IPC (AllowOrigin) e as do AllowNavigation }
function TBorionWindow.NavigationAllowed(const Uri: WideString): Boolean;
var
  Origin: string;
begin
  Origin := LowerCase(BorionOriginOf(Uri));
  Result := (Origin = 'about:blank') or (FNavigation.IndexOf('*') >= 0) or
    (FNavigation.IndexOf(Origin) >= 0) or ((FIpc <> nil) and FIpc.IsOriginAllowed(Uri));
end;

{ para fora do app: cancela e, se foi um clique, abre no navegador do sistema }
procedure TBorionWindow.BrowserNavigating(Sender: TObject; const Uri: WideString;
  IsUserInitiated, IsRedirected: Boolean; var Cancel: Boolean);
begin
  if NavigationAllowed(Uri) then
    Exit;
  Cancel := True;
  if IsUserInitiated and not IsRedirected then
    AbrirNoNavegador(Uri);
end;

{ janela nova nunca abre: o que é de fora vai para o navegador do sistema }
procedure TBorionWindow.BrowserNewWindow(Sender: TObject; const Uri: WideString;
  IsUserInitiated: Boolean; var Action: TWV2NewWindowAction);
begin
  Action := nwaCancel;
  if IsUserInitiated and not NavigationAllowed(Uri) then
    AbrirNoNavegador(Uri);
end;

{ browserKeys: false. Recarregar, ver fonte e zoom (a página não recebe a tecla) }
procedure TBorionWindow.BrowserKey(Sender: TObject; KeyEventKind, VirtualKey: Integer;
  var Handled: Boolean);
var
  Ctrl: Boolean;
begin
  Ctrl := GetKeyState(VK_CONTROL) < 0;
  case VirtualKey of
    VK_F5:
      Handled := True;
    Ord('R'), Ord('U'), Ord('0'), VK_NUMPAD0, VK_ADD, VK_SUBTRACT, 187, 189:
      if Ctrl then
        Handled := True;
  end;
end;

procedure TBorionWindow.Preparar;
begin
  FTitleFromPage := True;
  FResizable := True;
  Position := poScreenCenter;
  FBrowser := TWebView2Browser.Create(Self);
  FBrowser.Parent := Self;
  FBrowser.Align := alClient;
  FBrowser.OnInitialized := BrowserInitialized;
  FBrowser.OnTitleChanged := BrowserTitleChanged;
  FNavigation := TStringList.Create;
  FBrowser.OnNavigationStarting := BrowserNavigating;
  FBrowser.OnNewWindowRequested := BrowserNewWindow;
  OnCloseQuery := FecharConsulta;
  OnClose := Fechar;
end;

function TBorionWindow.IsMain: Boolean;
begin
  Result := (FIpc <> nil) and (FIpc.Owner = Self);
end;

function TBorionWindow.Scope: TBorionScope;
begin
  Result := BorionAppScope(FIpc);
end;

procedure TBorionWindow.ApplyConfig(const Config: TBorionWindowConfig; const DefaultTitle: string);
begin
  if Config.Title <> '' then
    Caption := Config.Title
  else
    Caption := DefaultTitle;
  Width := Config.Width;
  Height := Config.Height;
  Constraints.MinWidth := Config.MinWidth;
  Constraints.MinHeight := Config.MinHeight;
  Constraints.MaxWidth := Config.MaxWidth;
  Constraints.MaxHeight := Config.MaxHeight;
  FResizable := Config.Resizable;
  FStartFullscreen := Config.Fullscreen;
  FBrowser.DevToolsEnabled := Config.DevTools;
  FBrowser.ContextMenusEnabled := Config.ContextMenu;
  FBrowser.ZoomControlEnabled := Config.BrowserKeys;
  if not Config.BrowserKeys then
    FBrowser.OnAcceleratorKeyPressed := BrowserKey;
  if Config.Center then
    Position := poScreenCenter
  else
    Position := poDefaultPosOnly;
  if not Config.Decorations then
    BorderStyle := bsNone
  else if not Config.Resizable then
  begin
    BorderStyle := bsSingle;
    BorderIcons := BorderIcons - [biMaximize];
  end
  else
  begin
    BorderStyle := bsSizeable;
    BorderIcons := BorderIcons + [biMaximize];
  end;
  if Config.AlwaysOnTop then
    FormStyle := fsStayOnTop
  else
    FormStyle := fsNormal;
  if Config.Maximized then
    WindowState := wsMaximized
  else
    WindowState := wsNormal;
end;

procedure TBorionWindow.WMMove(var Message: TWMMove);
begin
  inherited;
  if FBrowser <> nil then
    FBrowser.NotifyParentWindowPositionChanged;
  GuardarNormal;
end;

procedure TBorionWindow.WMSize(var Message: TWMSize);
begin
  inherited;
  GuardarNormal;
end;

{ o NormalBounds acompanha a janela só no estado normal }
procedure TBorionWindow.GuardarNormal;
begin
  if HandleAllocated and not FFullscreen and not IsIconic(Handle) and not IsZoomed(Handle) then
    FNormalBounds := BoundsRect;
end;

procedure TBorionWindow.BrowserInitialized(Sender: TObject; ErrorCode: HResult);
begin
  if Failed(ErrorCode) then
    MessageDlg(Format('Falha ao criar o WebView2 (HRESULT $%.8x). O Runtime do WebView2 ' +
      'está instalado?', [ErrorCode]), mtError, [mbOK], 0);
end;

procedure TBorionWindow.BrowserTitleChanged(Sender: TObject; const Value: WideString);
begin
  if not FTitleFromPage or (Value = '') then
    Exit;
  Caption := Value;
  if (FAssets <> nil) and (FAssets.DevUrl <> '') then
    Caption := Caption + '  [dev: ' + FAssets.DevUrl + ']'  { para não confundir com o build }
  else if (FAssets <> nil) and (FAssets.DevDir <> '') then
    Caption := Caption + '  [dev: ' + FAssets.DevDir + ']';
end;

procedure TBorionWindow.FecharConsulta(Sender: TObject; var CanClose: Boolean);
begin
  if Assigned(FOnCloseQuery) then
    FOnCloseQuery(Self, CanClose);
end;

procedure TBorionWindow.Fechar(Sender: TObject; var Action: TCloseAction);
begin
  { a principal fecha o app (é o MainForm); as outras são liberadas }
  if not IsMain then
    Action := caFree;
  if Assigned(FOnClose) then
    FOnClose(Self);
end;

{ TBorionBuilder }

constructor TBorionBuilder.Create(const Title: string);
begin
  inherited Create;
  FTitle := Title;
  FExplicitTitle := Title <> '';
  FTitleFromPage := True;
  FPlugins := TList.Create;
  FCommands := TStringList.Create;
  FCommandSets := TList.Create;
  FOrigins := TStringList.Create;
  FNavigation := TStringList.Create;
  Config(BorionAppConfig);
end;

destructor TBorionBuilder.Destroy;
var
  I: Integer;
begin
  { o que não foi para o Ipc (o Run não chegou a montar a janela) }
  for I := 0 to FPlugins.Count - 1 do
    TBorionPlugin(FPlugins[I]).Free;
  FPlugins.Free;
  FScope.Free;
  FCommands.Free;
  FCommandSets.Free;
  FOrigins.Free;
  FNavigation.Free;
  inherited;
end;

function TBorionBuilder.Config(AConfig: TBorionConfig): TBorionBuilder;
var
  I: Integer;
begin
  if not FExplicitTitle then
  begin
    FTitle := AConfig.ProductName;
    if FTitle = '' then
      FTitle := ChangeFileExt(ExtractFileName(ParamStr(0)), '');
  end;
  Application.Title := FTitle;  { antes dos plugins: vários o usam como nome }
  FWindow := AConfig.Window;
  { um title explícito na janela fica; sem ele, o caption segue o document.title }
  FTitleFromPage := FWindow.Title = '';
  FCsp := AConfig.Csp;
  FNavigation.Assign(AConfig.AllowNavigation);
  SetLength(FDefs, AConfig.WindowCount);
  for I := 0 to AConfig.WindowCount - 1 do
    FDefs[I] := AConfig.Windows[I];
  Result := Self;
end;

function TBorionBuilder.WindowCount: Integer;
begin
  Result := Length(FDefs);
end;

function TBorionBuilder.WindowConfig(Index: Integer): TBorionWindowConfig;
begin
  if Index = 0 then
    Result := FWindow
  else
    Result := FDefs[Index];
end;

function TBorionBuilder.Size(Width, Height: Integer): TBorionBuilder;
begin
  FWindow.Width := Width;
  FWindow.Height := Height;
  Result := Self;
end;

function TBorionBuilder.MinSize(Width, Height: Integer): TBorionBuilder;
begin
  FWindow.MinWidth := Width;
  FWindow.MinHeight := Height;
  Result := Self;
end;

function TBorionBuilder.MaxSize(Width, Height: Integer): TBorionBuilder;
begin
  FWindow.MaxWidth := Width;
  FWindow.MaxHeight := Height;
  Result := Self;
end;

function TBorionBuilder.Maximized: TBorionBuilder;
begin
  FWindow.Maximized := True;
  Result := Self;
end;

function TBorionBuilder.Resizable(Value: Boolean): TBorionBuilder;
begin
  FWindow.Resizable := Value;
  Result := Self;
end;

function TBorionBuilder.Centered(Value: Boolean): TBorionBuilder;
begin
  FWindow.Center := Value;
  Result := Self;
end;

function TBorionBuilder.Decorations(Value: Boolean): TBorionBuilder;
begin
  FWindow.Decorations := Value;
  Result := Self;
end;

function TBorionBuilder.AlwaysOnTop(Value: Boolean): TBorionBuilder;
begin
  FWindow.AlwaysOnTop := Value;
  Result := Self;
end;

function TBorionBuilder.Csp(const Policy: string): TBorionBuilder;
begin
  FCsp := Policy;
  Result := Self;
end;

function TBorionBuilder.FixedTitle: TBorionBuilder;
begin
  FTitleFromPage := False;
  Result := Self;
end;

function TBorionBuilder.Url(const AUrl: string): TBorionBuilder;
begin
  FUrl := AUrl;
  Result := Self;
end;

function TBorionBuilder.AllowOrigin(const Origin: string): TBorionBuilder;
begin
  FOrigins.Add(Origin);
  Result := Self;
end;

function TBorionBuilder.AllowNavigation(const Origin: string): TBorionBuilder;
begin
  FNavigation.Add(Origin);
  Result := Self;
end;

function TBorionBuilder.UserDataFolder(const Dir: string): TBorionBuilder;
begin
  FUserDataFolder := Dir;
  Result := Self;
end;

function TBorionBuilder.AllowDir(const Dir: string; Recursive: Boolean): TBorionBuilder;
begin
  if FScope = nil then
    FScope := TBorionScope.Create(FTitle);
  FScope.AllowDir(Dir, Recursive);
  Result := Self;
end;

function TBorionBuilder.AllowFile(const FileName: string): TBorionBuilder;
begin
  if FScope = nil then
    FScope := TBorionScope.Create(FTitle);
  FScope.AllowFile(FileName);
  Result := Self;
end;

function TBorionBuilder.Plugin(APlugin: TBorionPlugin): TBorionBuilder;
begin
  FPlugins.Add(APlugin);
  Result := Self;
end;

function TBorionBuilder.Command(const Name: string; Handler: TBorionCommandProc): TBorionBuilder;
begin
  FCommands.AddObject(Name, TObject(Pointer(@Handler)));
  Result := Self;
end;

function TBorionBuilder.Commands(Register: TBorionCommandsProc): TBorionBuilder;
begin
  FCommandSets.Add(@Register);
  Result := Self;
end;

function TBorionBuilder.Setup(Proc: TBorionSetupProc): TBorionBuilder;
begin
  FSetup := Proc;
  Result := Self;
end;

function TBorionBuilder.OnCloseQuery(Proc: TBorionCloseQueryProc): TBorionBuilder;
begin
  FOnCloseQuery := Proc;
  Result := Self;
end;

function TBorionBuilder.OnClose(Proc: TBorionCloseProc): TBorionBuilder;
begin
  FOnClose := Proc;
  Result := Self;
end;

procedure TBorionBuilder.Montar(W: TBorionWindow; Janelas: TBorionWindows);
var
  I: Integer;
begin
  Janelas.FMain := W;
  Janelas.FList.Add(W);
  Janelas.FTitle := FTitle;
  Janelas.FCsp := FCsp;
  Janelas.FUrl := FUrl;
  Janelas.FUserDataFolder := FUserDataFolder;
  Janelas.FNavigation.Assign(FNavigation);
  Janelas.FOnCloseQuery := FOnCloseQuery;
  Janelas.FOnClose := FOnClose;
  SetLength(Janelas.FDefs, Length(FDefs));
  for I := 0 to High(FDefs) do
    Janelas.FDefs[I] := FDefs[I];
  Janelas.FDefs[0] := FWindow;
  Janelas.Preparar(W, FWindow);
  W.TitleFromPage := FTitleFromPage;

  { o escopo passa a ser do Ipc antes dos plugins, que o procuram no Install }
  if FScope <> nil then
  begin
    W.Ipc.Scope := FScope;
    FScope := nil;
  end;
  for I := 0 to FPlugins.Count - 1 do
    W.Ipc.AddPlugin(TBorionPlugin(FPlugins[I]));
  FPlugins.Clear;
  for I := 0 to FCommands.Count - 1 do
    W.Ipc.RegisterCommandProc(FCommands[I], TBorionCommandProc(Pointer(FCommands.Objects[I])));
  for I := 0 to FCommandSets.Count - 1 do
    TBorionCommandsProc(FCommandSets[I])(W.Ipc);

  for I := 0 to FOrigins.Count - 1 do
    W.Ipc.AllowOrigin(FOrigins[I]);
  if FUrl <> '' then
    W.Ipc.AllowOrigin(BorionOriginOf(FUrl))
  else
  begin
    W.Ipc.AllowOrigin(BorionOriginOf(W.Assets.StartUrl));
    if not W.Assets.IsDev and (W.Assets.Pack = nil) then
      MessageDlg('Interface não encontrada no executável: ' + W.Assets.PackError + #13#10 +
        'Empacote o frontend com "borion pack" e inclua o .res no projeto.', mtWarning, [mbOK], 0);
  end;

  if Assigned(FSetup) then
    FSetup(W);
end;

procedure TBorionBuilder.Run;
var
  W: TBorionWindow;
  I: Integer;
begin
  try
    Application.Initialize;
    Application.Title := FTitle;
    { um plugin já encerrou o app (o single-instance numa segunda execução) }
    if Application.Terminated then
      Exit;
    if BorionAppConfigError <> '' then
      MessageDlg('Configuração do app (app.json) inválida; usando os padrões.'#13#10 +
        BorionAppConfigError, mtWarning, [mbOK], 0);
    BorionWindows := TBorionWindows.Create;
    try
      Application.CreateForm(TBorionWindow, W);
      Montar(W, BorionWindows);
      if not FWindow.Visible then
        Application.ShowMainForm := False;
      BorionWindows.Abrir(W, FWindow);
      { as outras janelas do app.json, menos as com "create": false }
      for I := 1 to High(FDefs) do
        if FDefs[I].CreateAtStart then
          try
            BorionWindows.CreateWindow(FDefs[I]);
          except
            on E: Exception do
              MessageDlg('Janela "' + FDefs[I].WindowLabel + '": ' + E.Message, mtError, [mbOK], 0);
          end;
      Application.Run;
    finally
      FreeAndNil(BorionWindows);
    end;
  finally
    Free;
  end;
end;

{ TBorionWindows }

constructor TBorionWindows.Create;
begin
  inherited Create;
  FList := TList.Create;
  FNavigation := TStringList.Create;
end;

destructor TBorionWindows.Destroy;
begin
  FNavigation.Free;
  FList.Free;
  inherited;
end;

function TBorionWindows.Count: Integer;
begin
  Result := FList.Count;
end;

function TBorionWindows.GetItem(Index: Integer): TBorionWindow;
begin
  Result := TBorionWindow(FList[Index]);
end;

function TBorionWindows.Find(const WindowLabel: string): TBorionWindow;
var
  I: Integer;
begin
  for I := 0 to FList.Count - 1 do
  begin
    Result := TBorionWindow(FList[I]);
    if Result.WindowLabel = WindowLabel then
      Exit;
  end;
  Result := nil;
end;

function TBorionWindows.Definition(const WindowLabel: string; out Config: TBorionWindowConfig): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FDefs) do
    if FDefs[I].WindowLabel = WindowLabel then
    begin
      Config := FDefs[I];
      Result := True;
      Exit;
    end;
  Result := False;
end;

procedure TBorionWindows.Saiu(W: TBorionWindow);
begin
  FList.Remove(W);
  if W = FMain then
    FMain := nil;
end;

{ tudo o que a janela precisa antes de criar o WebView }
procedure TBorionWindows.Preparar(W: TBorionWindow; const Config: TBorionWindowConfig);
var
  I: Integer;
begin
  W.ApplyConfig(Config, FTitle);
  { um title explícito fica; sem ele, o caption segue o document.title }
  W.TitleFromPage := Config.Title = '';
  W.FOnCloseQuery := FOnCloseQuery;
  W.FOnClose := FOnClose;
  for I := 0 to FNavigation.Count - 1 do
    W.AllowNavigation(FNavigation[I]);
  if FUserDataFolder <> '' then
    W.Browser.UserDataFolder := FUserDataFolder;
  { a interface: o pacote embutido no exe (ou o --dev-url), ou a URL do Url() }
  W.FAssets := TBorionAssets.Create(W, W.Browser);
  if FCsp <> '' then
    W.Assets.ContentSecurityPolicy := FCsp;
end;

{ cria o WebView e abre a página da janela }
procedure TBorionWindows.Abrir(W: TBorionWindow; const Config: TBorionWindowConfig);
var
  Base: string;
begin
  try
    W.Browser.CreateWebView;
    if FUrl <> '' then
    begin
      if W = FMain then
        Base := ''
      else
        Base := BorionOriginOf(FUrl);
      if Base = '' then
        W.Browser.Navigate(FUrl)
      else
        W.Browser.Navigate(UrlDaJanela(Base, Config.Url));
    end
    else
      W.Browser.Navigate(UrlDaJanela(W.Assets.StartUrl, Config.Url));
  except
    on E: Exception do
      MessageDlg(E.Message, mtError, [mbOK], 0);
  end;
end;

function TBorionWindows.CreateWindow(const Config: TBorionWindowConfig): TBorionWindow;
begin
  if FMain = nil then
    raise EBorionError.Create('NO_WINDOW', 'o app não tem janela principal');
  if Find(Config.WindowLabel) <> nil then
    raise EBorionError.Create('WINDOW_EXISTS', 'a janela "' + Config.WindowLabel + '" já está aberta');
  Result := TBorionWindow.CreateWindow(Application, nil, Config.WindowLabel);
  try
    FList.Add(Result);
    Preparar(Result, Config);
    { no IPC só agora: os plugins já recebem a janela configurada (o
      window-state restaura o tamanho dela antes de aparecer) }
    Result.Ligar(FMain.Ipc);
  except
    Result.Free;
    raise;
  end;
  Abrir(Result, Config);
  if Config.Visible then
    Result.Show;
  FMain.Ipc.EmitJson('window:created', '{"label":"' + Config.WindowLabel + '"}');
end;

function TBorionWindows.Open(const WindowLabel: string): TBorionWindow;
var
  C: TBorionWindowConfig;
begin
  Result := Find(WindowLabel);
  if Result <> nil then
  begin
    Result.Show;
    if Result.WindowState = wsMinimized then
      Result.WindowState := wsNormal;
    SetForegroundWindow(Result.Handle);
    Exit;
  end;
  if not Definition(WindowLabel, C) then
    raise EBorionError.Create('WINDOW_NOT_FOUND', 'nenhuma janela "' + WindowLabel + '" no app.json');
  Result := CreateWindow(C);
end;

end.
