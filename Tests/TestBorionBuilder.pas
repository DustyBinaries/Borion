unit TestBorionBuilder;

{ Testes do TBorionBuilder (sem rodar o app: o Run precisa de janela e do
  WebView2) e do escopo de arquivos do app (Ipc.Scope), que os plugins fs,
  dialog e shell usam quando criados sem escopo próprio. }

interface

uses
  Windows, SysUtils, Classes, Forms, TestFramework,
  BorionIpc, BorionScope, BorionFs, BorionDialog, BorionShell, Borion, TestBorionPlugins;

type
  TTestBorionBuilder = class(TTestCase)
  published
    procedure TestEncadeamentoDevolveOMesmoBuilder;
    procedure TestTituloDoAppJaNoCreate;
    procedure TestLiberaPluginsQueNaoForamUsados;
  end;

  TTestEscopoDoApp = class(TTesteComIpc)
  private
    FDir: string;
  protected
    procedure SetUp; override;
  published
    procedure TestPluginsSemEscopoUsamODoApp;
    procedure TestEscopoCriadoSobDemanda;
    procedure TestEscopoExplicitoContinuaValendo;
  end;

implementation

type
  TPluginContado = class(TBorionPlugin)
  protected
    procedure Install; override;
  public
    destructor Destroy; override;
    function Name: string; override;
  end;

var
  Liberados: Integer;

destructor TPluginContado.Destroy;
begin
  Inc(Liberados);
  inherited;
end;

procedure TPluginContado.Install;
begin
end;

function TPluginContado.Name: string;
begin
  Result := 'contado';
end;

procedure Comando(Call: TBorionCall);
begin
end;

procedure Registrar(Ipc: TBorionIpc);
begin
end;

procedure Montar(Window: TBorionWindow);
begin
end;

{ TTestBorionBuilder }

procedure TTestBorionBuilder.TestEncadeamentoDevolveOMesmoBuilder;
var
  B: TBorionBuilder;
begin
  B := TBorionBuilder.Create('Teste');
  try
    Check(B.Size(800, 600) = B);
    Check(B.MinSize(400, 300) = B);
    Check(B.Maximized = B);
    Check(B.FixedTitle = B);
    Check(B.Url('https://exemplo.com/') = B);
    Check(B.AllowOrigin('https://outro.com') = B);
    Check(B.UserDataFolder('C:\dados') = B);
    Check(B.AllowDir('$APPDATA') = B);
    Check(B.AllowFile('$DOCUMENT\x.txt') = B);
    Check(B.Command('ola', Comando) = B);
    Check(B.Commands(Registrar) = B);
    Check(B.Setup(Montar) = B);
    Check(B.Size(1, 1).MinSize(1, 1).FixedTitle = B, 'em cadeia');
  finally
    B.Free;
  end;
end;

procedure TTestBorionBuilder.TestTituloDoAppJaNoCreate;
var
  Antes: string;
begin
  Antes := Application.Title;
  try
    TBorionBuilder.Create('Meu App de Teste').Free;
    { os plugins criados na mesma expressão (antes do Run) já veem o título }
    CheckEquals('Meu App de Teste', Application.Title);
  finally
    Application.Title := Antes;
  end;
end;

procedure TTestBorionBuilder.TestLiberaPluginsQueNaoForamUsados;
begin
  { o Run pode terminar sem montar a janela (single-instance numa segunda
    execução): os plugins ainda são do builder e saem com ele }
  Liberados := 0;
  TBorionBuilder.Create('Teste')
    .Plugin(TPluginContado.Create)
    .Plugin(TPluginContado.Create)
    .Free;
  CheckEquals(2, Liberados);
end;

{ TTestEscopoDoApp }

procedure TTestEscopoDoApp.SetUp;
begin
  inherited;
  FDir := ExtractFilePath(ParamStr(0)) + 'out\escopo-app';
  ForceDirectories(FDir);
  with TStringList.Create do
  try
    Text := 'ok';
    SaveToFile(FDir + '\dentro.txt');
  finally
    Free;
  end;
end;

procedure TTestEscopoDoApp.TestPluginsSemEscopoUsamODoApp;
var
  Scope: TBorionScope;
  Fs: TBorionFsPlugin;
  Dialog: TBorionDialogPlugin;
  Shell: TBorionShellPlugin;
  Arquivo: string;
begin
  Scope := TBorionScope.Create('Teste');
  Scope.AllowDir(FDir);
  FIpc.Scope := Scope;  { como o builder faz: o Ipc passa a ser o dono }
  Fs := TBorionFsPlugin(FIpc.AddPlugin(TBorionFsPlugin.Create));
  Dialog := TBorionDialogPlugin(FIpc.AddPlugin(TBorionDialogPlugin.Create));
  Shell := TBorionShellPlugin(FIpc.AddPlugin(TBorionShellPlugin.Create));
  Check(Fs.Scope = Scope, 'fs');
  Check(Dialog.Scope = Scope, 'dialog: o que o usuário escolher entra no escopo do app');
  Check(Shell.Scope = Scope, 'shell');
  Arquivo := StringReplace(FDir + '\dentro.txt', '\', '\\', [rfReplaceAll]);
  Check(Pos('ok', Ok('fs:readTextFile', '{"path":"' + Arquivo + '"}')) > 0);
  CheckEquals('FORBIDDEN_PATH', Erro('fs:readTextFile', '{"path":"C:\\Windows\\win.ini"}'));
  { o TearDown libera o Ipc, e ele o escopo, depois dos plugins: sem liberação dupla }
end;

procedure TTestEscopoDoApp.TestEscopoCriadoSobDemanda;
begin
  Check(FIpc.Scope = nil);
  FIpc.AddPlugin(TBorionFsPlugin.Create);
  Check(FIpc.Scope is TBorionScope, 'criado vazio no Install do fs');
  CheckEquals('FORBIDDEN_PATH', Erro('fs:readTextFile', '{"path":"C:\\Windows\\win.ini"}'), 'vazio = tudo negado');
  Check(BorionAppScope(FIpc) = FIpc.Scope, 'sempre o mesmo');
end;

procedure TTestEscopoDoApp.TestEscopoExplicitoContinuaValendo;
var
  Proprio: TBorionScope;
  Fs: TBorionFsPlugin;
begin
  Proprio := TBorionScope.Create('Teste');
  Fs := TBorionFsPlugin(FIpc.AddPlugin(TBorionFsPlugin.Create(Proprio)));  { o fs é o dono }
  Check(Fs.Scope = Proprio);
  Check(FIpc.Scope = nil, 'o escopo do app nem foi criado');
end;

initialization
  RegisterTest('Borion', TTestBorionBuilder.Suite);
  RegisterTest('Plugins', TTestEscopoDoApp.Suite);

end.
