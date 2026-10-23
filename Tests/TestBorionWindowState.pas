unit TestBorionWindowState;

{ Testes do plugin window-state: grava o estado das TBorionWindow (nunca
  mostradas; a Position poDesigned faz o papel de "já apareceu") num arquivo
  da pasta out\window-state e o restaura em janelas novas. }

interface

uses
  Windows, Messages, SysUtils, Classes, Controls, Forms, TestFramework, Jsons,
  BorionIpc, BorionWindowState, Borion;

type
  TTestBorionWindowState = class(TTestCase)
  private
    FArquivo: string;
    FPosts: TStringList;
    procedure PostouPara(Sender: TObject; const WindowLabel: string; const Json: WideString);
    function NovaJanela(AFlags: TBorionWindowStateFlags = BORION_WINDOW_STATE_ALL): TBorionWindow;
    function Plugin(W: TBorionWindow): TBorionWindowStatePlugin;
    procedure Gravar(const Json: string);
    function Ler: TJsonObject;
    function Conteudo: string;
    function Invocar(W: TBorionWindow; const Janela, Cmd, ArgsJson: string): TJsonObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSemArquivoNaoMexe;
    procedure TestGravaERestaura;
    procedure TestMaximizadaGuardaONormal;
    procedure TestTelaCheiaGuardaONormal;
    procedure TestNuncaApareceuNaoGrava;
    procedure TestPosicaoForaDaTela;
    procedure TestMesmoLugarDoPadraoFicaFixo;
    procedure TestNaoRedimensionavelSoAPosicao;
    procedure TestFlags;
    procedure TestIgnorada;
    procedure TestArquivoCorrompido;
    procedure TestOutrasJanelasDoArquivoFicam;
    procedure TestSecundaria;
    procedure TestComandos;
  end;

implementation

const
  ORIGEM = 'https://app.localhost/';

procedure TTestBorionWindowState.SetUp;
begin
  FArquivo := ExtractFilePath(ParamStr(0)) + 'out\window-state\' + BORION_WINDOW_STATE_FILE;
  ForceDirectories(ExtractFileDir(FArquivo));
  DeleteFile(FArquivo);
  FPosts := TStringList.Create;
end;

procedure TTestBorionWindowState.TearDown;
begin
  FPosts.Free;
end;

procedure TTestBorionWindowState.PostouPara(Sender: TObject; const WindowLabel: string; const Json: WideString);
begin
  FPosts.Add(WindowLabel + '=' + Json);
end;

{ uma janela 'main' de 1000x700 centralizada, como a do app.json padrão }
function TTestBorionWindowState.NovaJanela(AFlags: TBorionWindowStateFlags): TBorionWindow;
begin
  Result := TBorionWindow.Create(nil);
  Result.SetBounds(0, 0, 1000, 700);
  Result.Ipc.AllowOrigin(ORIGEM);
  Result.Ipc.OnPostTo := PostouPara;
end;

function TTestBorionWindowState.Plugin(W: TBorionWindow): TBorionWindowStatePlugin;
begin
  Result := TBorionWindowStatePlugin.Create;
  Result.FileName := FArquivo;
  W.Ipc.AddPlugin(Result);
end;

procedure TTestBorionWindowState.Gravar(const Json: string);
var
  S: TStringList;
begin
  S := TStringList.Create;
  try
    S.Text := Json;
    S.SaveToFile(FArquivo);
  finally
    S.Free;
  end;
end;

function TTestBorionWindowState.Ler: TJsonObject;
var
  S: TStringList;
begin
  S := TStringList.Create;
  try
    S.LoadFromFile(FArquivo);
    Result := TJsonObject.Create;
    Result.Parse(S.Text);
  finally
    S.Free;
  end;
end;

function TTestBorionWindowState.Conteudo: string;
var
  S: TStringList;
begin
  S := TStringList.Create;
  try
    S.LoadFromFile(FArquivo);
    Result := S.Text;
  finally
    S.Free;
  end;
end;

function TTestBorionWindowState.Invocar(W: TBorionWindow; const Janela, Cmd, ArgsJson: string): TJsonObject;
begin
  FPosts.Clear;
  W.Ipc.ProcessMessageFrom(Janela, '{"__borion":1,"kind":"invoke","id":7,"cmd":"' + Cmd + '","args":' +
    ArgsJson + '}', ORIGEM);
  CheckEquals(1, FPosts.Count, Cmd);
  Result := TJsonObject.Create;
  Result.Parse(FPosts.ValueFromIndex[0]);
end;

procedure TTestBorionWindowState.TestSemArquivoNaoMexe;
var
  W: TBorionWindow;
begin
  W := NovaJanela;
  try
    W.WindowState := wsMaximized;  { o app.json manda abrir maximizada }
    Plugin(W);
    CheckEquals(1000, W.Width);
    Check(W.WindowState = wsMaximized, 'sem estado gravado, vale a configuração');
    Check(W.Position = poScreenCenter);
  finally
    W.Free;
  end;
  CheckEquals('{}', StringReplace(Trim(Conteudo), #13#10, '', [rfReplaceAll]),
    'a janela nunca apareceu: nada gravado');
end;

procedure TTestBorionWindowState.TestGravaERestaura;
var
  W: TBorionWindow;
  O: TJsonObject;
  H: HWND;
begin
  W := NovaJanela;
  Plugin(W);
  W.Position := poDesigned;  { já apareceu }
  W.SetBounds(100, 120, 700, 500);
  W.Free;  { fechar grava }

  O := Ler;
  try
    CheckEquals(100, O['main'].AsObject['x'].AsInteger);
    CheckEquals(120, O['main'].AsObject['y'].AsInteger);
    CheckEquals(700, O['main'].AsObject['width'].AsInteger);
    CheckEquals(500, O['main'].AsObject['height'].AsInteger);
    CheckFalse(O['main'].AsObject['maximized'].AsBoolean);
  finally
    O.Free;
  end;

  W := NovaJanela;
  try
    W.HandleNeeded;  { como o principal, que tem handle desde o Application.CreateForm }
    H := W.Handle;
    Plugin(W);
    CheckEquals(Integer(H), Integer(W.Handle), 'fixar a posição não recria a janela');
    CheckEquals(100, W.Left);
    CheckEquals(120, W.Top);
    CheckEquals(700, W.Width);
    CheckEquals(500, W.Height);
    Check(W.Position = poDesigned, 'o Show não centraliza de novo');
    Check(W.WindowState = wsNormal);
    CheckEquals(700, W.NormalBounds.Right - W.NormalBounds.Left);
  finally
    W.Free;
  end;
end;

procedure TTestBorionWindowState.TestMaximizadaGuardaONormal;
var
  W: TBorionWindow;
  O: TJsonObject;
begin
  W := NovaJanela;
  Plugin(W);
  W.Position := poDesigned;
  W.HandleNeeded;
  W.SetBounds(100, 100, 640, 480);
  CheckEquals(640, W.NormalBounds.Right - W.NormalBounds.Left, 'acompanha pelo WM_SIZE');
  W.WindowState := wsMaximized;
  W.Free;

  O := Ler;
  try
    CheckEquals(640, O['main'].AsObject['width'].AsInteger, 'o tamanho de antes do maximizado');
    Check(O['main'].AsObject['maximized'].AsBoolean);
  finally
    O.Free;
  end;

  W := NovaJanela;
  try
    Plugin(W);
    CheckEquals(640, W.Width, 'o tamanho para quando sair do maximizado');
    CheckEquals(100, W.Left);
    Check(W.WindowState = wsMaximized);
  finally
    W.Free;
  end;
end;

procedure TTestBorionWindowState.TestTelaCheiaGuardaONormal;
var
  W: TBorionWindow;
  O: TJsonObject;
begin
  W := NovaJanela;
  Plugin(W);
  W.Position := poDesigned;
  W.HandleNeeded;
  W.SetBounds(200, 150, 500, 400);
  W.Fullscreen := True;  { o plugin window marca antes de mudar a borda e o tamanho }
  W.SetBounds(0, 0, 1920, 1080);
  CheckEquals(500, W.NormalBounds.Right - W.NormalBounds.Left, 'em tela cheia, não acompanha');
  W.Free;

  O := Ler;
  try
    CheckEquals(200, O['main'].AsObject['x'].AsInteger);
    CheckEquals(500, O['main'].AsObject['width'].AsInteger);
    CheckFalse(O['main'].AsObject['maximized'].AsBoolean);
  finally
    O.Free;
  end;
end;

procedure TTestBorionWindowState.TestNuncaApareceuNaoGrava;
var
  W: TBorionWindow;
  O: TJsonObject;
begin
  Gravar('{"main": {"x": 10, "y": 20, "width": 300, "height": 200, "maximized": true}}');
  W := NovaJanela;
  Plugin(W);
  W.Position := poScreenCenter;  { o estado gravado voltou, mas a janela não apareceu }
  W.SetBounds(0, 0, 999, 999);
  W.Free;
  O := Ler;
  try
    CheckEquals(300, O['main'].AsObject['width'].AsInteger, 'fica o estado que já havia');
  finally
    O.Free;
  end;
end;

procedure TTestBorionWindowState.TestPosicaoForaDaTela;
var
  W: TBorionWindow;
begin
  Gravar('{"main": {"x": -30000, "y": -30000, "width": 640, "height": 480, "maximized": false}}');
  W := NovaJanela;
  try
    Plugin(W);
    CheckEquals(640, W.Width, 'o tamanho volta');
    CheckEquals(0, W.Left, 'monitor desligado: a posição não volta');
    Check(W.Position = poScreenCenter, 'centraliza como no app.json');
  finally
    W.Free;
  end;
end;

procedure TTestBorionWindowState.TestMesmoLugarDoPadraoFicaFixo;
var
  W: TBorionWindow;
begin
  { gravada no canto, com o tamanho do app.json: os campos já batem, mas o Show
    centralizaria }
  Gravar('{"main": {"x": 0, "y": 0, "width": 1000, "height": 700, "maximized": false}}');
  W := NovaJanela;
  try
    Plugin(W);
    Check(W.Position = poDesigned, 'a posição gravada fica');
  finally
    W.Free;
  end;
end;

procedure TTestBorionWindowState.TestNaoRedimensionavelSoAPosicao;
var
  W: TBorionWindow;
begin
  Gravar('{"main": {"x": 50, "y": 60, "width": 640, "height": 480, "maximized": false}}');
  W := NovaJanela;
  try
    W.Resizable := False;
    Plugin(W);
    CheckEquals(1000, W.Width, 'o tamanho é o do app.json');
    CheckEquals(50, W.Left);
    CheckEquals(60, W.Top);
  finally
    W.Free;
  end;
end;

procedure TTestBorionWindowState.TestFlags;
var
  W: TBorionWindow;
  P: TBorionWindowStatePlugin;
begin
  Gravar('{"main": {"x": 50, "y": 60, "width": 640, "height": 480, "maximized": true}}');
  W := NovaJanela;
  try
    P := TBorionWindowStatePlugin.Create('', [wsfMaximized]);
    P.FileName := FArquivo;
    W.Ipc.AddPlugin(P);
    CheckEquals(1000, W.Width);
    CheckEquals(0, W.Left);
    Check(W.WindowState = wsMaximized);
  finally
    W.Free;
  end;
end;

procedure TTestBorionWindowState.TestIgnorada;
var
  W: TBorionWindow;
  P: TBorionWindowStatePlugin;
begin
  Gravar('{"main": {"x": 50, "y": 60, "width": 640, "height": 480, "maximized": false}}');
  W := NovaJanela;
  P := TBorionWindowStatePlugin.Create.Ignore('main');
  P.FileName := FArquivo;
  W.Ipc.AddPlugin(P);
  CheckEquals(1000, W.Width, 'não restaura');
  W.Position := poDesigned;
  W.Free;
  Check(Pos('"width": 640', Conteudo) > 0, 'nem grava: fica o que havia');

end;

procedure TTestBorionWindowState.TestArquivoCorrompido;
var
  W: TBorionWindow;
  O: TJsonObject;
begin
  Gravar('{"main": {"x": 1,');
  W := NovaJanela;
  Plugin(W);
  CheckEquals(1000, W.Width, 'começa vazio');
  W.Position := poDesigned;
  W.Free;
  O := Ler;
  try
    CheckEquals(1000, O['main'].AsObject['width'].AsInteger, 'o arquivo foi substituído');
  finally
    O.Free;
  end;
end;

procedure TTestBorionWindowState.TestOutrasJanelasDoArquivoFicam;
var
  W: TBorionWindow;
  O: TJsonObject;
begin
  Gravar('{"notas": {"x": 5, "y": 6, "width": 300, "height": 200, "maximized": false}, "main": {"width": 0}}');
  W := NovaJanela;
  Plugin(W);
  CheckEquals(1000, W.Width, 'entrada sem tamanho válido');
  W.Position := poDesigned;
  W.Free;
  O := Ler;
  try
    CheckEquals(300, O['notas'].AsObject['width'].AsInteger, 'janela fechada: o estado fica');
    CheckEquals(1000, O['main'].AsObject['width'].AsInteger);
  finally
    O.Free;
  end;
end;

procedure TTestBorionWindowState.TestSecundaria;
var
  W, C: TBorionWindow;
  O: TJsonObject;
begin
  Gravar('{"config": {"x": 40, "y": 30, "width": 420, "height": 310, "maximized": false}}');
  W := NovaJanela;
  try
    Plugin(W);
    C := TBorionWindow.CreateWindow(nil, W.Ipc, 'config');
    CheckEquals(420, C.Width, 'restaurada ao entrar no IPC');
    CheckEquals(40, C.Left);
    C.SetBounds(41, 31, 421, 311);
    C.Free;  { fechar a secundária grava }
    O := Ler;
    try
      CheckEquals(421, O['config'].AsObject['width'].AsInteger);
    finally
      O.Free;
    end;
  finally
    W.Free;
  end;
end;

procedure TTestBorionWindowState.TestComandos;
var
  W: TBorionWindow;
  O: TJsonObject;
begin
  W := NovaJanela;
  try
    Plugin(W);
    O := Invocar(W, 'main', 'window-state:filename', '{}');
    try
      CheckEquals(FArquivo, O['result'].AsString);
    finally
      O.Free;
    end;
    O := Invocar(W, 'main', 'window-state:restore', '{}');
    try
      CheckFalse(O['result'].AsBoolean, 'nada gravado ainda');
    finally
      O.Free;
    end;

    W.Position := poDesigned;
    W.SetBounds(70, 80, 600, 400);
    O := Invocar(W, 'main', 'window-state:save', '{}');
    O.Free;
    Check(FileExists(FArquivo));

    W.SetBounds(0, 0, 900, 900);
    O := Invocar(W, 'main', 'window-state:restore', '{}');
    try
      Check(O['result'].AsBoolean);
    finally
      O.Free;
    end;
    CheckEquals(600, W.Width);
    CheckEquals(70, W.Left);

    O := Invocar(W, 'main', 'window-state:restore', '{"label":"nada"}');
    try
      CheckEquals('WINDOW_NOT_FOUND', O['error'].AsObject['code'].AsString);
    finally
      O.Free;
    end;
  finally
    W.Free;
  end;
end;

initialization
  RegisterTest('Plugins', TTestBorionWindowState.Suite);

end.
