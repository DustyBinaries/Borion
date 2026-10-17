unit TestBorionIpc;

{ Testes do roteamento do TBorionIpc, sem WebView2: as mensagens entram por
  ProcessMessage (como se viessem da página) e as respostas são capturadas
  pelo OnPost. }

interface

uses
  Windows, Messages, SysUtils, Classes, TestFramework, Jsons, BorionJson, BorionIpc;

const
  ORIGEM = 'https://app.localhost/index.html';

type
  TTestBorionIpc = class(TTestCase)
  private
    FIpc: TBorionIpc;
    FPosts: TStringList;
    FLogs: TStringList;
    FEventos: TStringList;
    FAdiada: TBorionCall;
    procedure Postou(Sender: TObject; const Json: WideString);
    procedure Logou(Sender: TObject; const Msg: string);
    procedure Evento(const Event: string; Payload: TJsonValue);
    procedure EventoComErro(const Event: string; Payload: TJsonValue);
    { envia um invoke; ArgsJson já em JSON (ou '' para omitir) }
    function Invocar(const Cmd, ArgsJson: string; const Source: WideString = ORIGEM;
      const IdJson: string = '7'): Boolean;
    { última mensagem enviada à página, já parseada (o chamador libera) }
    function Ultima: TJsonObject;
    function UltimoErro: string;
    procedure Bombear(Quantas: Integer; TimeoutMs: Cardinal = 3000);
    function TemLog(const Trecho: string): Boolean;
    { comandos }
    procedure CmdSomar(Call: TBorionCall);
    procedure CmdArgs(Call: TBorionCall);
    procedure CmdObjeto(Call: TBorionCall);
    procedure CmdEco(Call: TBorionCall);
    procedure CmdFalharBorion(Call: TBorionCall);
    procedure CmdFalharGenerico(Call: TBorionCall);
    procedure CmdRejeitarDuasVezes(Call: TBorionCall);
    procedure CmdAdiar(Call: TBorionCall);
    procedure CmdAdiarEResolverJa(Call: TBorionCall);
    procedure CmdAdiarEFalhar(Call: TBorionCall);
    procedure CmdThread(Call: TBorionCall);
    procedure CmdA(Call: TBorionCall);
    procedure CmdB(Call: TBorionCall);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { comandos }
    procedure TestInvokeDevolveResultado;
    procedure TestIdTextoEhDevolvido;
    procedure TestArgsAusentesUsamPadrao;
    procedure TestArgsQueNaoSaoObjetoViramVazios;
    procedure TestResultadoObjetoEArray;
    procedure TestCommandProc;
    procedure TestRegistrarDeNovoSubstitui;
    procedure TestUnregister;
    procedure TestComandoDesconhecido;
    procedure TestNomesDiferenciamMaiusculas;
    { erros }
    procedure TestEBorionErrorViraCodigo;
    procedure TestExcecaoComumUsaNomeDaClasse;
    procedure TestRejectRepetidoNoHandlerIgnorado;
    { chamadas adiadas }
    procedure TestDeferSoRespondeNoResolve;
    procedure TestDeferRejectDepois;
    procedure TestDeferResolveDentroDoHandler;
    procedure TestExcecaoDepoisDoDefer;
    procedure TestResolveDeOutraThread;
    procedure TestChamadaOrfaAposDestruirIpc;
    { origens }
    procedure TestOrigemNegadaPorPadrao;
    procedure TestOrigemLiberadaIgnoraCaixaEBarra;
    procedure TestOrigemComPortaDiferenteNegada;
    procedure TestOrigemCuringa;
    procedure TestBorionOriginOf;
    { eventos }
    procedure TestEmitJson;
    procedure TestEmitSemPayload;
    procedure TestEmitObjeto;
    procedure TestEmitUnicode;
    procedure TestEmitDeOutraThread;
    procedure TestListenRecebeEvento;
    procedure TestListenCuringa;
    procedure TestUnlisten;
    procedure TestListenerComErroNaoParaOsOutros;
    procedure TestEmitDeOrigemNegadaIgnorado;
    { mensagens }
    procedure TestMensagemQueNaoEhDoBorionNaoEhTratada;
    procedure TestJsonInvalidoNaoQuebra;
    procedure TestCampoComTipoErradoNaoQuebra;
    procedure TestInvokeSemIdIgnorado;
    procedure TestUnicodeIdaEVolta;
  end;

  TTestBorionBridge = class(TTestCase)
  published
    procedure TestScriptExpoeApi;
    procedure TestExportaParaTestesJs;
  end;

implementation

{ comando como procedure solta (RegisterCommandProc) }
procedure CmdProcDobro(Call: TBorionCall);
begin
  Call.Result.AsInteger := Call.ArgInt('n') * 2;
end;

type
  TThreadResolve = class(TThread)
  private
    FCall: TBorionCall;
  protected
    procedure Execute; override;
  public
    constructor Create(ACall: TBorionCall);
  end;

  TThreadEmit = class(TThread)
  private
    FIpc: TBorionIpc;
  protected
    procedure Execute; override;
  public
    constructor Create(AIpc: TBorionIpc);
  end;

constructor TThreadResolve.Create(ACall: TBorionCall);
begin
  inherited Create(True);
  FCall := ACall;
  FreeOnTerminate := True;
end;

procedure TThreadResolve.Execute;
begin
  Sleep(50);
  FCall.Result.AsString := 'da thread';
  FCall.Resolve;
end;

constructor TThreadEmit.Create(AIpc: TBorionIpc);
begin
  inherited Create(True);
  FIpc := AIpc;
  FreeOnTerminate := True;
end;

procedure TThreadEmit.Execute;
begin
  FIpc.EmitJson('da-thread', '{"ok":true}');
end;

{ TTestBorionIpc }

procedure TTestBorionIpc.SetUp;
begin
  FPosts := TStringList.Create;
  FLogs := TStringList.Create;
  FEventos := TStringList.Create;
  FAdiada := nil;
  FIpc := TBorionIpc.Create(nil, nil);
  FIpc.OnPost := Postou;
  FIpc.OnLog := Logou;
  FIpc.AllowOrigin('https://app.localhost');
  FIpc.RegisterCommand('somar', CmdSomar);
  FIpc.RegisterCommand('args', CmdArgs);
  FIpc.RegisterCommand('objeto', CmdObjeto);
  FIpc.RegisterCommand('eco', CmdEco);
  FIpc.RegisterCommand('falharBorion', CmdFalharBorion);
  FIpc.RegisterCommand('falharGenerico', CmdFalharGenerico);
  FIpc.RegisterCommand('rejeitarDuasVezes', CmdRejeitarDuasVezes);
  FIpc.RegisterCommand('adiar', CmdAdiar);
  FIpc.RegisterCommand('adiarEResolverJa', CmdAdiarEResolverJa);
  FIpc.RegisterCommand('adiarEFalhar', CmdAdiarEFalhar);
  FIpc.RegisterCommand('thread', CmdThread);
  FIpc.RegisterCommandProc('dobro', CmdProcDobro);
end;

procedure TTestBorionIpc.TearDown;
begin
  FIpc.Free;
  FEventos.Free;
  FLogs.Free;
  FPosts.Free;
end;

procedure TTestBorionIpc.Postou(Sender: TObject; const Json: WideString);
begin
  FPosts.Add(Json);  { as mensagens de saída são só ASCII }
end;

procedure TTestBorionIpc.Logou(Sender: TObject; const Msg: string);
begin
  FLogs.Add(Msg);
end;

procedure TTestBorionIpc.Evento(const Event: string; Payload: TJsonValue);
begin
  FEventos.Add(Event + '=' + Payload.Stringify);
end;

procedure TTestBorionIpc.EventoComErro(const Event: string; Payload: TJsonValue);
begin
  raise Exception.Create('listener quebrado');
end;

function TTestBorionIpc.Invocar(const Cmd, ArgsJson: string; const Source: WideString;
  const IdJson: string): Boolean;
var
  Json: string;
begin
  Json := '{"__borion":1,"kind":"invoke","id":' + IdJson + ',"cmd":' + JsonQuote(Cmd);
  if ArgsJson <> '' then
    Json := Json + ',"args":' + ArgsJson;
  Result := FIpc.ProcessMessage(Json + '}', Source);
end;

function TTestBorionIpc.Ultima: TJsonObject;
begin
  Check(FPosts.Count > 0, 'nenhuma mensagem enviada');
  Result := TJsonObject.Create;
  Result.Parse(WideJsonToAnsi(FPosts[FPosts.Count - 1]));
end;

function TTestBorionIpc.UltimoErro: string;
var
  R: TJsonObject;
begin
  R := Ultima;
  try
    CheckFalse(R['ok'].AsBoolean, 'era esperado ok=false');
    Result := R['error'].AsObject['code'].AsString;
  finally
    R.Free;
  end;
end;

procedure TTestBorionIpc.Bombear(Quantas: Integer; TimeoutMs: Cardinal);
var
  Msg: TMsg;
  Inicio: Cardinal;
begin
  Inicio := GetTickCount;
  while (FPosts.Count < Quantas) and (GetTickCount - Inicio < TimeoutMs) do
  begin
    while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
    begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
    Sleep(5);
  end;
end;

function TTestBorionIpc.TemLog(const Trecho: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to FLogs.Count - 1 do
    if Pos(Trecho, FLogs[I]) > 0 then
    begin
      Result := True;
      Exit;
    end;
end;

{ --- comandos ------------------------------------------------------------ }

procedure TTestBorionIpc.CmdSomar(Call: TBorionCall);
begin
  Call.Result.AsNumber := Call.ArgNum('a') + Call.ArgNum('b');
end;

procedure TTestBorionIpc.CmdArgs(Call: TBorionCall);
var
  O: TJsonObject;
begin
  O := Call.Result.AsObject;
  O.Put('str', Call.ArgStr('nada', 'padrao'));
  O.Put('int', Call.ArgInt('nada', 5));
  O.Put('num', Call.ArgNum('nulo', 1.5));
  O.Put('bool', Call.ArgBool('nada', True));
  O.Put('tem', Call.HasArg('nulo'));
  O.Put('naoTem', Call.HasArg('nada'));
  O.Put('argNil', Call.Arg('nada') = nil);
  O.Put('qtd', Call.Args.Count);
end;

procedure TTestBorionIpc.CmdObjeto(Call: TBorionCall);
var
  Lista: TJsonArray;
begin
  Call.Result.AsObject.Put('nome', 'x');
  Lista := Call.Result.AsObject['itens'].AsArray;
  Lista.Put(1);
  Lista.Add.AsObject.Put('id', 2);
end;

procedure TTestBorionIpc.CmdEco(Call: TBorionCall);
begin
  Call.Result.AsString := Call.ArgStr('texto') + '|' + Call.Command;
end;

procedure TTestBorionIpc.CmdFalharBorion(Call: TBorionCall);
begin
  raise EBorionError.Create('VALIDACAO', 'campo obrigatório');
end;

procedure TTestBorionIpc.CmdFalharGenerico(Call: TBorionCall);
begin
  StrToInt('abc');  { EConvertError }
end;

procedure TTestBorionIpc.CmdRejeitarDuasVezes(Call: TBorionCall);
begin
  Call.Reject('primeiro', 'UM');
  Call.Reject('segundo', 'DOIS');
  Call.Resolve;
end;

procedure TTestBorionIpc.CmdAdiar(Call: TBorionCall);
begin
  Call.Defer;
  FAdiada := Call;
end;

procedure TTestBorionIpc.CmdAdiarEResolverJa(Call: TBorionCall);
begin
  Call.Defer;
  Call.Result.AsString := 'na hora';
  Call.Resolve;
end;

procedure TTestBorionIpc.CmdAdiarEFalhar(Call: TBorionCall);
begin
  Call.Defer;
  raise EBorionError.Create('DEPOIS', 'falhou depois do Defer');
end;

procedure TTestBorionIpc.CmdThread(Call: TBorionCall);
begin
  Call.Defer;
  TThreadResolve.Create(Call).Resume;
end;

procedure TTestBorionIpc.CmdA(Call: TBorionCall);
begin
  Call.Result.AsString := 'A';
end;

procedure TTestBorionIpc.CmdB(Call: TBorionCall);
begin
  Call.Result.AsString := 'B';
end;

{ --- testes: comandos ----------------------------------------------------- }

procedure TTestBorionIpc.TestInvokeDevolveResultado;
var
  R: TJsonObject;
begin
  Check(Invocar('somar', '{"a":20,"b":22}'));
  CheckEquals(1, FPosts.Count);
  R := Ultima;
  try
    CheckEquals(1, R['__borion'].AsInteger);
    CheckEquals('response', R['kind'].AsString);
    CheckEquals(7, R['id'].AsInteger);
    CheckTrue(R['ok'].AsBoolean);
    CheckEquals(42, R['result'].AsInteger);
  finally
    R.Free;
  end;
end;

procedure TTestBorionIpc.TestIdTextoEhDevolvido;
var
  R: TJsonObject;
begin
  Invocar('somar', '{}', ORIGEM, '"abc"');
  R := Ultima;
  try
    CheckEquals('abc', R['id'].AsString);
  finally
    R.Free;
  end;
end;

procedure TTestBorionIpc.TestArgsAusentesUsamPadrao;
var
  R, O: TJsonObject;
begin
  Invocar('args', '{"nulo":null}');
  R := Ultima;
  try
    O := R['result'].AsObject;
    CheckEquals('padrao', O['str'].AsString);
    CheckEquals(5, O['int'].AsInteger);
    CheckEquals(1.5, O['num'].AsNumber, 0.0001);
    CheckTrue(O['bool'].AsBoolean);
    CheckTrue(O['tem'].AsBoolean, 'HasArg de um argumento null');
    CheckFalse(O['naoTem'].AsBoolean);
    CheckTrue(O['argNil'].AsBoolean);
    CheckEquals(1, O['qtd'].AsInteger, 'Arg/ArgStr não podem criar chaves (AutoAdd)');
  finally
    R.Free;
  end;
end;

procedure TTestBorionIpc.TestArgsQueNaoSaoObjetoViramVazios;
var
  R: TJsonObject;
begin
  Invocar('args', '[1,2]');
  R := Ultima;
  try
    CheckTrue(R['ok'].AsBoolean);
    CheckEquals(0, R['result'].AsObject['qtd'].AsInteger);
  finally
    R.Free;
  end;
  Invocar('args', '');  { sem "args" }
  R := Ultima;
  try
    CheckEquals(0, R['result'].AsObject['qtd'].AsInteger);
  finally
    R.Free;
  end;
end;

procedure TTestBorionIpc.TestResultadoObjetoEArray;
var
  R: TJsonObject;
  Itens: TJsonArray;
begin
  Invocar('objeto', '');
  R := Ultima;
  try
    CheckEquals('x', R['result'].AsObject['nome'].AsString);
    Itens := R['result'].AsObject['itens'].AsArray;
    CheckEquals(2, Itens.Count);
    CheckEquals(1, Itens[0].AsInteger);
    CheckEquals(2, Itens[1].AsObject['id'].AsInteger);
  finally
    R.Free;
  end;
end;

procedure TTestBorionIpc.TestCommandProc;
var
  R: TJsonObject;
begin
  Invocar('dobro', '{"n":21}');
  R := Ultima;
  try
    CheckEquals(42, R['result'].AsInteger);
  finally
    R.Free;
  end;
end;

procedure TTestBorionIpc.TestRegistrarDeNovoSubstitui;
var
  R: TJsonObject;
begin
  FIpc.RegisterCommand('x', CmdA);
  FIpc.RegisterCommand('x', CmdB);
  Invocar('x', '');
  R := Ultima;
  try
    CheckEquals('B', R['result'].AsString);
  finally
    R.Free;
  end;
end;

procedure TTestBorionIpc.TestUnregister;
begin
  FIpc.UnregisterCommand('somar');
  Invocar('somar', '{}');
  CheckEquals('UNKNOWN_COMMAND', UltimoErro);
  FIpc.UnregisterCommand('nao-existe');  { não deve falhar }
end;

procedure TTestBorionIpc.TestComandoDesconhecido;
begin
  Check(Invocar('naoExiste', ''), 'mensagem do Borion deve ser tratada');
  CheckEquals('UNKNOWN_COMMAND', UltimoErro);
end;

procedure TTestBorionIpc.TestNomesDiferenciamMaiusculas;
begin
  Invocar('Somar', '{}');
  CheckEquals('UNKNOWN_COMMAND', UltimoErro);
end;

{ --- testes: erros -------------------------------------------------------- }

procedure TTestBorionIpc.TestEBorionErrorViraCodigo;
var
  R: TJsonObject;
begin
  Invocar('falharBorion', '');
  R := Ultima;
  try
    CheckFalse(R['ok'].AsBoolean);
    CheckEquals('VALIDACAO', R['error'].AsObject['code'].AsString);
    CheckEquals('campo obrigatório', R['error'].AsObject['message'].AsString);
  finally
    R.Free;
  end;
end;

procedure TTestBorionIpc.TestExcecaoComumUsaNomeDaClasse;
begin
  Invocar('falharGenerico', '');
  CheckEquals('EConvertError', UltimoErro);
end;

procedure TTestBorionIpc.TestRejectRepetidoNoHandlerIgnorado;
begin
  Invocar('rejeitarDuasVezes', '');
  CheckEquals(1, FPosts.Count);
  CheckEquals('UM', UltimoErro);
end;

{ --- testes: chamadas adiadas -------------------------------------------- }

procedure TTestBorionIpc.TestDeferSoRespondeNoResolve;
var
  R: TJsonObject;
begin
  Invocar('adiar', '');
  CheckEquals(0, FPosts.Count, 'chamada adiada não pode responder ao retornar');
  Check(FAdiada <> nil);
  FAdiada.Result.AsString := 'depois';
  FAdiada.Resolve;  { libera a chamada }
  FAdiada := nil;
  CheckEquals(1, FPosts.Count);
  R := Ultima;
  try
    CheckEquals('depois', R['result'].AsString);
  finally
    R.Free;
  end;
end;

procedure TTestBorionIpc.TestDeferRejectDepois;
begin
  Invocar('adiar', '');
  FAdiada.Reject('desistiu', 'CANCELADO');
  FAdiada := nil;
  CheckEquals('CANCELADO', UltimoErro);
end;

procedure TTestBorionIpc.TestDeferResolveDentroDoHandler;
var
  R: TJsonObject;
begin
  Invocar('adiarEResolverJa', '');
  CheckEquals(1, FPosts.Count, 'exatamente uma resposta');
  R := Ultima;
  try
    CheckEquals('na hora', R['result'].AsString);
  finally
    R.Free;
  end;
end;

procedure TTestBorionIpc.TestExcecaoDepoisDoDefer;
begin
  Invocar('adiarEFalhar', '');
  CheckEquals(1, FPosts.Count);
  CheckEquals('DEPOIS', UltimoErro);
end;

procedure TTestBorionIpc.TestResolveDeOutraThread;
var
  R: TJsonObject;
begin
  Invocar('thread', '');
  CheckEquals(0, FPosts.Count);
  Bombear(1);
  CheckEquals(1, FPosts.Count, 'a resposta da thread não chegou');
  R := Ultima;
  try
    CheckEquals('da thread', R['result'].AsString);
  finally
    R.Free;
  end;
end;

procedure TTestBorionIpc.TestChamadaOrfaAposDestruirIpc;
var
  Call: TBorionCall;
begin
  Invocar('adiar', '');
  Call := FAdiada;
  FAdiada := nil;
  FIpc.Free;
  FIpc := nil;
  Check(Call.Ipc = nil, 'chamada pendente deve ficar órfã');
  Call.Resolve;  { não pode falhar: a chamada se libera sozinha }
  CheckEquals(0, FPosts.Count);
end;

{ --- testes: origens ------------------------------------------------------ }

procedure TTestBorionIpc.TestOrigemNegadaPorPadrao;
begin
  Invocar('somar', '{}', 'https://example.com/pagina');
  CheckEquals('FORBIDDEN_ORIGIN', UltimoErro);
  Check(TemLog('https://example.com'), 'a tentativa deve aparecer no log');
end;

procedure TTestBorionIpc.TestOrigemLiberadaIgnoraCaixaEBarra;
begin
  FIpc.AllowOrigin('HTTPS://Outro.Local/');
  Invocar('somar', '{"a":1}', 'https://outro.local/x/y?z=1#w');
  CheckTrue(Pos('"ok":true', FPosts[FPosts.Count - 1]) > 0, FPosts[FPosts.Count - 1]);
end;

procedure TTestBorionIpc.TestOrigemComPortaDiferenteNegada;
begin
  Invocar('somar', '{}', 'https://app.localhost:8443/index.html');
  CheckEquals('FORBIDDEN_ORIGIN', UltimoErro);
end;

procedure TTestBorionIpc.TestOrigemCuringa;
begin
  FIpc.AllowOrigin('*');
  Invocar('somar', '{}', 'https://qualquer.coisa/');
  CheckTrue(Pos('"ok":true', FPosts[FPosts.Count - 1]) > 0);
end;

procedure TTestBorionIpc.TestBorionOriginOf;
begin
  CheckEquals('https://app.localhost', BorionOriginOf('https://app.localhost/a/b.html?x=1'));
  CheckEquals('https://app.localhost', BorionOriginOf('HTTPS://APP.LOCALHOST'));
  CheckEquals('http://localhost:5173', BorionOriginOf('http://localhost:5173/#/rota'));
  CheckEquals('https://h', BorionOriginOf('https://h?q'));
  CheckEquals('about:blank', BorionOriginOf('about:blank'));
end;

{ --- testes: eventos ------------------------------------------------------ }

procedure TTestBorionIpc.TestEmitJson;
begin
  FIpc.EmitJson('progresso', '{"pct":50}');
  CheckEquals('{"__borion":1,"kind":"event","event":"progresso","payload":{"pct":50}}', FPosts[0]);
end;

procedure TTestBorionIpc.TestEmitSemPayload;
begin
  FIpc.Emit('ping');
  FIpc.EmitJson('pong', '');
  CheckEquals('{"__borion":1,"kind":"event","event":"ping","payload":null}', FPosts[0]);
  CheckEquals('{"__borion":1,"kind":"event","event":"pong","payload":null}', FPosts[1]);
end;

procedure TTestBorionIpc.TestEmitObjeto;
var
  P: TJsonObject;
  R: TJsonObject;
begin
  P := TJsonObject.Create;
  try
    P.Put('a', 1);
    P.Put('b', 'x');
    FIpc.Emit('obj', P);
  finally
    P.Free;
  end;
  R := Ultima;
  try
    CheckEquals('obj', R['event'].AsString);
    CheckEquals(1, R['payload'].AsObject['a'].AsInteger);
    CheckEquals('x', R['payload'].AsObject['b'].AsString);
  finally
    R.Free;
  end;
end;

procedure TTestBorionIpc.TestEmitUnicode;
var
  V: TJsonValue;
begin
  Check(GetACP = 1252, 'teste assume cp1252');
  V := TJsonValue.Create(nil);
  try
    V.AsString := #147'oi'#148' '#227;
    FIpc.Emit('t', V);
  finally
    V.Free;
  end;
  CheckTrue(Pos('"payload":"\u201coi\u201d \u00e3"', FPosts[0]) > 0, FPosts[0]);
end;

procedure TTestBorionIpc.TestEmitDeOutraThread;
begin
  TThreadEmit.Create(FIpc).Resume;
  Bombear(1);
  CheckEquals(1, FPosts.Count, 'o evento da thread não chegou');
  CheckEquals('{"__borion":1,"kind":"event","event":"da-thread","payload":{"ok":true}}', FPosts[0]);
end;

procedure TTestBorionIpc.TestListenRecebeEvento;
begin
  FIpc.Listen('salvou', Evento);
  Check(FIpc.ProcessMessage('{"__borion":1,"kind":"emit","event":"salvou","payload":{"id":7}}', ORIGEM));
  FIpc.ProcessMessage('{"__borion":1,"kind":"emit","event":"outro","payload":1}', ORIGEM);
  CheckEquals(1, FEventos.Count);
  CheckEquals('salvou={"id":7}', FEventos[0]);
  CheckEquals(0, FPosts.Count, 'emit não tem resposta');
end;

procedure TTestBorionIpc.TestListenCuringa;
begin
  FIpc.Listen('*', Evento);
  FIpc.ProcessMessage('{"__borion":1,"kind":"emit","event":"a","payload":null}', ORIGEM);
  FIpc.ProcessMessage('{"__borion":1,"kind":"emit","event":"b"}', ORIGEM);
  CheckEquals(2, FEventos.Count);
  CheckEquals('a=null', FEventos[0]);
  CheckEquals('b=null', FEventos[1]);
end;

procedure TTestBorionIpc.TestUnlisten;
begin
  FIpc.Listen('x', Evento);
  FIpc.Unlisten('x', Evento);
  FIpc.ProcessMessage('{"__borion":1,"kind":"emit","event":"x","payload":1}', ORIGEM);
  CheckEquals(0, FEventos.Count);
end;

procedure TTestBorionIpc.TestListenerComErroNaoParaOsOutros;
begin
  FIpc.Listen('x', EventoComErro);
  FIpc.Listen('x', Evento);
  FIpc.ProcessMessage('{"__borion":1,"kind":"emit","event":"x","payload":1}', ORIGEM);
  CheckEquals(1, FEventos.Count, 'o segundo listener deve rodar');
  Check(TemLog('listener quebrado'));
end;

procedure TTestBorionIpc.TestEmitDeOrigemNegadaIgnorado;
begin
  FIpc.Listen('*', Evento);
  Check(FIpc.ProcessMessage('{"__borion":1,"kind":"emit","event":"x","payload":1}',
    'https://example.com/'));
  CheckEquals(0, FEventos.Count);
  Check(TemLog('emit negado'));
end;

{ --- testes: mensagens ---------------------------------------------------- }

procedure TTestBorionIpc.TestMensagemQueNaoEhDoBorionNaoEhTratada;
begin
  CheckFalse(FIpc.ProcessMessage('"texto"', ORIGEM));
  CheckFalse(FIpc.ProcessMessage('{"acao":"salvar"}', ORIGEM));
  CheckFalse(FIpc.ProcessMessage('{"texto":"menciona \"__borion\""}', ORIGEM));
  CheckFalse(FIpc.ProcessMessage('', ORIGEM));
  CheckEquals(0, FPosts.Count);
end;

procedure TTestBorionIpc.TestJsonInvalidoNaoQuebra;
begin
  CheckFalse(FIpc.ProcessMessage('{"__borion":1, "kind":', ORIGEM));
  Check(TemLog('inválida'));
end;

procedure TTestBorionIpc.TestCampoComTipoErradoNaoQuebra;
begin
  Check(FIpc.ProcessMessage('{"__borion":1,"kind":"invoke","id":1,"cmd":{"x":1}}', ORIGEM));
  Check(TemLog('malformada'));
  FIpc.ProcessMessage('{"__borion":1,"kind":"desconhecido"}', ORIGEM);
  Check(TemLog('desconhecido'));
end;

procedure TTestBorionIpc.TestInvokeSemIdIgnorado;
begin
  Check(FIpc.ProcessMessage('{"__borion":1,"kind":"invoke","cmd":"somar"}', ORIGEM));
  CheckEquals(0, FPosts.Count);
  Check(TemLog('sem id'));
end;

procedure TTestBorionIpc.TestUnicodeIdaEVolta;
var
  Msg: WideString;
begin
  Check(GetACP = 1252, 'teste assume cp1252');
  { como o WebView2 entrega: acentos literais e um escape \u acima de $FF }
  Msg := '{"__borion":1,"kind":"invoke","id":1,"cmd":"eco","args":{"texto":"S' +
    WideChar($E3) + 'o ' + WideChar($201C) + 'x” €"}}';
  FIpc.ProcessMessage(Msg, ORIGEM);
  CheckTrue(Pos('"result":"S\u00e3o \u201cx\u201d \u20ac|eco"', FPosts[0]) > 0, FPosts[0]);
end;

{ TTestBorionBridge }

procedure TTestBorionBridge.TestScriptExpoeApi;
var
  S: string;
begin
  S := BorionBridgeScript;
  Check(Pos('defineProperty(window, "borion"', S) = 0, 'sem window.borion, só __BORION__');
  Check(Pos('defineProperty(window, "__BORION__"', S) > 0);
  Check(Pos('version: "' + BORION_VERSION + '"', S) > 0, 'versão da ponte');
  Check(Pos('''', S) = 0, 'a ponte não deve ter aspas simples (vive numa string Pascal)');
end;

procedure TTestBorionBridge.TestExportaParaTestesJs;
var
  Pasta, Arquivo: string;
  F: TextFile;
begin
  { os testes JS (js/test) carregam a ponte deste arquivo }
  Pasta := ExtractFilePath(ParamStr(0)) + 'out';
  ForceDirectories(Pasta);
  Arquivo := Pasta + '\borion-bridge.js';
  AssignFile(F, Arquivo);
  Rewrite(F);
  try
    Write(F, string(BorionBridgeScript));  { só ASCII }
  finally
    CloseFile(F);
  end;
  Check(FileExists(Arquivo));
end;

initialization
  RegisterTest('BorionIpc', TTestBorionIpc.Suite);
  RegisterTest('BorionBridge', TTestBorionBridge.Suite);

end.
