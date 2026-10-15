unit uPrincipal;

{ Borion Editor: a janela só monta o browser, o IPC, os assets e os plugins
  oficiais (dialog, fs, shell, menu, tray, app). Toda a lógica do editor, inclusive
  a barra de menu e o ícone da bandeja, está no frontend (frontend\src\main.js). }

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

const
  APP_NOME = 'Borion Editor';

var
  frmPrincipal: TfrmPrincipal;

implementation

{$R *.dfm}

uses
  BorionScope, BorionFs, BorionDialog, BorionShell, BorionMenu, BorionTray, BorionApp;

procedure TfrmPrincipal.FormCreate(Sender: TObject);
var
  Scope: TBorionScope;
begin
  FBrowser := TWebView2Browser.Create(Self);
  FBrowser.Parent := Self;
  FBrowser.Align := alClient;
  FBrowser.OnInitialized := BrowserInitialized;
  FBrowser.OnTitleChanged := BrowserTitleChanged;

  FIpc := TBorionIpc.Create(Self, FBrowser);

  { Escopo de arquivos: negado por padrão. O app libera só a própria pasta de
    dados (arquivos recentes) e uma pasta em Documentos; o resto, só o que o
    usuário escolher nos diálogos (o plugin dialog acrescenta ao escopo). }
  Scope := TBorionScope.Create(APP_NOME);
  ForceDirectories(BorionBaseDirPath(bdAppData, APP_NOME));
  ForceDirectories(BorionBaseDirPath(bdDocument, APP_NOME) + '\' + APP_NOME);
  Scope.AllowDir('$APPDATA');
  Scope.AllowDir('$DOCUMENT\' + APP_NOME);

  FIpc.AddPlugin(TBorionFsPlugin.Create(Scope));        { dono do escopo }
  FIpc.AddPlugin(TBorionDialogPlugin.Create(Scope));
  FIpc.AddPlugin(TBorionShellPlugin.Create(Scope));

  { barra de menu (os atalhos funcionam com o foco no texto), bandeja e janela }
  FIpc.AddPlugin(TBorionMenuPlugin.Create);
  TBorionTrayPlugin(FIpc.AddPlugin(TBorionTrayPlugin.Create)).MinimizeToTray := True;
  FIpc.AddPlugin(TBorionAppPlugin.Create);

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
  Caption := Value;
end;

end.
