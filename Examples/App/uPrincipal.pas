unit uPrincipal;

{ Exemplo do plugin "app": a janela só monta o browser, o IPC, os assets e o
  plugin. A página (web\app.js) mostra os dados do executável e controla a
  janela: minimizar, esconder, mostrar e sair. O app:exit fecha a janela como o
  botão X, passando pelo OnCloseQuery abaixo. }

interface

uses
  Windows, Messages, SysUtils, Classes, Controls, Forms, Dialogs,
  WebView2Browser, BorionIpc, BorionAssets;

type
  TfrmPrincipal = class(TForm)
  private
    FBrowser: TWebView2Browser;
    FIpc: TBorionIpc;
    FAssets: TBorionAssets;
    procedure WMMove(var Message: TWMMove); message WM_MOVE;
    procedure BrowserTitleChanged(Sender: TObject; const Value: WideString);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  frmPrincipal: TfrmPrincipal;

implementation

uses
  BorionApp;

constructor TfrmPrincipal.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);  { sem .dfm: a janela inteira é o browser }
  Caption := 'Borion: app';
  OnCloseQuery := FormCloseQuery;
  Width := 900;
  Height := 640;
  Position := poScreenCenter;

  FBrowser := TWebView2Browser.Create(Self);
  FBrowser.Parent := Self;
  FBrowser.Align := alClient;
  FBrowser.OnTitleChanged := BrowserTitleChanged;

  FIpc := TBorionIpc.Create(Self, FBrowser);
  FIpc.AddPlugin(TBorionAppPlugin.Create);  { controla este form }

  FAssets := TBorionAssets.Create(Self, FBrowser);
  FIpc.AllowOrigin(BorionOriginOf(FAssets.StartUrl));
  try
    FBrowser.CreateWebView;
    FBrowser.Navigate(FAssets.StartUrl);
  except
    on E: Exception do
      MessageDlg(E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TfrmPrincipal.WMMove(var Message: TWMMove);
begin
  inherited;
  if FBrowser <> nil then
    FBrowser.NotifyParentWindowPositionChanged;
end;

procedure TfrmPrincipal.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  { vale para o X da janela e para o app.exit() da página (que posta um WM_CLOSE) }
  CanClose := Application.MessageBox('Fechar o exemplo?', 'Borion: app',
    MB_YESNO or MB_ICONQUESTION) = IDYES;
end;

procedure TfrmPrincipal.BrowserTitleChanged(Sender: TObject; const Value: WideString);
begin
  Caption := Value;
end;

end.
