unit TestBorionConfig;

{ Testes do app.json (BorionConfig.pas): leitura, validação e avisos, o
  recurso no .res e a aplicação no TBorionBuilder e na janela. }

interface

uses
  Windows, SysUtils, Classes, Forms, Controls, TestFramework, BorionConfig, BorionPack, Borion;

type
  TTestBorionConfig = class(TTestCase)
  private
    FConfig: TBorionConfig;
    procedure DeveFalhar(const Json, Trecho: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestPadroes;
    procedure TestLeTudo;
    procedure TestUtf8EBom;
    procedure TestNullEhAusente;
    procedure TestTiposEValoresInvalidos;
    procedure TestAvisos;
    procedure TestVariasJanelas;
    procedure TestJanelasInvalidas;
    procedure TestVersao;
    procedure TestIdentificador;
    procedure TestDevPort;
    procedure TestRecursoNoRes;
    procedure TestSemRecursoNoExe;
  end;

  TTestBuilderConfig = class(TTestCase)
  private
    FConfig: TBorionConfig;
    FTituloAntes: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestBuilderAplicaConfig;
    procedure TestMetodosVencemOConfig;
    procedure TestTituloExplicitoVence;
    procedure TestSemProductNameUsaOExe;
    procedure TestJanelaAplicaConfig;
  end;

implementation

const
  COMPLETO =
    '{ "$schema": "x", "productName": "Loja", "version": "1.2.3", "identifier": "com.exemplo.loja",' +
    '  "build": { "frontendDist": "frontend/dist", "devUrl": "http://localhost:5300" },' +
    '  "app": { "windows": [ { "title": "Loja - Caixa", "width": 800, "height": 600,' +
    '    "minWidth": 400, "minHeight": 300, "maxWidth": 1600, "maxHeight": 1200,' +
    '    "resizable": false, "center": false, "maximized": true, "decorations": false,' +
    '    "alwaysOnTop": true } ],' +
    '    "security": { "csp": "default-src ''self''" } } }';

{ TTestBorionConfig }

procedure TTestBorionConfig.SetUp;
begin
  FConfig := TBorionConfig.Create;
end;

procedure TTestBorionConfig.TearDown;
begin
  FConfig.Free;
end;

procedure TTestBorionConfig.DeveFalhar(const Json, Trecho: string);
begin
  try
    FConfig.LoadFromJson(Json);
    Fail('aceitou: ' + Json);
  except
    on E: EBorionConfig do
      Check(Pos(Trecho, E.Message) > 0, 'mensagem: ' + E.Message);
  end;
end;

procedure TTestBorionConfig.TestPadroes;
var
  W: TBorionWindowConfig;
begin
  Check(not FConfig.Loaded);
  W := FConfig.Window;
  CheckEquals(1000, W.Width);
  CheckEquals(700, W.Height);
  CheckEquals(0, W.MinWidth);
  Check(W.Resizable and W.Center and W.Decorations, 'redimensionável, centralizada, com borda');
  Check(not W.Maximized and not W.AlwaysOnTop);
  CheckEquals('', W.Title);
  FConfig.LoadFromJson('{}');
  Check(FConfig.Loaded, '{} é um app.json válido');
  CheckEquals(1000, FConfig.Window.Width, 'tudo opcional');
  CheckEquals(0, FConfig.Warnings.Count);
end;

procedure TTestBorionConfig.TestLeTudo;
var
  W: TBorionWindowConfig;
begin
  FConfig.LoadFromJson(COMPLETO);
  CheckEquals('Loja', FConfig.ProductName);
  CheckEquals('1.2.3', FConfig.Version);
  CheckEquals('com.exemplo.loja', FConfig.Identifier);
  CheckEquals('frontend/dist', FConfig.FrontendDist);
  CheckEquals('http://localhost:5300', FConfig.DevUrl);
  CheckEquals('default-src ''self''', FConfig.Csp);
  W := FConfig.Window;
  CheckEquals('Loja - Caixa', W.Title);
  CheckEquals(800, W.Width);
  CheckEquals(600, W.Height);
  CheckEquals(400, W.MinWidth);
  CheckEquals(300, W.MinHeight);
  CheckEquals(1600, W.MaxWidth);
  CheckEquals(1200, W.MaxHeight);
  Check(not W.Resizable, 'resizable');
  Check(not W.Center, 'center');
  Check(W.Maximized, 'maximized');
  Check(not W.Decorations, 'decorations');
  Check(W.AlwaysOnTop, 'alwaysOnTop');
  CheckEquals(0, FConfig.Warnings.Count, FConfig.Warnings.Text);
  { uma leitura nova começa dos padrões }
  FConfig.LoadFromJson('{"productName": "Outro"}');
  CheckEquals(1000, FConfig.Window.Width);
  CheckEquals('', FConfig.Csp);
end;

procedure TTestBorionConfig.TestUtf8EBom;
begin
  FConfig.LoadFromJson(#$EF#$BB#$BF + AnsiToUtf8('{"productName": "Gestão Ávila"}'));
  CheckEquals('Gestão Ávila', FConfig.ProductName, 'UTF-8 com BOM -> ANSI');
  { os escapes JSON montados aos pedacos, para nenhum editor os converter }
  FConfig.LoadFromJson('{"productName": "Pre\' + 'u00e7o em \' + 'u20ac"}');
  CheckEquals('Preço em €', FConfig.ProductName, 'escapes de ç e € (cp1252 $80)');
  DeveFalhar('{"productName": "' + #$E9 + '"}', 'UTF-8');
end;

procedure TTestBorionConfig.TestNullEhAusente;
begin
  FConfig.LoadFromJson('{"productName": null, "app": {"windows": [{"width": null}], "security": null}}');
  CheckEquals('', FConfig.ProductName);
  CheckEquals(1000, FConfig.Window.Width);
end;

procedure TTestBorionConfig.TestTiposEValoresInvalidos;
begin
  DeveFalhar('{"app": {"windows": [{"width": "800"}]}}', '"app.windows[0].width"');
  DeveFalhar('{"app": {"windows": [{"width": 0}]}}', 'de 1 a 32767');
  DeveFalhar('{"app": {"windows": [{"height": 10.5}]}}', '"app.windows[0].height"');
  DeveFalhar('{"app": {"windows": [{"minWidth": -1}]}}', '"app.windows[0].minWidth"');
  DeveFalhar('{"app": {"windows": [{"resizable": 1}]}}', 'true ou false');
  DeveFalhar('{"app": {"windows": [{"minWidth": 900, "maxWidth": 800}]}}', 'maxWidth');
  DeveFalhar('{"app": {"windows": {"width": 800}}}', '"app.windows" deve ser uma lista');
  DeveFalhar('{"app": {"windows": [42]}}', '"app.windows[0]" deve ser um objeto');
  DeveFalhar('{"app": {"security": {"csp": {"default-src": "self"}}}}', '"app.security.csp" deve ser um texto');
  DeveFalhar('{"productName": 5}', '"productName" deve ser um texto');
  DeveFalhar('{"build": "web"}', '"build" deve ser um objeto');
  DeveFalhar('{"version": "1.x"}', '"version" inválida');
  DeveFalhar('{"identifier": "meu app"}', '"identifier" inválido');
  DeveFalhar('{"build": {"devUrl": "localhost:5173"}}', '"build.devUrl"');
  DeveFalhar('[1, 2]', 'objeto JSON');
  DeveFalhar('', 'objeto JSON');
  DeveFalhar('{"productName": ', 'JSON inválido');
end;

procedure TTestBorionConfig.TestAvisos;
begin
  FConfig.LoadFromJson('{"productNmae": "x", "app": {"windows": [{"widht": 800}, ' +
    '{"label": "b", "heigth": 400}], "security": {"cps": ""}}, "build": {"beforeBuildCommand": "npm run build"}}');
  CheckEquals(5, FConfig.Warnings.Count, FConfig.Warnings.Text);
  Check(Pos('"productNmae"', FConfig.Warnings.Text) > 0);
  Check(Pos('"app.windows[0].widht"', FConfig.Warnings.Text) > 0);
  Check(Pos('"app.windows[1].heigth"', FConfig.Warnings.Text) > 0);
  Check(Pos('"app.security.cps"', FConfig.Warnings.Text) > 0);
  Check(Pos('"build.beforeBuildCommand"', FConfig.Warnings.Text) > 0);
  FConfig.LoadFromJson('{}');
  CheckEquals(0, FConfig.Warnings.Count, 'os avisos são da última leitura');
end;

procedure TTestBorionConfig.TestVariasJanelas;
var
  C: TBorionWindowConfig;
begin
  CheckEquals(1, FConfig.WindowCount, 'sem app.json: só a principal');
  CheckEquals('main', FConfig.Window.WindowLabel);
  CheckEquals('/', FConfig.Window.Url);
  FConfig.LoadFromJson('{"app": {"windows": [{"width": 900}, ' +
    '{"label": "config", "url": "/config.html", "width": 500, "create": false},' +
    '{"label": "log-2", "visible": false}]}}');
  CheckEquals(3, FConfig.WindowCount);
  CheckEquals('main', FConfig.Windows[0].WindowLabel, 'a primeira sem label vira main');
  CheckEquals(900, FConfig.Window.Width);
  Check(FConfig.Window.CreateAtStart and FConfig.Window.Visible);
  Check(FConfig.FindWindow('config', C));
  CheckEquals('/config.html', C.Url);
  CheckEquals(500, C.Width);
  CheckEquals(700, C.Height, 'o resto com os padrões');
  CheckFalse(C.CreateAtStart, 'create: false');
  Check(C.Visible);
  Check(FConfig.FindWindow('log-2', C));
  CheckEquals('/', C.Url);
  CheckFalse(C.Visible);
  Check(C.CreateAtStart);
  CheckFalse(FConfig.FindWindow('outra', C));
  FConfig.LoadFromJson('{"app": {"windows": [{"label": "inicio"}]}}');
  CheckEquals('inicio', FConfig.Window.WindowLabel, 'a principal pode ter outro rótulo');
  FConfig.LoadFromJson('{"app": {"windows": [{"visible": false}]}}');
  Check(Pos('começa escondida', FConfig.Warnings.Text) > 0, FConfig.Warnings.Text);
end;

procedure TTestBorionConfig.TestJanelasInvalidas;
begin
  DeveFalhar('{"app": {"windows": [{}, {"width": 400}]}}', '"app.windows[1].label" é obrigatório');
  DeveFalhar('{"app": {"windows": [{}, {"label": "main"}]}}', '"app.windows[1].label" repetido');
  DeveFalhar('{"app": {"windows": [{}, {"label": "a b"}]}}', '"app.windows[1].label" inválido');
  DeveFalhar('{"app": {"windows": [{"label": ""}]}}', '"app.windows[0].label" inválido');
  DeveFalhar('{"app": {"windows": [{"url": "config.html"}]}}', '"app.windows[0].url"');
  DeveFalhar('{"app": {"windows": [{"url": "//outro.com/x"}]}}', '"app.windows[0].url"');
  DeveFalhar('{"app": {"windows": [{"url": "https://x.com/"}]}}', '"app.windows[0].url"');
  DeveFalhar('{"app": {"windows": [{"create": false}]}}', 'janela principal');
  DeveFalhar('{"app": {"windows": [{}, {"label": "b", "visible": "sim"}]}}', '"app.windows[1].visible"');
end;

procedure TTestBorionConfig.TestVersao;
begin
  Check(BorionIsValidVersion('1'));
  Check(BorionIsValidVersion('0.1.0'));
  Check(BorionIsValidVersion('1.2.3.4'));
  Check(BorionIsValidVersion('1.0.0-beta.1'));
  Check(BorionIsValidVersion('1.0.0+20261016'));
  Check(BorionIsValidVersion('65535.0.0'));
  Check(not BorionIsValidVersion(''));
  Check(not BorionIsValidVersion('1.2.3.4.5'), 'mais de 4 partes');
  Check(not BorionIsValidVersion('65536.0'), 'não cabe no VERSIONINFO');
  Check(not BorionIsValidVersion('1..2'));
  Check(not BorionIsValidVersion('1.2.'));
  Check(not BorionIsValidVersion('v1.2'));
  Check(not BorionIsValidVersion('1.0-'), 'sufixo vazio');
end;

procedure TTestBorionConfig.TestIdentificador;
begin
  Check(BorionIsValidIdentifier('com.exemplo.app'));
  Check(BorionIsValidIdentifier('br.com.ello-tecnologia.meu_app2'));
  Check(not BorionIsValidIdentifier('app'), 'uma parte só');
  Check(not BorionIsValidIdentifier('com..app'));
  Check(not BorionIsValidIdentifier('.com.app'));
  Check(not BorionIsValidIdentifier('com.app.'));
  Check(not BorionIsValidIdentifier('com.meu app'));
  Check(not BorionIsValidIdentifier('com.gestão'));
end;

procedure TTestBorionConfig.TestDevPort;
begin
  CheckEquals(0, FConfig.DevPort, 'sem devUrl');
  FConfig.DevUrl := 'http://localhost:5300';
  CheckEquals(5300, FConfig.DevPort);
  FConfig.DevUrl := 'http://127.0.0.1:8080/app/';
  CheckEquals(8080, FConfig.DevPort);
  FConfig.DevUrl := 'http://meu-servidor/';
  CheckEquals(80, FConfig.DevPort);
  FConfig.DevUrl := 'https://meu-servidor';
  CheckEquals(443, FConfig.DevPort);
end;

procedure TTestBorionConfig.TestRecursoNoRes;
var
  Arquivo, S: string;
  A, B, Lido: TMemoryStream;
begin
  Arquivo := ExtractFilePath(ParamStr(0)) + 'out\config.res';
  ForceDirectories(ExtractFileDir(Arquivo));
  A := TMemoryStream.Create;
  B := TMemoryStream.Create;
  Lido := TMemoryStream.Create;
  try
    S := 'pacote';  { tamanho que não é múltiplo de 4: testa o alinhamento }
    A.WriteBuffer(S[1], Length(S));
    S := '{"productName": "Loja"}';
    B.WriteBuffer(S[1], Length(S));
    BorionWriteResources(Arquivo, [BORION_PACK_RESOURCE, BORION_CONFIG_RESOURCE], [A, B]);
    Check(BorionReadRes(Arquivo, BORION_PACK_RESOURCE, Lido), 'o pacote');
    CheckEquals(6, Lido.Size);
    Lido.Clear;
    Check(BorionReadRes(Arquivo, BORION_CONFIG_RESOURCE, Lido), 'o app.json, depois do pacote');
    SetLength(S, Lido.Size);
    Lido.Position := 0;
    Lido.ReadBuffer(S[1], Lido.Size);
    FConfig.LoadFromJson(S);
    CheckEquals('Loja', FConfig.ProductName);
    Check(not BorionReadRes(Arquivo, 'OUTRO', Lido));
  finally
    Lido.Free;
    B.Free;
    A.Free;
  end;
end;

procedure TTestBorionConfig.TestSemRecursoNoExe;
begin
  Check(not FConfig.LoadFromResource(HInstance), 'o exe dos testes não tem app.json');
  Check(not FConfig.Loaded);
  CheckEquals(1000, FConfig.Window.Width);
  Check(not BorionAppConfig.Loaded, 'BorionAppConfig: os padrões');
  CheckEquals('', BorionAppConfigError);
end;

{ TTestBuilderConfig }

procedure TTestBuilderConfig.SetUp;
begin
  FTituloAntes := Application.Title;
  FConfig := TBorionConfig.Create;
  FConfig.LoadFromJson(COMPLETO);
end;

procedure TTestBuilderConfig.TearDown;
begin
  FConfig.Free;
  Application.Title := FTituloAntes;
end;

procedure TTestBuilderConfig.TestBuilderAplicaConfig;
var
  B: TBorionBuilder;
begin
  B := TBorionBuilder.Create;
  try
    Check(B.Config(FConfig) = B, 'encadeável');
    CheckEquals('Loja', B.Title, 'productName');
    CheckEquals('Loja', Application.Title, 'Application.Title já no Config, antes dos plugins');
    CheckEquals('Loja - Caixa', B.Window.Title);
    Check(not B.TitleFromPage, 'title explícito: caption fixo');
    CheckEquals(800, B.Window.Width);
    Check(not B.Window.Decorations);
    CheckEquals('default-src ''self''', B.ContentSecurityPolicy);
  finally
    B.Free;
  end;
end;

procedure TTestBuilderConfig.TestMetodosVencemOConfig;
var
  B: TBorionBuilder;
begin
  B := TBorionBuilder.Create.Config(FConfig)
    .Size(1200, 900)
    .MaxSize(0, 0)
    .Resizable
    .Centered
    .Decorations
    .AlwaysOnTop(False)
    .Csp('');
  try
    CheckEquals(1200, B.Window.Width);
    CheckEquals(900, B.Window.Height);
    CheckEquals(400, B.Window.MinWidth, 'o que o .dpr não mudou continua do app.json');
    CheckEquals(0, B.Window.MaxWidth);
    Check(B.Window.Resizable and B.Window.Center and B.Window.Decorations);
    Check(not B.Window.AlwaysOnTop);
    Check(B.Window.Maximized, 'continua do app.json');
    CheckEquals('', B.ContentSecurityPolicy);
  finally
    B.Free;
  end;
end;

procedure TTestBuilderConfig.TestTituloExplicitoVence;
var
  B: TBorionBuilder;
begin
  B := TBorionBuilder.Create('Explícito').Config(FConfig);
  try
    CheckEquals('Explícito', B.Title);
    CheckEquals('Explícito', Application.Title);
    CheckEquals(800, B.Window.Width, 'o resto vem do app.json');
  finally
    B.Free;
  end;
end;

procedure TTestBuilderConfig.TestSemProductNameUsaOExe;
var
  B: TBorionBuilder;
  Vazio: TBorionConfig;
begin
  Vazio := TBorionConfig.Create;
  B := TBorionBuilder.Create.Config(Vazio);
  try
    CheckEquals(ChangeFileExt(ExtractFileName(ParamStr(0)), ''), B.Title);
    Check(B.TitleFromPage, 'sem title: o caption segue a página');
    CheckEquals(1000, B.Window.Width);
  finally
    B.Free;
    Vazio.Free;
  end;
end;

procedure TTestBuilderConfig.TestJanelaAplicaConfig;
var
  W: TBorionWindow;
  C: TBorionWindowConfig;
begin
  W := TBorionWindow.Create(nil);
  try
    W.ApplyConfig(FConfig.Window, 'Padrão');
    CheckEquals('Loja - Caixa', W.Caption);
    CheckEquals(400, W.Constraints.MinWidth);
    CheckEquals(1600, W.Constraints.MaxWidth);
    Check(W.BorderStyle = bsNone, 'decorations: false');
    Check(W.FormStyle = fsStayOnTop, 'alwaysOnTop');
    Check(W.WindowState = wsMaximized, 'maximized');
    Check(W.Position = poDefaultPosOnly, 'center: false');

    C := BorionDefaultWindow;
    C.Resizable := False;
    W.ApplyConfig(C, 'Padrão');
    CheckEquals('Padrão', W.Caption, 'sem title: o título do app');
    CheckEquals(1000, W.Width);
    CheckEquals(700, W.Height);
    Check(W.BorderStyle = bsSingle, 'resizable: false');
    Check(not (biMaximize in W.BorderIcons), 'sem maximizar');
    Check(W.FormStyle = fsNormal);
    Check(W.WindowState = wsNormal);
    Check(W.Position = poScreenCenter);

    W.ApplyConfig(BorionDefaultWindow, 'Padrão');
    Check(W.BorderStyle = bsSizeable);
    Check(biMaximize in W.BorderIcons);
  finally
    W.Free;
  end;
end;

initialization
  RegisterTest('Borion', TTestBorionConfig.Suite);
  RegisterTest('Borion', TTestBuilderConfig.Suite);

end.
