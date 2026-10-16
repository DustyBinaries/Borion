unit TestBorionStartup;

{ Testes dos plugins deep-link e autostart. Gravam no HKCU com nomes de teste
  (esquema borion-teste-dunit, valor Borion.TesteDUnit.Autostart) e apagam
  tudo no fim. O caminho de exe usado tem acento, para testar o Unicode. }

interface

uses
  Windows, SysUtils, Classes, TestFramework, Jsons,
  BorionJson, BorionIpc, BorionRegistry, BorionSingleInstance, BorionDeepLink,
  BorionAutostart, TestBorionPlugins;

type
  TTestBorionDeepLink = class(TTesteComIpc)
  private
    FLink: TBorionDeepLinkPlugin;
    procedure Adicionar(ComUnica: Boolean);
  protected
    procedure TearDown; override;
  published
    procedure TestEsquemasValidos;
    procedure TestRegistraNoHkcu;
    procedure TestNaoApagaRegistroDeOutroApp;
    procedure TestEsquemaNaoDeclarado;
    procedure TestUrlsIn;
    procedure TestLinkComOAppAberto;
    procedure TestGetCurrent;
  end;

  TTestBorionAutostart = class(TTesteComIpc)
  private
    FAuto: TBorionAutostartPlugin;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLigaEDesliga;
    procedure TestDesligadoNoGerenciadorDeTarefas;
    procedure TestValorDeOutroExe;
    procedure TestLaunchedAtLogin;
  end;

implementation

const
  ESQUEMA = 'borion-teste-dunit';
  CHAVE = 'Software\Classes\' + ESQUEMA;
  NOME_AUTO = 'Borion.TesteDUnit.Autostart';

function ExeFalso: WideString;
begin
  Result := WideString('C:\Programas\') + WideChar($C1) + 'rea ' + WideChar($D83D) + WideChar($DE00) + '\app.exe';
end;

{ TTestBorionDeepLink }

procedure TTestBorionDeepLink.Adicionar(ComUnica: Boolean);
var
  U: TBorionSingleInstancePlugin;
begin
  if ComUnica then
  begin
    BorionIsSecondInstance('Borion.TesteDUnit.Unica');
    U := TBorionSingleInstancePlugin(FIpc.AddPlugin(TBorionSingleInstancePlugin.Create));
    U.FocusOnSecondInstance := False;
  end;
  FLink := TBorionDeepLinkPlugin.Create([ESQUEMA]);
  FLink.ExePath := ExeFalso;
  FLink.DisplayName := 'Teste do Borion';
  FIpc.AddPlugin(FLink);  { AutoRegister: registra no Install }
end;

procedure TTestBorionDeepLink.TearDown;
begin
  inherited;
  BorionRegDeleteTree(HKEY_CURRENT_USER, CHAVE);
end;

procedure TTestBorionDeepLink.TestEsquemasValidos;
begin
  Check(BorionValidScheme('meuapp'));
  Check(BorionValidScheme('meu-app.v2+x'));
  Check(not BorionValidScheme(''));
  Check(not BorionValidScheme('1app'), 'começa com número');
  Check(not BorionValidScheme('meu app'));
  Check(not BorionValidScheme('meuapp://'), 'sem o ://');
  Check(not BorionValidScheme('http'), 'esquema do sistema');
  Check(not BorionValidScheme('HTTPS'));
  Check(not BorionValidScheme('file'));
  Check(not BorionValidScheme('ms-settings'));
  try
    TBorionDeepLinkPlugin.Create(['mailto']).Free;
    Fail('mailto não pode');
  except
    on E: EBorionError do
      CheckEquals('INVALID_SCHEME', E.Code);
  end;
end;

procedure TTestBorionDeepLink.TestRegistraNoHkcu;
var
  V: WideString;
begin
  Adicionar(False);
  Check(BorionRegRead(HKEY_CURRENT_USER, CHAVE, '', V));
  CheckEquals('URL:Teste do Borion', V);
  Check(BorionRegRead(HKEY_CURRENT_USER, CHAVE, 'URL Protocol', V), 'URL Protocol');
  Check(BorionRegRead(HKEY_CURRENT_USER, CHAVE + '\shell\open\command', '', V));
  Check(V = '"' + ExeFalso + '" "%1"', 'comando com o caminho Unicode intacto');
  Check(BorionRegRead(HKEY_CURRENT_USER, CHAVE + '\DefaultIcon', '', V));
  Check(V = '"' + ExeFalso + '",0');
  CheckEquals('true', Ok('deep-link:isRegistered', '{"scheme":"' + ESQUEMA + '"}'));
  CheckEquals('true', Ok('deep-link:isRegistered', '{"scheme":"' + ESQUEMA + '://"}'), 'aceita com ://');
  Ok('deep-link:unregister', '{"scheme":"' + ESQUEMA + '"}');
  Check(not BorionRegKeyExists(HKEY_CURRENT_USER, CHAVE), 'apagado');
  CheckEquals('false', Ok('deep-link:isRegistered', '{"scheme":"' + ESQUEMA + '"}'));
  Ok('deep-link:register', '{"scheme":"' + ESQUEMA + '"}');
  Check(BorionRegKeyExists(HKEY_CURRENT_USER, CHAVE), 'registrado de novo');
end;

procedure TTestBorionDeepLink.TestNaoApagaRegistroDeOutroApp;
begin
  Adicionar(False);
  BorionRegWrite(HKEY_CURRENT_USER, CHAVE + '\shell\open\command', '', '"C:\outro\app.exe" "%1"');
  CheckEquals('false', Ok('deep-link:isRegistered', '{"scheme":"' + ESQUEMA + '"}'));
  Ok('deep-link:unregister', '{"scheme":"' + ESQUEMA + '"}');
  Check(BorionRegKeyExists(HKEY_CURRENT_USER, CHAVE), 'o registro do outro app ficou');
end;

procedure TTestBorionDeepLink.TestEsquemaNaoDeclarado;
begin
  Adicionar(False);
  CheckEquals('FORBIDDEN_SCHEME', Erro('deep-link:register', '{"scheme":"outro-app"}'));
  CheckEquals('FORBIDDEN_SCHEME', Erro('deep-link:unregister', '{"scheme":"http"}'));
  CheckEquals('FORBIDDEN_SCHEME', Erro('deep-link:isRegistered', '{}'));
end;

procedure TTestBorionDeepLink.TestUrlsIn;
var
  Args, Urls: TBorionArgs;
begin
  Adicionar(False);
  SetLength(Args, 4);
  Args[0] := '--x';
  Args[1] := 'BORION-TESTE-DUNIT://abrir?id=1';
  Args[2] := 'outro://x';
  Args[3] := ESQUEMA + ':sem-barras';
  Urls := FLink.UrlsIn(Args);
  CheckEquals(2, Length(Urls));
  Check(Urls[0] = Args[1]);
  Check(Urls[1] = Args[3]);
end;

procedure TTestBorionDeepLink.TestLinkComOAppAberto;
var
  Args: TBorionArgs;
begin
  Adicionar(True);
  SetLength(Args, 1);
  Args[0] := ESQUEMA + '://pedido/42?nome=Jo' + WideChar($E3) + 'o';
  FPosts.Clear;
  Check(BorionSingleInstanceSend('Borion.TesteDUnit.Unica', Args, 'C:\'));
  Bombear(2);
  CheckEquals(2, FPosts.Count, 'single-instance:second e deep-link:open');
  Check(Pos('"event":"single-instance:second"', FPosts[0]) > 0, FPosts[0]);
  CheckEquals('{"__borion":1,"kind":"event","event":"deep-link:open","payload":' +
    '{"urls":["\"' + ESQUEMA + ':\/\/pedido\/42?nome=Jo\\u00e3o\""]}}', FPosts[1]);
  { argumentos sem link: só o evento do single-instance }
  Args[0] := 'nota.txt';
  FPosts.Clear;
  BorionSingleInstanceSend('Borion.TesteDUnit.Unica', Args, 'C:\');
  Bombear(1);
  Sleep(100);
  Bombear(2, 200);
  CheckEquals(1, FPosts.Count);
end;

procedure TTestBorionDeepLink.TestGetCurrent;
begin
  Adicionar(False);
  CheckEquals('[]', Ok('deep-link:getCurrent', ''), 'o runner dos testes não veio de um link');
end;

{ TTestBorionAutostart }

procedure TTestBorionAutostart.SetUp;
begin
  inherited;
  FAuto := TBorionAutostartPlugin(FIpc.AddPlugin(TBorionAutostartPlugin.Create(NOME_AUTO)));
  FAuto.ExePath := ExeFalso;
end;

procedure TTestBorionAutostart.TearDown;
begin
  BorionRegDeleteValue(HKEY_CURRENT_USER, BORION_RUN_KEY, NOME_AUTO);
  BorionRegDeleteValue(HKEY_CURRENT_USER, BORION_STARTUP_APPROVED_KEY, NOME_AUTO);
  inherited;
end;

procedure TTestBorionAutostart.TestLigaEDesliga;
var
  V: WideString;
  B: string;
begin
  CheckEquals('false', Ok('autostart:isEnabled', ''));
  Ok('autostart:enable', '');
  Check(BorionRegRead(HKEY_CURRENT_USER, BORION_RUN_KEY, NOME_AUTO, V));
  Check(V = '"' + ExeFalso + '" --autostart', 'caminho Unicode e o argumento');
  Check(BorionRegReadBinary(HKEY_CURRENT_USER, BORION_STARTUP_APPROVED_KEY, NOME_AUTO, B));
  CheckEquals(#2 + StringOfChar(#0, 11), B, 'habilitado para o Gerenciador de Tarefas');
  CheckEquals('true', Ok('autostart:isEnabled', ''));
  Ok('autostart:disable', '');
  Check(not BorionRegRead(HKEY_CURRENT_USER, BORION_RUN_KEY, NOME_AUTO, V), 'Run apagado');
  Check(not BorionRegReadBinary(HKEY_CURRENT_USER, BORION_STARTUP_APPROVED_KEY, NOME_AUTO, B));
  CheckEquals('false', Ok('autostart:isEnabled', ''));
  Ok('autostart:disable', '');  { desligar de novo não é erro }
end;

procedure TTestBorionAutostart.TestDesligadoNoGerenciadorDeTarefas;
begin
  Ok('autostart:enable', '');
  { o que o Gerenciador de Tarefas grava ao desabilitar }
  BorionRegWriteBinary(HKEY_CURRENT_USER, BORION_STARTUP_APPROVED_KEY, NOME_AUTO,
    #3#0#0#0 + 'carimbo!');
  CheckEquals('false', Ok('autostart:isEnabled', ''));
  Ok('autostart:enable', '');
  CheckEquals('true', Ok('autostart:isEnabled', ''), 'enable volta a ligar');
end;

procedure TTestBorionAutostart.TestValorDeOutroExe;
begin
  BorionRegWrite(HKEY_CURRENT_USER, BORION_RUN_KEY, NOME_AUTO, '"C:\outro\app.exe" --autostart');
  CheckEquals('false', Ok('autostart:isEnabled', ''), 'o valor existe, mas é de outro exe');
end;

procedure TTestBorionAutostart.TestLaunchedAtLogin;
begin
  CheckEquals('false', Ok('autostart:launchedAtLogin', ''));
end;

initialization
  RegisterTest('Plugins', TTestBorionDeepLink.Suite);
  RegisterTest('Plugins', TTestBorionAutostart.Suite);

end.
