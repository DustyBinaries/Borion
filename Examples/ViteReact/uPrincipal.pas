unit uPrincipal;

{ Janela do app: só o browser. A interface é o frontend React (pasta frontend\),
  embutido no exe pelo "borion pack"; em modo dev, vem do servidor do Vite. }

interface

uses
  Windows, Messages, SysUtils, Classes, Controls, Forms, Dialogs,
  WebView2Browser, BorionIpc, BorionAssets;

type
  TfrmPrincipal = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    FBrowser: TWebView2Browser;
    FIpc: TBorionIpc;
    FAssets: TBorionAssets;
    procedure WMMove(var Message: TWMMove); message WM_MOVE;
    procedure BrowserInitialized(Sender: TObject; ErrorCode: HResult);
    procedure BrowserTitleChanged(Sender: TObject; const Value: WideString);
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
  FBrowser.OnTitleChanged := BrowserTitleChanged;

  FIpc := TBorionIpc.Create(Self, FBrowser);
  RegistrarComandos(FIpc);

  { pacote BORION_ASSETS do exe, ou o servidor do Vite com --dev-url }
  FAssets := TBorionAssets.Create(Self, FBrowser);
  FIpc.AllowOrigin(BorionOriginOf(FAssets.StartUrl));

  if not FAssets.IsDev and (FAssets.Pack = nil) then
    MessageDlg('Interface não encontrada no executável: ' + FAssets.PackError + #13#10 +
      'Compile com o build.bat (que roda o "borion pack").', mtWarning, [mbOK], 0);
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

procedure TfrmPrincipal.BrowserInitialized(Sender: TObject; ErrorCode: HResult);
begin
  if Failed(ErrorCode) then
    MessageDlg(Format('Falha ao criar o WebView2 (HRESULT $%.8x)', [ErrorCode]), mtError, [mbOK], 0);
end;

procedure TfrmPrincipal.BrowserTitleChanged(Sender: TObject; const Value: WideString);
begin
  if FAssets.IsDev then
    Caption := Value + '  [dev: ' + FAssets.DevUrl + ']'
  else
    Caption := Value;
end;

end.
