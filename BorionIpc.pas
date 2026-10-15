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

  TBorionIpc = class(TComponent)
  private
    FBrowser: TWebView2Browser;
    FCommands: TStringList;
    FListeners: TList;
    FOrigins: TStringList;
    FPending: TList;
    FWindow: HWND;
    FOnLog: TBorionLogEvent;
    FOnPost: TBorionPostEvent;
    procedure WebMessageJson(Sender: TObject; const Json, Source: WideString; var Handled: Boolean);
    procedure HandleInvoke(Msg: TJsonObject; const Source: WideString);
    procedure HandleEmit(Msg: TJsonObject; const Source: WideString);
    procedure SendResponse(Call: TBorionCall);
    procedure PostJson(const Json: string);
    procedure WndProc(var Message: TMessage);
    procedure Log(const Msg: string);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    { Liga o IPC ao browser: injeta a ponte JS e assume o OnWebMessageJson.
      Crie antes do Browser.CreateWebView (ou recarregue a página depois). }
    constructor Create(AOwner: TComponent; ABrowser: TWebView2Browser); reintroduce;
    { ABrowser = nil: IPC sem página (testes); as respostas só saem pelo OnPost }
    destructor Destroy; override;

    { Origens que podem usar o IPC, ex.: 'https://app.local'. '*' libera todas. }
    procedure AllowOrigin(const Origin: string);
    function IsOriginAllowed(const Source: WideString): Boolean;

    procedure RegisterCommand(const Name: string; Handler: TBorionCommandMethod);
    procedure RegisterCommandProc(const Name: string; Handler: TBorionCommandProc);
    procedure UnregisterCommand(const Name: string);

    { Delphi -> JS. Podem ser chamados de qualquer thread. }
    procedure Emit(const Event: string; Payload: TJsonBase = nil);
    procedure EmitJson(const Event, PayloadJson: string);

    { JS -> Delphi. Event = '*' recebe todos os eventos. }
    procedure Listen(const Event: string; Handler: TBorionEventMethod);
    procedure Unlisten(const Event: string; Handler: TBorionEventMethod);

    property Browser: TWebView2Browser read FBrowser;
    { Diagnóstico: origem negada, JSON inválido, exceção em listener... }
    property OnLog: TBorionLogEvent read FOnLog write FOnLog;

    { Processa uma mensagem como se viesse da página (Json = mensagem do
      postMessage; Source = URL do documento). True se era do Borion. }
    function ProcessMessage(const Json, Source: WideString): Boolean;
    { Cada mensagem enviada à página (respostas e eventos), já no formato final.
      Para diagnóstico e testes; não substitui o envio ao browser. }
    property OnPost: TBorionPostEvent read FOnPost write FOnPost;
  end;

{ A ponte JS injetada em todo documento (window.borion / window.__BORION__) }
function BorionBridgeScript: WideString;

{ 'https://app.local/x/y?z' -> 'https://app.local' }
function BorionOriginOf(const Url: WideString): string;

implementation

uses
  BorionJson;

const
  WM_BORION_FINISH = WM_USER + 1;
  WM_BORION_POST = WM_USER + 2;

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
    '  var api = Object.freeze({ invoke: invoke, listen: listen, once: once, emit: emit,' + #10 +
    '    version: "' + BORION_VERSION + '" });' + #10 +
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
  FWindow := AllocateHWnd(WndProc);
  FBrowser := ABrowser;
  if FBrowser <> nil then
  begin
    FBrowser.FreeNotification(Self);
    FBrowser.OnWebMessageJson := WebMessageJson;
    FBrowser.AddScriptOnDocumentCreated(BorionBridgeScript);
  end;
end;

destructor TBorionIpc.Destroy;
var
  I: Integer;
begin
  if FBrowser <> nil then
  begin
    FBrowser.OnWebMessageJson := nil;
    FBrowser.RemoveFreeNotification(Self);
  end;
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
  inherited Destroy;
end;

procedure TBorionIpc.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FBrowser) then
    FBrowser := nil;
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
var
  Json: string;
begin
  if PayloadJson = '' then
    Json := 'null'
  else
    Json := PayloadJson;
  PostJson('{"__borion":1,"kind":"event","event":' + JsonQuote(Event) + ',"payload":' + Json + '}');
end;

procedure TBorionIpc.PostJson(const Json: string);
var
  P: PString;
  W: WideString;
begin
  if GetCurrentThreadId <> MainThreadID then
  begin
    { o WebView2 só pode ser usado na thread da interface }
    New(P);
    P^ := Json;
    if not PostMessage(FWindow, WM_BORION_POST, 0, LPARAM(P)) then
      Dispose(P);
    Exit;
  end;
  W := AnsiJsonToWide(Json);
  if Assigned(FOnPost) then
    FOnPost(Self, W);
  if FBrowser <> nil then
    FBrowser.PostWebMessageAsJson(W);
end;

procedure TBorionIpc.WndProc(var Message: TMessage);
var
  P: PString;
begin
  case Message.Msg of
    WM_BORION_FINISH:
      TBorionCall(Message.LParam).Finish;  { agora na thread da interface }
    WM_BORION_POST:
      begin
        P := PString(Message.LParam);
        try
          PostJson(P^);
        finally
          Dispose(P);
        end;
      end;
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
    PostJson(Json);
  finally
    FPending.Remove(Call);
    Call.Free;
  end;
end;

procedure TBorionIpc.WebMessageJson(Sender: TObject; const Json, Source: WideString;
  var Handled: Boolean);
begin
  if ProcessMessage(Json, Source) then
    Handled := True;
end;

function TBorionIpc.ProcessMessage(const Json, Source: WideString): Boolean;
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
        HandleInvoke(Msg, Source)
      else if Kind = 'emit' then
        HandleEmit(Msg, Source)
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

procedure TBorionIpc.HandleInvoke(Msg: TJsonObject; const Source: WideString);
var
  Call: TBorionCall;
  I: Integer;
  Entry: TBorionCommandEntry;
begin
  if Msg.Find('id') < 0 then
  begin
    Log('invoke sem id');
    Exit;
  end;
  Call := TBorionCall.Create(Self, Msg['id'].Stringify, Msg['cmd'].AsString, Source);
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
      end;
    end;
  end;

  if Call.FDeferred and not Call.FFinished then
    FPending.Add(Call)  { a resposta sai no Resolve/Reject }
  else
    SendResponse(Call);
end;

procedure TBorionIpc.HandleEmit(Msg: TJsonObject; const Source: WideString);
var
  Event: string;
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
  end;
end;

end.
