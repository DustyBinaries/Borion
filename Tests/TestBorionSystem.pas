unit TestBorionSystem;

{ Testes dos plugins notification e single-instance. Nenhuma notificação de
  verdade é mostrada: o XML, os argumentos e os eventos são testados direto, e
  o registro do AppUserModelID usa um AppId de teste que é apagado no fim. }

interface

uses
  Windows, Messages, SysUtils, Classes, Registry, TestFramework, Jsons,
  BorionJson, BorionIpc, BorionNotification, BorionSingleInstance, TestBorionPlugins;

type
  TTestBorionNotification = class(TTesteComIpc)
  private
    FNotif: TBorionNotificationPlugin;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestToastXml;
    procedure TestToastXmlEscapaTexto;
    procedure TestAppIdPadrao;
    procedure TestIdsValidos;
    procedure TestArgsInvalidos;
    procedure TestCliqueEBotao;
    procedure TestDispensadaEFalha;
    procedure TestRegistraOAppId;
  end;

  TTestBorionSingleInstance = class(TTesteComIpc)
  private
    FPlugin: TBorionSingleInstancePlugin;
  protected
    procedure SetUp; override;
  published
    procedure TestPrimeiraInstancia;
    procedure TestSegundaInstanciaEntregaArgumentos;
    procedure TestSemInstanciaAberta;
    procedure TestArgsJson;
    procedure TestComandoArgs;
  end;

implementation

const
  APP_TESTE = 'Borion.TesteDUnit';

function Ola: WideString;
begin
  Result := WideString('ol') + WideChar($E1) + ' ' + WideChar($D83D) + WideChar($DE00);
end;

{ TTestBorionNotification }

procedure TTestBorionNotification.SetUp;
begin
  inherited;
  FNotif := TBorionNotificationPlugin(FIpc.AddPlugin(TBorionNotificationPlugin.Create(APP_TESTE)));
  FNotif.FocusOnClick := False;  { sem janela nos testes }
end;

procedure TTestBorionNotification.TearDown;
begin
  inherited;
  BorionNotificationUnregister(APP_TESTE);
end;

procedure TTestBorionNotification.TestToastXml;
var
  Acoes: TBorionNotificationActions;
begin
  CheckEquals('<toast launch="borion|n1|"><visual><binding template="ToastGeneric">' +
    '<text>T</text></binding></visual></toast>', string(BorionToastXml('n1', 'T', '', False, nil, '')));
  SetLength(Acoes, 2);
  Acoes[0].Id := 'sim';
  Acoes[0].Title := 'Sim';
  Acoes[1].Id := 'nao';
  Acoes[1].Title := WideString('N') + WideChar($E3) + 'o';
  Check(BorionToastXml('n2', 'T', 'Corpo', True, Acoes, 'C:\img\logo.png') =
    '<toast launch="borion|n2|"><visual><binding template="ToastGeneric">' +
    '<text>T</text><text>Corpo</text>' +
    '<image placement="appLogoOverride" src="file:///C:/img/logo.png"/></binding></visual>' +
    '<actions><action content="Sim" arguments="borion|n2|sim" activationType="foreground"/>' +
    WideString('<action content="N') + WideChar($E3) + 'o" arguments="borion|n2|nao" activationType="foreground"/></actions>' +
    '<audio silent="true"/></toast>', 'botões, ícone e silencioso');
end;

procedure TTestBorionNotification.TestToastXmlEscapaTexto;
var
  X: WideString;
begin
  X := BorionToastXml('n', '<b>"A" & ''B''</b>', Ola, False, nil, '');
  Check(Pos('<text>&lt;b&gt;&quot;A&quot; &amp; &apos;B&apos;&lt;/b&gt;</text>', X) > 0, X);
  Check(Pos('<text>' + Ola + '</text>', X) > 0, 'emoji intacto no XML');
end;

procedure TTestBorionNotification.TestAppIdPadrao;
begin
  CheckEquals('Borion.MeuApp2', BorionDefaultAppId('Meu App 2!'));
  CheckEquals('Borion.App', BorionDefaultAppId('***'));
  CheckEquals(APP_TESTE, FNotif.AppId);
end;

procedure TTestBorionNotification.TestIdsValidos;
begin
  Check(BorionValidNotificationId('pedido-123'));
  Check(BorionValidNotificationId('a.b_c:d'));
  Check(not BorionValidNotificationId(''));
  Check(not BorionValidNotificationId('com|barra'), 'o | separa os argumentos');
  Check(not BorionValidNotificationId('com espaço'));
  Check(not BorionValidNotificationId(StringOfChar('a', 65)));
end;

procedure TTestBorionNotification.TestArgsInvalidos;
begin
  CheckEquals('INVALID_ARGS', Erro('notification:send', '{}'));
  CheckEquals('INVALID_ARGS', Erro('notification:send', '{"title":"sem aspas"}'));
  CheckEquals('INVALID_ARGS', Erro('notification:send', '{"title":"\"T\"","id":"com|barra"}'));
  CheckEquals('INVALID_ARGS', Erro('notification:send', '{"title":"\"T\"","actions":[{"id":"a"}]}'));
  CheckEquals('INVALID_ARGS', Erro('notification:send', '{"title":"\"T\"","actions":[{"id":"a b","title":"\"A\""}]}'));
  CheckEquals('INVALID_ARGS', Erro('notification:send', '{"title":"\"T\"","actions":[' +
    '{"id":"1","title":"\"1\""},{"id":"2","title":"\"2\""},{"id":"3","title":"\"3\""},' +
    '{"id":"4","title":"\"4\""},{"id":"5","title":"\"5\""},{"id":"6","title":"\"6\""}]}'));
end;

procedure TTestBorionNotification.TestCliqueEBotao;
begin
  FPosts.Clear;
  FNotif.Activated('pedido-1', 'borion|pedido-1|');
  FNotif.Activated('pedido-1', 'borion|pedido-1|aprovar');
  CheckEquals('{"__borion":1,"kind":"event","event":"notification:click","payload":' +
    '{"id":"pedido-1","action":null}}', FPosts[0]);
  CheckEquals('{"__borion":1,"kind":"event","event":"notification:click","payload":' +
    '{"id":"pedido-1","action":"aprovar"}}', FPosts[1]);
end;

procedure TTestBorionNotification.TestDispensadaEFalha;
begin
  FPosts.Clear;
  FNotif.Dismissed('a', 0);
  FNotif.Dismissed('b', 1);
  FNotif.Dismissed('c', 2);
  FNotif.NotificationFailed('d', Integer($80070490));
  Check(Pos('"payload":{"id":"a","reason":"user"}', FPosts[0]) > 0, FPosts[0]);
  Check(Pos('"payload":{"id":"b","reason":"hidden"}', FPosts[1]) > 0, FPosts[1]);
  Check(Pos('"payload":{"id":"c","reason":"timeout"}', FPosts[2]) > 0, FPosts[2]);
  Check(Pos('"event":"notification:failed","payload":{"id":"d","error":"$80070490"}', FPosts[3]) > 0, FPosts[3]);
end;

procedure TTestBorionNotification.TestRegistraOAppId;
var
  R: TRegistry;
  P: string;
begin
  if not FNotif.ToastsAvailable then
    Exit;  { Windows 7: sem WinRT, sem registro }
  FNotif.DisplayName := 'Teste do Borion';
  P := Ok('notification:permission', '');
  Check((P = '"granted"') or (P = '"denied"'), P);
  R := TRegistry.Create(KEY_READ);
  try
    R.RootKey := HKEY_CURRENT_USER;
    Check(R.OpenKey('Software\Classes\AppUserModelId\' + APP_TESTE, False), 'AppId registrado');
    CheckEquals('Teste do Borion', R.ReadString('DisplayName'));
    R.CloseKey;
    BorionNotificationUnregister(APP_TESTE);
    Check(not R.KeyExists('Software\Classes\AppUserModelId\' + APP_TESTE), 'removido');
  finally
    R.Free;
  end;
end;

{ TTestBorionSingleInstance }

procedure TTestBorionSingleInstance.SetUp;
begin
  inherited;
  BorionIsSecondInstance('Borion.TesteDUnit.Unica');  { primeira: passa a escutar }
  FPlugin := TBorionSingleInstancePlugin(FIpc.AddPlugin(TBorionSingleInstancePlugin.Create));
  FPlugin.FocusOnSecondInstance := False;
end;

procedure TTestBorionSingleInstance.TestPrimeiraInstancia;
begin
  { já é a primeira: chamar de novo não muda nada }
  Check(not BorionIsSecondInstance('Borion.TesteDUnit.Unica'));
end;

procedure TTestBorionSingleInstance.TestSegundaInstanciaEntregaArgumentos;
var
  Args: TBorionArgs;
  Recebidos: string;
begin
  SetLength(Args, 2);
  Args[0] := '--abrir';
  Args[1] := 'C:\notas\' + Ola + '.txt';
  FPosts.Clear;
  Check(BorionSingleInstanceSend('Borion.TesteDUnit.Unica', Args, 'C:\pasta'));
  Bombear(1);
  CheckEquals(1, FPosts.Count, 'o evento chegou');
  Recebidos := FPosts[0];
  CheckEquals('{"__borion":1,"kind":"event","event":"single-instance:second","payload":' +
    '{"args":["\"--abrir\"","\"C:\\\\notas\\\\ol\\u00e1 \\ud83d\\ude00.txt\""],' +
    '"cwd":"\"C:\\\\pasta\""}}', Recebidos);
end;

procedure TTestBorionSingleInstance.TestSemInstanciaAberta;
var
  T: Cardinal;
begin
  T := GetTickCount;
  Check(not BorionSingleInstanceSend('Borion.TesteDUnit.NinguemAberto', nil, '', 300));
  Check(GetTickCount - T < 2000, 'respeita o timeout');
end;

procedure TTestBorionSingleInstance.TestArgsJson;
var
  Args: TBorionArgs;
begin
  CheckEquals('{"args":[],"cwd":"\"\""}', BorionArgsJson(nil, ''));
  SetLength(Args, 1);
  Args[0] := 'a "b"';
  CheckEquals('{"args":["\"a \\\"b\\\"\""],"cwd":"\"C:\\\\x\""}', BorionArgsJson(Args, 'C:\x'));
end;

procedure TTestBorionSingleInstance.TestComandoArgs;
var
  R: TJsonObject;
begin
  R := TJsonObject.Create;
  try
    R.Parse(Ok('single-instance:args', ''));
    CheckEquals(Length(BorionCommandLineArgs), R['args'].AsArray.Count);
    Check(Pos('"', R['cwd'].AsString) = 1, 'cwd como literal JSON: ' + R['cwd'].AsString);
  finally
    R.Free;
  end;
end;

initialization
  RegisterTest('Plugins', TTestBorionNotification.Suite);
  RegisterTest('Plugins', TTestBorionSingleInstance.Suite);

end.
