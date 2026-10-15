unit BorionHttp;

(*
  Borion — Native Application Engine
  Plugin "http": requisições HTTP/HTTPS feitas pelo Delphi (WinInet), sem as
  restrições de CORS do navegador.

    Http := TBorionHttpPlugin(Ipc.AddPlugin(TBorionHttpPlugin.Create));
    Http.Allow('https://api.github.com/*');     // escopo: tudo negado por padrão
    Http.Allow('https://*.exemplo.com.br');     // sem caminho = o host inteiro

  Comandos:
    http:fetch  {rid, url, method?, headers?: [[nome, valor], ...], body? (base64),
                 timeout? (ms), redirect?: 'follow' | 'manual' | 'error',
                 maxRedirections? (padrão 10)}
                -> {status, statusText, url, redirected, headers: [[nome, valor], ...],
                    body (base64)}
    http:cancel {rid}   cancela a requisição: o fetch rejeita com CANCELED

  Cada requisição roda numa thread própria; a interface não trava. Os
  redirecionamentos são seguidos aqui, não pelo WinInet, para que cada destino
  passe pelo escopo (um redirect para fora dele rejeita com FORBIDDEN_URL) e o
  Authorization não vá para outro host.

  Erros: INVALID_URL, FORBIDDEN_URL, TIMEOUT, CANCELED, TOO_MANY_REDIRECTS,
  TOO_LARGE, NETWORK_ERROR (DNS, conexão, certificado...).
*)

interface

uses
  Windows, Messages, SysUtils, Classes, WinInet, Jsons, BorionIpc;

type
  TBorionHttpPlugin = class;

  { Uma URL quebrada nas partes que o escopo compara }
  TBorionUrl = record
    Scheme: string;  { 'http' ou 'https' }
    Host: string;    { minúsculo }
    Port: Integer;
    Path: string;    { caminho + query, começando com '/' }
  end;

  TBorionHttpRequest = class(TThread)
  private
    FWindow: HWND;
    FPatterns: TStringList;
    FCall: TBorionCall;
    FRid: string;
    FUrl, FMethod, FHeaders, FBody: string;
    FTimeout: Cardinal;
    FRedirect: string;
    FMaxRedirections: Integer;
    FMaxSize: Integer;
    FLock: TRTLCriticalSection;
    FNet: HINTERNET;
    FCanceled: Boolean;
    FTimedOut: Boolean;
    FTimerId: Cardinal;
    { resultado }
    FStatus: Integer;
    FStatusText, FFinalUrl, FRespHeaders, FRespBody: string;
    FRedirected: Boolean;
    FErrorCode, FErrorMessage: string;
    procedure Falhar(const Code, Msg: string);
    procedure FalhaDoWinInet(const Etapa: string);
    function Requisitar(var Url, Method, Headers, Body: string): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(Plugin: TBorionHttpPlugin; Call: TBorionCall);
    destructor Destroy; override;
    procedure Cancel;
  end;

  TBorionHttpPlugin = class(TBorionPlugin)
  private
    FPatterns: TStringList;
    FRequests: TList;
    FWindow: HWND;
    FMaxResponseSize: Integer;
    FUserAgent: string;
    FProximoTimer: Cardinal;
    procedure WndProc(var Message: TMessage);
    procedure Terminou(R: TBorionHttpRequest);
    procedure TempoEsgotado(TimerId: Cardinal);
    procedure CmdFetch(Call: TBorionCall);
    procedure CmdCancel(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    constructor Create;
    destructor Destroy; override;
    function Name: string; override;
    { Libera URLs: 'https://api.exemplo.com/*', 'https://*.exemplo.com',
      'http://localhost:5000/api/*'. '*' no host vale só dentro do host. Sem
      porta = a porta padrão do esquema; ':*' = qualquer porta. Sem caminho = '/*'. }
    procedure Allow(const Pattern: string);
    function IsAllowed(const Url: string): Boolean;
    property Patterns: TStringList read FPatterns;
    { Tamanho máximo da resposta (padrão 50 MB): acima disso, TOO_LARGE }
    property MaxResponseSize: Integer read FMaxResponseSize write FMaxResponseSize;
    property UserAgent: string read FUserAgent write FUserAgent;
  end;

{ Quebra e valida uma URL http(s) absoluta (sem usuário/senha). False se inválida. }
function BorionParseUrl(const Url: string; out Parts: TBorionUrl): Boolean;
{ True se Url casa com o padrão (veja TBorionHttpPlugin.Allow) }
function BorionUrlMatches(const Pattern: string; const Url: TBorionUrl): Boolean;
{ Casamento com '*' (qualquer sequência, inclusive vazia) }
function BorionWildcardMatch(const Pattern, Text: string): Boolean;

implementation

uses
  BorionJson, BorionFs;

const
  WM_BORION_HTTP = WM_USER + 30;
  INTERNET_OPTION_HTTP_DECODING = 65;
  HTTP_QUERY_LOCATION_ = 33;
  HTTP_QUERY_STATUS_TEXT_ = 20;

function BorionWildcardMatch(const Pattern, Text: string): Boolean;
var
  P, T, Estrela, Volta: Integer;
begin
  { guloso com retrocesso: O(n*m) no pior caso, sem recursão }
  P := 1;
  T := 1;
  Estrela := 0;
  Volta := 0;
  while T <= Length(Text) do
  begin
    if (P <= Length(Pattern)) and (Pattern[P] <> '*') and (Pattern[P] = Text[T]) then
    begin
      Inc(P);
      Inc(T);
    end
    else if (P <= Length(Pattern)) and (Pattern[P] = '*') then
    begin
      Estrela := P;
      Volta := T;
      Inc(P);
    end
    else if Estrela > 0 then
    begin
      P := Estrela + 1;
      Inc(Volta);
      T := Volta;
    end
    else
    begin
      Result := False;
      Exit;
    end;
  end;
  while (P <= Length(Pattern)) and (Pattern[P] = '*') do
    Inc(P);
  Result := P > Length(Pattern);
end;

function PortaPadrao(const Scheme: string): Integer;
begin
  if Scheme = 'https' then
    Result := 443
  else
    Result := 80;
end;

function BorionParseUrl(const Url: string; out Parts: TBorionUrl): Boolean;
var
  C: TURLComponents;
  Scheme, Host, User, Pass, Path, Extra: array[0..2047] of Char;
  I: Integer;
begin
  Result := False;
  if (Url = '') or (Length(Url) > 8000) then
    Exit;
  for I := 1 to Length(Url) do
    if (Url[I] <= ' ') or (Url[I] > '~') then
      Exit;  { o @borion/api manda a URL já codificada (new URL().href) }
  FillChar(C, SizeOf(C), 0);
  C.dwStructSize := SizeOf(C);
  C.lpszScheme := Scheme;
  C.dwSchemeLength := SizeOf(Scheme);
  C.lpszHostName := Host;
  C.dwHostNameLength := SizeOf(Host);
  C.lpszUserName := User;
  C.dwUserNameLength := SizeOf(User);
  C.lpszPassword := Pass;
  C.dwPasswordLength := SizeOf(Pass);
  C.lpszUrlPath := Path;
  C.dwUrlPathLength := SizeOf(Path);
  C.lpszExtraInfo := Extra;
  C.dwExtraInfoLength := SizeOf(Extra);
  if not InternetCrackUrl(PChar(Url), Length(Url), 0, C) then
    Exit;
  Parts.Scheme := LowerCase(Scheme);
  if (Parts.Scheme <> 'http') and (Parts.Scheme <> 'https') then
    Exit;
  if (C.dwUserNameLength > 0) or (C.dwPasswordLength > 0) or (C.dwHostNameLength = 0) then
    Exit;  { https://api.ok.com@outro.com/ não engana o escopo }
  { a URL tem de começar exatamente por esquema://host: nada de barras invertidas }
  if Pos(Parts.Scheme + '://', LowerCase(Url)) <> 1 then
    Exit;
  Parts.Host := LowerCase(Host);
  for I := 1 to Length(Parts.Host) do
    if not (Parts.Host[I] in ['a'..'z', '0'..'9', '.', '-', '_', '[', ']', ':']) then
      Exit;
  Parts.Port := C.nPort;
  if Parts.Port = 0 then
    Parts.Port := PortaPadrao(Parts.Scheme);
  Parts.Path := string(Path) + string(Extra);
  I := Pos('#', Parts.Path);  { o fragmento não vai para o servidor }
  if I > 0 then
    SetLength(Parts.Path, I - 1);
  if Parts.Path = '' then
    Parts.Path := '/';
  Result := Parts.Path[1] = '/';
end;

function BorionUrlMatches(const Pattern: string; const Url: TBorionUrl): Boolean;
var
  P, Scheme, HostPorta, Host, Porta, Path: string;
  I: Integer;
begin
  Result := False;
  P := Pattern;
  I := Pos('://', P);
  if I = 0 then
    Exit;
  Scheme := LowerCase(Copy(P, 1, I - 1));
  Delete(P, 1, I + 2);
  I := Pos('/', P);
  if I = 0 then
  begin
    HostPorta := P;
    Path := '/*';
  end
  else
  begin
    HostPorta := Copy(P, 1, I - 1);
    Path := Copy(P, I, MaxInt);
  end;
  HostPorta := LowerCase(HostPorta);
  I := LastDelimiter(':]', HostPorta);
  if (I > 0) and (HostPorta[I] = ':') then
  begin
    Host := Copy(HostPorta, 1, I - 1);
    Porta := Copy(HostPorta, I + 1, MaxInt);
  end
  else
  begin
    Host := HostPorta;
    Porta := '';
  end;
  if Scheme <> Url.Scheme then
    Exit;
  if Porta = '' then
  begin
    if Url.Port <> PortaPadrao(Url.Scheme) then
      Exit;
  end
  else if (Porta <> '*') and (StrToIntDef(Porta, -1) <> Url.Port) then
    Exit;
  Result := BorionWildcardMatch(Host, Url.Host) and BorionWildcardMatch(Path, Url.Path);
end;

function Permitido(Patterns: TStrings; const Url: TBorionUrl): Boolean;
var
  I: Integer;
begin
  for I := 0 to Patterns.Count - 1 do
    if BorionUrlMatches(Patterns[I], Url) then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

function MesmaOrigem(const A, B: TBorionUrl): Boolean;
begin
  Result := (A.Scheme = B.Scheme) and (A.Host = B.Host) and (A.Port = B.Port);
end;

{ Tira um cabeçalho (nome sem diferenciar maiúsculas) do bloco 'Nome: valor'#13#10... }
function SemCabecalho(const Headers, Nome: string): string;
var
  L: TStringList;
  I: Integer;
begin
  L := TStringList.Create;
  try
    L.Text := Headers;
    for I := L.Count - 1 downto 0 do
      if SameText(Trim(Copy(L[I], 1, Pos(':', L[I]) - 1)), Nome) then
        L.Delete(I);
    Result := L.Text;
  finally
    L.Free;
  end;
end;

function EhRedirect(Status: Integer): Boolean;
begin
  case Status of
    301, 302, 303, 307, 308: Result := True;
  else
    Result := False;
  end;
end;

function TemCabecalho(const Headers, Nome: string): Boolean;
begin
  Result := SemCabecalho(Headers, Nome) <> Headers;
end;

{ TBorionHttpRequest }

constructor TBorionHttpRequest.Create(Plugin: TBorionHttpPlugin; Call: TBorionCall);
var
  H: TJsonValue;
  Par: TJsonArray;
  I: Integer;
  Nome, Valor: string;
begin
  inherited Create(True);
  InitializeCriticalSection(FLock);
  FWindow := Plugin.FWindow;
  FPatterns := TStringList.Create;
  FPatterns.Assign(Plugin.FPatterns);  { cópia: a thread não lê o plugin }
  FMaxSize := Plugin.FMaxResponseSize;
  FCall := Call;
  FRid := Call.ArgStr('rid');
  FUrl := Call.ArgStr('url');
  FMethod := UpperCase(Call.ArgStr('method', 'GET'));
  FTimeout := Call.ArgInt('timeout', 0);
  FRedirect := Call.ArgStr('redirect', 'follow');
  FMaxRedirections := Call.ArgInt('maxRedirections', 10);
  if Call.HasArg('body') and (Call.Arg('body').ValueType = jvString) then
    FBody := BorionBase64Decode(Call.ArgStr('body'));
  H := Call.Arg('headers');
  if (H <> nil) and (H.ValueType = jvArray) then
    for I := 0 to H.AsArray.Count - 1 do
    begin
      if H.AsArray[I].ValueType <> jvArray then
        raise EBorionError.Create('INVALID_ARGS', 'headers deve ser uma lista de [nome, valor]');
      Par := H.AsArray[I].AsArray;
      if Par.Count <> 2 then
        raise EBorionError.Create('INVALID_ARGS', 'headers deve ser uma lista de [nome, valor]');
      Nome := Par[0].AsString;
      Valor := Par[1].AsString;
      { quebra de linha num cabeçalho injetaria outros cabeçalhos }
      if (Nome = '') or (LastDelimiter(#13#10':', Nome) > 0) or (LastDelimiter(#13#10, Valor) > 0) then
        raise EBorionError.Create('INVALID_ARGS', 'cabeçalho inválido: ' + Nome);
      FHeaders := FHeaders + Nome + ': ' + Valor + #13#10;
    end;
  if Plugin.FUserAgent <> '' then
    FHeaders := SemCabecalho(FHeaders, 'User-Agent') + 'User-Agent: ' + Plugin.FUserAgent + #13#10;
  if not TemCabecalho(FHeaders, 'Accept-Encoding') then
    FHeaders := FHeaders + 'Accept-Encoding: gzip, deflate'#13#10;  { o WinInet descompacta }
  if FMethod = '' then
    FMethod := 'GET';
  for I := 1 to Length(FMethod) do
    if not (FMethod[I] in ['A'..'Z', '-', '_']) then
      raise EBorionError.Create('INVALID_ARGS', 'método inválido: ' + FMethod);
end;

destructor TBorionHttpRequest.Destroy;
begin
  if FNet <> nil then
    InternetCloseHandle(FNet);
  FPatterns.Free;
  DeleteCriticalSection(FLock);
  inherited;
end;

procedure TBorionHttpRequest.Cancel;
begin
  EnterCriticalSection(FLock);
  try
    FCanceled := True;
    { fechar a raiz aborta o que estiver bloqueado (conexão, envio, leitura) }
    if FNet <> nil then
    begin
      InternetCloseHandle(FNet);
      FNet := nil;
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TBorionHttpRequest.Falhar(const Code, Msg: string);
begin
  if FErrorCode = '' then
  begin
    FErrorCode := Code;
    FErrorMessage := Msg;
  end;
end;

procedure TBorionHttpRequest.FalhaDoWinInet(const Etapa: string);
var
  Erro: DWORD;
  Buf: array[0..1023] of Char;
  Texto: string;
begin
  Erro := GetLastError;
  if FCanceled then
  begin
    Falhar('CANCELED', 'requisição cancelada');
    Exit;
  end;
  if Erro = ERROR_INTERNET_TIMEOUT then
  begin
    Falhar('TIMEOUT', 'tempo esgotado (' + Etapa + ')');
    Exit;
  end;
  if FormatMessage(FORMAT_MESSAGE_FROM_HMODULE or FORMAT_MESSAGE_IGNORE_INSERTS,
    Pointer(GetModuleHandle('wininet.dll')), Erro, 0, Buf, SizeOf(Buf), nil) > 0 then
    Texto := Trim(Buf)
  else
    Texto := SysErrorMessage(Erro);
  Falhar('NETWORK_ERROR', Format('%s: %s (%d)', [Etapa, Texto, Erro]));
end;

{ Uma ida ao servidor. True se terminou (resposta final ou erro); False se
  houve um redirect a seguir (Url, Method, Headers e Body já atualizados). }
function TBorionHttpRequest.Requisitar(var Url, Method, Headers, Body: string): Boolean;
var
  Partes, Destino: TBorionUrl;
  Conn, Req: HINTERNET;
  Flags, N, Reservado, Lidos: DWORD;
  Ligado: BOOL;
  Buf: array[0..65535] of Char;
  Local, Nova: string;
  Combinada: array[0..8191] of Char;
begin
  Result := True;
  if not BorionParseUrl(Url, Partes) then
  begin
    Falhar('INVALID_URL', 'URL inválida (só http e https absolutos): ' + Url);
    Exit;
  end;
  if not Permitido(FPatterns, Partes) then
  begin
    Falhar('FORBIDDEN_URL', 'URL fora do escopo do plugin http: ' + Url);
    Exit;
  end;

  Conn := InternetConnect(FNet, PChar(Partes.Host), Partes.Port, nil, nil, INTERNET_SERVICE_HTTP, 0, 0);
  if Conn = nil then
  begin
    FalhaDoWinInet('conexão');
    Exit;
  end;
  try
    Flags := INTERNET_FLAG_NO_AUTO_REDIRECT or INTERNET_FLAG_NO_COOKIES or
      INTERNET_FLAG_NO_CACHE_WRITE or INTERNET_FLAG_RELOAD or INTERNET_FLAG_PRAGMA_NOCACHE or
      INTERNET_FLAG_NO_UI or INTERNET_FLAG_KEEP_CONNECTION;
    if Partes.Scheme = 'https' then
      Flags := Flags or INTERNET_FLAG_SECURE;
    Req := HttpOpenRequest(Conn, PChar(Method), PChar(Partes.Path), nil, nil, nil, Flags, 0);
    if Req = nil then
    begin
      FalhaDoWinInet('requisição');
      Exit;
    end;
    try
      Ligado := True;
      InternetSetOption(Req, INTERNET_OPTION_HTTP_DECODING, @Ligado, SizeOf(Ligado));
      if not HttpSendRequest(Req, PChar(Headers), Length(Headers), Pointer(Body), Length(Body)) then
      begin
        FalhaDoWinInet('envio');
        Exit;
      end;

      N := SizeOf(FStatus);
      Reservado := 0;
      FStatus := 0;
      HttpQueryInfo(Req, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @FStatus, N, Reservado);

      { redirect: seguido aqui, passando o destino pelo escopo }
      if EhRedirect(FStatus) and (FRedirect <> 'manual') then
      begin
        N := SizeOf(Buf);
        Reservado := 0;
        if HttpQueryInfo(Req, HTTP_QUERY_LOCATION_, @Buf, N, Reservado) then
        begin
          if FRedirect = 'error' then
          begin
            Falhar('REDIRECT', 'a resposta é um redirecionamento (redirect: ''error'')');
            Exit;
          end;
          Local := Buf;
          N := SizeOf(Combinada);
          if InternetCombineUrl(PChar(Url), PChar(Local), Combinada, N, ICU_NO_ENCODE) then
            Nova := Combinada
          else
            Nova := Local;
          if not BorionParseUrl(Nova, Destino) then
          begin
            Falhar('INVALID_URL', 'redirecionamento para uma URL inválida: ' + Nova);
            Exit;
          end;
          if (FStatus = 303) or (((FStatus = 301) or (FStatus = 302)) and (Method = 'POST')) then
          begin
            Method := 'GET';
            Body := '';
            Headers := SemCabecalho(SemCabecalho(Headers, 'Content-Type'), 'Content-Length');
          end;
          if not MesmaOrigem(Partes, Destino) then
            Headers := SemCabecalho(SemCabecalho(Headers, 'Authorization'), 'Cookie');
          Url := Nova;
          FRedirected := True;
          Result := False;
          Exit;
        end;
      end;

      N := SizeOf(Buf);
      Reservado := 0;
      if HttpQueryInfo(Req, HTTP_QUERY_STATUS_TEXT_, @Buf, N, Reservado) then
        FStatusText := Buf;
      N := SizeOf(Buf);
      Reservado := 0;
      if HttpQueryInfo(Req, HTTP_QUERY_RAW_HEADERS_CRLF, @Buf, N, Reservado) then
        SetString(FRespHeaders, Buf, N)
      else if GetLastError = ERROR_INSUFFICIENT_BUFFER then
      begin
        SetLength(FRespHeaders, N);
        Reservado := 0;
        if not HttpQueryInfo(Req, HTTP_QUERY_RAW_HEADERS_CRLF, Pointer(FRespHeaders), N, Reservado) then
          FRespHeaders := '';
        SetLength(FRespHeaders, N);
      end;

      FRespBody := '';
      repeat
        if not InternetReadFile(Req, @Buf, SizeOf(Buf), Lidos) then
        begin
          FalhaDoWinInet('leitura');
          Exit;
        end;
        if Lidos > 0 then
        begin
          if Length(FRespBody) + Integer(Lidos) > FMaxSize then
          begin
            Falhar('TOO_LARGE', Format('resposta maior que %d bytes', [FMaxSize]));
            Exit;
          end;
          SetLength(FRespBody, Length(FRespBody) + Integer(Lidos));
          Move(Buf, FRespBody[Length(FRespBody) - Integer(Lidos) + 1], Lidos);
        end;
      until Lidos = 0;
      FFinalUrl := Url;
    finally
      if not FCanceled then
        InternetCloseHandle(Req);
    end;
  finally
    if not FCanceled then
      InternetCloseHandle(Conn);
  end;
end;

procedure TBorionHttpRequest.Execute;
var
  Url, Method, Headers, Body: string;
  Redirs: Integer;
  T: DWORD;
begin
  try
    EnterCriticalSection(FLock);
    try
      if not FCanceled then
        FNet := InternetOpen('Borion', INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
    finally
      LeaveCriticalSection(FLock);
    end;
    if FCanceled then
      Falhar('CANCELED', 'requisição cancelada')
    else if FNet = nil then
      FalhaDoWinInet('WinInet')
    else
    begin
      if FTimeout > 0 then
      begin
        T := FTimeout;
        InternetSetOption(FNet, INTERNET_OPTION_CONNECT_TIMEOUT, @T, SizeOf(T));
        InternetSetOption(FNet, INTERNET_OPTION_SEND_TIMEOUT, @T, SizeOf(T));
        InternetSetOption(FNet, INTERNET_OPTION_RECEIVE_TIMEOUT, @T, SizeOf(T));
      end;
      Url := FUrl;
      Method := FMethod;
      Headers := FHeaders;
      Body := FBody;
      Redirs := 0;
      while not Requisitar(Url, Method, Headers, Body) do
      begin
        Inc(Redirs);
        if Redirs > FMaxRedirections then
        begin
          Falhar('TOO_MANY_REDIRECTS', Format('mais de %d redirecionamentos', [FMaxRedirections]));
          Break;
        end;
      end;
    end;
  except
    on E: Exception do
      Falhar('NETWORK_ERROR', E.Message);
  end;
  if FTimedOut then
  begin
    FErrorCode := 'TIMEOUT';
    FErrorMessage := Format('tempo esgotado (%d ms)', [FTimeout]);
  end
  else if FCanceled then
  begin
    FErrorCode := 'CANCELED';
    FErrorMessage := 'requisição cancelada';
  end;
  PostMessage(FWindow, WM_BORION_HTTP, 0, LPARAM(Self));
end;

{ TBorionHttpPlugin }

constructor TBorionHttpPlugin.Create;
begin
  inherited Create;
  FPatterns := TStringList.Create;
  FRequests := TList.Create;
  FMaxResponseSize := 50 * 1024 * 1024;
  FWindow := Classes.AllocateHWnd(WndProc);
end;

destructor TBorionHttpPlugin.Destroy;
var
  I: Integer;
  R: TBorionHttpRequest;
begin
  for I := 0 to FRequests.Count - 1 do
  begin
    R := TBorionHttpRequest(FRequests[I]);
    if R.FTimerId <> 0 then
      KillTimer(FWindow, R.FTimerId);
    R.Cancel;
  end;
  for I := 0 to FRequests.Count - 1 do
  begin
    R := TBorionHttpRequest(FRequests[I]);
    R.WaitFor;
    R.FCall.Reject('o plugin http foi destruído', 'CANCELED');  { chamada órfã: só se libera }
    R.Free;
  end;
  FRequests.Free;
  Classes.DeallocateHWnd(FWindow);
  FPatterns.Free;
  inherited;
end;

function TBorionHttpPlugin.Name: string;
begin
  Result := 'http';
end;

procedure TBorionHttpPlugin.Install;
begin
  Command('fetch', CmdFetch);
  Command('cancel', CmdCancel);
end;

procedure TBorionHttpPlugin.Allow(const Pattern: string);
begin
  if Pos('://', Pattern) = 0 then
    raise EBorionError.Create('INVALID_PATTERN', 'padrão de URL inválido: ' + Pattern);
  FPatterns.Add(Pattern);
end;

function TBorionHttpPlugin.IsAllowed(const Url: string): Boolean;
var
  Partes: TBorionUrl;
begin
  Result := BorionParseUrl(Url, Partes) and Permitido(FPatterns, Partes);
end;

procedure TBorionHttpPlugin.CmdFetch(Call: TBorionCall);
var
  R: TBorionHttpRequest;
  Partes: TBorionUrl;
begin
  { o que dá para recusar na hora, recusa sem criar thread }
  if not BorionParseUrl(Call.ArgStr('url'), Partes) then
    raise EBorionError.Create('INVALID_URL', 'URL inválida (só http e https absolutos): ' + Call.ArgStr('url'));
  if not Permitido(FPatterns, Partes) then
    raise EBorionError.Create('FORBIDDEN_URL', 'URL fora do escopo do plugin http: ' + Call.ArgStr('url'));
  R := TBorionHttpRequest.Create(Self, Call);
  Call.Defer;
  FRequests.Add(R);
  { o timeout do WinInet não vale enquanto espera a resposta: o plugin mede o
    tempo total e cancela a requisição quando ele acaba }
  if R.FTimeout > 0 then
  begin
    Inc(FProximoTimer);
    R.FTimerId := FProximoTimer;
    SetTimer(FWindow, R.FTimerId, R.FTimeout, nil);
  end;
  R.Resume;
end;

procedure TBorionHttpPlugin.CmdCancel(Call: TBorionCall);
var
  I: Integer;
  R: TBorionHttpRequest;
begin
  for I := 0 to FRequests.Count - 1 do
  begin
    R := TBorionHttpRequest(FRequests[I]);
    if (R.FRid <> '') and (R.FRid = Call.ArgStr('rid')) then
    begin
      R.Cancel;
      Call.Result.AsBoolean := True;
      Exit;
    end;
  end;
  Call.Result.AsBoolean := False;  { já terminou (ou nunca existiu) }
end;

procedure TBorionHttpPlugin.WndProc(var Message: TMessage);
begin
  if Message.Msg = WM_BORION_HTTP then
    Terminou(TBorionHttpRequest(Message.LParam))
  else if Message.Msg = WM_TIMER then
    TempoEsgotado(Message.WParam)
  else
    Message.Result := DefWindowProc(FWindow, Message.Msg, Message.WParam, Message.LParam);
end;

procedure TBorionHttpPlugin.TempoEsgotado(TimerId: Cardinal);
var
  I: Integer;
  R: TBorionHttpRequest;
begin
  KillTimer(FWindow, TimerId);
  for I := 0 to FRequests.Count - 1 do
  begin
    R := TBorionHttpRequest(FRequests[I]);
    if R.FTimerId = TimerId then
    begin
      R.FTimedOut := True;
      R.Cancel;
      Exit;
    end;
  end;
end;

procedure TBorionHttpPlugin.Terminou(R: TBorionHttpRequest);
var
  O: TJsonObject;
  Lista, Par: TJsonArray;
  Linhas: TStringList;
  I, P: Integer;
begin
  I := FRequests.IndexOf(R);
  if I < 0 then
    Exit;
  FRequests.Delete(I);
  if R.FTimerId <> 0 then
    KillTimer(FWindow, R.FTimerId);
  R.WaitFor;
  try
    if R.FErrorCode <> '' then
      R.FCall.Reject(R.FErrorMessage, R.FErrorCode)
    else
    begin
      O := R.FCall.Result.AsObject;
      O.Put('status', R.FStatus);
      O.Put('statusText', R.FStatusText);
      O.Put('url', R.FFinalUrl);
      O.Put('redirected', R.FRedirected);
      Lista := O.Add('headers').Value.AsArray;
      Linhas := TStringList.Create;
      try
        Linhas.Text := R.FRespHeaders;
        for I := 1 to Linhas.Count - 1 do  { a primeira é a linha de status }
        begin
          P := Pos(':', Linhas[I]);
          if P <= 1 then
            Continue;
          Par := Lista.Add.AsArray;
          Par.Put(Trim(Copy(Linhas[I], 1, P - 1)));
          Par.Put(Trim(Copy(Linhas[I], P + 1, MaxInt)));
        end;
      finally
        Linhas.Free;
      end;
      O.Put('body', BorionBase64Encode(R.FRespBody));
      R.FCall.Resolve;
    end;
  finally
    R.Free;
  end;
end;

end.
