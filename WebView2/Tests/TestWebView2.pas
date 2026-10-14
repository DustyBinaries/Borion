unit TestWebView2;

{ Testes das partes do TWebView2Browser que não precisam do runtime do WebView2:
  requisição/resposta interceptadas, decodificação de URL, MIME, nomes de
  recurso, opções do ambiente e o controle antes do CreateWebView. A requisição
  é um objeto falso que implementa ICoreWebView2WebResourceRequest. }

interface

uses
  Windows, SysUtils, Classes, ActiveX, TestFramework, WebView2, WebView2Browser;

type
  TFakeRequest = class(TInterfacedObject, ICoreWebView2WebResourceRequest)
  private
    FUri, FMethod: WideString;
    FBody: string;
  public
    constructor Create(const AUri: WideString; const AMethod: WideString = 'GET'; const ABody: string = '');
    function get_Uri(out Uri: PWideChar): HResult; stdcall;
    function put_Uri(Uri: PWideChar): HResult; stdcall;
    function get_Method(out Method: PWideChar): HResult; stdcall;
    function put_Method(Method: PWideChar): HResult; stdcall;
    function get_Content(out Content: IStream): HResult; stdcall;
    function put_Content(const Content: IStream): HResult; stdcall;
    function get_Headers(out Headers: ICoreWebView2HttpRequestHeaders): HResult; stdcall;
  end;

  TTestRequest = class(TTestCase)
  private
    function Req(const Uri: WideString; const Method: WideString = 'GET'; const Body: string = ''): TWV2WebResourceRequest;
  published
    procedure TestPathERawPath;
    procedure TestPathSemBarraOuVazio;
    procedure TestPathIgnoraQueryEFragmento;
    procedure TestPathUtf8InvalidoViraAnsi;
    procedure TestQueryCrua;
    procedure TestQueryParam;
    procedure TestMetodoEConteudo;
    procedure TestSemConteudo;
    procedure TestHeadersSemSuporteNaoQuebram;
  end;

  TTestResponse = class(TTestCase)
  published
    procedure TestPadrao;
    procedure TestSetTextEmUtf8;
    procedure TestSetJson;
    procedure TestHeadersText;
    procedure TestLoadFromStreamEArquivo;
    procedure TestDeferForaDoEventoFalha;
    procedure TestCompleteSemDeferFalha;
  end;

  TTestUtilitarios = class(TTestCase)
  published
    procedure TestMimeType;
    procedure TestResourceName;
    procedure TestUrlDecode;
    procedure TestAcaoPadraoDeQueda;
    procedure TestBoolToWV2;
    procedure TestTakeCoTaskString;
  end;

  TTestEnvironmentOptions = class(TTestCase)
  published
    procedure TestPadroes;
    procedure TestIdaEVolta;
  end;

  TTestBrowserSemWebView = class(TTestCase)
  private
    FBrowser: TWebView2Browser;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEstadoInicial;
    procedure TestOperacoesSemWebViewNaoFalham;
    procedure TestFiltrosPendentes;
    procedure TestPropriedadesDoAmbiente;
  end;

implementation

function CoTaskCopia(const S: WideString): PWideChar;
var
  N: Integer;
begin
  N := (Length(S) + 1) * SizeOf(WideChar);
  Result := CoTaskMemAlloc(N);
  Move(PWideChar(S)^, Result^, N);
end;

function LerStream(S: TStream): string;
begin
  SetLength(Result, S.Size);
  S.Position := 0;
  if S.Size > 0 then
    S.ReadBuffer(Result[1], S.Size);
end;

{ TFakeRequest }

constructor TFakeRequest.Create(const AUri, AMethod: WideString; const ABody: string);
begin
  inherited Create;
  FUri := AUri;
  FMethod := AMethod;
  FBody := ABody;
end;

function TFakeRequest.get_Uri(out Uri: PWideChar): HResult;
begin
  Uri := CoTaskCopia(FUri);
  Result := S_OK;
end;

function TFakeRequest.put_Uri(Uri: PWideChar): HResult;
begin
  Result := E_NOTIMPL;
end;

function TFakeRequest.get_Method(out Method: PWideChar): HResult;
begin
  Method := CoTaskCopia(FMethod);
  Result := S_OK;
end;

function TFakeRequest.put_Method(Method: PWideChar): HResult;
begin
  Result := E_NOTIMPL;
end;

function TFakeRequest.get_Content(out Content: IStream): HResult;
begin
  if FBody = '' then
    Content := nil
  else
    Content := TStreamAdapter.Create(TStringStream.Create(FBody), soOwned);
  Result := S_OK;
end;

function TFakeRequest.put_Content(const Content: IStream): HResult;
begin
  Result := E_NOTIMPL;
end;

function TFakeRequest.get_Headers(out Headers: ICoreWebView2HttpRequestHeaders): HResult;
begin
  Headers := nil;
  Result := E_NOTIMPL;
end;

{ TTestRequest }

function TTestRequest.Req(const Uri, Method: WideString; const Body: string): TWV2WebResourceRequest;
begin
  Result := TWV2WebResourceRequest.Create(TFakeRequest.Create(Uri, Method, Body), COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
end;

procedure TTestRequest.TestPathERawPath;
var
  R: TWV2WebResourceRequest;
begin
  R := Req('https://app.localhost/a%20b/a%C3%A7%C3%A3o.txt');
  try
    CheckEqualsWideString('a%20b/a%C3%A7%C3%A3o.txt', R.RawPath);
    CheckEqualsWideString('a b/a' + WideChar($E7) + WideChar($E3) + 'o.txt', R.Path);
  finally
    R.Free;
  end;
  R := Req('https://app.localhost/100%25+mais');
  try
    CheckEqualsWideString('100%+mais', R.Path, '"+" não é espaço no caminho');
  finally
    R.Free;
  end;
end;

procedure TTestRequest.TestPathSemBarraOuVazio;
var
  R: TWV2WebResourceRequest;
begin
  R := Req('https://app.localhost');
  try
    CheckEqualsWideString('', R.Path);
  finally
    R.Free;
  end;
  R := Req('https://app.localhost/');
  try
    CheckEqualsWideString('', R.Path);
  finally
    R.Free;
  end;
end;

procedure TTestRequest.TestPathIgnoraQueryEFragmento;
var
  R: TWV2WebResourceRequest;
begin
  R := Req('https://app.localhost/api/x?a=1&b=2#topo');
  try
    CheckEqualsWideString('api/x', R.Path);
    CheckEqualsWideString('a=1&b=2', R.Query);
  finally
    R.Free;
  end;
end;

procedure TTestRequest.TestPathUtf8InvalidoViraAnsi;
var
  R: TWV2WebResourceRequest;
begin
  { %E3 sozinho não é UTF-8 válido: os bytes são lidos como ANSI (cp1252: ã) }
  R := Req('https://app.localhost/S%E3o');
  try
    CheckEqualsWideString(WideString('S') + WideChar($E3) + 'o', R.Path);
  finally
    R.Free;
  end;
end;

procedure TTestRequest.TestQueryCrua;
var
  R: TWV2WebResourceRequest;
begin
  R := Req('https://app.localhost/x?q=a%26b%3Dc');
  try
    CheckEqualsWideString('q=a%26b%3Dc', R.Query, 'Query fica codificada');
    CheckEqualsWideString('a&b=c', R.QueryParam('q'), 'QueryParam decodifica cada valor');
  finally
    R.Free;
  end;
end;

procedure TTestRequest.TestQueryParam;
var
  R: TWV2WebResourceRequest;
begin
  R := Req('https://app.localhost/busca?termo=s%C3%A3o+paulo&n=10&vazio=&flag&a%20b=ok#x');
  try
    CheckEqualsWideString(WideString('s') + WideChar($E3) + 'o paulo', R.QueryParam('termo'), '"+" vira espaço na query');
    CheckEqualsWideString('10', R.QueryParam('n'));
    CheckEqualsWideString('', R.QueryParam('vazio'));
    Check(R.HasQueryParam('vazio'));
    Check(R.HasQueryParam('flag'), 'parâmetro sem "="');
    CheckEqualsWideString('ok', R.QueryParam('a b'), 'o nome também é decodificado');
    CheckFalse(R.HasQueryParam('ausente'));
    CheckEqualsWideString('', R.QueryParam('ausente'));
    CheckFalse(R.HasQueryParam('N'), 'nomes diferenciam maiúsculas');
  finally
    R.Free;
  end;
end;

procedure TTestRequest.TestMetodoEConteudo;
var
  R: TWV2WebResourceRequest;
begin
  R := Req('https://app.localhost/api', 'POST', UTF8Encode(WideString('{"nome":"a' + WideChar($E7) + WideChar($E3) + 'o"}')));
  try
    CheckEqualsWideString('POST', R.Method);
    CheckEqualsWideString('{"nome":"a' + WideChar($E7) + WideChar($E3) + 'o"}', R.ContentText);
    CheckEquals(UTF8Encode(WideString('{"nome":"a' + WideChar($E7) + WideChar($E3) + 'o"}')), R.Content, 'bytes brutos');
  finally
    R.Free;
  end;
end;

procedure TTestRequest.TestSemConteudo;
var
  R: TWV2WebResourceRequest;
begin
  R := Req('https://app.localhost/');
  try
    CheckEquals('', R.Content);
    CheckEqualsWideString('', R.ContentText);
  finally
    R.Free;
  end;
end;

procedure TTestRequest.TestHeadersSemSuporteNaoQuebram;
var
  R: TWV2WebResourceRequest;
begin
  R := Req('https://app.localhost/');
  try
    CheckEqualsWideString('', R.GetHeader('Content-Type'));
    R.SetHeader('X-Teste', '1');  { get_Headers falhou: não pode levantar }
    R.RemoveHeader('X-Teste');
  finally
    R.Free;
  end;
end;

{ TTestResponse }

procedure TTestResponse.TestPadrao;
var
  R: TWV2WebResourceResponse;
begin
  R := TWV2WebResourceResponse.Create;
  try
    CheckEquals(200, R.StatusCode);
    CheckEqualsWideString('OK', R.ReasonPhrase);
    CheckEquals(0, R.Content.Size);
    CheckEqualsWideString('', R.HeadersText);
    CheckFalse(R.Deferred);
  finally
    R.Free;
  end;
end;

procedure TTestResponse.TestSetTextEmUtf8;
var
  R: TWV2WebResourceResponse;
begin
  R := TWV2WebResourceResponse.Create;
  try
    R.SetText(WideString('a') + WideChar($E7) + WideChar($201C) + WideChar($20AC));
    CheckEquals('a'#$C3#$A7#$E2#$80#$9C#$E2#$82#$AC, LerStream(R.Content));
    CheckEquals('text/plain; charset=utf-8', R.Headers.Values['Content-Type']);
    R.SetText('<p>x</p>', 'text/html');
    CheckEquals('<p>x</p>', LerStream(R.Content), 'SetText substitui o conteúdo');
    CheckEquals('text/html; charset=utf-8', R.Headers.Values['Content-Type']);
  finally
    R.Free;
  end;
end;

procedure TTestResponse.TestSetJson;
var
  R: TWV2WebResourceResponse;
begin
  R := TWV2WebResourceResponse.Create;
  try
    R.SetJson('{"a":1}');
    CheckEquals('{"a":1}', LerStream(R.Content));
    CheckEquals('application/json; charset=utf-8', R.Headers.Values['Content-Type']);
  finally
    R.Free;
  end;
end;

procedure TTestResponse.TestHeadersText;
var
  R: TWV2WebResourceResponse;
begin
  R := TWV2WebResourceResponse.Create;
  try
    R.SetHeader('Cache-Control', 'no-cache');
    R.SetHeader('X-A', '1');
    R.SetHeader('X-A', '2');  { substitui }
    CheckEqualsWideString('Cache-Control: no-cache'#13#10'X-A: 2', R.HeadersText);
  finally
    R.Free;
  end;
end;

procedure TTestResponse.TestLoadFromStreamEArquivo;
var
  R: TWV2WebResourceResponse;
  S: TStringStream;
  Arquivo: string;
begin
  R := TWV2WebResourceResponse.Create;
  S := TStringStream.Create('conteudo');
  try
    S.Position := 5;  { LoadFromStream copia desde o início }
    R.LoadFromStream(S, 'text/plain');
    CheckEquals('conteudo', LerStream(R.Content));
    Arquivo := ExtractFilePath(ParamStr(0)) + 'teste-resposta.css';
    with TFileStream.Create(Arquivo, fmCreate) do
    try
      WriteBuffer(PChar(S.DataString)^, Length(S.DataString));
    finally
      Free;
    end;
    R.LoadFromFile(Arquivo);
    CheckEquals('text/css; charset=utf-8', R.Headers.Values['Content-Type'], 'MIME pela extensão');
    DeleteFile(Arquivo);
  finally
    S.Free;
    R.Free;
  end;
end;

procedure TTestResponse.TestDeferForaDoEventoFalha;
var
  R: TWV2WebResourceResponse;
begin
  R := TWV2WebResourceResponse.Create;
  try
    try
      R.Defer;
      Fail('Defer fora do OnWebResourceRequested deveria falhar');
    except
      on EWebView2Error do ;
    end;
    CheckFalse(R.Deferred);
  finally
    R.Free;
  end;
end;

procedure TTestResponse.TestCompleteSemDeferFalha;
var
  R: TWV2WebResourceResponse;
begin
  R := TWV2WebResourceResponse.Create;
  try
    try
      R.Complete;
      Fail('Complete sem Defer deveria falhar');
    except
      on EWebView2Error do ;
    end;
  finally
    R.Free;
  end;
end;

{ TTestUtilitarios }

procedure TTestUtilitarios.TestMimeType;
begin
  CheckEquals('text/html; charset=utf-8', WV2MimeType('index.HTML'));
  CheckEquals('text/javascript; charset=utf-8', WV2MimeType('js/app.mjs'));
  CheckEquals('image/webp', WV2MimeType('a/b/foto.webp'));
  CheckEquals('application/wasm', WV2MimeType('m.wasm'));
  CheckEquals('application/octet-stream', WV2MimeType('dados.bin'));
  CheckEquals('application/octet-stream', WV2MimeType('sem-extensao'));
end;

procedure TTestUtilitarios.TestResourceName;
begin
  CheckEquals('INDEX_HTML', WV2ResourceName('index.html'));
  CheckEquals('JS_APP_JS', WV2ResourceName('js/app.js'));
  CheckEquals('IMG_LOGO_V2_SVG', WV2ResourceName('img/logo-v2.svg'));
end;

procedure TTestUtilitarios.TestUrlDecode;
begin
  CheckEqualsWideString('a b', WV2UrlDecode('a%20b'));
  CheckEqualsWideString('a+b', WV2UrlDecode('a+b'));
  CheckEqualsWideString('a b', WV2UrlDecode('a+b', True));
  CheckEqualsWideString(WideChar($20AC), WV2UrlDecode('%E2%82%AC'), 'euro em UTF-8');
  CheckEqualsWideString('100%', WV2UrlDecode('100%'), '% sem dígitos fica');
  CheckEqualsWideString('%zz', WV2UrlDecode('%zz'));
  CheckEqualsWideString('', WV2UrlDecode(''));
end;

procedure TTestUtilitarios.TestAcaoPadraoDeQueda;
begin
  Check(WV2DefaultProcessFailedAction(COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED) = pfaRecreate);
  Check(WV2DefaultProcessFailedAction(COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED) = pfaReload);
  Check(WV2DefaultProcessFailedAction(COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_UNRESPONSIVE) = pfaNone);
  Check(WV2DefaultProcessFailedAction(COREWEBVIEW2_PROCESS_FAILED_KIND_GPU_PROCESS_EXITED) = pfaNone);
end;

procedure TTestUtilitarios.TestBoolToWV2;
begin
  { o motivo de existir: LongBool(True) é -1, e o WebView2 só aceita 1 }
  CheckEquals(1, BoolToWV2(True));
  CheckEquals(0, BoolToWV2(False));
end;

procedure TTestUtilitarios.TestTakeCoTaskString;
begin
  CheckEqualsWideString('', TakeCoTaskString(nil));
  CheckEqualsWideString('texto', TakeCoTaskString(CoTaskCopia('texto')));
end;

{ TTestEnvironmentOptions }

procedure TTestEnvironmentOptions.TestPadroes;
var
  O: ICoreWebView2EnvironmentOptions;
  P: PWideChar;
  B: BOOL;
begin
  O := TWV2EnvironmentOptions.Create;
  O.get_TargetCompatibleBrowserVersion(P);
  CheckEqualsWideString(WV2_TARGET_COMPATIBLE_BROWSER_VERSION, TakeCoTaskString(P));
  O.get_Language(P);
  CheckEqualsWideString('', TakeCoTaskString(P));
  O.get_AllowSingleSignOnUsingOSPrimaryAccount(B);
  CheckFalse(B);
end;

procedure TTestEnvironmentOptions.TestIdaEVolta;
var
  O: ICoreWebView2EnvironmentOptions;
  P: PWideChar;
  B: BOOL;
begin
  O := TWV2EnvironmentOptions.Create;
  O.put_Language('pt-BR');
  O.put_AdditionalBrowserArguments('--disable-gpu --lang=pt-BR');
  O.put_AllowSingleSignOnUsingOSPrimaryAccount(BoolToWV2(True));
  O.get_Language(P);
  CheckEqualsWideString('pt-BR', TakeCoTaskString(P));
  O.get_AdditionalBrowserArguments(P);
  CheckEqualsWideString('--disable-gpu --lang=pt-BR', TakeCoTaskString(P));
  O.get_AllowSingleSignOnUsingOSPrimaryAccount(B);
  Check(B);
end;

{ TTestBrowserSemWebView }

procedure TTestBrowserSemWebView.SetUp;
begin
  FBrowser := TWebView2Browser.Create(nil);
end;

procedure TTestBrowserSemWebView.TearDown;
begin
  FBrowser.Free;
end;

procedure TTestBrowserSemWebView.TestEstadoInicial;
begin
  CheckFalse(FBrowser.Ready);
  Check(FBrowser.WebView = nil);
  CheckEqualsWideString('', FBrowser.Source);
  CheckFalse(FBrowser.CanGoBack);
  CheckFalse(FBrowser.CanGoForward);
end;

procedure TTestBrowserSemWebView.TestOperacoesSemWebViewNaoFalham;
begin
  FBrowser.Navigate('https://example.com');  { fica pendente }
  FBrowser.Reload;
  FBrowser.GoBack;
  FBrowser.Stop;
  FBrowser.ExecuteScript('1+1');
  FBrowser.PostWebMessage('x');
  FBrowser.NotifyParentWindowPositionChanged;
  FBrowser.AddScriptOnDocumentCreated('window.x = 1;');
  Check(True);
end;

procedure TTestBrowserSemWebView.TestFiltrosPendentes;
begin
  FBrowser.AddWebResourceRequestedFilter('https://a.local/*');
  FBrowser.ServeEmbeddedResources('b.local');
  FBrowser.AddWebResourceRequestedFilter('*.png', 3);
  CheckEquals(3, FBrowser.ResourceFilterCount);
  FBrowser.RemoveWebResourceRequestedFilter('*.png');  { contexto diferente: não remove }
  CheckEquals(3, FBrowser.ResourceFilterCount);
  FBrowser.RemoveWebResourceRequestedFilter('*.png', 3);
  FBrowser.RemoveWebResourceRequestedFilter('https://a.local/*');
  CheckEquals(1, FBrowser.ResourceFilterCount);
  FBrowser.RemoveWebResourceRequestedFilter('nao-existe');
  CheckEquals(1, FBrowser.ResourceFilterCount);
  CheckEqualsWideString('https://b.local/x.js', FBrowser.EmbeddedUrl('x.js'));
end;

procedure TTestBrowserSemWebView.TestPropriedadesDoAmbiente;
begin
  FBrowser.Language := 'en-US';
  FBrowser.AdditionalBrowserArguments := '--disable-gpu';
  CheckEqualsWideString('en-US', FBrowser.Language);
  CheckEqualsWideString('--disable-gpu', FBrowser.AdditionalBrowserArguments);
end;

initialization
  RegisterTest('WebView2.Request', TTestRequest.Suite);
  RegisterTest('WebView2.Response', TTestResponse.Suite);
  RegisterTest('WebView2.Utilitarios', TTestUtilitarios.Suite);
  RegisterTest('WebView2.EnvironmentOptions', TTestEnvironmentOptions.Suite);
  RegisterTest('WebView2.SemWebView', TTestBrowserSemWebView.Suite);

end.
