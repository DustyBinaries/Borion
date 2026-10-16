unit BorionDeepLink;

(*
  Borion — Native Application Engine
  Plugin "deep-link": links meuapp://... abrem o app (como o deep-link do Tauri).

    Ipc.AddPlugin(TBorionSingleInstancePlugin.Create);          // antes: links com o app aberto
    Ipc.AddPlugin(TBorionDeepLinkPlugin.Create(['meuapp']));

  O esquema é registrado em HKCU\Software\Classes\<esquema> ao iniciar
  (AutoRegister), apontando para este exe. Clicar num link meuapp://... abre o
  app com a URL como argumento; com o app já aberto, o single-instance entrega
  a URL à janela aberta e este plugin emite o evento.

  Comandos:
    deep-link:getCurrent           -> [url, ...] desta execução (vazio se não veio de um link)
    deep-link:register   {scheme}  só esquemas passados ao Create
    deep-link:unregister {scheme}  só apaga o registro se ele apontar para este exe
    deep-link:isRegistered {scheme} -> boolean (registrado para este exe)
  Evento:
    deep-link:open {urls}          link aberto com o app já rodando

  As URLs vão como literais JSON só com ASCII (o @borion/api/deep-link
  decodifica). ATENÇÃO: qualquer site pode abrir um link meuapp://; trate a URL
  como entrada não confiável.
*)

interface

uses
  Windows, SysUtils, Classes, Jsons, BorionIpc, BorionSingleInstance;

type
  TBorionOpenUrlEvent = procedure(Sender: TObject; const Urls: TBorionArgs) of object;

  TBorionDeepLinkPlugin = class(TBorionPlugin)
  private
    FSchemes: TStringList;
    FExePath: WideString;
    FDisplayName: string;
    FAutoRegister: Boolean;
    FOnOpenUrl: TBorionOpenUrlEvent;
    FPrevSecond: TBorionSecondInstanceEvent;
    procedure SegundaInstancia(Sender: TObject; const Args: TBorionArgs; const Cwd: WideString);
    function Esquema(Call: TBorionCall): string;
    procedure CmdGetCurrent(Call: TBorionCall);
    procedure CmdRegister(Call: TBorionCall);
    procedure CmdUnregister(Call: TBorionCall);
    procedure CmdIsRegistered(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    { Schemes: os esquemas do app, sem '://' (ex.: 'meuapp') }
    constructor Create(const Schemes: array of string);
    destructor Destroy; override;
    function Name: string; override;
    procedure RegisterScheme(const Scheme: string);
    procedure UnregisterScheme(const Scheme: string);
    function IsRegistered(const Scheme: string): Boolean;
    { As URLs de Args que são de um dos esquemas do app }
    function UrlsIn(const Args: TBorionArgs): TBorionArgs;
    { Entrega URLs como se tivessem chegado agora (evento + OnOpenUrl) }
    procedure OpenUrls(const Urls: TBorionArgs);
    property Schemes: TStringList read FSchemes;
    { Exe que os links abrem (padrão: este) }
    property ExePath: WideString read FExePath write FExePath;
    { Nome mostrado pelo Windows ("URL:<nome>"); padrão: Application.Title }
    property DisplayName: string read FDisplayName write FDisplayName;
    { Registrar os esquemas ao iniciar (padrão: True; mantém o caminho do exe atualizado) }
    property AutoRegister: Boolean read FAutoRegister write FAutoRegister;
    property OnOpenUrl: TBorionOpenUrlEvent read FOnOpenUrl write FOnOpenUrl;
  end;

{ 'meuapp': começa com letra; letras, números, '+', '-' e '.'. Recusa esquemas
  do sistema (http, file, ms-settings...). }
function BorionValidScheme(const Scheme: string): Boolean;

implementation

uses
  Forms, BorionJson, BorionRegistry;

const
  RESERVADOS: array[0..13] of string = ('http', 'https', 'file', 'ftp', 'mailto', 'javascript',
    'data', 'about', 'blob', 'shell', 'vbscript', 'res', 'microsoft-edge', 'search-ms');

function BorionValidScheme(const Scheme: string): Boolean;
var
  I: Integer;
  S: string;
begin
  S := LowerCase(Scheme);
  Result := (S <> '') and (Length(S) <= 64) and (S[1] in ['a'..'z']);
  if not Result then
    Exit;
  for I := 1 to Length(S) do
    if not (S[I] in ['a'..'z', '0'..'9', '+', '-', '.']) then
    begin
      Result := False;
      Exit;
    end;
  for I := Low(RESERVADOS) to High(RESERVADOS) do
    if S = RESERVADOS[I] then
    begin
      Result := False;
      Exit;
    end;
  if Copy(S, 1, 3) = 'ms-' then
    Result := False;
end;

function Chave(const Scheme: string): WideString;
begin
  Result := 'Software\Classes\' + LowerCase(Scheme);
end;

{ TBorionDeepLinkPlugin }

constructor TBorionDeepLinkPlugin.Create(const Schemes: array of string);
var
  I: Integer;
begin
  inherited Create;
  FSchemes := TStringList.Create;
  for I := Low(Schemes) to High(Schemes) do
  begin
    if not BorionValidScheme(Schemes[I]) then
      raise EBorionError.Create('INVALID_SCHEME', 'esquema inválido: ' + Schemes[I]);
    FSchemes.Add(LowerCase(Schemes[I]));
  end;
  FExePath := BorionExePathW;
  FDisplayName := Application.Title;
  FAutoRegister := True;
end;

destructor TBorionDeepLinkPlugin.Destroy;
begin
  FSchemes.Free;
  inherited;
end;

function TBorionDeepLinkPlugin.Name: string;
begin
  Result := 'deep-link';
end;

procedure TBorionDeepLinkPlugin.Install;
var
  I: Integer;
  Unica: TBorionPlugin;
begin
  Command('getCurrent', CmdGetCurrent);
  Command('register', CmdRegister);
  Command('unregister', CmdUnregister);
  Command('isRegistered', CmdIsRegistered);
  if FAutoRegister then
    for I := 0 to FSchemes.Count - 1 do
      try
        RegisterScheme(FSchemes[I]);
      except
        { sem acesso ao registro: o app abre igual, só os links não funcionam }
      end;
  { links abertos com o app rodando chegam pela outra execução }
  Unica := Ipc.FindPlugin('single-instance');
  if Unica <> nil then
  begin
    FPrevSecond := TBorionSingleInstancePlugin(Unica).OnSecondInstance;
    TBorionSingleInstancePlugin(Unica).OnSecondInstance := SegundaInstancia;
  end;
end;

procedure TBorionDeepLinkPlugin.SegundaInstancia(Sender: TObject; const Args: TBorionArgs;
  const Cwd: WideString);
var
  Urls: TBorionArgs;
begin
  if Assigned(FPrevSecond) then
    FPrevSecond(Sender, Args, Cwd);
  Urls := UrlsIn(Args);
  if Length(Urls) > 0 then
    OpenUrls(Urls);
end;

function TBorionDeepLinkPlugin.UrlsIn(const Args: TBorionArgs): TBorionArgs;
var
  I, J: Integer;
  A: string;
begin
  Result := nil;
  for I := 0 to High(Args) do
  begin
    A := LowerCase(string(Copy(Args[I], 1, 70)));
    for J := 0 to FSchemes.Count - 1 do
      if Pos(FSchemes[J] + ':', A) = 1 then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Args[I];
        Break;
      end;
  end;
end;

function UrlsJson(const Urls: TBorionArgs): string;
var
  I: Integer;
begin
  Result := '[';
  for I := 0 to High(Urls) do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + JsonQuote(WideToJsonLiteral(Urls[I]));
  end;
  Result := Result + ']';
end;

procedure TBorionDeepLinkPlugin.OpenUrls(const Urls: TBorionArgs);
begin
  if Ipc <> nil then
    Ipc.EmitJson('deep-link:open', '{"urls":' + UrlsJson(Urls) + '}');
  if Assigned(FOnOpenUrl) then
    FOnOpenUrl(Self, Urls);
end;

procedure TBorionDeepLinkPlugin.RegisterScheme(const Scheme: string);
var
  K: WideString;
begin
  if not BorionValidScheme(Scheme) then
    raise EBorionError.Create('INVALID_SCHEME', 'esquema inválido: ' + Scheme);
  K := Chave(Scheme);
  BorionRegWrite(HKEY_CURRENT_USER, K, '', 'URL:' + FDisplayName);
  BorionRegWrite(HKEY_CURRENT_USER, K, 'URL Protocol', '');
  BorionRegWrite(HKEY_CURRENT_USER, K + '\DefaultIcon', '', '"' + FExePath + '",0');
  BorionRegWrite(HKEY_CURRENT_USER, K + '\shell\open\command', '', '"' + FExePath + '" "%1"');
end;

function TBorionDeepLinkPlugin.IsRegistered(const Scheme: string): Boolean;
var
  Comando: WideString;
begin
  Result := BorionValidScheme(Scheme) and
    BorionRegRead(HKEY_CURRENT_USER, Chave(Scheme) + '\shell\open\command', '', Comando) and
    (Pos(WideLowerCase('"' + FExePath + '"'), WideLowerCase(Comando)) = 1);
end;

procedure TBorionDeepLinkPlugin.UnregisterScheme(const Scheme: string);
begin
  { só apaga o que é deste exe: outro app pode ter o mesmo esquema }
  if IsRegistered(Scheme) then
    BorionRegDeleteTree(HKEY_CURRENT_USER, Chave(Scheme));
end;

function TBorionDeepLinkPlugin.Esquema(Call: TBorionCall): string;
begin
  Result := LowerCase(Call.ArgStr('scheme'));
  if Pos('://', Result) > 0 then
    SetLength(Result, Pos('://', Result) - 1);
  if FSchemes.IndexOf(Result) < 0 then
    raise EBorionError.Create('FORBIDDEN_SCHEME',
      'esquema não declarado no Delphi (TBorionDeepLinkPlugin.Create): ' + Call.ArgStr('scheme'));
end;

procedure TBorionDeepLinkPlugin.CmdGetCurrent(Call: TBorionCall);
var
  O: TJsonArray;
begin
  O := TJsonArray.Create;
  try
    O.Parse(UrlsJson(UrlsIn(BorionCommandLineArgs)));  { só ASCII: o Parse não perde nada }
    Call.Result.AsArray := O;
  finally
    O.Free;
  end;
end;

procedure TBorionDeepLinkPlugin.CmdRegister(Call: TBorionCall);
begin
  RegisterScheme(Esquema(Call));
end;

procedure TBorionDeepLinkPlugin.CmdUnregister(Call: TBorionCall);
begin
  UnregisterScheme(Esquema(Call));
end;

procedure TBorionDeepLinkPlugin.CmdIsRegistered(Call: TBorionCall);
begin
  Call.Result.AsBoolean := IsRegistered(Esquema(Call));
end;

end.
