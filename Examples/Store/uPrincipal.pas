unit uPrincipal;

{ Exemplo do plugin "store": a página (web\app.js) guarda preferências em
  %APPDATA%\Borion Store Demo\prefs.json. O Delphi usa o mesmo store pela API
  nativa: grava a posição da janela ao fechar e a restaura ao abrir. }

interface

uses
  Windows, Messages, SysUtils, Classes, Controls, Forms, Dialogs,
  WebView2Browser, BorionIpc, BorionAssets, BorionStore;

type
  TfrmPrincipal = class(TForm)
  private
    FBrowser: TWebView2Browser;
    FIpc: TBorionIpc;
    FAssets: TBorionAssets;
    FStore: TBorionStorePlugin;
    procedure WMMove(var Message: TWMMove); message WM_MOVE;
    procedure BrowserTitleChanged(Sender: TObject; const Value: WideString);
    procedure RestaurarJanela;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  frmPrincipal: TfrmPrincipal;

implementation

uses
  Jsons;

constructor TfrmPrincipal.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);  { sem .dfm: a janela inteira é o browser }
  Caption := 'Borion: store';
  OnClose := FormClose;
  Width := 900;
  Height := 640;
  Position := poScreenCenter;

  FBrowser := TWebView2Browser.Create(Self);
  FBrowser.Parent := Self;
  FBrowser.Align := alClient;
  FBrowser.OnTitleChanged := BrowserTitleChanged;

  FIpc := TBorionIpc.Create(Self, FBrowser);
  FStore := TBorionStorePlugin(FIpc.AddPlugin(TBorionStorePlugin.Create('Borion Store Demo')));
  { FStore.AutoSave := False;  grava só no store.save() / ao fechar }
  RestaurarJanela;

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

{ A posição da janela fica no mesmo prefs.json da página, na chave "janela" }
procedure TfrmPrincipal.RestaurarJanela;
var
  Json: string;
  J: TJsonObject;
begin
  if not FStore.ReadJson('prefs', 'janela', Json) then
    Exit;
  J := TJsonObject.Create;
  try
    J.Parse(Json);
    Position := poDesigned;
    SetBounds(J['left'].AsInteger, J['top'].AsInteger, J['width'].AsInteger, J['height'].AsInteger);
  except
    { valor estranho (editado à mão?): fica a posição padrão }
  end;
  J.Free;
end;

procedure TfrmPrincipal.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  if WindowState = wsNormal then
    FStore.WriteJson('prefs', 'janela', Format('{"left":%d,"top":%d,"width":%d,"height":%d}',
      [Left, Top, Width, Height]));
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
