unit BorionIpc;

(*
  Borion — Native Application Engine
  IPC entre a página (JavaScript) e o Delphi, no estilo do Tauri:

    JS:     const soma = await borion.invoke('somar', { a: 20, b: 22 });
    Delphi: Ipc.RegisterCommand('somar', CmdSomar);

            procedure TForm1.CmdSomar(Call: TBorionCall);
            begin
              Call.Result.AsNumber := Call.ArgNum('a') + Call.ArgNum('b');
            end;

  Eventos nos dois sentidos:
    Delphi -> JS:  Ipc.Emit('progresso', Payload)   /  borion.listen('progresso', cb)
    JS -> Delphi:  borion.emit('salvou', {...})      /  Ipc.Listen('salvou', Handler)

  Transporte: chrome.webview.postMessage (JS -> Delphi) e PostWebMessageAsJson
  (Delphi -> JS), com um id de correlação por invoke. As mensagens do Borion
  levam "__borion": 1; as demais seguem para o OnWebMessageReceived do browser.

  Protocolo:
    JS -> Delphi  {"__borion":1,"kind":"invoke","id":7,"cmd":"somar","args":{...}}
                  {"__borion":1,"kind":"emit","event":"x","payload":...}
    Delphi -> JS  {"__borion":1,"kind":"response","id":7,"ok":true,"result":...}
                  {"__borion":1,"kind":"response","id":7,"ok":false,
                   "error":{"code":"...","message":"..."}}
                  {"__borion":1,"kind":"event","event":"x","payload":...}

  Segurança: só documentos de origens liberadas com AllowOrigin podem chamar
  comandos ou emitir eventos (negado por padrão).
*)

interface

uses
  Windows, Messages, SysUtils, Classes, Jsons, WebView2Browser;

const
  BORION_VERSION = '0.1.0';

type
  TBorionIpc = class;

  { Erro com código, devolvido ao JS como error.code }
  EBorionError = class(Exception)
  private
    FCode: string;
  public
    constructor Create(const ACode, AMessage: string);
    property Code: string read FCode;
  end;

  { Uma chamada de invoke(). Por padrão a resposta é enviada quando o handler
    retorna. Para responder depois (ex.: de uma thread), chame Defer no handler
    e, mais tarde, Resolve ou Reject. Resolve/Reject podem ser chamados de
    qualquer thread. }
  TBorionCall = class
  private
    FIpc: TBorionIpc;
    FId: string;
    FCommand: string;
    FSource: WideString;
    FArgs: TJsonObject;
    FResult: TJsonValue;
    FDeferred: Boolean;
    FFinished: Boolean;
    FInHandler: Boolean;
    FErrorCode: string;
    FErrorMessage: string;
    FWindow: string;
    procedure Finish;
  public
    constructor Create(AIpc: TBorionIpc; const AId, ACommand: string; const ASource: WideString);
    destructor Destroy; override;

    function HasArg(const Name: string): Boolean;
    { nil se o argumento não existir }
    function Arg(const Name: string): TJsonValue;
    function ArgStr(const Name: string; const Default: string = ''): string;
    function ArgInt(const Name: string; Default: Integer = 0): Integer;
    function ArgNum(const Name: string; Default: Extended = 0): Extended;
    function ArgBool(const Name: string; Default: Boolean = False): Boolean;

    { A resposta será enviada depois, por Resolve ou Reject }
    procedure Defer;
    { Envia Result (chamada adiada); numa chamada normal não é necessário }
    procedure Resolve;
    { Rejeita a Promise no JS com error.code / error.message }
    procedure Reject(const Msg: string; const Code: string = 'ERROR');

    { nil se o TBorionIpc já foi destruído (chamada adiada órfã) }
    property Ipc: TBorionIpc read FIpc;
    property Command: string read FCommand;
    { URL do documento que chamou }
    property Source: WideString read FSource;
    { Rótulo da janela que chamou ('main' na principal); a resposta volta para ela }
    property Window: string read FWindow;
    { O browser dessa janela (nil se ela já fechou, ou num IPC sem browser) }
    function Browser: TWebView2Browser;
    property Args: TJsonObject read FArgs;
    { Valor devolvido ao JS. Começa null; use AsString, AsNumber, AsObject, AsArray... }
    property Result: TJsonValue read FResult;
    property Deferred: Boolean read FDeferred;
  end;

  TBorionCommandMethod = procedure(Call: TBorionCall) of object;
  TBorionCommandProc = procedure(Call: TBorionCall);
  { Payload pertence ao Borion e só vale durante a chamada }
  TBorionEventMethod = procedure(const Event: string; Payload: TJsonValue) of object;
  TBorionLogEvent = procedure(Sender: TObject; const Msg: string) of object;
  TBorionPostEvent = procedure(Sender: TObject; const Json: WideString) of object;
  { WindowLabel: a janela de destino, ou '*' para todas }
  TBorionPostToEvent = procedure(Sender: TObject; const WindowLabel: string; const Json: WideString) of object;

  { Base dos plugins: um conjunto de comandos com o prefixo do plugin
    ('fs:readTextFile'). Registre com Ipc.AddPlugin; o TBorionIpc vira o dono. }
  TBorionPlugin = class
  private
    FIpc: TBorionIpc;
    FLater: TStringList;  { comando -> handler rodado pelo Ipc.Later }
    procedure DispatchLater(Call: TBorionCall);
  protected
    { Registra '<Name>:<Comando>' }
    procedure Command(const Comando: string; Handler: TBorionCommandMethod);
    { Como Command, mas o handler roda fora do callback do WebView2 (ver
      TBorionIpc.Later). Para o que abre janelas modais, como diálogos. }
    procedure CommandLater(const Comando: string; Handler: TBorionCommandMethod);
    { Registra os comandos (chamado pelo AddPlugin) }
    procedure Install; virtual; abstract;
    { Uma janela passou a usar o IPC (Ipc.AddWindow) ou saiu dele. Para os
      plugins que acompanham cada janela, como o window. O Install não recebe
      as janelas que já existiam: percorra Ipc.WindowCount, se precisar. }
    procedure WindowAdded(const WindowLabel: string; ABrowser: TWebView2Browser); virtual;
    procedure WindowRemoved(const WindowLabel: string; ABrowser: TWebView2Browser); virtual;
  public
    destructor Destroy; override;
    { Prefixo dos comandos, ex.: 'fs' }
    function Name: string; virtual; abstract;
    property Ipc: TBorionIpc read FIpc;
  end;

  { O IPC de um app: comandos, eventos e plugins registrados uma vez, servindo
    uma ou mais janelas (cada uma um browser com um rótulo). Cada chamada sabe
    de que janela veio (TBorionCall.Window), e a resposta volta só para ela. }
  TBorionIpc = class(TComponent)
  private
    FWindows: TStringList;   { rótulo -> TWebView2Browser, na ordem em que entraram }
    FCurrentWindow: string;
    FOnPostTo: TBorionPostToEvent;
    FCommands: TStringList;
    FListeners: TList;
    FOrigins: TStringList;
    FPending: TList;
    FWindow: HWND;
    FOnLog: TBorionLogEvent;
    FOnPost: TBorionPostEvent;
    FPlugins: TList;
    FScope: TObject;
    procedure WebMessageJson(Sender: TObject; const Json, Source: WideString; var Handled: Boolean);
    procedure HandleInvoke(Msg: TJsonObject; const Source: WideString; const WindowLabel: string);
    procedure HandleEmit(Msg: TJsonObject; const Source: WideString; const WindowLabel: string);
    procedure HandleEmitTo(Msg: TJsonObject; const Source: WideString);
    procedure SendResponse(Call: TBorionCall);
    { Target '' = todas as janelas }
    procedure PostJson(const Json, Target: string);
    procedure SoltarJanela(I: Integer; Destruindo: Boolean);
    function GetBrowser: TWebView2Browser;
    procedure WndProc(var Message: TMessage);
    procedure RunLater(P: Pointer);
    procedure Log(const Msg: string);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    { Liga o IPC ao browser (a janela 'main'): injeta a ponte JS e assume o
      OnWebMessageJson. Crie antes do Browser.CreateWebView (ou recarregue a
      página depois). }
    constructor Create(AOwner: TComponent; ABrowser: TWebView2Browser); reintroduce;
    { ABrowser = nil: IPC sem página (testes); as respostas só saem pelo OnPost }
    destructor Destroy; override;

    { --- janelas --- }
    { Mais uma janela usando este IPC (antes do CreateWebView dela). Rótulo:
      letras, dígitos, '-' e '_', único. A página recebe o rótulo em
      window.borion.label. }
    procedure AddWindow(const WindowLabel: string; ABrowser: TWebView2Browser);
    { A janela deixa o IPC (liberar o browser também a tira) }
    procedure RemoveWindow(const WindowLabel: string);
    function WindowCount: Integer;
    function WindowLabel(Index: Integer): string;
    { nil se não houver }
    function WindowBrowser(const WindowLabel: string): TWebView2Browser;
    { '' se o browser não for de nenhuma janela }
    function WindowOf(ABrowser: TWebView2Browser): string;
    { Durante um comando ou listener: o rótulo da janela que chamou }
    property CurrentWindow: string read FCurrentWindow;

    { Origens que podem usar o IPC, ex.: 'https://app.localhost'. '*' libera todas. }
    procedure AllowOrigin(const Origin: string);
    function IsOriginAllowed(const Source: WideString): Boolean;

    procedure RegisterCommand(const Name: string; Handler: TBorionCommandMethod);
    procedure RegisterCommandProc(const Name: string; Handler: TBorionCommandProc);
    procedure UnregisterCommand(const Name: string);

    { Delphi -> JS, para todas as janelas. Podem ser chamados de qualquer thread. }
    procedure Emit(const Event: string; Payload: TJsonBase = nil);
    procedure EmitJson(const Event, PayloadJson: string);
    { Delphi -> JS, só para uma janela ('*' = todas) }
    procedure EmitTo(const WindowLabel, Event: string; Payload: TJsonBase = nil);
    procedure EmitJsonTo(const WindowLabel, Event, PayloadJson: string);

    { JS -> Delphi. Event = '*' recebe todos os eventos. }
    procedure Listen(const Event: string; Handler: TBorionEventMethod);
    procedure Unlisten(const Event: string; Handler: TBorionEventMethod);

    { O browser da primeira janela (a principal) }
    property Browser: TWebView2Browser read GetBrowser;
    { Diagnóstico: origem negada, JSON inválido, exceção em listener... }
    property OnLog: TBorionLogEvent read FOnLog write FOnLog;

    { Processa uma mensagem como se viesse da página (Json = mensagem do
      postMessage; Source = URL do documento). True se era do Borion. }
    function ProcessMessage(const Json, Source: WideString): Boolean;
    { O mesmo, vindo de uma janela específica }
    function ProcessMessageFrom(const WindowLabel: string; const Json, Source: WideString): Boolean;
    { Cada mensagem enviada à página (respostas e eventos), já no formato final.
      Para diagnóstico e testes; não substitui o envio ao browser. }
    property OnPost: TBorionPostEvent read FOnPost write FOnPost;
    { O mesmo, com a janela de destino ('*' = todas) }
    property OnPostTo: TBorionPostToEvent read FOnPostTo write FOnPostTo;
    { Escopo de arquivos do app (TBorionScope), usado pelos plugins fs, dialog e
      shell criados sem escopo próprio. O TBorionIpc o libera, depois dos plugins.
      Veja BorionAppScope (BorionScope) e o TBorionBuilder (Borion). }
    property Scope: TObject read FScope write FScope;

    { Adiciona um plugin (o TBorionIpc passa a ser o dono) e registra os comandos
      dele. Devolve o próprio plugin, para configurar na mesma linha. }
    function AddPlugin(Plugin: TBorionPlugin): TBorionPlugin;
    { nil se não houver }
    function FindPlugin(const Name: string): TBorionPlugin;

    { Adia a chamada e roda Handler depois que o callback do WebView2 retornar,
      na thread da interface. A resposta sai quando Handler termina (Result,
      ou Reject/exceção). Use para janelas modais: abrir um diálogo dentro do
      callback COM do WebView2 causa reentrância. }
    procedure Later(Call: TBorionCall; Handler: TBorionCommandMethod);
  end;

{ A ponte JS injetada em todo documento (window.borion / window.__BORION__) }
function BorionBridgeScript: WideString;

{ 'https://app.localhost/x/y?z' -> 'https://app.localhost' }
function BorionOriginOf(const Url: WideString): string;

implementation

uses
  BorionJson;

const
  WM_BORION_FINISH = WM_USER + 1;
  WM_BORION_POST = WM_USER + 2;
  WM_BORION_LATER = WM_USER + 3;

type
  TBorionCommandEntry = class
    Method: TBorionCommandMethod;
    Proc: TBorionCommandProc;
  end;

  PBorionListener = ^TBorionListener;
  TBorionListener = record
    Event: string;
    Handler: TBorionEventMethod;
  end;

function BorionOriginOf(const Url: WideString): string;
var
  S: string;
  I: Integer;
begin
  S := Url;
  I := Pos('://', S);
  if I = 0 then
  begin
    Result := S;  { about:blank, data:... }
    Exit;
  end;
  Result := Copy(S, 1, I + 2);
  Delete(S, 1, I + 2);
  I := 1;
  while (I <= Length(S)) and not (S[I] in ['/', '?', '#']) do
    Inc(I);
  Result := LowerCase(Result + Copy(S, 1, I - 1));
end;

function BorionBridgeScript: WideString;
begin
  { JS só com aspas duplas, para não precisar escapar no Pascal }
  Result :=
    '(function () {' + #10 +
    '  "use strict";' + #10 +
    '  if (window.__BORION__) return;' + #10 +
    '  var wv = window.chrome && window.chrome.webview;' + #10 +
    '  if (!wv) return;' + #10 +
    '  var seq = 0, pending = Object.create(null), listeners = Object.create(null);' + #10 +
    '  function post(msg) { msg.__borion = 1; wv.postMessage(msg); }' + #10 +
    '  function makeError(code, message, cmd) {' + #10 +
    '    var e = new Error(message); e.code = code; if (cmd) e.command = cmd; return e;' + #10 +
    '  }' + #10 +
    '  function invoke(cmd, args, options) {' + #10 +
    '    return new Promise(function (resolve, reject) {' + #10 +
    '      var id = ++seq, timer = null, timeout = options && options.timeout;' + #10 +
    '      if (timeout) timer = setTimeout(function () {' + #10 +
    '        delete pending[id];' + #10 +
    '        reject(makeError("TIMEOUT", "timeout after " + timeout + " ms", cmd));' + #10 +
    '      }, timeout);' + #10 +
    '      pending[id] = { resolve: resolve, reject: reject, timer: timer, cmd: cmd };' + #10 +
    '      post({ kind: "invoke", id: id, cmd: String(cmd), args: args == null ? {} : args });' + #10 +
    '    });' + #10 +
    '  }' + #10 +
    '  function listen(event, cb) {' + #10 +
    '    (listeners[event] = listeners[event] || []).push(cb);' + #10 +
    '    return function unlisten() {' + #10 +
    '      var list = listeners[event] || [], i = list.indexOf(cb);' + #10 +
    '      if (i >= 0) list.splice(i, 1);' + #10 +
    '    };' + #10 +
    '  }' + #10 +
    '  function once(event, cb) {' + #10 +
    '    var off = listen(event, function (payload, name) { off(); cb(payload, name); });' + #10 +
    '    return off;' + #10 +
    '  }' + #10 +
    '  function emit(event, payload) {' + #10 +
    '    post({ kind: "emit", event: String(event), payload: payload === undefined ? null : payload });' + #10 +
    '  }' + #10 +
    '  function emitTo(target, event, payload) {' + #10 +
    '    post({ kind: "emitTo", target: String(target), event: String(event),' + #10 +
    '      payload: payload === undefined ? null : payload });' + #10 +
    '  }' + #10 +
    '  function dispatch(event, payload) {' + #10 +
    '    (listeners[event] || []).slice().forEach(function (cb) {' + #10 +
    '      try { cb(payload, event); } catch (x) { console.error(x); }' + #10 +
    '    });' + #10 +
    '  }' + #10 +
    '  wv.addEventListener("message", function (e) {' + #10 +
    '    var m = e.data;' + #10 +
    '    if (!m || typeof m !== "object" || m.__borion !== 1) return;' + #10 +
    '    if (e.stopImmediatePropagation) e.stopImmediatePropagation();' + #10 +
    '    if (m.kind === "response") {' + #10 +
    '      var p = pending[m.id];' + #10 +
    '      if (!p) return;' + #10 +
    '      delete pending[m.id];' + #10 +
    '      if (p.timer) clearTimeout(p.timer);' + #10 +
    '      if (m.ok) p.resolve(m.result);' + #10 +
    '      else p.reject(makeError(m.error && m.error.code || "ERROR",' + #10 +
    '        m.error && m.error.message || "erro", p.cmd));' + #10 +
    '    } else if (m.kind === "event") {' + #10 +
    '      dispatch(m.event, m.payload);' + #10 +
    '    }' + #10 +
    '  });' + #10 +
    '  var label = typeof window.__BORION_WINDOW__ === "string" ? window.__BORION_WINDOW__ : "main";' + #10 +
    '  var api = Object.freeze({ invoke: invoke, listen: listen, once: once, emit: emit,' + #10 +
    '    emitTo: emitTo, label: label, version: "' + BORION_VERSION + '" });' + #10 +
    '  Object.defineProperty(window, "__BORION__", { value: api });' + #10 +
    '  Object.defineProperty(window, "borion", { value: api });' + #10 +
    '})();';
end;

{ EBorionError }

constructor EBorionError.Create(const ACode, AMessage: string);
begin
  inherited Create(AMessage);
  FCode := ACode;
end;

{ TBorionCall }

constructor TBorionCall.Create(AIpc: TBorionIpc; const AId, ACommand: string;
  const ASource: WideString);
begin
  inherited Create;
  FIpc := AIpc;
  FId := AId;
  FCommand := ACommand;
  FSource := ASource;
  FArgs := TJsonObject.Create;
  FResult := TJsonValue.Create(nil);
end;

destructor TBorionCall.Destroy;
begin
  FResult.Free;
  FArgs.Free;
  inherited Destroy;
end;

function TBorionCall.HasArg(const Name: string): Boolean;
begin
  Result := FArgs.Find(Name) >= 0;
end;

function TBorionCall.Arg(const Name: string): TJsonValue;
var
  I: Integer;
begin
  I := FArgs.Find(Name);
  if I >= 0 then
    Result := FArgs.Items[I].Value
  else
    Result := nil;
end;

function TBorionCall.ArgStr(const Name, Default: string): string;
var
  V: TJsonValue;
begin
  V := Arg(Name);
  if (V = nil) or (V.ValueType in [jvNone, jvNull]) then
    Result := Default
  else
    Result := V.AsString;
end;

function TBorionCall.ArgInt(const Name: string; Default: Integer): Integer;
var
  V: TJsonValue;
begin
  V := Arg(Name);
  if (V = nil) or (V.ValueType in [jvNone, jvNull]) then
    Result := Default
  else
    Result := V.AsInteger;
end;

function TBorionCall.ArgNum(const Name: string; Default: Extended): Extended;
var
  V: TJsonValue;
begin
  V := Arg(Name);
  if (V = nil) or (V.ValueType in [jvNone, jvNull]) then
    Result := Default
  else
    Result := V.AsNumber;
end;

function TBorionCall.ArgBool(const Name: string; Default: Boolean): Boolean;
var
  V: TJsonValue;
begin
  V := Arg(Name);
  if (V = nil) or (V.ValueType in [jvNone, jvNull]) then
    Result := Default
  else
    Result := V.AsBoolean;
end;

function TBorionCall.Browser: TWebView2Browser;
begin
  if FIpc <> nil then
    Result := FIpc.WindowBrowser(FWindow)
  else
    Result := nil;
end;

procedure TBorionCall.Defer;
begin
  FDeferred := True;
end;

procedure TBorionCall.Resolve;
begin
  Finish;
end;

procedure TBorionCall.Reject(const Msg, Code: string);
begin
  if FFinished or (FErrorCode <> '') then
    Exit;
  FErrorMessage := Msg;
  if Code = '' then
    FErrorCode := 'ERROR'
  else
    FErrorCode := Code;
  Finish;
end;

procedure TBorionCall.Finish;
begin
  { Todo o estado da chamada muda só na thread da interface: de outra thread,
    apenas avisa o TBorionIpc, que chama Finish de novo na thread certa. }
  if GetCurrentThreadId <> MainThreadID then
  begin
    if FIpc <> nil then
      PostMessage(FIpc.FWindow, WM_BORION_FINISH, 0, LPARAM(Self));
    Exit;
  end;
  if FFinished then
    Exit;
  FFinished := True;
  { dentro do handler (ou numa chamada não adiada), quem envia é o
    HandleInvoke, quando o handler retornar }
  if FInHandler or not FDeferred then
    Exit;
  if FIpc <> nil then
    FIpc.SendResponse(Self)
  else
    Free;  { o TBorionIpc já foi destruído: ninguém mais espera esta resposta }
end;

{ TBorionIpc }

constructor TBorionIpc.Create(AOwner: TComponent; ABrowser: TWebView2Browser);
begin
  inherited Create(AOwner);
  FCommands := TStringList.Create;
  FCommands.CaseSensitive := True;
  FCommands.Sorted := True;
  FListeners := TList.Create;
  FOrigins := TStringList.Create;
  FPending := TList.Create;
  FPlugins := TList.Create;
  FWindows := TStringList.Create;
  FWindows.CaseSensitive := True;
  FWindow := AllocateHWnd(WndProc);
  if ABrowser <> nil then
    AddWindow('main', ABrowser);
end;

destructor TBorionIpc.Destroy;
var
  I: Integer;
begin
  while FWindows.Count > 0 do
    SoltarJanela(FWindows.Count - 1, False);
  { chamadas adiadas ainda em andamento: ficam órfãs e se liberam no Resolve/Reject }
  for I := 0 to FPending.Count - 1 do
    TBorionCall(FPending[I]).FIpc := nil;
  FPending.Free;
  DeallocateHWnd(FWindow);
  for I := 0 to FCommands.Count - 1 do
    FCommands.Objects[I].Free;
  FCommands.Free;
  for I := 0 to FListeners.Count - 1 do
    Dispose(PBorionListener(FListeners[I]));
  FListeners.Free;
  FOrigins.Free;
  for I := 0 to FPlugins.Count - 1 do
    TBorionPlugin(FPlugins[I]).Free;
  FPlugins.Free;
  FScope.Free;
  FWindows.Free;
  inherited Destroy;
end;

function ValidWindowLabel(const S: string): Boolean;
var
  I: Integer;
begin
  Result := S <> '';
  for I := 1 to Length(S) do
    if not (S[I] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then
    begin
      Result := False;
      Exit;
    end;
end;

procedure TBorionIpc.AddWindow(const WindowLabel: string; ABrowser: TWebView2Browser);
var
  I: Integer;
begin
  if not ValidWindowLabel(WindowLabel) then
    raise EBorionError.Create('INVALID_LABEL', 'rótulo de janela inválido: "' + WindowLabel +
      '" (use letras, dígitos, "-" e "_")');
  if FWindows.IndexOf(WindowLabel) >= 0 then
    raise EBorionError.Create('WINDOW_EXISTS', 'já existe uma janela "' + WindowLabel + '"');
  FWindows.AddObject(WindowLabel, ABrowser);
  ABrowser.FreeNotification(Self);
  ABrowser.OnWebMessageJson := WebMessageJson;
  { o rótulo antes da ponte, que o lê ao se instalar }
  ABrowser.AddScriptOnDocumentCreated('Object.defineProperty(window, "__BORION_WINDOW__", { value: ' +
    JsonQuote(WindowLabel) + ' });');
  ABrowser.AddScriptOnDocumentCreated(BorionBridgeScript);
  for I := 0 to FPlugins.Count - 1 do
    TBorionPlugin(FPlugins[I]).WindowAdded(WindowLabel, ABrowser);
end;

{ Destruindo: o browser está sendo liberado (não mexe nele) }
procedure TBorionIpc.SoltarJanela(I: Integer; Destruindo: Boolean);
var
  B: TWebView2Browser;
  L: string;
  J: Integer;
begin
  L := FWindows[I];
  B := TWebView2Browser(FWindows.Objects[I]);
  FWindows.Delete(I);
  if not Destruindo then
  begin
    B.OnWebMessageJson := nil;
    B.RemoveFreeNotification(Self);
  end;
  for J := 0 to FPlugins.Count - 1 do
    TBorionPlugin(FPlugins[J]).WindowRemoved(L, B);
end;

procedure TBorionIpc.RemoveWindow(const WindowLabel: string);
var
  I: Integer;
begin
  I := FWindows.IndexOf(WindowLabel);
  if I >= 0 then
    SoltarJanela(I, False);
end;

function TBorionIpc.WindowCount: Integer;
begin
  Result := FWindows.Count;
end;

function TBorionIpc.WindowLabel(Index: Integer): string;
begin
  Result := FWindows[Index];
end;

function TBorionIpc.WindowBrowser(const WindowLabel: string): TWebView2Browser;
var
  I: Integer;
begin
  I := FWindows.IndexOf(WindowLabel);
  if I >= 0 then
    Result := TWebView2Browser(FWindows.Objects[I])
  else
    Result := nil;
end;

function TBorionIpc.WindowOf(ABrowser: TWebView2Browser): string;
var
  I: Integer;
begin
  I := FWindows.IndexOfObject(ABrowser);
  if I >= 0 then
    Result := FWindows[I]
  else
    Result := '';
end;

function TBorionIpc.GetBrowser: TWebView2Browser;
begin
  if FWindows.Count > 0 then
    Result := TWebView2Browser(FWindows.Objects[0])
  else
    Result := nil;
end;

function TBorionIpc.AddPlugin(Plugin: TBorionPlugin): TBorionPlugin;
begin
  if FindPlugin(Plugin.Name) <> nil then
    raise EBorionError.Create('PLUGIN', 'plugin já adicionado: ' + Plugin.Name);
  Plugin.FIpc := Self;
  FPlugins.Add(Plugin);
  Plugin.Install;
  Result := Plugin;
end;

function TBorionIpc.FindPlugin(const Name: string): TBorionPlugin;
var
  I: Integer;
begin
  for I := 0 to FPlugins.Count - 1 do
  begin
    Result := TBorionPlugin(FPlugins[I]);
    if SameText(Result.Name, Name) then
      Exit;
  end;
  Result := nil;
end;

type
  PBorionMethod = ^TMethod;
  PBorionLater = ^TBorionLater;
  TBorionLater = record
    Call: TBorionCall;
    Handler: TBorionCommandMethod;
  end;

procedure TBorionIpc.Later(Call: TBorionCall; Handler: TBorionCommandMethod);
var
  P: PBorionLater;
begin
  Call.Defer;
  New(P);
  P^.Call := Call;
  P^.Handler := Handler;
  if not PostMessage(FWindow, WM_BORION_LATER, 0, LPARAM(P)) then
  begin
    Dispose(P);
    Call.Reject('não foi possível agendar o comando', 'INTERNAL');
  end;
end;

procedure TBorionIpc.RunLater(P: Pointer);
var
  Call: TBorionCall;
  Handler: TBorionCommandMethod;
  Anterior: string;
begin
  Call := PBorionLater(P)^.Call;
  Handler := PBorionLater(P)^.Handler;
  Dispose(PBorionLater(P));
  Call.FInHandler := True;
  Anterior := FCurrentWindow;
  FCurrentWindow := Call.FWindow;
  try
    try
      Handler(Call);
    except
      on E: EBorionError do
        Call.Reject(E.Message, E.Code);
      on E: Exception do
        Call.Reject(E.Message, E.ClassName);
    end;
  finally
    Call.FInHandler := False;
    FCurrentWindow := Anterior;
  end;
  Call.FFinished := True;
  SendResponse(Call);
end;

{ TBorionPlugin }

destructor TBorionPlugin.Destroy;
var
  I: Integer;
begin
  if FLater <> nil then
  begin
    for I := 0 to FLater.Count - 1 do
      Dispose(PBorionMethod(FLater.Objects[I]));
    FLater.Free;
  end;
  inherited Destroy;
end;

procedure TBorionPlugin.WindowAdded(const WindowLabel: string; ABrowser: TWebView2Browser);
begin
end;

procedure TBorionPlugin.WindowRemoved(const WindowLabel: string; ABrowser: TWebView2Browser);
begin
end;

procedure TBorionPlugin.Command(const Comando: string; Handler: TBorionCommandMethod);
begin
  FIpc.RegisterCommand(Name + ':' + Comando, Handler);
end;

procedure TBorionPlugin.CommandLater(const Comando: string; Handler: TBorionCommandMethod);
var
  M: PBorionMethod;
begin
  if FLater = nil then
  begin
    FLater := TStringList.Create;
    FLater.CaseSensitive := True;
  end;
  New(M);
  M^ := TMethod(Handler);
  FLater.AddObject(Name + ':' + Comando, TObject(M));
  FIpc.RegisterCommand(Name + ':' + Comando, DispatchLater);
end;

procedure TBorionPlugin.DispatchLater(Call: TBorionCall);
var
  I: Integer;
begin
  I := FLater.IndexOf(Call.Command);
  FIpc.Later(Call, TBorionCommandMethod(PBorionMethod(FLater.Objects[I])^));
end;

procedure TBorionIpc.Notification(AComponent: TComponent; Operation: TOperation);
var
  I: Integer;
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FWindows <> nil) then
  begin
    I := FWindows.IndexOfObject(AComponent);
    if I >= 0 then
      SoltarJanela(I, True);
  end;
end;

procedure TBorionIpc.Log(const Msg: string);
begin
  if Assigned(FOnLog) then
    FOnLog(Self, Msg);
end;

procedure TBorionIpc.AllowOrigin(const Origin: string);
var
  S: string;
begin
  S := LowerCase(Origin);
  while (S <> '') and (S[Length(S)] = '/') do
    Delete(S, Length(S), 1);
  if FOrigins.IndexOf(S) < 0 then
    FOrigins.Add(S);
end;

function TBorionIpc.IsOriginAllowed(const Source: WideString): Boolean;
begin
  Result := (FOrigins.IndexOf('*') >= 0) or (FOrigins.IndexOf(BorionOriginOf(Source)) >= 0);
end;

procedure TBorionIpc.RegisterCommand(const Name: string; Handler: TBorionCommandMethod);
var
  Entry: TBorionCommandEntry;
begin
  UnregisterCommand(Name);
  Entry := TBorionCommandEntry.Create;
  Entry.Method := Handler;
  FCommands.AddObject(Name, Entry);
end;

procedure TBorionIpc.RegisterCommandProc(const Name: string; Handler: TBorionCommandProc);
var
  Entry: TBorionCommandEntry;
begin
  UnregisterCommand(Name);
  Entry := TBorionCommandEntry.Create;
  Entry.Proc := Handler;
  FCommands.AddObject(Name, Entry);
end;

procedure TBorionIpc.UnregisterCommand(const Name: string);
var
  I: Integer;
begin
  I := FCommands.IndexOf(Name);
  if I >= 0 then
  begin
    FCommands.Objects[I].Free;
    FCommands.Delete(I);
  end;
end;

procedure TBorionIpc.Listen(const Event: string; Handler: TBorionEventMethod);
var
  L: PBorionListener;
begin
  New(L);
  L^.Event := Event;
  L^.Handler := Handler;
  FListeners.Add(L);
end;

procedure TBorionIpc.Unlisten(const Event: string; Handler: TBorionEventMethod);
var
  I: Integer;
  L: PBorionListener;
begin
  for I := FListeners.Count - 1 downto 0 do
  begin
    L := FListeners[I];
    if (L^.Event = Event) and (TMethod(L^.Handler).Code = TMethod(Handler).Code) and
      (TMethod(L^.Handler).Data = TMethod(Handler).Data) then
    begin
      Dispose(L);
      FListeners.Delete(I);
    end;
  end;
end;

procedure TBorionIpc.Emit(const Event: string; Payload: TJsonBase);
var
  PayloadJson: string;
begin
  if Payload = nil then
    PayloadJson := 'null'
  else
    PayloadJson := Payload.Stringify;
  EmitJson(Event, PayloadJson);
end;

procedure TBorionIpc.EmitJson(const Event, PayloadJson: string);
begin
  EmitJsonTo('*', Event, PayloadJson);
end;

procedure TBorionIpc.EmitTo(const WindowLabel, Event: string; Payload: TJsonBase);
var
  PayloadJson: string;
begin
  if Payload = nil then
    PayloadJson := 'null'
  else
    PayloadJson := Payload.Stringify;
  EmitJsonTo(WindowLabel, Event, PayloadJson);
end;

procedure TBorionIpc.EmitJsonTo(const WindowLabel, Event, PayloadJson: string);
var
  Json, Alvo: string;
begin
  if PayloadJson = '' then
    Json := 'null'
  else
    Json := PayloadJson;
  if WindowLabel = '*' then
    Alvo := ''
  else
    Alvo := WindowLabel;
  PostJson('{"__borion":1,"kind":"event","event":' + JsonQuote(Event) + ',"payload":' + Json + '}', Alvo);
end;

type
  PBorionPost = ^TBorionPost;
  TBorionPost = record
    Json: string;
    Target: string;
  end;

procedure TBorionIpc.PostJson(const Json, Target: string);
var
  P: PBorionPost;
  W: WideString;
  I: Integer;
begin
  if GetCurrentThreadId <> MainThreadID then
  begin
    { o WebView2 só pode ser usado na thread da interface }
    New(P);
    P^.Json := Json;
    P^.Target := Target;
    if not PostMessage(FWindow, WM_BORION_POST, 0, LPARAM(P)) then
      Dispose(P);
    Exit;
  end;
  W := AnsiJsonToWide(Json);
  if Assigned(FOnPost) then
    FOnPost(Self, W);
  if Assigned(FOnPostTo) then
    if Target = '' then
      FOnPostTo(Self, '*', W)
    else
      FOnPostTo(Self, Target, W);
  for I := 0 to FWindows.Count - 1 do
    if (Target = '') or (FWindows[I] = Target) then
      TWebView2Browser(FWindows.Objects[I]).PostWebMessageAsJson(W);
end;

procedure TBorionIpc.WndProc(var Message: TMessage);
var
  P: PBorionPost;
begin
  case Message.Msg of
    WM_BORION_FINISH:
      TBorionCall(Message.LParam).Finish;  { agora na thread da interface }
    WM_BORION_POST:
      begin
        P := PBorionPost(Message.LParam);
        try
          PostJson(P^.Json, P^.Target);
        finally
          Dispose(P);
        end;
      end;
    WM_BORION_LATER:
      RunLater(Pointer(Message.LParam));
  else
    Message.Result := DefWindowProc(FWindow, Message.Msg, Message.WParam, Message.LParam);
  end;
end;

procedure TBorionIpc.SendResponse(Call: TBorionCall);
var
  Json: string;
begin
  try
    if Call.FErrorCode = '' then
      Json := '{"__borion":1,"kind":"response","id":' + Call.FId + ',"ok":true,"result":' +
        Call.FResult.Stringify + '}'
    else
      Json := '{"__borion":1,"kind":"response","id":' + Call.FId + ',"ok":false,"error":{"code":' +
        JsonQuote(Call.FErrorCode) + ',"message":' + JsonQuote(Call.FErrorMessage) + '}}';
    { só para a janela que chamou (se ela ainda existir) }
    if (Call.FWindow = '') or (FWindows.Count = 0) or (FWindows.IndexOf(Call.FWindow) >= 0) then
      PostJson(Json, Call.FWindow)
    else
      Log('resposta descartada: a janela "' + Call.FWindow + '" fechou');
  finally
    FPending.Remove(Call);
    Call.Free;
  end;
end;

procedure TBorionIpc.WebMessageJson(Sender: TObject; const Json, Source: WideString;
  var Handled: Boolean);
var
  L: string;
begin
  L := WindowOf(TWebView2Browser(Sender));
  if L = '' then
    Exit;
  if ProcessMessageFrom(L, Json, Source) then
    Handled := True;
end;

function TBorionIpc.ProcessMessage(const Json, Source: WideString): Boolean;
begin
  if FWindows.Count > 0 then
    Result := ProcessMessageFrom(FWindows[0], Json, Source)
  else
    Result := ProcessMessageFrom('main', Json, Source);
end;

function TBorionIpc.ProcessMessageFrom(const WindowLabel: string; const Json, Source: WideString): Boolean;
var
  S, Kind: string;
  Msg: TJsonObject;
begin
  Result := False;
  S := WideJsonToAnsi(Json);
  { filtro rápido: só objetos do protocolo Borion }
  if (S = '') or (S[1] <> '{') or (Pos('"__borion"', S) = 0) then
    Exit;
  Msg := TJsonObject.Create;
  try
    try
      Msg.Parse(S);
    except
      on E: Exception do
      begin
        Log('mensagem inválida: ' + E.Message);
        Exit;
      end;
    end;
    if Msg.Find('__borion') < 0 then
      Exit;
    Result := True;
    try
      Kind := Msg['kind'].AsString;
      if Kind = 'invoke' then
        HandleInvoke(Msg, Source, WindowLabel)
      else if Kind = 'emit' then
        HandleEmit(Msg, Source, WindowLabel)
      else if Kind = 'emitTo' then
        HandleEmitTo(Msg, Source)
      else
        Log('tipo de mensagem desconhecido: ' + Kind);
    except
      { campos com o tipo errado (ex.: "cmd" com um objeto) não podem derrubar o app }
      on E: Exception do
        Log('mensagem malformada: ' + E.Message);
    end;
  finally
    Msg.Free;
  end;
end;

procedure TBorionIpc.HandleInvoke(Msg: TJsonObject; const Source: WideString; const WindowLabel: string);
var
  Call: TBorionCall;
  I: Integer;
  Entry: TBorionCommandEntry;
  Anterior: string;
begin
  if Msg.Find('id') < 0 then
  begin
    Log('invoke sem id');
    Exit;
  end;
  Call := TBorionCall.Create(Self, Msg['id'].Stringify, Msg['cmd'].AsString, Source);
  Call.FWindow := WindowLabel;
  I := Msg.Find('args');
  if (I >= 0) and (Msg.Items[I].Value.ValueType = jvObject) then
    Call.FArgs.Assign(Msg.Items[I].Value.AsObject);

  if not IsOriginAllowed(Source) then
  begin
    Log('invoke negado para a origem ' + BorionOriginOf(Source) + ': ' + Call.Command);
    Call.Reject('origem não permitida: ' + BorionOriginOf(Source), 'FORBIDDEN_ORIGIN');
  end
  else
  begin
    I := FCommands.IndexOf(Call.Command);
    if I < 0 then
      Call.Reject('comando desconhecido: ' + Call.Command, 'UNKNOWN_COMMAND')
    else
    begin
      Entry := TBorionCommandEntry(FCommands.Objects[I]);
      Call.FInHandler := True;
      Anterior := FCurrentWindow;
      FCurrentWindow := WindowLabel;
      try
        try
          if Assigned(Entry.Method) then
            Entry.Method(Call)
          else
            Entry.Proc(Call);
        except
          on E: EBorionError do
            Call.Reject(E.Message, E.Code);
          on E: Exception do
            Call.Reject(E.Message, E.ClassName);
        end;
      finally
        Call.FInHandler := False;
        FCurrentWindow := Anterior;
      end;
    end;
  end;

  if Call.FDeferred and not Call.FFinished then
    FPending.Add(Call)  { a resposta sai no Resolve/Reject }
  else
    SendResponse(Call);
end;

procedure TBorionIpc.HandleEmitTo(Msg: TJsonObject; const Source: WideString);
var
  Target, PayloadJson: string;
  I: Integer;
begin
  if not IsOriginAllowed(Source) then
  begin
    Log('emitTo negado para a origem ' + BorionOriginOf(Source));
    Exit;
  end;
  Target := Msg['target'].AsString;
  if (Target <> '*') and (FWindows.IndexOf(Target) < 0) then
  begin
    Log('emitTo para uma janela que não existe: ' + Target);
    Exit;
  end;
  I := Msg.Find('payload');
  if I >= 0 then
    PayloadJson := Msg.Items[I].Value.Stringify
  else
    PayloadJson := 'null';
  { repassado como um evento comum para a(s) janela(s) de destino }
  EmitJsonTo(Target, Msg['event'].AsString, PayloadJson);
end;

procedure TBorionIpc.HandleEmit(Msg: TJsonObject; const Source: WideString; const WindowLabel: string);
var
  Event, Anterior: string;
  Payload: TJsonValue;
  Snapshot: TList;
  I: Integer;
  L: PBorionListener;
begin
  if not IsOriginAllowed(Source) then
  begin
    Log('emit negado para a origem ' + BorionOriginOf(Source));
    Exit;
  end;
  Event := Msg['event'].AsString;
  Payload := Msg['payload'];
  { cópia da lista: um listener pode chamar Listen/Unlisten }
  Snapshot := TList.Create;
  Anterior := FCurrentWindow;
  FCurrentWindow := WindowLabel;
  try
    Snapshot.Assign(FListeners);
    for I := 0 to Snapshot.Count - 1 do
    begin
      L := Snapshot[I];
      if FListeners.IndexOf(L) < 0 then
        Continue;  { removido por um listener anterior }
      if (L^.Event = Event) or (L^.Event = '*') then
        try
          L^.Handler(Event, Payload);
        except
          on E: Exception do
            Log('erro no listener de "' + Event + '": ' + E.Message);
        end;
    end;
  finally
    Snapshot.Free;
    FCurrentWindow := Anterior;
  end;
end;

end.
