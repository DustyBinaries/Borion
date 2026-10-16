unit TestBorionNew;

{ Testes do "borion new" (Tools\BorionNew.pas): nomes derivados da pasta e a
  geração a partir dos templates de verdade (Tools\templates), em Tests\out\new. }

interface

uses
  Windows, SysUtils, Classes, TestFramework, BorionNew, BorionConfig;

type
  TTestBorionNew = class(TTestCase)
  private
    FSaida: string;
    function Opcoes(const Pasta, Template: string): TBorionNewOptions;
    function Ler(const Arquivo: string): string;
    procedure SemPlaceholders(const Pasta: string; Arquivos: TStrings);
  protected
    procedure SetUp; override;
  published
    procedure TestNomeDoPrograma;
    procedure TestTituloENomeNpm;
    procedure TestListaTemplates;
    procedure TestGeraVanilla;
    procedure TestGeraViteEReact;
    procedure TestRecusaPastaComArquivos;
    procedure TestTemplateDesconhecido;
    procedure TestPlaceholderDesconhecido;
  end;

implementation

const
  TITULO = 'D''Ávila & Cia "Gestão"';  { aspas, & e acentos: cada arquivo escapa do seu jeito }

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

procedure TTestBorionNew.SetUp;
begin
  FSaida := ExtractFilePath(ParamStr(0)) + 'out\new';
  ApagarPasta(FSaida);
  ForceDirectories(FSaida);
end;

function TTestBorionNew.Opcoes(const Pasta, Template: string): TBorionNewOptions;
begin
  Result.Folder := FSaida + '\' + Pasta;
  Result.Title := TITULO;
  Result.Template := Template;
  Result.TemplatesDir := ExpandFileName(ExtractFilePath(ParamStr(0)) + '..\Tools\templates');
  Result.BorionHome := 'C:\Borion';
  Result.WebView2Home := 'C:\WebView2';
  Result.Json4Delphi := 'C:\json';
  Result.AcbrComum := 'C:\acbr';
  Result.DevPort := 5190;
end;

function TTestBorionNew.Ler(const Arquivo: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(Arquivo, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

procedure TTestBorionNew.SemPlaceholders(const Pasta: string; Arquivos: TStrings);
var
  I: Integer;
begin
  for I := 0 to Arquivos.Count - 1 do
  begin
    Check(Pos('{{', Ler(Pasta + '\' + Arquivos[I])) = 0, 'sobrou placeholder em ' + Arquivos[I]);
    Check(Pos('__PROGRAM__', Arquivos[I]) = 0, Arquivos[I]);
  end;
end;

procedure TTestBorionNew.TestNomeDoPrograma;
begin
  CheckEquals('MeuApp', BorionProgramName('meu-app'));
  CheckEquals('MeuApp2', BorionProgramName('meu app 2'));
  CheckEquals('GestaoDeVendas', BorionProgramName('Gestão de Vendas'));
  CheckEquals('App2fast', BorionProgramName('2fast'), 'não pode começar com número');
  CheckEquals('App', BorionProgramName('***'));
  CheckEquals('BorionApp', BorionProgramName('borion'), 'colidiria com a unit Borion');
  CheckEquals('SysUtilsApp', BorionProgramName('sys-utils'));
end;

procedure TTestBorionNew.TestTituloENomeNpm;
begin
  CheckEquals('Meu App', BorionTitleFromName('meu-app'));
  CheckEquals('Meu App 2', BorionTitleFromName('meu_app_2'));
  CheckEquals('Gestão De Vendas', BorionTitleFromName('gestão de vendas'));
  CheckEquals('meu-app', BorionNpmName('Meu App!'));
  CheckEquals('gestao-de-vendas', BorionNpmName('Gestão de Vendas'));
  CheckEquals('x.y', BorionNpmName('..x.y..'));
  CheckEquals('app', BorionNpmName('***'));
end;

procedure TTestBorionNew.TestListaTemplates;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    BorionListTemplates(Opcoes('x', '').TemplatesDir, L);
    CheckEquals('react,vanilla,vite', StringReplace(L.CommaText, '"', '', [rfReplaceAll]), '_comum não é template');
  finally
    L.Free;
  end;
end;

procedure TTestBorionNew.TestGeraVanilla;
var
  Criados: TStringList;
  P, S: string;
  Config: TBorionConfig;
begin
  Criados := TStringList.Create;
  try
    BorionNewProject(Opcoes('meu-app', 'vanilla'), Criados);
    P := FSaida + '\meu-app';
    CheckEquals('.gitignore,app.json,build.bat,dev.bat,MeuApp.dof,MeuApp.dpr,MeuApp.rc,README.md,web\app.js,' +
      'web\index.html,web\style.css', StringReplace(Criados.CommaText, '"', '', [rfReplaceAll]));
    SemPlaceholders(P, Criados);
    S := Ler(P + '\MeuApp.dpr');
    Check(Pos('program MeuApp;', S) = 1, 'program');
    Check(Pos('TBorionBuilder.Create  //', S) > 0, 'título e janela do app.json');
    S := Ler(P + '\app.json');
    Check(Pos('"productName": "D''' + #$C3#$81 + 'vila & Cia \"Gest' + #$C3#$A3 + 'o\""', S) > 0,
      'título em JSON, UTF-8: ' + S);
    Check(Pos('"identifier": "com.exemplo.meu-app"', S) > 0, S);
    Check(Pos('"frontendDist": "web"', S) > 0, S);
    Config := TBorionConfig.Create;
    try
      Config.LoadFromFile(P + '\app.json');
      CheckEquals(TITULO, Config.ProductName, 'o app.json gerado é válido');
      CheckEquals(0, Config.Warnings.Count, Config.Warnings.Text);
      CheckEquals(900, Config.Window.Width);
    finally
      Config.Free;
    end;
    S := Ler(P + '\web\index.html');
    Check(Pos('<title>D''' + #$C3#$81 + 'vila &amp; Cia &quot;Gest' + #$C3#$A3 + 'o&quot;</title>', S) > 0,
      'título em HTML, UTF-8: ' + Copy(S, Pos('<title>', S), 80));
    S := Ler(P + '\MeuApp.rc');
    Check(Pos('"D''Ávila & Cia ""Gestão""\0"', S) > 0, 'título no .rc');
    S := Ler(P + '\MeuApp.dof');
    Check(Pos('SearchPath=C:\json;C:\acbr;C:\Borion;C:\Borion\Plugins;C:\WebView2', S) > 0, S);
    S := Ler(P + '\build.bat');
    Check(Pos('set BORION_HOME=C:\Borion', S) > 0);
    Check(Pos('borion.exe" build', S) > 0, 'chama o borion build');
    Check(Pos(#13#10, S) > 0, 'CRLF nos .bat');
  finally
    Criados.Free;
  end;
end;

procedure TTestBorionNew.TestGeraViteEReact;
var
  Criados: TStringList;
  S: string;
begin
  Criados := TStringList.Create;
  try
    BorionNewProject(Opcoes('app-vite', 'vite'), Criados);
    SemPlaceholders(FSaida + '\app-vite', Criados);
    Check(Criados.IndexOf('dev.bat') >= 0);
    Check(Criados.IndexOf('frontend\src\main.js') >= 0);
    S := Ler(FSaida + '\app-vite\frontend\package.json');
    Check(Pos('"name": "app-vite"', S) > 0, S);
    Check(Pos('"@borion/api": "file:C:/Borion/js"', S) > 0, 'caminho com barras para o npm');
    Check(Pos('port: 5190,', Ler(FSaida + '\app-vite\frontend\vite.config.js')) > 0);
    Check(Pos('borion.exe" dev', Ler(FSaida + '\app-vite\dev.bat')) > 0, 'chama o borion dev');
    S := Ler(FSaida + '\app-vite\app.json');
    Check(Pos('"frontendDist": "frontend/dist"', S) > 0, S);
    Check(Pos('"devUrl": "http://localhost:5190"', S) > 0, 'a porta do --port: ' + S);

    Criados.Clear;
    BorionNewProject(Opcoes('app react', 'react'), Criados);
    SemPlaceholders(FSaida + '\app react', Criados);
    S := Ler(FSaida + '\app react\frontend\src\App.jsx');
    Check(Pos('{''D\''' + #$C3#$81 + 'vila & Cia "Gest' + #$C3#$A3 + 'o"''}', S) > 0, 'título como string JS');
    Check(FileExists(FSaida + '\app react\AppReact.dpr'));
  finally
    Criados.Free;
  end;
end;

procedure TTestBorionNew.TestRecusaPastaComArquivos;
var
  Criados: TStringList;
begin
  ForceDirectories(FSaida + '\ocupada');
  with TStringList.Create do
  try
    SaveToFile(FSaida + '\ocupada\meu.txt');
  finally
    Free;
  end;
  Criados := TStringList.Create;
  try
    try
      BorionNewProject(Opcoes('ocupada', 'vanilla'), Criados);
      Fail('não pode escrever numa pasta com arquivos');
    except
      on E: EBorionNew do
        Check(Pos('não está vazia', E.Message) > 0, E.Message);
    end;
    CheckEquals(0, Criados.Count);
    { pasta vazia pode }
    ForceDirectories(FSaida + '\vazia');
    BorionNewProject(Opcoes('vazia', 'vanilla'), Criados);
    Check(FileExists(FSaida + '\vazia\Vazia.dpr'));
  finally
    Criados.Free;
  end;
end;

procedure TTestBorionNew.TestTemplateDesconhecido;
var
  Criados: TStringList;
begin
  Criados := TStringList.Create;
  try
    try
      BorionNewProject(Opcoes('x', 'angular'), Criados);
      Fail('template desconhecido');
    except
      on E: EBorionNew do
        Check(Pos('react, vanilla, vite', E.Message) > 0, E.Message);
    end;
    Check(not DirectoryExists(FSaida + '\x'), 'nada criado');
  finally
    Criados.Free;
  end;
end;

procedure TTestBorionNew.TestPlaceholderDesconhecido;
var
  O: TBorionNewOptions;
  Criados: TStringList;
begin
  O := Opcoes('y', 'ruim');
  O.TemplatesDir := FSaida + '\templates';
  ForceDirectories(O.TemplatesDir + '\ruim');
  ForceDirectories(O.TemplatesDir + '\_comum');
  with TStringList.Create do
  try
    Text := 'ok {{PROGRAM}} e {{NAO_EXISTE}}';
    SaveToFile(O.TemplatesDir + '\ruim\a.txt');
  finally
    Free;
  end;
  Criados := TStringList.Create;
  try
    try
      BorionNewProject(O, Criados);
      Fail('placeholder desconhecido');
    except
      on E: EBorionNew do
        Check(Pos('{{NAO_EXISTE}}', E.Message) > 0, E.Message);
    end;
  finally
    Criados.Free;
  end;
end;

initialization
  RegisterTest('Ferramentas', TTestBorionNew.Suite);

end.
