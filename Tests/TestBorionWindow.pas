unit TestBorionWindow;

{ Testes do plugin window: comandos sobre um form criado em memória (nunca
  mostrado), os eventos e o fechamento interceptado pelo JS. }

interface

uses
  Windows, Messages, SysUtils, Classes, Controls, Forms, TestFramework, Jsons,
  BorionIpc, BorionWindow, Borion, TestBorionPlugins;

type
  TTestBorionWindow = class(TTesteComIpc)
  private
    FForm: TForm;
    FWin: TBorionWindowPlugin;
    FFechou: Boolean;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure Processar(Ms: Cardinal);
    function Eventos(const Nome: string): Integer;
    function Estado: TJsonObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTituloTamanhoEPosicao;
    procedure TestLimites;
    procedure TestArgumentosInvalidos;
    procedure TestMaximizar;
    procedure TestBordas;
    procedure TestTelaCheia;
    procedure TestSempreNoTopo;
    procedure TestEstado;
    procedure TestEventosDeTamanho;
    procedure TestFecharSemInterceptar;
    procedure TestFecharInterceptado;
    procedure TestSemConfirmacaoFechaSozinho;
    procedure TestConfirmacaoSeguraAJanela;
    procedure TestDestroyIgnoraAInterceptacao;
    procedure TestRespostaAntigaIgnorada;
    procedure TestDesligarInterceptacao;
    procedure TestFormLiberadoAntesDoPlugin;
    procedure TestTituloFixoNaTBorionWindow;
  end;

implementation

procedure TTestBorionWindow.SetUp;
begin
  inherited;
  FFechou := False;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(100, 100, 800, 600);
  FForm.OnClose := FormClose;
  FForm.HandleNeeded;  { WM_SIZE e WM_MOVE só com a janela criada }
  FWin := TBorionWindowPlugin(FIpc.AddPlugin(TBorionWindowPlugin.Create(FForm)));
end;

procedure TTestBorionWindow.TearDown;
begin
  inherited;  { o Ipc (e o plugin, que desfaz o WindowProc) antes do form }
  FForm.Free;
end;

procedure TTestBorionWindow.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FFechou := True;
  Action := caHide;
end;

procedure TTestBorionWindow.Processar(Ms: Cardinal);
var
  Msg: TMsg;
  Inicio: Cardinal;
begin
  Inicio := GetTickCount;
  repeat
    while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
    begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
    Sleep(5);
  until GetTickCount - Inicio >= Ms;
end;

function TTestBorionWindow.Eventos(const Nome: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FPosts.Count - 1 do
    if Pos('"event":"' + Nome + '"', FPosts[I]) > 0 then
      Inc(Result);
end;

function TTestBorionWindow.Estado: TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.Parse(Ok('window:state', ''));
end;

procedure TTestBorionWindow.TestTituloTamanhoEPosicao;
begin
  Ok('window:setTitle', '{"title":"Pedido 42"}');
  CheckEquals('Pedido 42', FForm.Caption);
  Ok('window:setSize', '{"width":640,"height":480}');
  CheckEquals(640, FForm.Width);
  CheckEquals(480, FForm.Height);
  CheckEquals(100, FForm.Left, 'o tamanho não move a janela');
  Ok('window:setPosition', '{"x":-50,"y":20}');
  CheckEquals(-50, FForm.Left, 'posição negativa: monitor à esquerda');
  CheckEquals(20, FForm.Top);
  CheckEquals(640, FForm.Width);
end;

procedure TTestBorionWindow.TestLimites;
begin
  Ok('window:setMinSize', '{"width":400,"height":300}');
  CheckEquals(400, FForm.Constraints.MinWidth);
  CheckEquals(300, FForm.Constraints.MinHeight);
  Ok('window:setMaxSize', '{"width":1200,"height":900}');
  CheckEquals(1200, FForm.Constraints.MaxWidth);
  Ok('window:setSize', '{"width":100,"height":100}');
  CheckEquals(400, FForm.Width, 'o limite vale para o setSize');
  Ok('window:setMinSize', '{"width":0,"height":0}');
  CheckEquals(0, FForm.Constraints.MinWidth, '0 = sem limite');
end;

procedure TTestBorionWindow.TestArgumentosInvalidos;
begin
  CheckEquals('INVALID_ARGS', Erro('window:setSize', '{"width":"800","height":600}'));
  CheckEquals('INVALID_ARGS', Erro('window:setSize', '{"width":0,"height":600}'));
  CheckEquals('INVALID_ARGS', Erro('window:setSize', '{"width":800.5,"height":600}'));
  CheckEquals('INVALID_ARGS', Erro('window:setSize', '{"width":800}'));
  CheckEquals('INVALID_ARGS', Erro('window:setPosition', '{"x":10}'));
  CheckEquals('INVALID_ARGS', Erro('window:setMinSize', '{"width":-1,"height":0}'));
  CheckEquals('INVALID_ARGS', Erro('window:setFullscreen', '{}'));
  CheckEquals('INVALID_ARGS', Erro('window:setAlwaysOnTop', '{"alwaysOnTop":1}'));
  CheckEquals(800, FForm.Width, 'nada mudou');
end;

procedure TTestBorionWindow.TestMaximizar;
begin
  Ok('window:maximize', '');
  Check(FForm.WindowState = wsMaximized);
  Ok('window:toggleMaximize', '');
  Check(FForm.WindowState = wsNormal);
  Ok('window:toggleMaximize', '');
  Check(FForm.WindowState = wsMaximized);
  Ok('window:unmaximize', '');
  Check(FForm.WindowState = wsNormal);
  Ok('window:minimize', '');
  Check(FForm.WindowState = wsMinimized, 'form que não é o principal: o próprio form');
  Ok('window:unminimize', '');
  Check(FForm.WindowState = wsNormal);
end;

procedure TTestBorionWindow.TestBordas;
begin
  Ok('window:setResizable', '{"resizable":false}');
  Check(FForm.BorderStyle = bsSingle);
  Check(not (biMaximize in FForm.BorderIcons));
  Ok('window:setDecorations', '{"decorations":false}');
  Check(FForm.BorderStyle = bsNone);
  Ok('window:setResizable', '{"resizable":true}');
  Check(FForm.BorderStyle = bsNone, 'sem borda continua sem borda');
  Ok('window:setDecorations', '{"decorations":true}');
  Check(FForm.BorderStyle = bsSizeable, 'volta redimensionável, como pedido antes');
  Check(biMaximize in FForm.BorderIcons);
end;

procedure TTestBorionWindow.TestTelaCheia;
var
  R: TRect;
  O: TJsonObject;
begin
  Ok('window:setResizable', '{"resizable":false}');
  Ok('window:setFullscreen', '{"fullscreen":true}');
  R := Screen.MonitorFromWindow(FForm.Handle).BoundsRect;
  Check(FForm.BorderStyle = bsNone);
  CheckEquals(R.Right - R.Left, FForm.Width, 'o monitor inteiro');
  CheckEquals(R.Left, FForm.Left);
  Check(FWin.Fullscreen);
  O := Estado;
  try
    Check(O['fullscreen'].AsBoolean);
    Check(O['decorations'].AsBoolean, 'a borda de antes da tela cheia');
  finally
    O.Free;
  end;
  Ok('window:setFullscreen', '{"fullscreen":true}');  { de novo: não perde o que guardou }
  Ok('window:setFullscreen', '{"fullscreen":false}');
  Check(FForm.BorderStyle = bsSingle, 'a borda de antes');
  CheckEquals(800, FForm.Width);
  CheckEquals(100, FForm.Left);
  { o setSize sai da tela cheia }
  Ok('window:setFullscreen', '{"fullscreen":true}');
  Ok('window:setSize', '{"width":500,"height":400}');
  Check(not FWin.Fullscreen);
  CheckEquals(500, FForm.Width);
end;

procedure TTestBorionWindow.TestSempreNoTopo;
begin
  Ok('window:setAlwaysOnTop', '{"alwaysOnTop":true}');
  Check(FForm.FormStyle = fsStayOnTop);
  Ok('window:setAlwaysOnTop', '{"alwaysOnTop":false}');
  Check(FForm.FormStyle = fsNormal);
end;

procedure TTestBorionWindow.TestEstado;
var
  O: TJsonObject;
begin
  FForm.Caption := 'Caixa';
  O := Estado;
  try
    CheckEquals('Caixa', O['title'].AsString);
    CheckEquals(100, O['x'].AsInteger);
    CheckEquals(800, O['width'].AsInteger);
    CheckEquals(600, O['height'].AsInteger);
    CheckFalse(O['minimized'].AsBoolean);
    CheckFalse(O['maximized'].AsBoolean);
    CheckFalse(O['fullscreen'].AsBoolean);
    CheckFalse(O['visible'].AsBoolean, 'o form dos testes nunca é mostrado');
    CheckFalse(O['alwaysOnTop'].AsBoolean);
    Check(O['resizable'].AsBoolean);
    Check(O['decorations'].AsBoolean);
  finally
    O.Free;
  end;
end;

procedure TTestBorionWindow.TestEventosDeTamanho;
begin
  FPosts.Clear;
  Ok('window:setSize', '{"width":700,"height":500}');
  Check(Eventos('window:resized') > 0, FPosts.Text);
  Check(Pos('"width":700,"height":500,"minimized":false,"maximized":false', FPosts.Text) > 0, FPosts.Text);
  FPosts.Clear;
  Ok('window:setPosition', '{"x":30,"y":40}');
  Check(Pos('"event":"window:moved","payload":{"x":30,"y":40}', FPosts.Text) > 0, FPosts.Text);
end;

procedure TTestBorionWindow.TestFecharSemInterceptar;
begin
  SendMessage(FForm.Handle, WM_CLOSE, 0, 0);
  Check(FFechou, 'sem interceptação, fecha direto');
  CheckEquals(0, Eventos('window:close-requested'));
end;

procedure TTestBorionWindow.TestFecharInterceptado;
begin
  Ok('window:interceptClose', '{"enabled":true}');
  Check(FWin.InterceptClose);
  FPosts.Clear;
  SendMessage(FForm.Handle, WM_CLOSE, 0, 0);
  CheckFalse(FFechou, 'a página decide');
  CheckEquals(1, Eventos('window:close-requested'));
  Check(Pos('"payload":{"id":1}', FPosts.Text) > 0, FPosts.Text);
  SendMessage(FForm.Handle, WM_CLOSE, 0, 0);
  CheckEquals(1, Eventos('window:close-requested'), 'um pedido de cada vez');
  Ok('window:closeAck', '{"id":1}');
  Ok('window:closeResolve', '{"id":1,"close":false}');
  Processar(50);
  CheckFalse(FFechou, 'a página cancelou');

  FPosts.Clear;
  PostMessage(FForm.Handle, WM_CLOSE, 0, 0);  { o app:exit e o window:close postam }
  Processar(20);
  CheckEquals(1, Eventos('window:close-requested'), 'pedido novo');
  Check(Pos('"payload":{"id":2}', FPosts.Text) > 0, FPosts.Text);
  Ok('window:closeAck', '{"id":2}');
  Ok('window:closeResolve', '{"id":2,"close":true}');
  CheckFalse(FFechou, 'o fechamento é postado, não acontece dentro do callback');
  Processar(50);
  Check(FFechou, 'a página confirmou');
  CheckEquals(1, Eventos('window:close-requested'), 'o fechamento confirmado não pergunta de novo');
end;

procedure TTestBorionWindow.TestSemConfirmacaoFechaSozinho;
begin
  FWin.AckTimeout := 50;
  Ok('window:interceptClose', '{"enabled":true}');
  SendMessage(FForm.Handle, WM_CLOSE, 0, 0);
  CheckFalse(FFechou);
  Processar(300);
  Check(FFechou, 'a página não respondeu: fechou assim mesmo');
end;

procedure TTestBorionWindow.TestConfirmacaoSeguraAJanela;
begin
  FWin.AckTimeout := 50;
  Ok('window:interceptClose', '{"enabled":true}');
  SendMessage(FForm.Handle, WM_CLOSE, 0, 0);
  Ok('window:closeAck', '{"id":1}');
  Processar(300);
  CheckFalse(FFechou, 'com a confirmação, a página pode demorar (um diálogo aberto)');
end;

procedure TTestBorionWindow.TestDestroyIgnoraAInterceptacao;
begin
  Ok('window:interceptClose', '{"enabled":true}');
  FPosts.Clear;
  Ok('window:destroy', '');
  Processar(50);
  Check(FFechou);
  CheckEquals(0, Eventos('window:close-requested'));
end;

procedure TTestBorionWindow.TestRespostaAntigaIgnorada;
begin
  Ok('window:interceptClose', '{"enabled":true}');
  Ok('window:closeResolve', '{"id":99,"close":true}');
  Processar(50);
  CheckFalse(FFechou, 'nenhum pedido em aberto');
  SendMessage(FForm.Handle, WM_CLOSE, 0, 0);
  Ok('window:closeResolve', '{"id":7,"close":true}');
  Processar(50);
  CheckFalse(FFechou, 'id de outro pedido');
end;

procedure TTestBorionWindow.TestDesligarInterceptacao;
begin
  Ok('window:interceptClose', '{"enabled":true}');
  SendMessage(FForm.Handle, WM_CLOSE, 0, 0);
  Ok('window:interceptClose', '{"enabled":false}');
  CheckFalse(FWin.InterceptClose);
  SendMessage(FForm.Handle, WM_CLOSE, 0, 0);
  Check(FFechou, 'o último handler saiu: fecha direto');
end;

procedure TTestBorionWindow.TestFormLiberadoAntesDoPlugin;
var
  Outro: TForm;
  Ipc: TBorionIpc;
  W: TBorionWindowPlugin;
begin
  Ipc := TBorionIpc.Create(nil, nil);
  try
    Outro := TForm.CreateNew(nil);
    W := TBorionWindowPlugin(Ipc.AddPlugin(TBorionWindowPlugin.Create(Outro)));
    Outro.Free;
    Check(W.Form = nil, 'o plugin soube que o form saiu');
  finally
    Ipc.Free;  { libera o plugin sem tocar no form liberado }
  end;
end;

procedure TTestBorionWindow.TestTituloFixoNaTBorionWindow;
var
  Janela: TBorionWindow;
begin
  Janela := TBorionWindow.Create(nil);
  try
    Janela.Ipc.OnPost := Postou;
    Janela.Ipc.AllowOrigin('https://app.localhost/');
    Janela.Ipc.AddPlugin(TBorionWindowPlugin.Create);  { acha o form pelo browser do Ipc }
    Check(Janela.TitleFromPage);
    Janela.Ipc.ProcessMessage('{"__borion":1,"kind":"invoke","id":"1","cmd":"window:setTitle",' +
      '"args":{"title":"Do JS"}}', 'https://app.localhost/');
    CheckEquals('Do JS', Janela.Caption);
    CheckFalse(Janela.TitleFromPage, 'o document.title não sobrescreve mais');
  finally
    Janela.Free;
  end;
end;

initialization
  RegisterTest('BorionWindow', TTestBorionWindow.Suite);

end.
