unit uPrincipal;

{ Janela do exemplo do Borion: só o browser e um painel de log.
  A interface é a página (web\); a lógica nativa são os comandos de uComandos.pas. }

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, ExtCtrls, Jsons, WebView2Browser, BorionIpc, BorionAssets;

type
  TfrmPrincipal = class(TForm)
    splBase: TSplitter;
    pnlBase: TPanel;
    grpEmitir: TGroupBox;
    lblMensagem: TLabel;
    edtMensagem: TEdit;
    btnEmitir: TButton;
    btnDevTools: TButton;
    memLog: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure btnEmitirClick(Sender: TObject);
    procedure btnDevToolsClick(Sender: TObject);
  private
    FBrowser: TWebView2Browser;
    FIpc: TBorionIpc;
    FAssets: TBorionAssets;
    procedure Log(const S: string);
    procedure WMMove(var Message: TWMMove); message WM_MOVE;
    procedure BrowserInitialized(Sender: TObject; ErrorCode: HResult);
    procedure IpcEvento(const Event: string; Payload: TJsonValue);
    procedure IpcLog(Sender: TObject; const Msg: string);
  end;

var
  frmPrincipal: TfrmPrincipal;

implementation

{$R *.dfm}

uses
  uComandos;

procedure TfrmPrincipal.FormCreate(Sender: TObject);
begin
  FBrowser := TWebView2Browser.Create(Self);
  FBrowser.Parent := Self;
  FBrowser.Align := alClient;
  FBrowser.OnInitialized := BrowserInitialized;

  { Borion IPC. Criado antes do CreateWebView para a ponte JS (window.borion)
    entrar já no primeiro documento. }
  FIpc := TBorionIpc.Create(Self, FBrowser);
  FIpc.OnLog := IpcLog;
  FIpc.Listen('*', IpcEvento);
  RegistrarComandos(FIpc);

  { A interface: o pacote BORION_ASSETS do exe (gerado por "borion pack web
    web.res"), servido em https://app.localhost/. Com --dev-url=<url>, carrega
    do servidor de desenvolvimento em vez do pacote. }
  FAssets := TBorionAssets.Create(Self, FBrowser);
  FIpc.AllowOrigin(BorionOriginOf(FAssets.StartUrl));  { só a interface do app usa o IPC }

  Log('Borion ' + BORION_VERSION + ' iniciando...');
  if FAssets.IsDev then
    Log('modo dev: ' + FAssets.DevUrl)
  else if FAssets.Pack = nil then
    Log('AVISO: ' + FAssets.PackError);
  try
    FBrowser.CreateWebView;
    FBrowser.Navigate(FAssets.StartUrl);
  except
    on E: Exception do
    begin
      Log('ERRO: ' + E.Message);
      MessageDlg(E.Message, mtError, [mbOK], 0);
    end;
  end;
end;

procedure TfrmPrincipal.Log(const S: string);
begin
  memLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + S);
end;

procedure TfrmPrincipal.WMMove(var Message: TWMMove);
begin
  inherited;
  if FBrowser <> nil then
    FBrowser.NotifyParentWindowPositionChanged;
end;

procedure TfrmPrincipal.BrowserInitialized(Sender: TObject; ErrorCode: HResult);
begin
  if Succeeded(ErrorCode) then
    Log('WebView2 pronto')
  else
    Log(Format('Falha ao criar o WebView2 (HRESULT $%.8x)', [ErrorCode]));
  btnEmitir.Enabled := Succeeded(ErrorCode);
  btnDevTools.Enabled := Succeeded(ErrorCode);
end;

{ borion.emit(...) da página }
procedure TfrmPrincipal.IpcEvento(const Event: string; Payload: TJsonValue);
begin
  Log('evento da página: ' + Event + ' ' + Payload.Stringify);
end;

{ diagnóstico do Borion: origem negada, mensagem inválida... }
procedure TfrmPrincipal.IpcLog(Sender: TObject; const Msg: string);
begin
  Log('Borion: ' + Msg);
end;

procedure TfrmPrincipal.btnEmitirClick(Sender: TObject);
var
  Payload: TJsonObject;
begin
  Payload := TJsonObject.Create;
  try
    Payload.Put('texto', edtMensagem.Text);
    Payload.Put('hora', FormatDateTime('hh:nn:ss', Now));
    FIpc.Emit('delphi:mensagem', Payload);
  finally
    Payload.Free;
  end;
  Log('Ipc.Emit delphi:mensagem');
end;

procedure TfrmPrincipal.btnDevToolsClick(Sender: TObject);
begin
  FBrowser.OpenDevTools;
end;

end.
