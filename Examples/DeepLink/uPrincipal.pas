unit uPrincipal;

{ Exemplo do plugin "deep-link": links borion-exemplo://... abrem este app. Com
  o app já aberto, o single-instance entrega o link a esta janela. }

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
  BorionSingleInstance, BorionDeepLink;

constructor TfrmPrincipal.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);  { sem .dfm: a janela inteira é o browser }
  Caption := 'Borion: deep-link';
  Width := 900;
  Height := 640;
  Position := poScreenCenter;

  FBrowser := TWebView2Browser.Create(Self);
  FBrowser.Parent := Self;
  FBrowser.Align := alClient;
  FBrowser.OnTitleChanged := BrowserTitleChanged;

  FIpc := TBorionIpc.Create(Self, FBrowser);
  FIpc.AddPlugin(TBorionSingleInstancePlugin.Create);  { antes: links com o app aberto }
  { registra o esquema em HKCU\Software\Classes ao iniciar }
  FIpc.AddPlugin(TBorionDeepLinkPlugin.Create(['borion-exemplo']));

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
