unit TestBorionProject;

{ Testes do borion build / dev (Tools\BorionProject.pas e BorionBuild.pas): a
  detecção do projeto por convenção e um build de verdade de um projeto gerado
  pelo borion new (precisa do Delphi 7, como os próprios testes). }

interface

uses
  Windows, SysUtils, Classes, TestFramework, BorionProject, BorionBuild, BorionNew;

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
begin
  { um projeto de verdade, gerado pelo borion new e compilado pelo borion build }
  Borion := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..');
  O.Folder := FDir + '\meu-app';
  O.Title := 'Teste do Build';
  O.Template := 'vanilla';
  O.TemplatesDir := Borion + '\Tools\templates';
  O.BorionHome := Borion;
  O.WebView2Home := ExpandFileName(Borion + '\..\WebView2');
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
      Check(Pos('OK: MeuApp.exe', Saida.Text) > 0, Saida.Text);
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
