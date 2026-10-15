unit uPrincipal;

{ Exemplo do plugin "http": a janela só monta o browser, o IPC, os assets e o
  plugin, com as URLs que a página pode acessar. As requisições ficam na página
  (web\app.js). }

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
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  frmPrincipal: TfrmPrincipal;

implementation

uses
  BorionHttp;

constructor TfrmPrincipal.Create(AOwner: TComponent);
var
  Http: TBorionHttpPlugin;
begin
  inherited CreateNew(AOwner);  { sem .dfm: a janela inteira é o browser }
  Caption := 'Borion: http';
  Width := 900;
  Height := 640;
  Position := poScreenCenter;

  FBrowser := TWebView2Browser.Create(Self);
  FBrowser.Parent := Self;
  FBrowser.Align := alClient;
  FBrowser.OnTitleChanged := BrowserTitleChanged;

  FIpc := TBorionIpc.Create(Self, FBrowser);
  Http := TBorionHttpPlugin(FIpc.AddPlugin(TBorionHttpPlugin.Create));
  { escopo: tudo negado por padrão; só estas URLs }
  Http.Allow('https://example.com/*');
  Http.Allow('https://api.github.com/*');
  Http.Allow('https://httpbin.org/*');

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

procedure TfrmPrincipal.BrowserTitleChanged(Sender: TObject; const Value: WideString);
begin
  Caption := Value;
end;

end.
