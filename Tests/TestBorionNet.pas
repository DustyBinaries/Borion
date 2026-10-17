unit TestBorionNet;

{ Testes dos plugins os e http. O http fala com um servidor HTTP local (WinSock,
  em 127.0.0.1, porta livre), sem depender da internet. }

interface

uses
  Windows, SysUtils, Classes, Registry, WinSock, TestFramework, Jsons,
  BorionJson, BorionIpc, BorionFs, BorionOs, BorionHttp, TestBorionPlugins;

type
  TServidorTeste = class(TThread)
  private
    FSocket: TSocket;
    FPorta: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    property Porta: Integer read FPorta;
  end;

  TTestBorionOs = class(TTesteComIpc)
  protected
    procedure SetUp; override;
  published
    procedure TestInfo;
  end;

  TTestBorionHttpEscopo = class(TTestCase)
  published
    procedure TestWildcard;
    procedure TestParseUrl;
    procedure TestEscopo;
  end;

  TTestBorionHttp = class(TTesteComIpc)
  private
    FHttp: TBorionHttpPlugin;
    FServidor: TServidorTeste;
    function Url(const Caminho: string; const Host: string = '127.0.0.1'): string;
    function Buscar(const Caminho, Extra: string): TJsonObject;
    function Corpo(R: TJsonObject): string;
    function Cabecalho(R: TJsonObject; const Nome: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestGetTexto;
    procedure TestPostComCabecalhosECorpo;
    procedure TestStatusDeErroNaoRejeita;
    procedure TestBinario;
    procedure TestCabecalhosRepetidos;
    procedure TestRedirect;
    procedure TestRedirect303ViraGet;
    procedure TestRedirectManualEErro;
    procedure TestRedirectParaForaDoEscopo;
    procedure TestAuthorizationNaoVaiParaOutroHost;
    procedure TestMuitosRedirects;
    procedure TestRecusaNaHora;
    procedure TestCabecalhoInvalido;
    procedure TestTimeout;
    procedure TestCancel;
    procedure TestRespostaGrandeDemais;
    procedure TestConexaoRecusada;
  end;

implementation

{ --- servidor de teste ------------------------------------------------------ }

type
  TConexao = class(TThread)
  private
    FSocket: TSocket;
    FPorta: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(S: TSocket; Porta: Integer);
  end;

constructor TConexao.Create(S: TSocket; Porta: Integer);
begin
  FSocket := S;
  FPorta := Porta;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TConexao.Execute;
var
  Pedido, Linha, Caminho, Resposta, Corpo, Extra: string;
  Buf: array[0..8191] of Char;
  N, Fim, Tamanho, I: Integer;
begin
  try
    { lê cabeçalhos e corpo (Content-Length) }
    Pedido := '';
    repeat
      N := recv(FSocket, Buf, SizeOf(Buf), 0);
      if N <= 0 then
        Exit;
      Pedido := Pedido + Copy(Buf, 1, N);
      Fim := Pos(#13#10#13#10, Pedido);
    until Fim > 0;
    I := Pos('content-length:', LowerCase(Pedido));
    if (I > 0) and (I < Fim) then
    begin
      Linha := Copy(Pedido, I + 15, MaxInt);
      Tamanho := StrToIntDef(Trim(Copy(Linha, 1, Pos(#13#10, Linha) - 1)), 0);
      while Length(Pedido) < Fim + 3 + Tamanho do
      begin
        N := recv(FSocket, Buf, SizeOf(Buf), 0);
        if N <= 0 then
          Break;
        Pedido := Pedido + Copy(Buf, 1, N);
      end;
    end;
    Linha := Copy(Pedido, 1, Pos(#13#10, Pedido) - 1);  { GET /x HTTP/1.1 }
    Caminho := Copy(Linha, Pos(' ', Linha) + 1, MaxInt);
    Caminho := Copy(Caminho, 1, Pos(' ', Caminho) - 1);

    Extra := '';
    Corpo := '';
    Resposta := '200 OK';
    if Caminho = '/texto' then
    begin
      Corpo := 'ol'#$C3#$A1;
      Extra := 'Content-Type: text/plain; charset=utf-8'#13#10;
    end
    else if Caminho = '/eco' then
      Corpo := Pedido  { a requisição inteira, como chegou }
    else if Caminho = '/bin' then
    begin
      SetLength(Corpo, 256);
      for I := 0 to 255 do
        Corpo[I + 1] := Chr(I);
      Extra := 'Content-Type: application/octet-stream'#13#10;
    end
    else if Caminho = '/cookies' then
      Extra := 'Set-Cookie: a=1'#13#10'Set-Cookie: b=2'#13#10
    else if Caminho = '/redir' then
    begin
      Resposta := '302 Found';
      Extra := 'Location: /texto'#13#10;
    end
    else if Caminho = '/redir-303' then
    begin
      Resposta := '303 See Other';
      Extra := 'Location: /eco'#13#10;
    end
    else if Caminho = '/redir-307' then
    begin
      Resposta := '307 Temporary Redirect';
      Extra := 'Location: /eco'#13#10;
    end
    else if Caminho = '/redir-fora' then
    begin
      Resposta := '302 Found';
      Extra := Format('Location: http://localhost:%d/eco'#13#10, [FPorta]);
    end
    else if Caminho = '/redir-loop' then
    begin
      Resposta := '302 Found';
      Extra := 'Location: /redir-loop'#13#10;
    end
    else if Caminho = '/lento' then
    begin
      Sleep(3000);
      Corpo := 'tarde';
    end
    else if Caminho = '/grande' then
      Corpo := StringOfChar('x', 5000)
    else
    begin
      Resposta := '404 Not Found';
      Corpo := 'nada aqui';
    end;
    Resposta := 'HTTP/1.1 ' + Resposta + #13#10 + Extra +
      Format('Content-Length: %d'#13#10'Connection: close'#13#10#13#10, [Length(Corpo)]) + Corpo;
    send(FSocket, Resposta[1], Length(Resposta), 0);
  finally
    closesocket(FSocket);
  end;
end;

constructor TServidorTeste.Create;
var
  Dados: TWSAData;
  End_: TSockAddrIn;
  N: Integer;
begin
  WSAStartup($0101, Dados);
  FSocket := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  FillChar(End_, SizeOf(End_), 0);
  End_.sin_family := AF_INET;
  End_.sin_addr.S_addr := inet_addr('127.0.0.1');
  End_.sin_port := 0;  { porta livre }
  bind(FSocket, End_, SizeOf(End_));
  listen(FSocket, 16);
  N := SizeOf(End_);
  getsockname(FSocket, End_, N);
  FPorta := ntohs(End_.sin_port);
  inherited Create(False);
end;

destructor TServidorTeste.Destroy;
begin
  closesocket(FSocket);  { o accept falha e o Execute termina }
  WaitFor;
  WSACleanup;
  inherited;
end;

procedure TServidorTeste.Execute;
var
  S: TSocket;
begin
  while not Terminated do
  begin
    S := accept(FSocket, nil, nil);
    if S = INVALID_SOCKET then
      Break;
    TConexao.Create(S, FPorta);
  end;
end;

{ TTestBorionOs }

function NomeNoRegistro64: string;
var
  R: TRegistry;
  Build: Integer;
begin
  R := TRegistry.Create(KEY_READ or $0100);
  try
    R.RootKey := HKEY_LOCAL_MACHINE;
    R.OpenKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion', False);
    Result := R.ReadString('ProductName');
    Build := StrToIntDef(R.ReadString('CurrentBuildNumber'), 0);
  finally
    R.Free;
  end;
  if (Build >= 22000) and (Pos('Windows 10', Result) = 1) then
    Result := 'Windows 11' + Copy(Result, 11, MaxInt);
end;

procedure TTestBorionOs.SetUp;
begin
  inherited;
  FIpc.AddPlugin(TBorionOsPlugin.Create);
end;

procedure TTestBorionOs.TestInfo;
var
  R: TJsonObject;
  V: string;
begin
  R := TJsonObject.Create;
  try
    R.Parse(Ok('os:info', ''));
    CheckEquals('windows', R['platform'].AsString);
    CheckEquals('windows', R['family'].AsString);
    CheckEquals('windows', R['type'].AsString);
    Check(Pos(',' + R['arch'].AsString + ',', ',x86_64,aarch64,x86,arm,') > 0, R['arch'].AsString);
    CheckEquals('x86', R['processArch'].AsString);
    V := R['version'].AsString;
    Check(Pos(Format('.%d', [R['build'].AsInteger]), V) > 0, V);
    Check(R['build'].AsInteger >= 2600, 'build real (não o do modo de compatibilidade)');
    Check(Pos('Windows', R['name'].AsString) = 1, R['name'].AsString);
    { a visão de 64 bits do registro, não a do WOW6432Node }
    CheckEquals(NomeNoRegistro64, R['name'].AsString);
    Check(R['hostname'].AsString <> '');
    Check((R['locale'].ValueType = jvNull) or (Pos('-', R['locale'].AsString) > 0), 'locale BCP 47');
    CheckEquals(#13#10, R['eol'].AsString);
    CheckEquals('exe', R['exeExtension'].AsString);
  finally
    R.Free;
  end;
end;

{ TTestBorionHttpEscopo }

procedure TTestBorionHttpEscopo.TestWildcard;
begin
  Check(BorionWildcardMatch('*', ''));
  Check(BorionWildcardMatch('/api/*', '/api/'));
  Check(BorionWildcardMatch('/api/*', '/api/x/y?z=1'));
  Check(not BorionWildcardMatch('/api/*', '/apix'));
  Check(BorionWildcardMatch('*.exemplo.com', 'a.b.exemplo.com'));
  Check(not BorionWildcardMatch('*.exemplo.com', 'exemplo.com'));
  Check(BorionWildcardMatch('a*b*c', 'aXXbYYc'));
  Check(not BorionWildcardMatch('a*b*c', 'aXXbYY'));
  Check(BorionWildcardMatch('exato', 'exato'));
  Check(not BorionWildcardMatch('exato', 'exatos'));
end;

procedure TTestBorionHttpEscopo.TestParseUrl;
var
  U: TBorionUrl;
begin
  Check(BorionParseUrl('https://Api.Exemplo.com/v1/x?y=1#frag', U));
  CheckEquals('https', U.Scheme);
  CheckEquals('api.exemplo.com', U.Host);
  CheckEquals(443, U.Port);
  CheckEquals('/v1/x?y=1', U.Path);
  Check(BorionParseUrl('http://localhost:5000', U));
  CheckEquals(5000, U.Port);
  CheckEquals('/', U.Path);
  Check(not BorionParseUrl('ftp://exemplo.com/', U), 'ftp');
  Check(not BorionParseUrl('file:///C:/x', U), 'file');
  Check(not BorionParseUrl('/relativo', U), 'relativa');
  Check(not BorionParseUrl('https://user:senha@exemplo.com/', U), 'com usuário');
  Check(not BorionParseUrl('https://api.ok.com@outro.com/', U), 'usuário disfarçado');
  Check(not BorionParseUrl('https://exemplo.com/a b', U), 'espaço');
  Check(not BorionParseUrl('https://exempl' + #243 + '.com/', U), 'não-ASCII');
  Check(not BorionParseUrl('https:\\exemplo.com\x', U), 'barras invertidas');
  Check(not BorionParseUrl('', U), 'vazia');
end;

procedure TTestBorionHttpEscopo.TestEscopo;
var
  P: TBorionHttpPlugin;
begin
  P := TBorionHttpPlugin.Create;
  try
    Check(not P.IsAllowed('https://api.exemplo.com/'), 'negado por padrão');
    P.Allow('https://api.exemplo.com/v1/*');
    P.Allow('https://*.cdn.com');
    P.Allow('http://localhost:*/dev/*');
    Check(P.IsAllowed('https://api.exemplo.com/v1/usuarios?x=1'));
    Check(P.IsAllowed('https://API.exemplo.com/v1/'), 'host sem diferenciar maiúsculas');
    Check(not P.IsAllowed('https://api.exemplo.com/v2/'), 'outro caminho');
    Check(not P.IsAllowed('http://api.exemplo.com/v1/'), 'outro esquema');
    Check(not P.IsAllowed('https://api.exemplo.com:8443/v1/'), 'outra porta');
    Check(not P.IsAllowed('https://api.exemplo.com.mal.com/v1/'), 'host vizinho');
    Check(P.IsAllowed('https://a.cdn.com/qualquer/coisa'), 'sem caminho = host inteiro');
    Check(not P.IsAllowed('https://cdn.com/'), '*. exige subdomínio');
    Check(not P.IsAllowed('https://mal.com/.cdn.com'), '* do host não atravessa para o caminho');
    Check(P.IsAllowed('http://localhost:5173/dev/x'), 'qualquer porta');
    Check(not P.IsAllowed('http://localhost:5173/prod/x'));
    try
      P.Allow('sem-esquema.com');
      Fail('padrão sem esquema');
    except
      on E: EBorionError do
        CheckEquals('INVALID_PATTERN', E.Code);
    end;
  finally
    P.Free;
  end;
end;

{ TTestBorionHttp }

procedure TTestBorionHttp.SetUp;
begin
  inherited;
  FServidor := TServidorTeste.Create;
  FHttp := TBorionHttpPlugin(FIpc.AddPlugin(TBorionHttpPlugin.Create));
  FHttp.Allow(Format('http://127.0.0.1:%d/*', [FServidor.Porta]));
end;

procedure TTestBorionHttp.TearDown;
begin
  inherited;  { libera o IPC e o plugin (cancela o que estiver em andamento) }
  FServidor.Free;
end;

function TTestBorionHttp.Url(const Caminho, Host: string): string;
begin
  Result := Format('http://%s:%d%s', [Host, FServidor.Porta, Caminho]);
end;

function TTestBorionHttp.Buscar(const Caminho, Extra: string): TJsonObject;
var
  Args: string;
begin
  Args := '{"rid":"r1","url":' + JsonQuote(Url(Caminho));
  if Extra <> '' then
    Args := Args + ',' + Extra;
  Result := TJsonObject.Create;
  Result.Parse(Ok('http:fetch', Args + '}'));
end;

function TTestBorionHttp.Corpo(R: TJsonObject): string;
begin
  Result := BorionBase64Decode(R['body'].AsString);
end;

function TTestBorionHttp.Cabecalho(R: TJsonObject; const Nome: string): string;
var
  L: TJsonArray;
  I: Integer;
begin
  Result := '';
  L := R['headers'].AsArray;
  for I := 0 to L.Count - 1 do
    if SameText(L[I].AsArray[0].AsString, Nome) then
    begin
      if Result <> '' then
        Result := Result + '|';
      Result := Result + L[I].AsArray[1].AsString;
    end;
end;

procedure TTestBorionHttp.TestGetTexto;
var
  R: TJsonObject;
begin
  R := Buscar('/texto', '');
  try
    CheckEquals(200, R['status'].AsInteger);
    CheckEquals('OK', R['statusText'].AsString);
    CheckEquals(Url('/texto'), R['url'].AsString);
    Check(not R['redirected'].AsBoolean);
    CheckEquals('ol'#$C3#$A1, Corpo(R), 'bytes UTF-8 intactos');
    CheckEquals('text/plain; charset=utf-8', Cabecalho(R, 'content-type'));
  finally
    R.Free;
  end;
end;

procedure TTestBorionHttp.TestPostComCabecalhosECorpo;
var
  R: TJsonObject;
  Eco: string;
begin
  { corpo 'a=1&b=ç' (UTF-8) em base64 }
  R := Buscar('/eco', '"method":"post","headers":[["X-Teste","1"],["Content-Type","text/plain"]],' +
    '"body":' + JsonQuote(BorionBase64Encode('a=1&b='#$C3#$A7)));
  try
    Eco := Corpo(R);
    Check(Pos('POST /eco HTTP/1.1', Eco) = 1, Eco);
    Check(Pos('X-Teste: 1'#13#10, Eco) > 0, Eco);
    Check(Pos('Content-Length: 8'#13#10, Eco) > 0, Eco);
    Check(Pos('Accept-Encoding: gzip, deflate', Eco) > 0, 'pede compressão (o WinInet descompacta)');
    CheckEquals(#13#10#13#10'a=1&b='#$C3#$A7, Copy(Eco, Pos(#13#10#13#10, Eco), MaxInt));
  finally
    R.Free;
  end;
end;

procedure TTestBorionHttp.TestStatusDeErroNaoRejeita;
var
  R: TJsonObject;
begin
  { como o fetch: 404 é uma resposta, não um erro }
  R := Buscar('/nao-existe', '');
  try
    CheckEquals(404, R['status'].AsInteger);
    CheckEquals('Not Found', R['statusText'].AsString);
    CheckEquals('nada aqui', Corpo(R));
  finally
    R.Free;
  end;
end;

procedure TTestBorionHttp.TestBinario;
var
  R: TJsonObject;
  S: string;
  I: Integer;
begin
  R := Buscar('/bin', '');
  try
    S := Corpo(R);
    CheckEquals(256, Length(S));
    for I := 0 to 255 do
      CheckEquals(I, Ord(S[I + 1]));
  finally
    R.Free;
  end;
end;

procedure TTestBorionHttp.TestCabecalhosRepetidos;
var
  R: TJsonObject;
begin
  R := Buscar('/cookies', '');
  try
    CheckEquals('a=1|b=2', Cabecalho(R, 'Set-Cookie'), 'cada Set-Cookie é um par');
  finally
    R.Free;
  end;
end;

procedure TTestBorionHttp.TestRedirect;
var
  R: TJsonObject;
begin
  R := Buscar('/redir', '');
  try
    CheckEquals(200, R['status'].AsInteger);
    CheckEquals(Url('/texto'), R['url'].AsString);
    Check(R['redirected'].AsBoolean);
    CheckEquals('ol'#$C3#$A1, Corpo(R));
  finally
    R.Free;
  end;
end;

procedure TTestBorionHttp.TestRedirect303ViraGet;
var
  R: TJsonObject;
begin
  R := Buscar('/redir-303', '"method":"POST","body":' + JsonQuote(BorionBase64Encode('dados')) +
    ',"headers":[["Content-Type","text/plain"]]');
  try
    Check(Pos('GET /eco ', Corpo(R)) = 1, Corpo(R));
    Check(Pos('dados', Corpo(R)) = 0, 'sem corpo depois do 303');
    Check(Pos('Content-Type', Corpo(R)) = 0, 'sem Content-Type depois do 303');
  finally
    R.Free;
  end;
  { 307 mantém método e corpo }
  R := Buscar('/redir-307', '"method":"POST","body":' + JsonQuote(BorionBase64Encode('dados')));
  try
    Check(Pos('POST /eco ', Corpo(R)) = 1, Corpo(R));
    Check(Pos(#13#10#13#10'dados', Corpo(R)) > 0, Corpo(R));
  finally
    R.Free;
  end;
end;

procedure TTestBorionHttp.TestRedirectManualEErro;
var
  R: TJsonObject;
begin
  R := Buscar('/redir', '"redirect":"manual"');
  try
    CheckEquals(302, R['status'].AsInteger);
    CheckEquals('/texto', Cabecalho(R, 'Location'));
    Check(not R['redirected'].AsBoolean);
  finally
    R.Free;
  end;
  CheckEquals('REDIRECT', Erro('http:fetch', '{"url":' + JsonQuote(Url('/redir')) + ',"redirect":"error"}'));
end;

procedure TTestBorionHttp.TestRedirectParaForaDoEscopo;
begin
  { localhost não está no escopo (só 127.0.0.1) }
  CheckEquals('FORBIDDEN_URL', Erro('http:fetch', '{"url":' + JsonQuote(Url('/redir-fora')) + '}'));
end;

procedure TTestBorionHttp.TestAuthorizationNaoVaiParaOutroHost;
var
  R: TJsonObject;
begin
  FHttp.Allow(Format('http://localhost:%d/*', [FServidor.Porta]));
  R := Buscar('/redir-fora', '"headers":[["Authorization","Bearer segredo"],["X-Outro","fica"]]');
  try
    CheckEquals(Url('/eco', 'localhost'), R['url'].AsString);
    Check(Pos('segredo', Corpo(R)) = 0, 'Authorization não pode ir para outro host');
    Check(Pos('X-Outro: fica', Corpo(R)) > 0, Corpo(R));
  finally
    R.Free;
  end;
  { no mesmo host, vai }
  R := Buscar('/redir-307', '"headers":[["Authorization","Bearer segredo"]]');
  try
    Check(Pos('Authorization: Bearer segredo', Corpo(R)) > 0, Corpo(R));
  finally
    R.Free;
  end;
end;

procedure TTestBorionHttp.TestMuitosRedirects;
begin
  CheckEquals('TOO_MANY_REDIRECTS', Erro('http:fetch', '{"url":' + JsonQuote(Url('/redir-loop')) +
    ',"maxRedirections":3}'));
end;

procedure TTestBorionHttp.TestRecusaNaHora;
begin
  CheckEquals('FORBIDDEN_URL', Erro('http:fetch', '{"url":"https://exemplo.com/"}'));
  CheckEquals('FORBIDDEN_URL', Erro('http:fetch', '{"url":' + JsonQuote(Url('/texto', 'localhost')) + '}'));
  CheckEquals('INVALID_URL', Erro('http:fetch', '{"url":"ftp://127.0.0.1/"}'));
  CheckEquals('INVALID_URL', Erro('http:fetch', '{"url":"/relativa"}'));
  CheckEquals('INVALID_URL', Erro('http:fetch', '{}'));
end;

procedure TTestBorionHttp.TestCabecalhoInvalido;
var
  U: string;
begin
  U := '{"url":' + JsonQuote(Url('/eco'));
  CheckEquals('INVALID_ARGS', Erro('http:fetch', U + ',"headers":[["X","a\r\nInjetado: 1"]]}'));
  CheckEquals('INVALID_ARGS', Erro('http:fetch', U + ',"headers":[["X: y","1"]]}'));
  CheckEquals('INVALID_ARGS', Erro('http:fetch', U + ',"headers":[["só o nome"]]}'));
  CheckEquals('INVALID_ARGS', Erro('http:fetch', U + ',"method":"GET X"}'));
end;

procedure TTestBorionHttp.TestTimeout;
begin
  CheckEquals('TIMEOUT', Erro('http:fetch', '{"url":' + JsonQuote(Url('/lento')) + ',"timeout":500}'));
end;

procedure TTestBorionHttp.TestCancel;
var
  Antes: Integer;
  R: TJsonObject;
begin
  Antes := FPosts.Count;
  Check(FIpc.ProcessMessage(AnsiJsonToWide('{"__borion":1,"kind":"invoke","id":2,"cmd":"http:fetch",' +
    '"args":{"rid":"lenta","url":' + JsonQuote(Url('/lento')) + '}}'), 'https://app.localhost/'));
  CheckEquals(Antes, FPosts.Count, 'o fetch é adiado');
  Sleep(300);  { a requisição já está esperando o servidor }
  CheckEquals('true', Ok('http:cancel', '{"rid":"lenta"}'));
  Bombear(Antes + 2, 1500);  { bem antes dos 3 s do /lento }
  CheckEquals(Antes + 2, FPosts.Count, 'o fetch cancelado respondeu');
  R := TJsonObject.Create;
  try
    R.Parse(FPosts[FPosts.Count - 1]);
    Check(not R['ok'].AsBoolean);
    CheckEquals('CANCELED', R['error'].AsObject['code'].AsString);
  finally
    R.Free;
  end;
  CheckEquals('false', Ok('http:cancel', '{"rid":"lenta"}'), 'já terminou');
end;

procedure TTestBorionHttp.TestRespostaGrandeDemais;
begin
  FHttp.MaxResponseSize := 1000;
  CheckEquals('TOO_LARGE', Erro('http:fetch', '{"url":' + JsonQuote(Url('/grande')) + '}'));
end;

procedure TTestBorionHttp.TestConexaoRecusada;
begin
  FHttp.Allow('http://127.0.0.1:1/*');  { porta fechada }
  CheckEquals('NETWORK_ERROR', Erro('http:fetch', '{"url":"http://127.0.0.1:1/x"}'));
end;

initialization
  RegisterTest('Plugins', TTestBorionOs.Suite);
  RegisterTest('Plugins', TTestBorionHttpEscopo.Suite);
  RegisterTest('Plugins', TTestBorionHttp.Suite);

end.
