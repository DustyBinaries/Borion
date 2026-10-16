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
  métodos do builder vencem o app.json: .Size(800, 600) muda só o tamanho.

  O Run inicializa a aplicação, cria a janela, instala os plugins e comandos,
  chama o Setup, abre a página e só volta quando o app fecha (liberando o
  builder). Se um plugin encerrar o app antes (o single-instance numa segunda
  execução), o Run não cria janela nenhuma.
*)

interface

uses
  Windows, Messages, SysUtils, Classes, Controls, Forms, Dialogs,
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
    FAssets: TBorionAssets;
    FTitleFromPage: Boolean;
    FOnCloseQuery: TBorionCloseQueryProc;
    FOnClose: TBorionCloseProc;
    procedure WMMove(var Message: TWMMove); message WM_MOVE;
    procedure BrowserInitialized(Sender: TObject; ErrorCode: HResult);
    procedure BrowserTitleChanged(Sender: TObject; const Value: WideString);
    procedure FecharConsulta(Sender: TObject; var CanClose: Boolean);
    procedure Fechar(Sender: TObject; var Action: TCloseAction);
  public
    constructor Create(AOwner: TComponent); override;
    property Browser: TWebView2Browser read FBrowser;
    property Ipc: TBorionIpc read FIpc;
    property Assets: TBorionAssets read FAssets;
    { O escopo de arquivos do app (o mesmo dos plugins fs, dialog e shell) }
    function Scope: TBorionScope;
    { Tamanho, limites, borda e estado da janela; o caption é Config.Title ou,
      se vazio, DefaultTitle. Antes de mostrar a janela. }
    procedure ApplyConfig(const Config: TBorionWindowConfig; const DefaultTitle: string);
    { O caption acompanha o document.title da página (padrão: True) }
    property TitleFromPage: Boolean read FTitleFromPage write FTitleFromPage;
  end;

  TBorionBuilder = class
  private
    FTitle: string;
    FExplicitTitle: Boolean;
    FWindow: TBorionWindowConfig;
    FCsp: string;
    FTitleFromPage: Boolean;
    FUrl: string;
    FUserDataFolder: string;
    FScope: TBorionScope;
    FPlugins: TList;
    FCommands: TStringList;    { nome -> TBorionCommandProc (em Objects) }
    FCommandSets: TList;       { TBorionCommandsProc }
    FOrigins: TStringList;
    FSetup: TBorionSetupProc;
    FOnCloseQuery: TBorionCloseQueryProc;
    FOnClose: TBorionCloseProc;
    procedure Montar(W: TBorionWindow);
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
    { Depois de montar a janela e antes de abrir a página: acesso ao form, ao
      browser, ao IPC e aos plugins }
    function Setup(Proc: TBorionSetupProc): TBorionBuilder;
    function OnCloseQuery(Proc: TBorionCloseQueryProc): TBorionBuilder;
    function OnClose(Proc: TBorionCloseProc): TBorionBuilder;

    { Roda o app e libera o builder }
    procedure Run;

    property Title: string read FTitle;
    property TitleFromPage: Boolean read FTitleFromPage;
    { A janela como vai ser criada (app.json + métodos do builder) }
    property Window: TBorionWindowConfig read FWindow;
    property ContentSecurityPolicy: string read FCsp;
  end;

implementation

{ TBorionWindow }

constructor TBorionWindow.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);  { sem .dfm }
  FTitleFromPage := True;
  Position := poScreenCenter;
  FBrowser := TWebView2Browser.Create(Self);
  FBrowser.Parent := Self;
  FBrowser.Align := alClient;
  FBrowser.OnInitialized := BrowserInitialized;
  FBrowser.OnTitleChanged := BrowserTitleChanged;
  { o IPC antes do CreateWebView: a ponte JS entra já no primeiro documento }
  FIpc := TBorionIpc.Create(Self, FBrowser);
  OnCloseQuery := FecharConsulta;
  OnClose := Fechar;
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
  inherited;
end;

function TBorionBuilder.Config(AConfig: TBorionConfig): TBorionBuilder;
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
  Result := Self;
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

procedure TBorionBuilder.Montar(W: TBorionWindow);
var
  I: Integer;
begin
  W.ApplyConfig(FWindow, FTitle);
  W.TitleFromPage := FTitleFromPage;
  W.FOnCloseQuery := FOnCloseQuery;
  W.FOnClose := FOnClose;
  if FUserDataFolder <> '' then
    W.Browser.UserDataFolder := FUserDataFolder;

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

  { a interface: o pacote embutido no exe (ou o --dev-url), ou a URL do Url() }
  W.FAssets := TBorionAssets.Create(W, W.Browser);
  if FCsp <> '' then
    W.Assets.ContentSecurityPolicy := FCsp;
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
    Application.CreateForm(TBorionWindow, W);
    Montar(W);
    try
      W.Browser.CreateWebView;
      if FUrl <> '' then
        W.Browser.Navigate(FUrl)
      else
        W.Browser.Navigate(W.Assets.StartUrl);
    except
      on E: Exception do
        MessageDlg(E.Message, mtError, [mbOK], 0);
    end;
    Application.Run;
  finally
    Free;
  end;
end;

end.
