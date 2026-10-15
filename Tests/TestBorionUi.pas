unit TestBorionUi;

{ Testes dos plugins de interface: menu, tray e app. Usam um form criado em
  memória (nunca mostrado) e capturam as chamadas ao Shell_NotifyIcon, para não
  criar ícones nem notificações de verdade durante os testes. }

interface

uses
  Windows, Messages, SysUtils, Classes, Controls, Forms, Menus, TestFramework, Jsons,
  BorionJson, BorionIpc, BorionMenu, BorionTray, BorionApp, TestBorionPlugins;

type
  TTestBorionMenu = class(TTesteComIpc)
  private
    FForm: TForm;
    FMenu: TBorionMenuPlugin;
    function MenuPadrao: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestMontaABarra;
    procedure TestItensInvalidos;
    procedure TestClear;
    procedure TestUpdate;
    procedure TestCliqueEmiteEvento;
    procedure TestCheckboxAlterna;
    procedure TestAtalhoDeTeclado;
    procedure TestAtalhoDesabilitadoIgnorado;
    procedure TestPopupMenuWin32;
    procedure TestPopupSemItensFalha;
    procedure TestParseAccelerator;
  end;

  TTestBorionTray = class(TTesteComIpc)
  private
    FTray: TBorionTrayPlugin;
    FChamadas: TStringList;
    FUltima: TBorionNotifyIconData;
    function Capturar(Msg: DWORD; var Data: TBorionNotifyIconData): Boolean;
    procedure Mensagem(LParam: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEstrutura;
    procedure TestShowEHide;
    procedure TestTooltip;
    procedure TestNotify;
    procedure TestNotifyExigeMensagem;
    procedure TestSetMenu;
    procedure TestEventosDeClique;
    procedure TestExplorerReiniciado;
    procedure TestDestroyTiraOIcone;
  end;

  TTestBorionApp = class(TTesteComIpc)
  private
    FForm: TForm;
    FFechou: Boolean;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestInfo;
    procedure TestExitFechaOForm;
    procedure TestHide;
  end;

implementation

{ TTestBorionMenu }

procedure TTestBorionMenu.SetUp;
begin
  inherited;
  FForm := TForm.CreateNew(nil);
  FMenu := TBorionMenuPlugin(FIpc.AddPlugin(TBorionMenuPlugin.Create(FForm)));
end;

procedure TTestBorionMenu.TearDown;
begin
  inherited;  { libera o Ipc e, com ele, o plugin }
  FForm.Free;
end;

function TTestBorionMenu.MenuPadrao: string;
begin
  Result := '{"items":[' +
    '{"label":"&Arquivo","items":[' +
      '{"id":"novo","label":"&Novo","accelerator":"Ctrl+N"},' +
      '{"id":"salvar","label":"&Salvar","accelerator":"Ctrl+S"},' +
      '{"id":"salvarComo","label":"Salvar como","accelerator":"Ctrl+Shift+S"},' +
      '{"type":"separator"},' +
      '{"id":"sair","label":"Sai&r"}]},' +
    '{"label":"E&xibir","items":[' +
      '{"id":"quebra","label":"Quebra de linha","type":"checkbox","checked":true},' +
      '{"id":"zoom","label":"Zoom","enabled":false,"accelerator":"Ctrl+Z"}]}]}';
end;

procedure TTestBorionMenu.TestMontaABarra;
var
  Arquivo: TMenuItem;
begin
  Ok('menu:setMenu', MenuPadrao);
  Check(FForm.Menu = FMenu.MainMenu, 'a barra vai para o form');
  CheckEquals(2, FMenu.MainMenu.Items.Count);
  Arquivo := FMenu.MainMenu.Items[0];
  CheckEquals('&Arquivo', Arquivo.Caption);
  CheckEquals(5, Arquivo.Count);
  CheckEquals('-', Arquivo.Items[3].Caption, 'separador');
  Check(FMenu.FindItem('salvar').ShortCut = Menus.ShortCut(Ord('S'), [ssCtrl]));
  Check(FMenu.FindItem('salvarComo').ShortCut = Menus.ShortCut(Ord('S'), [ssCtrl, ssShift]));
  Check(FMenu.FindItem('quebra').Checked);
  CheckFalse(FMenu.FindItem('zoom').Enabled);
  Check(FMenu.FindItem('nao-existe') = nil);
end;

procedure TTestBorionMenu.TestItensInvalidos;
begin
  CheckEquals('INVALID_MENU', Erro('menu:setMenu', '{"items":[{"label":"sem id"}]}'));
  CheckEquals('INVALID_MENU', Erro('menu:setMenu', '{"items":[{"id":"a","label":"A"},{"id":"a","label":"B"}]}'));
  CheckEquals('INVALID_MENU', Erro('menu:setMenu', '{"items":[{"id":"a","accelerator":"Ctrl+Banana"}]}'));
  CheckEquals('INVALID_MENU', Erro('menu:setMenu', '{"items":"isso não é lista"}'));
  CheckEquals(0, FMenu.MainMenu.Items.Count, 'erro não deixa barra pela metade');
  Check(FForm.Menu = nil);
end;

procedure TTestBorionMenu.TestClear;
begin
  Ok('menu:setMenu', MenuPadrao);
  Ok('menu:clear', '');
  Check(FForm.Menu = nil);
  CheckEquals(0, FMenu.MainMenu.Items.Count);
  Ok('menu:setMenu', MenuPadrao);
  Ok('menu:setMenu', '{"items":[]}');
  Check(FForm.Menu = nil, 'lista vazia remove a barra');
end;

procedure TTestBorionMenu.TestUpdate;
begin
  Ok('menu:setMenu', MenuPadrao);
  Ok('menu:update', '{"id":"salvar","enabled":false,"label":"Gravar","accelerator":"F2"}');
  CheckFalse(FMenu.FindItem('salvar').Enabled);
  CheckEquals('Gravar', FMenu.FindItem('salvar').Caption);
  Check(FMenu.FindItem('salvar').ShortCut = Menus.ShortCut(VK_F2, []));
  Ok('menu:update', '{"id":"quebra","checked":false}');
  CheckFalse(FMenu.FindItem('quebra').Checked);
  CheckEquals('NOT_FOUND', Erro('menu:update', '{"id":"nada"}'));
end;

procedure TTestBorionMenu.TestCliqueEmiteEvento;
begin
  Ok('menu:setMenu', MenuPadrao);
  FPosts.Clear;
  FMenu.FindItem('salvar').Click;
  CheckEquals(1, FPosts.Count);
  CheckEquals('{"__borion":1,"kind":"event","event":"menu:click","payload":{"id":"salvar"}}', FPosts[0]);
end;

procedure TTestBorionMenu.TestCheckboxAlterna;
begin
  Ok('menu:setMenu', MenuPadrao);
  FPosts.Clear;
  FMenu.FindItem('quebra').Click;
  CheckFalse(FMenu.FindItem('quebra').Checked);
  Check(Pos('"payload":{"id":"quebra","checked":false}', FPosts[0]) > 0, FPosts[0]);
  FMenu.FindItem('quebra').Click;
  Check(Pos('"checked":true', FPosts[1]) > 0, FPosts[1]);
end;

procedure TTestBorionMenu.TestAtalhoDeTeclado;
begin
  Ok('menu:setMenu', MenuPadrao);
  FPosts.Clear;
  Check(FMenu.HandleKey(Ord('S'), True, False, False), 'Ctrl+S');
  Check(Pos('"id":"salvar"', FPosts[0]) > 0, FPosts[0]);
  Check(FMenu.HandleKey(Ord('S'), True, True, False), 'Ctrl+Shift+S');
  Check(Pos('"id":"salvarComo"', FPosts[1]) > 0, FPosts[1]);
  CheckFalse(FMenu.HandleKey(Ord('S'), False, False, False), 'S sozinho não é atalho');
  CheckFalse(FMenu.HandleKey(Ord('Q'), True, False, False), 'sem item com Ctrl+Q');
  CheckEquals(2, FPosts.Count);
end;

procedure TTestBorionMenu.TestAtalhoDesabilitadoIgnorado;
begin
  Ok('menu:setMenu', MenuPadrao);
  CheckFalse(FMenu.HandleKey(Ord('Z'), True, False, False), 'item desabilitado');
  Ok('menu:update', '{"id":"zoom","enabled":true}');
  Check(FMenu.HandleKey(Ord('Z'), True, False, False));
  FMenu.MainMenu.Items[0].Enabled := False;  { submenu Arquivo inteiro desabilitado }
  CheckFalse(FMenu.HandleKey(Ord('S'), True, False, False), 'item dentro de submenu desabilitado');
end;

procedure TTestBorionMenu.TestPopupMenuWin32;
var
  A: TJsonArray;
  Ids: TStringList;
  M: HMENU;
begin
  A := TJsonArray.Create;
  Ids := TStringList.Create;
  try
    A.Parse('[{"id":"copiar","label":"Copiar","accelerator":"Ctrl+C"},{"type":"separator"},' +
      '{"id":"colar","label":"Colar","enabled":false},' +
      '{"label":"Mais","items":[{"id":"sub1","label":"Sub 1","checked":true}]}]');
    M := BorionBuildPopupMenu(A, Ids);
    try
      CheckEquals(4, GetMenuItemCount(M));
      CheckEquals(3, Ids.Count, 'só os itens clicáveis viram comandos');
      CheckEquals('copiar', Ids[0]);
      CheckEquals('sub1', Ids[2]);
      Check(GetMenuState(M, 2, MF_BYCOMMAND) and MF_GRAYED <> 0, 'colar desabilitado');
      Check(GetMenuState(M, 3, MF_BYCOMMAND) and MF_CHECKED <> 0, 'sub1 marcado');
      Check(GetSubMenu(M, 3) <> 0, 'submenu');
    finally
      DestroyMenu(M);
    end;
  finally
    Ids.Free;
    A.Free;
  end;
end;

procedure TTestBorionMenu.TestPopupSemItensFalha;
begin
  CheckEquals('INVALID_MENU', Erro('menu:popup', '{}'));
end;

procedure TTestBorionMenu.TestParseAccelerator;
begin
  Check(BorionParseAccelerator('') = 0);
  Check(BorionParseAccelerator('Ctrl+O') = Menus.ShortCut(Ord('O'), [ssCtrl]));
  Check(BorionParseAccelerator('F5') = Menus.ShortCut(VK_F5, []));
  try
    BorionParseAccelerator('Ctrl+Banana');
    Fail('atalho inválido');
  except
    on E: EBorionError do
      CheckEquals('INVALID_MENU', E.Code);
  end;
end;

{ TTestBorionTray }

procedure TTestBorionTray.SetUp;
begin
  inherited;
  FChamadas := TStringList.Create;
  FTray := TBorionTrayPlugin(FIpc.AddPlugin(TBorionTrayPlugin.Create));
  FTray.OnNotify := Capturar;
end;

procedure TTestBorionTray.TearDown;
begin
  inherited;
  FChamadas.Free;
end;

function TTestBorionTray.Capturar(Msg: DWORD; var Data: TBorionNotifyIconData): Boolean;
const
  Nomes: array[0..2] of string = ('ADD', 'MODIFY', 'DELETE');
begin
  FUltima := Data;
  FChamadas.Add(Nomes[Msg] + Format(' flags=%d', [Data.uFlags]));
  Result := True;
end;

procedure TTestBorionTray.Mensagem(LParam: Integer);
begin
  SendMessage(FTray.Window, WM_BORION_TRAY, 1, LParam);
end;

procedure TTestBorionTray.TestEstrutura;
begin
  CheckEquals(488, SizeOf(TBorionNotifyIconData), 'NOTIFYICONDATAA_V2_SIZE');
  CheckFalse(FTray.Visible);
  Check(FTray.Icon <> 0, 'ícone padrão');
end;

procedure TTestBorionTray.TestShowEHide;
begin
  Ok('tray:show', '{"tooltip":"Meu app"}');
  Check(FTray.Visible);
  CheckEquals('ADD flags=7', FChamadas[0], 'NIF_MESSAGE or NIF_ICON or NIF_TIP');
  CheckEquals('Meu app', string(FUltima.szTip));
  CheckEquals(WM_BORION_TRAY, Integer(FUltima.uCallbackMessage));
  Check(FUltima.Wnd = FTray.Window);
  CheckEquals(488, Integer(FUltima.cbSize));
  Ok('tray:show', '');
  CheckEquals(1, FChamadas.Count, 'mostrar de novo não duplica o ícone');
  Ok('tray:hide', '');
  CheckFalse(FTray.Visible);
  CheckEquals('DELETE flags=0', FChamadas[1]);
end;

procedure TTestBorionTray.TestTooltip;
var
  Longo: string;
begin
  Ok('tray:setTooltip', '{"tooltip":"antes de mostrar"}');
  CheckEquals(0, FChamadas.Count, 'sem ícone, só guarda');
  Ok('tray:show', '');
  CheckEquals('antes de mostrar', string(FUltima.szTip));
  Longo := StringOfChar('x', 300);
  Ok('tray:setTooltip', '{"tooltip":' + JsonQuote(Longo) + '}');
  CheckEquals('MODIFY flags=4', FChamadas[1]);
  CheckEquals(127, Length(string(FUltima.szTip)), 'cortado no tamanho do campo');
end;

procedure TTestBorionTray.TestNotify;
begin
  Ok('tray:notify', '{"title":"Salvo","message":"nota.txt foi salvo","kind":"warning"}');
  CheckEquals('ADD flags=7', FChamadas[0], 'o balão mostra o ícone se preciso');
  CheckEquals('MODIFY flags=16', FChamadas[1], 'NIF_INFO');
  CheckEquals('Salvo', string(FUltima.szInfoTitle));
  CheckEquals('nota.txt foi salvo', string(FUltima.szInfo));
  CheckEquals(2, Integer(FUltima.dwInfoFlags), 'NIIF_WARNING');
end;

procedure TTestBorionTray.TestNotifyExigeMensagem;
begin
  CheckEquals('INVALID_ARGS', Erro('tray:notify', '{"title":"só título"}'));
end;

procedure TTestBorionTray.TestSetMenu;
begin
  Ok('tray:setMenu', '{"items":[{"id":"mostrar","label":"Mostrar"},{"type":"separator"},{"id":"sair","label":"Sair"}]}');
  CheckEquals('INVALID_MENU', Erro('tray:setMenu', '{"items":5}'));
  Ok('tray:setMenu', '{"items":null}');
end;

procedure TTestBorionTray.TestEventosDeClique;
begin
  FTray.RestoreOnClick := False;  { não há janela nos testes }
  Mensagem(WM_LBUTTONUP);
  Mensagem(WM_LBUTTONDBLCLK);
  Mensagem(NIN_BALLOONUSERCLICK_);
  CheckEquals(3, FPosts.Count);
  Check(Pos('"event":"tray:click"', FPosts[0]) > 0, FPosts[0]);
  Check(Pos('"event":"tray:doubleClick"', FPosts[1]) > 0, FPosts[1]);
  Check(Pos('"event":"tray:balloonClick"', FPosts[2]) > 0, FPosts[2]);
  Mensagem(WM_MOUSEMOVE);
  CheckEquals(3, FPosts.Count, 'movimento do mouse não é evento');
end;

procedure TTestBorionTray.TestExplorerReiniciado;
begin
  Ok('tray:show', '');
  SendMessage(FTray.Window, RegisterWindowMessage('TaskbarCreated'), 0, 0);
  CheckEquals(2, FChamadas.Count);
  CheckEquals('ADD flags=7', FChamadas[1], 'o ícone é recolocado');
  Ok('tray:hide', '');
  SendMessage(FTray.Window, RegisterWindowMessage('TaskbarCreated'), 0, 0);
  CheckEquals(3, FChamadas.Count, 'escondido continua escondido');
end;

procedure TTestBorionTray.TestDestroyTiraOIcone;
begin
  Ok('tray:show', '');
  FIpc.Free;  { libera o plugin }
  FIpc := nil;
  CheckEquals('DELETE flags=0', FChamadas[FChamadas.Count - 1]);
end;

{ TTestBorionApp }

procedure TTestBorionApp.SetUp;
begin
  inherited;
  FForm := TForm.CreateNew(nil);
  FForm.OnClose := FormClose;
  FFechou := False;
  FIpc.AddPlugin(TBorionAppPlugin.Create(FForm));
end;

procedure TTestBorionApp.TearDown;
begin
  inherited;
  FForm.Free;
end;

procedure TTestBorionApp.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FFechou := True;
  Action := caHide;
end;

procedure TTestBorionApp.TestInfo;
var
  O: TJsonObject;
begin
  O := TJsonObject.Create;
  try
    O.Parse(Ok('app:info', ''));
    CheckEquals(ParamStr(0), O['exe'].AsString);
    CheckEquals(Integer(GetCurrentProcessId), O['pid'].AsInteger);
  finally
    O.Free;
  end;
end;

procedure TTestBorionApp.TestExitFechaOForm;
var
  Msg: TMsg;
  I: Integer;
begin
  Ok('app:exit', '');
  CheckFalse(FFechou, 'o fechamento é postado, não acontece dentro do callback');
  for I := 1 to 50 do
  begin
    while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
    begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
    if FFechou then
      Break;
    Sleep(10);
  end;
  Check(FFechou, 'passou pelo OnClose do form');
end;

procedure TTestBorionApp.TestHide;
begin
  Ok('app:hide', '');
  CheckFalse(FForm.Visible);
end;

initialization
  RegisterTest('BorionMenu', TTestBorionMenu.Suite);
  RegisterTest('BorionTray', TTestBorionTray.Suite);
  RegisterTest('BorionApp', TTestBorionApp.Suite);

end.
