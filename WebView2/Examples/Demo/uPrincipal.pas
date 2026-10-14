unit uPrincipal;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, ExtCtrls, ComCtrls, WebView2Browser;

type
  TfrmPrincipal = class(TForm)
    pnlTopo: TPanel;
    btnVoltar: TButton;
    btnAvancar: TButton;
    btnRecarregar: TButton;
    edtUrl: TEdit;
    btnIr: TButton;
    btnDevTools: TButton;
    pnlLateral: TPanel;
    grpPonte: TGroupBox;
    lblMensagem: TLabel;
    edtMensagem: TEdit;
    btnEnviarJS: TButton;
    lblScript: TLabel;
    edtScript: TEdit;
    btnExecutarJS: TButton;
    btnPaginaDemo: TButton;
    rgNovaJanela: TRadioGroup;
    grpLog: TGroupBox;
    memLog: TMemo;
    splLateral: TSplitter;
    sbStatus: TStatusBar;
    procedure FormCreate(Sender: TObject);
    procedure btnVoltarClick(Sender: TObject);
    procedure btnAvancarClick(Sender: TObject);
    procedure btnRecarregarClick(Sender: TObject);
    procedure btnIrClick(Sender: TObject);
    procedure btnDevToolsClick(Sender: TObject);
    procedure btnEnviarJSClick(Sender: TObject);
    procedure btnExecutarJSClick(Sender: TObject);
    procedure btnPaginaDemoClick(Sender: TObject);
    procedure edtUrlKeyPress(Sender: TObject; var Key: Char);
  private
    FBrowser: TWebView2Browser;
    procedure Log(const S: string);
    procedure AtualizarBotoes;
    procedure WMMove(var Message: TWMMove); message WM_MOVE;
    { eventos do browser }
    procedure BrowserInitialized(Sender: TObject; ErrorCode: HResult);
    procedure BrowserNavigationStarting(Sender: TObject; const Uri: WideString;
      IsUserInitiated, IsRedirected: Boolean; var Cancel: Boolean);
    procedure BrowserNavigationCompleted(Sender: TObject; Success: Boolean; WebErrorStatus: Integer);
    procedure BrowserNewWindowRequested(Sender: TObject; const Uri: WideString;
      IsUserInitiated: Boolean; var Action: TWV2NewWindowAction);
    procedure BrowserWebResourceRequested(Sender: TObject; Request: TWV2WebResourceRequest;
      Response: TWV2WebResourceResponse; var Handled: Boolean);
    procedure BrowserSourceChanged(Sender: TObject; const Value: WideString);
    procedure BrowserTitleChanged(Sender: TObject; const Value: WideString);
    procedure BrowserWebMessageReceived(Sender: TObject; const Value: WideString);
    procedure BrowserScriptResult(Sender: TObject; ErrorCode: HResult; const ResultJson: WideString);
  end;

var
  frmPrincipal: TfrmPrincipal;

implementation

{$R *.dfm}

uses
  ShellAPI, WebView2;

procedure TfrmPrincipal.FormCreate(Sender: TObject);
begin
  FBrowser := TWebView2Browser.Create(Self);
  FBrowser.Parent := Self;
  FBrowser.Align := alClient;
  FBrowser.OnInitialized := BrowserInitialized;
  FBrowser.OnNavigationStarting := BrowserNavigationStarting;
  FBrowser.OnNavigationCompleted := BrowserNavigationCompleted;
  FBrowser.OnNewWindowRequested := BrowserNewWindowRequested;
  FBrowser.OnWebResourceRequested := BrowserWebResourceRequested;
  FBrowser.OnSourceChanged := BrowserSourceChanged;
  FBrowser.OnTitleChanged := BrowserTitleChanged;
  FBrowser.OnWebMessageReceived := BrowserWebMessageReceived;
  FBrowser.OnScriptResult := BrowserScriptResult;

  AtualizarBotoes;
  Log('Iniciando WebView2...');
  try
    { a página de demo vem dos recursos do exe (web.rc), em https://app.localhost/ }
    FBrowser.ServeEmbeddedResources('app.localhost');
    FBrowser.CreateWebView;
    FBrowser.Navigate(FBrowser.EmbeddedUrl('index.html'));
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

procedure TfrmPrincipal.AtualizarBotoes;
var
  Pronto: Boolean;
begin
  Pronto := FBrowser.Ready;
  btnVoltar.Enabled := Pronto and FBrowser.CanGoBack;
  btnAvancar.Enabled := Pronto and FBrowser.CanGoForward;
  btnRecarregar.Enabled := Pronto;
  btnIr.Enabled := Pronto;
  btnDevTools.Enabled := Pronto;
  btnEnviarJS.Enabled := Pronto;
  btnExecutarJS.Enabled := Pronto;
  btnPaginaDemo.Enabled := Pronto;
end;

procedure TfrmPrincipal.WMMove(var Message: TWMMove);
begin
  inherited;
  if FBrowser <> nil then
    FBrowser.NotifyParentWindowPositionChanged;
end;

{ --- eventos do browser ------------------------------------------------- }

procedure TfrmPrincipal.BrowserInitialized(Sender: TObject; ErrorCode: HResult);
begin
  if Succeeded(ErrorCode) then
  begin
    Log('WebView2 pronto. Runtime: ' + GetWebView2RuntimeVersion);
    sbStatus.Panels[0].Text := 'Pronto';
  end
  else
  begin
    Log(Format('Falha ao criar o WebView2 (HRESULT $%.8x)', [ErrorCode]));
    sbStatus.Panels[0].Text := 'Erro';
  end;
  AtualizarBotoes;
end;

procedure TfrmPrincipal.BrowserNavigationStarting(Sender: TObject; const Uri: WideString;
  IsUserInitiated, IsRedirected: Boolean; var Cancel: Boolean);
const
  SimNao: array[Boolean] of string = ('nao', 'sim');
begin
  { Exemplo de filtro: bloqueia qualquer endereço que contenha "bloqueado" }
  Cancel := Pos('bloqueado', LowerCase(Uri)) > 0;
  Log(Format('NavigationStarting: %s (usuário: %s, redirect: %s)',
    [Uri, SimNao[IsUserInitiated], SimNao[IsRedirected]]));
  if Cancel then
    Log('  -> navegação cancelada');
  if Cancel then
    sbStatus.Panels[0].Text := 'Navegação bloqueada'
  else
    sbStatus.Panels[0].Text := 'Carregando...';
end;

procedure TfrmPrincipal.BrowserNavigationCompleted(Sender: TObject; Success: Boolean;
  WebErrorStatus: Integer);
begin
  if Success then
    sbStatus.Panels[0].Text := 'Carregado'
  else if WebErrorStatus = COREWEBVIEW2_WEB_ERROR_STATUS_OPERATION_CANCELED then
  begin
    { cancelada pelo OnNavigationStarting ou por Stop: o status ja foi atualizado }
  end
  else
  begin
    sbStatus.Panels[0].Text := 'Erro de navegação';
    Log('Navegação falhou. WebErrorStatus = ' + IntToStr(WebErrorStatus));
  end;
  AtualizarBotoes;
end;

procedure TfrmPrincipal.BrowserNewWindowRequested(Sender: TObject; const Uri: WideString;
  IsUserInitiated: Boolean; var Action: TWV2NewWindowAction);
const
  Descricao: array[0..3] of string = ('mesma janela', 'popup do WebView2', 'bloqueada',
    'navegador padrão');
begin
  case rgNovaJanela.ItemIndex of
    0: Action := nwaSameWindow;
    1: Action := nwaPopup;
    2: Action := nwaCancel;
    3: begin
         Action := nwaCancel;
         ShellExecute(Handle, 'open', PChar(string(Uri)), nil, nil, SW_SHOWNORMAL);
       end;
  end;
  Log('NewWindowRequested: ' + Uri + ' -> ' + Descricao[rgNovaJanela.ItemIndex]);
end;

function JsonStr(const S: WideString): WideString;
var
  I: Integer;
  C: WideChar;
begin
  Result := '"';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if Ord(C) < 32 then
        Result := Result + '\u' + IntToHex(Ord(C), 4)
      else
        Result := Result + C;
    end;
  end;
  Result := Result + '"';
end;

{ "API local": a página faz fetch('api/...') e o Delphi responde, sem servidor HTTP.
  As demais URLs de https://app.localhost/ caem no servidor de recursos embutidos. }
procedure TfrmPrincipal.BrowserWebResourceRequested(Sender: TObject; Request: TWV2WebResourceRequest;
  Response: TWV2WebResourceResponse; var Handled: Boolean);
var
  Path: WideString;
begin
  Path := Request.Path;
  if Copy(Path, 1, 4) <> 'api/' then
    Exit;  { não é da API: segue para os recursos embutidos }

  Handled := True;
  Log(Request.Method + ' ' + Path);

  if (Path = 'api/clientes') and (Request.Method = 'GET') then
    Response.SetJson(
      '[{"id":1,"nome":"Padaria São João","cidade":"Curitiba"},' +
      '{"id":2,"nome":"Mercado Bom Preço","cidade":"Londrina"},' +
      '{"id":3,"nome":"Farmácia Saúde","cidade":"Maringá"}]')
  else if Path = 'api/hora' then
    Response.SetJson('{"hora":' + JsonStr(FormatDateTime('dd/mm/yyyy hh:nn:ss', Now)) + '}')
  else if (Path = 'api/eco') and (Request.Method = 'POST') then
    Response.SetJson('{"metodo":' + JsonStr(Request.Method) +
      ',"contentType":' + JsonStr(Request.GetHeader('Content-Type')) +
      ',"corpo":' + JsonStr(Request.ContentText) +
      ',"query":' + JsonStr(Request.Query) + '}')
  else if Path = 'api/erro' then
    raise Exception.Create('erro proposital no handler Delphi')  { vira 500 }
  else
  begin
    Response.StatusCode := 404;
    Response.ReasonPhrase := 'Not Found';
    Response.SetJson('{"erro":' + JsonStr('rota desconhecida: ' + Path) + '}');
  end;
end;

procedure TfrmPrincipal.BrowserSourceChanged(Sender: TObject; const Value: WideString);
begin
  edtUrl.Text := Value;
  sbStatus.Panels[1].Text := Value;
  AtualizarBotoes;
end;

procedure TfrmPrincipal.BrowserTitleChanged(Sender: TObject; const Value: WideString);
begin
  Caption := 'WebView2 + Delphi 7 - ' + Value;
end;

procedure TfrmPrincipal.BrowserWebMessageReceived(Sender: TObject; const Value: WideString);
begin
  Log('JS -> Delphi: ' + Value);
  { Exemplo de "comando" vindo da página }
  if Value = 'hora' then
    FBrowser.PostWebMessage('Hora no Delphi: ' + FormatDateTime('dd/mm/yyyy hh:nn:ss', Now));
end;

procedure TfrmPrincipal.BrowserScriptResult(Sender: TObject; ErrorCode: HResult;
  const ResultJson: WideString);
begin
  if Succeeded(ErrorCode) then
    Log('Resultado do script: ' + ResultJson)
  else
    Log(Format('Erro ao executar script (HRESULT $%.8x)', [ErrorCode]));
end;

{ --- ações da interface ------------------------------------------------- }

procedure TfrmPrincipal.btnVoltarClick(Sender: TObject);
begin
  FBrowser.GoBack;
end;

procedure TfrmPrincipal.btnAvancarClick(Sender: TObject);
begin
  FBrowser.GoForward;
end;

procedure TfrmPrincipal.btnRecarregarClick(Sender: TObject);
begin
  FBrowser.Reload;
end;

procedure TfrmPrincipal.btnIrClick(Sender: TObject);
var
  Url: string;
begin
  Url := Trim(edtUrl.Text);
  if Url = '' then
    Exit;
  if Pos('://', Url) = 0 then
    Url := 'https://' + Url;
  sbStatus.Panels[0].Text := 'Carregando...';
  FBrowser.Navigate(Url);
end;

procedure TfrmPrincipal.edtUrlKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0;
    btnIrClick(Sender);
  end;
end;

procedure TfrmPrincipal.btnDevToolsClick(Sender: TObject);
begin
  FBrowser.OpenDevTools;
end;

procedure TfrmPrincipal.btnEnviarJSClick(Sender: TObject);
begin
  FBrowser.PostWebMessage(edtMensagem.Text);
  Log('Delphi -> JS: ' + edtMensagem.Text);
end;

procedure TfrmPrincipal.btnExecutarJSClick(Sender: TObject);
begin
  Log('ExecuteScript: ' + edtScript.Text);
  FBrowser.ExecuteScript(edtScript.Text);
end;

procedure TfrmPrincipal.btnPaginaDemoClick(Sender: TObject);
begin
  FBrowser.Navigate(FBrowser.EmbeddedUrl('index.html'));
end;

end.
