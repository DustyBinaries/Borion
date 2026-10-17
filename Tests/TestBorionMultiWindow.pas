unit TestBorionMultiWindow;

{ Testes de várias janelas: o TBorionIpc com mais de um browser (para onde vão
  as respostas e os eventos, o emitTo entre janelas, os avisos aos plugins) e
  o plugin window controlando duas TBorionWindow do mesmo IPC. Os browsers
  nunca criam o WebView: as mensagens entram por ProcessMessageFrom e saem
  pelo OnPostTo. }

interface

uses
  Windows, Messages, SysUtils, Classes, Controls, Forms, TestFramework, Jsons, BorionJson,
  WebView2Browser, BorionIpc, BorionWindow, Borion;

type
  TTestIpcJanelas = class(TTestCase)
  private
    FIpc: TBorionIpc;
    FMain, FConfig: TWebView2Browser;
    FPosts: TStringList;   { destino=json }
    FLogs: TStringList;
    FJanelaDoComando: string;
    FJanelaDoEvento: string;
    FAdiada: TBorionCall;
    procedure PostouPara(Sender: TObject; const WindowLabel: string; const Json: WideString);
    procedure Logou(Sender: TObject; const Msg: string);
    procedure CmdQuem(Call: TBorionCall);
    procedure CmdAdiar(Call: TBorionCall);
    procedure Evento(const Event: string; Payload: TJsonValue);
    function Invocar(const Janela, Cmd: string): Boolean;
    function Destinos: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestJanelas;
    procedure TestRotulosInvalidosERepetidos;
    procedure TestRespostaVoltaParaQuemChamou;
    procedure TestCallSabeAJanela;
    procedure TestEmitParaTodasEEmitTo;
    procedure TestEmitToDaPagina;
    procedure TestEmitToNegadoOuSemDestino;
    procedure TestListenerSabeAJanela;
    procedure TestRespostaDeJanelaFechadaDescartada;
    procedure TestLiberarOBrowserTiraAJanela;
    procedure TestPluginsSabemDasJanelas;
  end;

  TTestWindowVariasJanelas = class(TTestCase)
  private
    FMain, FConfig: TBorionWindow;
    FWin: TBorionWindowPlugin;
    FPosts: TStringList;
    procedure PostouPara(Sender: TObject; const WindowLabel: string; const Json: WideString);
    function Ok(const Janela, Cmd, ArgsJson: string): string;
    function Erro(const Janela, Cmd, ArgsJson: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCadaJanelaComOSeuForm;
    procedure TestComandoPeloRotulo;
    procedure TestEventosVaoParaAPropriaJanela;
    procedure TestInterceptacaoPorJanela;
    procedure TestList;
    procedure TestFecharUmaSecundaria;
    procedure TestCreateSemOBuilder;
  end;

implementation

const
  ORIGEM = 'https://app.local/';

type
  TPluginEspiao = class(TBorionPlugin)
  private
    FLog: TStringList;
  protected
    procedure Install; override;
    procedure WindowAdded(const WindowLabel: string; ABrowser: TWebView2Browser); override;
    procedure WindowRemoved(const WindowLabel: string; ABrowser: TWebView2Browser); override;
  public
    constructor Create(ALog: TStringList);
    function Name: string; override;
  end;

constructor TPluginEspiao.Create(ALog: TStringList);
begin
  inherited Create;
  FLog := ALog;
end;

function TPluginEspiao.Name: string;
begin
  Result := 'espiao';
end;

procedure TPluginEspiao.Install;
begin
  FLog.Add('install:' + IntToStr(Ipc.WindowCount));
end;

procedure TPluginEspiao.WindowAdded(const WindowLabel: string; ABrowser: TWebView2Browser);
begin
  FLog.Add('+' + WindowLabel);
end;

procedure TPluginEspiao.WindowRemoved(const WindowLabel: string; ABrowser: TWebView2Browser);
begin
  FLog.Add('-' + WindowLabel);
end;

function Mensagem(const Kind, Resto: string): string;
begin
  Result := '{"__borion":1,"kind":"' + Kind + '",' + Resto + '}';
end;

{ TTestIpcJanelas }

procedure TTestIpcJanelas.SetUp;
begin
  FPosts := TStringList.Create;
  FLogs := TStringList.Create;
  FMain := TWebView2Browser.Create(nil);
  FConfig := TWebView2Browser.Create(nil);
  FIpc := TBorionIpc.Create(nil, FMain);
  FIpc.AddWindow('config', FConfig);
  FIpc.AllowOrigin(ORIGEM);
  FIpc.OnPostTo := PostouPara;
  FIpc.OnLog := Logou;
  FIpc.RegisterCommand('quem', CmdQuem);
  FIpc.RegisterCommand('adiar', CmdAdiar);
end;

procedure TTestIpcJanelas.TearDown;
begin
  FreeAndNil(FIpc);
  FConfig.Free;
  FMain.Free;
  FLogs.Free;
  FPosts.Free;
end;

procedure TTestIpcJanelas.PostouPara(Sender: TObject; const WindowLabel: string; const Json: WideString);
begin
  FPosts.Add(WindowLabel + '=' + WideJsonToAnsi(Json));
end;

procedure TTestIpcJanelas.Logou(Sender: TObject; const Msg: string);
begin
  FLogs.Add(Msg);
end;

procedure TTestIpcJanelas.CmdQuem(Call: TBorionCall);
begin
  FJanelaDoComando := FIpc.CurrentWindow;
  Call.Result.AsString := Call.Window;
  Check(Call.Browser = FIpc.WindowBrowser(Call.Window), 'Call.Browser');
end;

procedure TTestIpcJanelas.CmdAdiar(Call: TBorionCall);
begin
  Call.Defer;
  FAdiada := Call;
end;

procedure TTestIpcJanelas.Evento(const Event: string; Payload: TJsonValue);
begin
  FJanelaDoEvento := FIpc.CurrentWindow;
end;

function TTestIpcJanelas.Invocar(const Janela, Cmd: string): Boolean;
begin
  Result := FIpc.ProcessMessageFrom(Janela, Mensagem('invoke', '"id":1,"cmd":"' + Cmd + '"'), ORIGEM);
end;

function TTestIpcJanelas.Destinos: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to FPosts.Count - 1 do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + FPosts.Names[I];
  end;
end;

procedure TTestIpcJanelas.TestJanelas;
begin
  CheckEquals(2, FIpc.WindowCount);
  CheckEquals('main', FIpc.WindowLabel(0), 'o browser do Create é a main');
  CheckEquals('config', FIpc.WindowLabel(1));
  Check(FIpc.Browser = FMain, 'Browser: o da principal');
  Check(FIpc.WindowBrowser('config') = FConfig);
  Check(FIpc.WindowBrowser('outra') = nil);
  CheckEquals('config', FIpc.WindowOf(FConfig));
  CheckEquals('', FIpc.WindowOf(nil));
  FIpc.RemoveWindow('config');
  CheckEquals(1, FIpc.WindowCount);
  FIpc.RemoveWindow('config');  { de novo: nada }
  Check(not Assigned(FConfig.OnWebMessageJson), 'o browser fica solto');
end;

procedure TTestIpcJanelas.TestRotulosInvalidosERepetidos;
var
  B: TWebView2Browser;
begin
  B := TWebView2Browser.Create(nil);
  try
    try
      FIpc.AddWindow('config', B);
      Fail('rótulo repetido');
    except
      on E: EBorionError do
        CheckEquals('WINDOW_EXISTS', E.Code);
    end;
    try
      FIpc.AddWindow('com espaço', B);
      Fail('rótulo inválido');
    except
      on E: EBorionError do
        CheckEquals('INVALID_LABEL', E.Code);
    end;
    CheckEquals(2, FIpc.WindowCount, 'nada entrou');
  finally
    B.Free;
  end;
end;

procedure TTestIpcJanelas.TestRespostaVoltaParaQuemChamou;
begin
  Check(Invocar('config', 'quem'));
  CheckEquals(1, FPosts.Count);
  CheckEquals('config', FPosts.Names[0], 'só para a janela que chamou');
  Check(Pos('"result":"config"', FPosts[0]) > 0, FPosts[0]);
  FPosts.Clear;
  Invocar('main', 'quem');
  CheckEquals('main', Destinos);
  FPosts.Clear;
  FIpc.ProcessMessage(Mensagem('invoke', '"id":1,"cmd":"quem"'), ORIGEM);
  CheckEquals('main', Destinos, 'ProcessMessage: a principal');
end;

procedure TTestIpcJanelas.TestCallSabeAJanela;
begin
  Invocar('config', 'quem');
  CheckEquals('config', FJanelaDoComando, 'Ipc.CurrentWindow durante o comando');
  CheckEquals('', FIpc.CurrentWindow, 'e só durante');
end;

procedure TTestIpcJanelas.TestEmitParaTodasEEmitTo;
begin
  FIpc.EmitJson('salvou', '{"id":1}');
  CheckEquals('*', Destinos, 'Emit: todas');
  FPosts.Clear;
  FIpc.EmitJsonTo('config', 'so-config', 'null');
  CheckEquals('config', Destinos);
  Check(Pos('"event":"so-config"', FPosts[0]) > 0);
  FPosts.Clear;
  FIpc.EmitTo('*', 'todas', nil);
  CheckEquals('*', Destinos);
end;

procedure TTestIpcJanelas.TestEmitToDaPagina;
begin
  Check(FIpc.ProcessMessageFrom('config', Mensagem('emitTo',
    '"target":"main","event":"preferencias","payload":{"tema":"escuro","acento":"é"}'), ORIGEM));
  CheckEquals('main', Destinos, 'repassado só para a main');
  Check(Pos('"kind":"event","event":"preferencias","payload":{"tema":"escuro","acento":"é"}', FPosts[0]) > 0,
    FPosts[0]);
  FPosts.Clear;
  FIpc.ProcessMessageFrom('main', Mensagem('emitTo', '"target":"*","event":"oi"'), ORIGEM);
  CheckEquals('*', Destinos);
  Check(Pos('"payload":null', FPosts[0]) > 0, 'sem payload: null');
end;

procedure TTestIpcJanelas.TestEmitToNegadoOuSemDestino;
begin
  FIpc.ProcessMessageFrom('config', Mensagem('emitTo', '"target":"main","event":"x"'), 'https://outro.com/');
  CheckEquals(0, FPosts.Count, 'origem não liberada');
  FIpc.ProcessMessageFrom('config', Mensagem('emitTo', '"target":"sumiu","event":"x"'), ORIGEM);
  CheckEquals(0, FPosts.Count, 'janela que não existe');
  Check(Pos('sumiu', FLogs.Text) > 0, FLogs.Text);
end;

procedure TTestIpcJanelas.TestListenerSabeAJanela;
begin
  FIpc.Listen('salvar', Evento);
  FIpc.ProcessMessageFrom('config', Mensagem('emit', '"event":"salvar","payload":1'), ORIGEM);
  CheckEquals('config', FJanelaDoEvento);
end;

procedure TTestIpcJanelas.TestRespostaDeJanelaFechadaDescartada;
begin
  Invocar('config', 'adiar');
  CheckEquals(0, FPosts.Count);
  FIpc.RemoveWindow('config');
  FAdiada.Result.AsString := 'tarde';
  FAdiada.Resolve;
  CheckEquals(0, FPosts.Count, 'a janela fechou: não há para quem responder');
  Check(Pos('descartada', FLogs.Text) > 0, FLogs.Text);
end;

procedure TTestIpcJanelas.TestLiberarOBrowserTiraAJanela;
begin
  FreeAndNil(FConfig);
  CheckEquals(1, FIpc.WindowCount);
  CheckEquals('', FIpc.WindowOf(nil));
  Check(FIpc.WindowBrowser('config') = nil);
end;

procedure TTestIpcJanelas.TestPluginsSabemDasJanelas;
var
  Log: TStringList;
  B: TWebView2Browser;
begin
  Log := TStringList.Create;
  B := TWebView2Browser.Create(nil);
  try
    FIpc.AddPlugin(TPluginEspiao.Create(Log));
    FIpc.AddWindow('log', B);
    FIpc.RemoveWindow('log');
    FIpc.AddWindow('log', B);
    FreeAndNil(B);
    CheckEquals('install:2,+log,-log,+log,-log', Log.CommaText);
  finally
    B.Free;
    FreeAndNil(FIpc);  { antes do Log, que o plugin usa }
    Log.Free;
  end;
end;

{ TTestWindowVariasJanelas }

procedure TTestWindowVariasJanelas.SetUp;
begin
  FPosts := TStringList.Create;
  FMain := TBorionWindow.Create(nil);
  FMain.SetBounds(10, 10, 800, 600);
  FMain.HandleNeeded;
  FConfig := TBorionWindow.CreateWindow(nil, FMain.Ipc, 'config');
  FConfig.SetBounds(50, 50, 400, 300);
  FConfig.HandleNeeded;
  FMain.Ipc.AllowOrigin(ORIGEM);
  FMain.Ipc.OnPostTo := PostouPara;
  FWin := TBorionWindowPlugin(FMain.Ipc.AddPlugin(TBorionWindowPlugin.Create));
end;

procedure TTestWindowVariasJanelas.TearDown;
begin
  FConfig.Free;  { as secundárias antes: o IPC é da principal }
  FMain.Free;
  FPosts.Free;
end;

procedure TTestWindowVariasJanelas.PostouPara(Sender: TObject; const WindowLabel: string;
  const Json: WideString);
begin
  FPosts.Add(WindowLabel + '=' + WideJsonToAnsi(Json));
end;

function TTestWindowVariasJanelas.Ok(const Janela, Cmd, ArgsJson: string): string;
var
  Args, S: string;
  O: TJsonObject;
begin
  FPosts.Clear;
  Args := ArgsJson;
  if Args = '' then
    Args := '{}';
  FMain.Ipc.ProcessMessageFrom(Janela, Mensagem('invoke', '"id":9,"cmd":"' + Cmd + '","args":' + Args), ORIGEM);
  CheckEquals(Janela, FPosts.Names[FPosts.Count - 1], 'a resposta volta para quem chamou');
  S := FPosts.ValueFromIndex[FPosts.Count - 1];
  O := TJsonObject.Create;
  try
    O.Parse(S);
    Check(O['ok'].AsBoolean, Cmd + ': ' + S);
    Result := O['result'].Stringify;
  finally
    O.Free;
  end;
end;

function TTestWindowVariasJanelas.Erro(const Janela, Cmd, ArgsJson: string): string;
var
  O: TJsonObject;
begin
  FPosts.Clear;
  FMain.Ipc.ProcessMessageFrom(Janela, Mensagem('invoke', '"id":9,"cmd":"' + Cmd + '","args":' + ArgsJson), ORIGEM);
  O := TJsonObject.Create;
  try
    O.Parse(FPosts.ValueFromIndex[FPosts.Count - 1]);
    CheckFalse(O['ok'].AsBoolean);
    Result := O['error'].AsObject['code'].AsString;
  finally
    O.Free;
  end;
end;

procedure TTestWindowVariasJanelas.TestCadaJanelaComOSeuForm;
begin
  Check(FWin.FormOf('main') = FMain);
  Check(FWin.FormOf('config') = FConfig);
  Check(FMain.IsMain);
  CheckFalse(FConfig.IsMain);
  CheckEquals('config', FConfig.WindowLabel);
  Ok('config', 'window:setSize', '{"width":420,"height":320}');
  CheckEquals(420, FConfig.Width, 'a janela que chamou');
  CheckEquals(800, FMain.Width, 'a outra não mudou');
  Ok('main', 'window:setTitle', '{"title":"Principal"}');
  CheckEquals('Principal', FMain.Caption);
end;

procedure TTestWindowVariasJanelas.TestComandoPeloRotulo;
begin
  Ok('config', 'window:setSize', '{"label":"main","width":700,"height":500}');
  CheckEquals(700, FMain.Width, 'o label escolhe a janela');
  CheckEquals(400, FConfig.Width);
  CheckEquals('WINDOW_NOT_FOUND', Erro('main', 'window:show', '{"label":"sumiu"}'));
end;

procedure TTestWindowVariasJanelas.TestEventosVaoParaAPropriaJanela;
var
  I: Integer;
begin
  Ok('config', 'window:setPosition', '{"x":60,"y":70}');
  for I := 0 to FPosts.Count - 1 do
    if Pos('"event":"window:moved"', FPosts[I]) > 0 then
      CheckEquals('config', FPosts.Names[I], 'o evento é da janela que mudou');
  Check(Pos('config={"__borion":1,"kind":"event","event":"window:moved","payload":{"x":60,"y":70}}',
    FPosts.Text) > 0, FPosts.Text);
end;

procedure TTestWindowVariasJanelas.TestInterceptacaoPorJanela;
begin
  Ok('config', 'window:interceptClose', '{"enabled":true}');
  FPosts.Clear;
  SendMessage(FMain.Handle, WM_CLOSE, 0, 0);
  CheckEquals(0, FPosts.Count, 'a principal não intercepta');
  SendMessage(FConfig.Handle, WM_CLOSE, 0, 0);
  Check(Pos('config={"__borion":1,"kind":"event","event":"window:close-requested"', FPosts.Text) > 0,
    FPosts.Text);
end;

procedure TTestWindowVariasJanelas.TestList;
var
  S: string;
begin
  S := Ok('config', 'window:list', '');
  Check(Pos('{"label":"main","title":"","visible":false,"main":true}', S) > 0, S);
  Check(Pos('{"label":"config","title":"","visible":false,"main":false}', S) > 0, S);
end;

procedure TTestWindowVariasJanelas.TestFecharUmaSecundaria;
begin
  FPosts.Clear;
  FreeAndNil(FConfig);
  CheckEquals(1, FMain.Ipc.WindowCount, 'saiu do IPC');
  Check(FWin.FormOf('config') = nil, 'o plugin soltou o form');
  Check(Pos('*={"__borion":1,"kind":"event","event":"window:destroyed","payload":{"label":"config"}}',
    FPosts.Text) > 0, FPosts.Text);
  CheckEquals('WINDOW_NOT_FOUND', Erro('main', 'window:show', '{"label":"config"}'));
end;

procedure TTestWindowVariasJanelas.TestCreateSemOBuilder;
var
  Msg: TMsg;
  I: Integer;
begin
  { o create roda pelo Ipc.Later: a resposta sai depois das mensagens }
  FPosts.Clear;
  FMain.Ipc.ProcessMessageFrom('main', Mensagem('invoke', '"id":9,"cmd":"window:create","args":{"label":"x"}'),
    ORIGEM);
  for I := 1 to 50 do
  begin
    while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
      DispatchMessage(Msg);
    if FPosts.Count > 0 then
      Break;
    Sleep(10);
  end;
  Check(Pos('"code":"NOT_SUPPORTED"', FPosts.Text) > 0, FPosts.Text);
end;

initialization
  RegisterTest('Janelas', TTestIpcJanelas.Suite);
  RegisterTest('Janelas', TTestWindowVariasJanelas.Suite);

end.
