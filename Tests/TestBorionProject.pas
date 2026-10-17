unit TestBorionProject;

{ Testes do borion build / dev (Tools\BorionProject.pas e BorionBuild.pas): a
  detecção do projeto por convenção e um build de verdade de um projeto gerado
  pelo borion new (precisa do Delphi 7, como os próprios testes). }

interface

uses
  Windows, SysUtils, Classes, ShellAPI, TestFramework, BorionProject, BorionBuild, BorionNew,
  BorionConfig, BorionPack, TestBorionPack;

type
  TTestBorionProject = class(TTestCase)
  private
    FDir: string;
    procedure Criar(const Rel, Conteudo: string);
  protected
    procedure SetUp; override;
  published
    procedure TestProjetoEstatico;
    procedure TestProjetoNpm;
    procedure TestSemFrontend;
    procedure TestAppJsonNpm;
    procedure TestAppJsonEstatico;
    procedure TestAppJsonInvalido;
    procedure TestPacoteComAppJson;
    procedure TestIconeDoAppJson;
    procedure TestIconeRepetidoNoResDoProjeto;
    procedure TestSemDprOuComDois;
    procedure TestDelphiPelaVariavel;
    procedure TestDatas;
    procedure TestBuildDeUmProjetoGerado;
  end;

implementation

var
  Saida: TStringList;

procedure Capturar(const Line: string);
begin
  Saida.Add(Line);
end;

procedure ApagarPasta(const Pasta: string);
var
  R: TSearchRec;
begin
  if FindFirst(Pasta + '\*', faAnyFile, R) = 0 then
  begin
    repeat
      if (R.Name = '.') or (R.Name = '..') then
        Continue;
      if (R.Attr and faDirectory) <> 0 then
        ApagarPasta(Pasta + '\' + R.Name)
      else
        DeleteFile(Pasta + '\' + R.Name);
    until FindNext(R) <> 0;
    FindClose(R);
  end;
  RemoveDir(Pasta);
end;

procedure TTestBorionProject.SetUp;
begin
  FDir := ExtractFilePath(ParamStr(0)) + 'out\projeto';
  ApagarPasta(FDir);
  ForceDirectories(FDir);
end;

procedure TTestBorionProject.Criar(const Rel, Conteudo: string);
var
  L: TStringList;
begin
  ForceDirectories(ExtractFileDir(FDir + '\' + Rel));
  L := TStringList.Create;
  try
    L.Text := Conteudo;
    L.SaveToFile(FDir + '\' + Rel);
  finally
    L.Free;
  end;
end;

procedure TTestBorionProject.TestProjetoEstatico;
var
  P: TBorionProject;
begin
  Criar('Loja.dpr', 'program Loja;'#13#10'{$R *.res}'#13#10'{$R web.res}  // a interface'#13#10'begin end.');
  Criar('web\index.html', '<script type="importmap">{"imports":{"@borion/api":"./borion-api/index.js"}}</script>');
  Criar('Loja.dof', '[Directories]'#13#10'SearchPath=..\libs;C:\abs\x;  ;Plugins');
  P := TBorionProject.Create(FDir);
  try
    CheckEquals('Loja', P.ProgramName);
    Check(P.Kind = fkStatic);
    CheckEquals('web.res', P.AssetsRes);
    Check(P.UsesBorionApi, 'o index.html usa o borion-api');
    CheckEquals(FDir + '\web', P.DistDir);
    CheckEquals(3, P.SearchPath.Count, 'vazios ignorados');
    CheckEquals(ExpandFileName(FDir + '\..\libs'), P.SearchPath[0], 'relativo à pasta do projeto');
    CheckEquals('C:\abs\x', P.SearchPath[1]);
    CheckEquals(FDir + '\Plugins', P.SearchPath[2]);
    CheckEquals(FDir + '\Loja.exe', P.ExeFile);
  finally
    P.Free;
  end;
end;

procedure TTestBorionProject.TestProjetoNpm;
var
  P: TBorionProject;
begin
  Criar('App.dpr', 'program App;'#13#10'{$R *.res}'#13#10'{$R app.res}'#13#10'begin end.');
  Criar('frontend\package.json', '{}');
  Criar('frontend\vite.config.js', 'export default { server: { port:   5181, strictPort: true } }');
  P := TBorionProject.Create(FDir);
  try
    Check(P.Kind = fkNpm);
    CheckEquals('app.res', P.AssetsRes);
    CheckEquals(5181, P.DevPort, 'porta do vite.config.js');
    CheckEquals(FDir + '\frontend\dist', P.DistDir);
    CheckEquals(0, P.SearchPath.Count, 'sem .dof');
  finally
    P.Free;
  end;
end;

procedure TTestBorionProject.TestSemFrontend;
var
  P: TBorionProject;
begin
  Criar('Console.dpr', 'program Console;'#13#10'{$R *.res}'#13#10'begin end.');
  P := TBorionProject.Create(FDir);
  try
    Check(P.Kind = fkNone);
    CheckEquals('', P.AssetsRes, 'só o *.res do projeto');
    CheckEquals(5173, P.DevPort);
  finally
    P.Free;
  end;
end;

procedure TTestBorionProject.TestAppJsonNpm;
var
  P: TBorionProject;
begin
  Criar('Loja.dpr', 'program Loja;'#13#10'{$R *.res}'#13#10'{$R app.res}'#13#10'begin end.');
  Criar('ui\package.json', '{}');
  Criar('frontend\package.json', '{}');  { a convenção perde para o app.json }
  Criar('app.json', '{"build": {"frontendDist": "ui/dist", "devUrl": "http://localhost:5300/"}}');
  P := TBorionProject.Create(FDir);
  try
    Check(P.HasConfig);
    Check(P.Config.Loaded);
    Check(P.Kind = fkNpm, 'package.json acima do frontendDist');
    CheckEquals(FDir + '\ui', P.FrontendDir);
    CheckEquals(FDir + '\ui\dist', P.DistDir);
    CheckEquals(5300, P.DevPort, 'porta do devUrl');
    CheckEquals('http://localhost:5300', P.DevUrl, 'sem a barra final');
    CheckEquals(FDir + '\app.json', P.ConfigFile);
  finally
    P.Free;
  end;
end;

procedure TTestBorionProject.TestAppJsonEstatico;
var
  P: TBorionProject;
begin
  Criar('Site.dpr', 'program Site;'#13#10'{$R *.res}'#13#10'{$R web.res}'#13#10'begin end.');
  Criar('public\index.html', '<script type="importmap">{"imports":{"@borion/api":"./borion-api/index.js"}}</script>');
  Criar('app.json', '{"build": {"frontendDist": "public"}}');
  P := TBorionProject.Create(FDir);
  try
    Check(P.Kind = fkStatic);
    CheckEquals(FDir + '\public', P.FrontendDir);
    CheckEquals(FDir + '\public', P.DistDir);
    Check(P.UsesBorionApi);
    CheckEquals('http://localhost:5173', P.DevUrl, 'sem devUrl');
  finally
    P.Free;
  end;
end;

procedure TTestBorionProject.TestAppJsonInvalido;
begin
  Criar('App.dpr', 'program App; begin end.');
  Criar('app.json', '{"app": {"windows": [{"width": "grande"}]}}');
  try
    TBorionProject.Create(FDir).Free;
    Fail('app.json inválido');
  except
    on E: EBorionProject do
      Check(Pos('"app.windows[0].width"', E.Message) > 0, E.Message);
  end;
end;

function LerRecurso(const Arquivo, Nome: string): string;
var
  M: TMemoryStream;
begin
  Result := '';
  M := TMemoryStream.Create;
  try
    if BorionReadRes(Arquivo, Nome, M) then
    begin
      SetLength(Result, M.Size);
      if M.Size > 0 then
        Move(M.Memory^, Result[1], M.Size);
    end;
  finally
    M.Free;
  end;
end;

procedure TTestBorionProject.TestPacoteComAppJson;
var
  P: TBorionProject;
  Res, Pacote: string;
begin
  Criar('App.dpr', 'program App;'#13#10'{$R *.res}'#13#10'{$R web.res}'#13#10'begin end.');
  Criar('web\index.html', '<p>oi</p>');
  Criar('app.json', '{"productName": "Primeiro"}');
  Res := FDir + '\web.res';
  Saida := TStringList.Create;
  BorionOut := Capturar;
  P := TBorionProject.Create(FDir);
  try
    BorionPackAssets(P.DistDir, Res, P.ConfigFile);
    Pacote := LerRecurso(Res, BORION_PACK_RESOURCE);
    Check(Pacote <> '', 'o pacote');
    Check(Pos('"Primeiro"', LerRecurso(Res, BORION_CONFIG_RESOURCE)) > 0, 'o app.json');
    Check(Pos('+ app.json', Saida.Text) > 0, Saida.Text);
    { o dev troca só o app.json, sem refazer o pacote }
    Criar('app.json', '{"productName": "Segundo"}');
    BorionUpdateConfigRes(P);
    CheckEquals(Pacote, LerRecurso(Res, BORION_PACK_RESOURCE), 'o mesmo pacote');
    Check(Pos('"Segundo"', LerRecurso(Res, BORION_CONFIG_RESOURCE)) > 0, 'o app.json novo');
    { sem frontend: só o app.json }
    BorionPackAssets('', Res, P.ConfigFile);
    CheckEquals('', LerRecurso(Res, BORION_PACK_RESOURCE));
    Check(Pos('"Segundo"', LerRecurso(Res, BORION_CONFIG_RESOURCE)) > 0);
  finally
    P.Free;
    BorionOut := nil;
    FreeAndNil(Saida);
  end;
end;

procedure TTestBorionProject.TestIconeDoAppJson;
var
  P: TBorionProject;
  Res, Pacote: string;
begin
  Criar('App.dpr', 'program App;'#13#10'{$R *.res}'#13#10'{$R web.res}'#13#10'begin end.');
  Criar('web\index.html', '<p>oi</p>');
  Criar('app.json', '{"bundle": {"icon": ["icons/32x32.png", "icons/app.ico"]}}');
  GravarIcoDeTeste(FDir + '\icons\app.ico', [16, 32]);
  Res := FDir + '\web.res';
  Saida := TStringList.Create;
  BorionOut := Capturar;
  P := TBorionProject.Create(FDir);
  try
    CheckEquals(FDir + '\icons\app.ico', P.IconFile);
    BorionPackAssets(P.DistDir, Res, P.ConfigFile, P.IconFile);
    Check(BorionResHasIcon(Res), 'o ícone no .res de assets');
    Pacote := LerRecurso(Res, BORION_PACK_RESOURCE);
    Check(Pacote <> '', 'o pacote');
    Check(Pos('+ app.json + app.ico', Saida.Text) > 0, Saida.Text);
    { o dev troca o app.json e o ícone sem refazer o pacote }
    BorionUpdateConfigRes(P);
    Check(BorionResHasIcon(Res), 'o ícone continua');
    CheckEquals(Pacote, LerRecurso(Res, BORION_PACK_RESOURCE), 'o mesmo pacote');
    { sem frontend: o app.json e o ícone }
    BorionPackAssets('', Res, P.ConfigFile, P.IconFile);
    Check(BorionResHasIcon(Res));
    Check(Pos('app.json + app.ico -> web.res', Saida.Text) > 0, Saida.Text);
  finally
    P.Free;
    BorionOut := nil;
    FreeAndNil(Saida);
  end;
  { o .ico tem que existir }
  DeleteFile(FDir + '\icons\app.ico');
  try
    TBorionProject.Create(FDir).Free;
    Fail('ícone inexistente');
  except
    on E: EBorionProject do
      Check(Pos('"icons/app.ico"', E.Message) > 0, E.Message);
  end;
end;

procedure TTestBorionProject.TestIconeRepetidoNoResDoProjeto;
var
  P: TBorionProject;
  M: TMemoryStream;
begin
  try
    BorionFindDelphi;
  except
    Exit;  { sem Delphi 7 nesta máquina }
  end;
  Criar('App.dpr', 'program App;'#13#10'{$R *.res}'#13#10'begin end.');
  Criar('app.json', '{"bundle": {"icon": ["app.ico"]}}');
  GravarIcoDeTeste(FDir + '\app.ico', [16]);
  { o App.res com um MAINICON, como o da IDE }
  M := TMemoryStream.Create;
  try
    BorionWriteResources(FDir + '\App.res', ['X'], [M], FDir + '\app.ico');
  finally
    M.Free;
  end;
  P := TBorionProject.Create(FDir);
  try
    try
      BorionCompileDelphi(P, FDir);
      Fail('dois MAINICON');
    except
      on E: EBorionProject do
        Check((Pos('App.res', E.Message) > 0) and (Pos('"bundle.icon"', E.Message) > 0), E.Message);
    end;
  finally
    P.Free;
  end;
end;

procedure TTestBorionProject.TestSemDprOuComDois;
begin
  try
    TBorionProject.Create(FDir).Free;
    Fail('sem .dpr');
  except
    on E: EBorionProject do
      Check(Pos('nenhum .dpr', E.Message) > 0, E.Message);
  end;
  Criar('A.dpr', 'program A; begin end.');
  Criar('B.dpr', 'program B; begin end.');
  try
    TBorionProject.Create(FDir).Free;
    Fail('dois .dpr');
  except
    on E: EBorionProject do
      Check(Pos('mais de um', E.Message) > 0, E.Message);
  end;
  try
    TBorionProject.Create(FDir + '\nao-existe').Free;
    Fail('pasta inexistente');
  except
    on E: EBorionProject do
      Check(Pos('não encontrada', E.Message) > 0, E.Message);
  end;
end;

procedure TTestBorionProject.TestDelphiPelaVariavel;
var
  Antes: string;
begin
  Antes := GetEnvironmentVariable('DELPHI');
  try
    Criar('delphi\Bin\dcc32.exe', 'falso');
    SetEnvironmentVariable('DELPHI', PChar(FDir + '\delphi\'));
    CheckEquals(FDir + '\delphi', BorionFindDelphi, 'a variável vence o registro');
    SetEnvironmentVariable('DELPHI', PChar(FDir + '\sem-dcc32'));
    Check(FileExists(BorionFindDelphi + '\Bin\dcc32.exe'), 'variável inválida: cai no registro');
  finally
    if Antes = '' then
      SetEnvironmentVariable('DELPHI', nil)
    else
      SetEnvironmentVariable('DELPHI', PChar(Antes));
  end;
end;

procedure TTestBorionProject.TestDatas;
var
  H: THandle;
  T: TFileTime;
  S: TSystemTime;
begin
  Criar('a.pas', 'x');
  Criar('b.txt', 'x');
  Check(BorionNewestFile(FDir, '*.pas;*.dpr') > 0);
  CheckEquals(0, BorionNewestFile(FDir, '*.inc'), 0.0001, 'nenhum arquivo');
  Check(BorionIsStale(FDir + '\nao-existe.res', FDir + '\a.pas'), 'alvo inexistente');
  { o .res mais antigo que o .rc: precisa refazer }
  Criar('x.res', 'velho');
  GetSystemTime(S);
  Dec(S.wYear);
  SystemTimeToFileTime(S, T);
  H := CreateFile(PChar(FDir + '\x.res'), GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
  SetFileTime(H, nil, nil, @T);
  CloseHandle(H);
  Check(BorionIsStale(FDir + '\x.res', FDir + '\a.pas'));
  Check(not BorionIsStale(FDir + '\a.pas', FDir + '\x.res'));
end;

procedure TTestBorionProject.TestBuildDeUmProjetoGerado;
var
  O: TBorionNewOptions;
  Criados: TStringList;
  P: TBorionProject;
  Borion: string;
  Grande, Pequeno: HICON;
  Modulo: HMODULE;
  Icone: THandle;
begin
  { um projeto de verdade, gerado pelo borion new e compilado pelo borion build }
  Borion := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..');
  O.Folder := FDir + '\meu-app';
  O.Title := 'Teste do Build';
  O.Template := 'vanilla';
  O.TemplatesDir := Borion + '\Tools\templates';
  O.BorionHome := Borion;
  O.WebView2Home := ExpandFileName(Borion + '\WebView2');
  O.Json4Delphi := 'C:\dev\lib\ACBr\Fontes\Terceiros\json4delphi\src';
  O.AcbrComum := 'C:\dev\lib\ACBr\Fontes\ACBrComum';
  O.DevPort := 5173;
  if not FileExists(O.Json4Delphi + '\Jsons.pas') then
    Exit;  { sem a Jsons.pas neste caminho (outra máquina): os testes de detecção bastam }
  Criados := TStringList.Create;
  Saida := TStringList.Create;
  BorionOut := Capturar;
  try
    BorionNewProject(O, Criados);
    P := TBorionProject.Create(O.Folder);
    try
      BorionBuildProject(P, Borion);
      Check(FileExists(O.Folder + '\MeuApp.exe'), 'exe compilado');
      Check(FileExists(O.Folder + '\web.res'), 'interface empacotada');
      Check(FileExists(O.Folder + '\MeuApp.res'), '.rc compilado');
      Check(FileExists(O.Folder + '\WebView2Loader.dll'), 'loader copiado');
      Check(FileExists(O.Folder + '\web\borion-api\index.js'), '@borion/api copiado');
      Check(Pos('"Teste do Build"', LerRecurso(O.Folder + '\web.res', BORION_CONFIG_RESOURCE)) > 0,
        'app.json embutido junto da interface');
      Check(Pos('OK: MeuApp.exe', Saida.Text) > 0, Saida.Text);
      { o ícone padrão do template (bundle.icon) é o do exe }
      CheckEquals(1, Integer(ExtractIconEx(PChar(O.Folder + '\MeuApp.exe'), -1, Grande, Pequeno, 0)),
        'um ícone no exe');
      Modulo := LoadLibraryEx(PChar(O.Folder + '\MeuApp.exe'), 0, LOAD_LIBRARY_AS_DATAFILE);
      Check(Modulo <> 0, 'abrir o exe');
      try
        Icone := LoadImage(Modulo, 'MAINICON', IMAGE_ICON, 32, 32, 0);
        Check(Icone <> 0, 'o MAINICON carrega');
        DestroyIcon(Icone);
      finally
        FreeLibrary(Modulo);
      end;
    finally
      P.Free;
    end;
  finally
    BorionOut := nil;
    Saida.Free;
    Criados.Free;
  end;
end;

initialization
  RegisterTest('Ferramentas', TTestBorionProject.Suite);

end.
