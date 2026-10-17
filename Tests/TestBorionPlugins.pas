unit TestBorionPlugins;

{$WARN SYMBOL_PLATFORM OFF}

{ Testes dos plugins (arquitetura, escopo, fs, dialog, shell). Os comandos
  entram pelo IPC (ProcessMessage) e as respostas saem pelo OnPost, como nos
  testes do TBorionIpc. Os arquivos ficam em out\plugins, ao lado do exe. }

interface

uses
  Windows, Messages, SysUtils, Classes, TestFramework, Jsons, BorionJson, BorionIpc,
  BorionScope, BorionFs, BorionDialog, BorionShell;

type
  TTesteComIpc = class(TTestCase)
  protected
    FIpc: TBorionIpc;
    FPosts: TStringList;
    procedure Postou(Sender: TObject; const Json: WideString);
    procedure Bombear(Quantas: Integer; TimeoutMs: Cardinal = 3000);
    { Envia o invoke e devolve a resposta parseada (o chamador libera) }
    function Invocar(const Cmd, ArgsJson: string): TJsonObject;
    { Resultado como JSON (null, "x", objeto...); falha se a resposta for erro }
    function Ok(const Cmd, ArgsJson: string): string;
    { Código do erro; falha se a resposta for sucesso }
    function Erro(const Cmd, ArgsJson: string): string;
    procedure SetUp; override;
    procedure TearDown; override;
  end;

  TPluginEco = class(TBorionPlugin)
  private
    procedure CmdAgora(Call: TBorionCall);
    procedure CmdDepois(Call: TBorionCall);
    procedure CmdFalharDepois(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    function Name: string; override;
  end;

  TTestPluginInfra = class(TTesteComIpc)
  published
    procedure TestComandosComPrefixo;
    procedure TestPluginDuplicadoRecusado;
    procedure TestFindPlugin;
    procedure TestLaterSoRespondeDepoisDoCallback;
    procedure TestLaterComExcecao;
  end;

  TTestBorionScope = class(TTestCase)
  private
    FScope: TBorionScope;
    procedure EsperarErro(const Path, Codigo: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNormalizaPontosEBarras;
    procedure TestRecusaRelativo;
    procedure TestRecusaDispositivosEStreams;
    procedure TestRecusaNomesReservados;
    procedure TestRecusaCaracteresInvalidos;
    procedure TestPastaRecursiva;
    procedure TestPrefixoVizinhoNegado;
    procedure TestEscapePorPontosNegado;
    procedure TestPastaNaoRecursiva;
    procedure TestArquivoUnico;
    procedure TestRaizDoDrive;
    procedure TestVariaveis;
    procedure TestBaseDir;
    procedure TestBaseDirFromName;
  end;

  TTestBorionFs = class(TTesteComIpc)
  private
    FRaiz: string;
    FFora: string;
    function Q(const Relativo: string): string;
    function Arg(const Relativo: string; const Extra: string = ''): string;
    procedure Criar(const Caminho, Conteudo: string);
    function Ler(const Caminho: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTextoUtf8IdaEVolta;
    procedure TestTextoLeComBom;
    procedure TestTextoAnsi;
    procedure TestAppend;
    procedure TestBinarioBase64;
    procedure TestExistsEStat;
    procedure TestReadDir;
    procedure TestMkdirERemove;
    procedure TestRemovePastaCheiaSemRecursiveFalha;
    procedure TestRemoveNaoSegueJuncao;
    procedure TestRenameECopy;
    procedure TestForaDoEscopo;
    procedure TestEscapePorPontos;
    procedure TestNaoEncontrado;
    procedure TestArgumentoObrigatorio;
    procedure TestBaseDir;
    procedure TestBase64;
  end;

  TTestBorionDialog = class(TTestCase)
  published
    procedure TestFiltro;
    procedure TestFiltroVazio;
    procedure TestMultiSelect;
  end;

  TTestBorionShell = class(TTesteComIpc)
  private
    FPasta: string;
    FExecutados: TStringList;
    FShell: TBorionShellPlugin;
    procedure Executou(const Verb, Target, Params: string);
    function Recusa(const Alvo: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestUrlsPermitidas;
    procedure TestEsquemasRecusados;
    procedure TestArquivoNoEscopo;
    procedure TestExecutavelRecusado;
    procedure TestArquivoForaDoEscopo;
    procedure TestOpenPeloIpc;
    procedure TestShowInFolder;
    procedure TestEsquemaPersonalizado;
  end;

implementation

const
  ORIGEM = 'https://app.localhost/';
  FILE_ATTRIBUTE_REPARSE_POINT = $400;

function PastaTestes(const Nome: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'out\plugins\' + Nome;
end;

procedure ApagarTudo(const Pasta: string);
var
  SR: TSearchRec;
  Item: string;
begin
  if FindFirst(Pasta + '\*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      Item := Pasta + '\' + SR.Name;
      if SR.FindData.dwFileAttributes and FILE_ATTRIBUTE_REPARSE_POINT <> 0 then
        RemoveDirectory(PChar(Item))
      else if SR.Attr and faDirectory <> 0 then
        ApagarTudo(Item)
      else
      begin
        SetFileAttributes(PChar(Item), FILE_ATTRIBUTE_NORMAL);
        DeleteFile(Item);
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  RemoveDir(Pasta);
end;

{ TTesteComIpc }

procedure TTesteComIpc.SetUp;
begin
  FPosts := TStringList.Create;
  FIpc := TBorionIpc.Create(nil, nil);
  FIpc.OnPost := Postou;
  FIpc.AllowOrigin(ORIGEM);
end;

procedure TTesteComIpc.TearDown;
begin
  FIpc.Free;
  FPosts.Free;
end;

procedure TTesteComIpc.Postou(Sender: TObject; const Json: WideString);
begin
  FPosts.Add(WideJsonToAnsi(Json));
end;

procedure TTesteComIpc.Bombear(Quantas: Integer; TimeoutMs: Cardinal);
var
  Msg: TMsg;
  Inicio: Cardinal;
begin
  Inicio := GetTickCount;
  while (FPosts.Count < Quantas) and (GetTickCount - Inicio < TimeoutMs) do
  begin
    while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
    begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
    Sleep(1);
  end;
end;

function TTesteComIpc.Invocar(const Cmd, ArgsJson: string): TJsonObject;
var
  Antes: Integer;
  Json: string;
begin
  Antes := FPosts.Count;
  Json := '{"__borion":1,"kind":"invoke","id":1,"cmd":' + JsonQuote(Cmd);
  if ArgsJson <> '' then
    Json := Json + ',"args":' + ArgsJson;
  { como o JS manda: Unicode de verdade (\u201c), não o \u0093 interno da Jsons }
  Check(FIpc.ProcessMessage(AnsiJsonToWide(Json + '}'), ORIGEM));
  Bombear(Antes + 1);  { comandos Later respondem depois }
  { eventos emitidos pelo comando (store:change...) saem antes da resposta }
  Check((FPosts.Count > Antes) and (Pos('"kind":"event"', FPosts[FPosts.Count - 1]) = 0),
    'sem resposta para ' + Cmd);
  Result := TJsonObject.Create;
  Result.Parse(FPosts[FPosts.Count - 1]);
end;

function TTesteComIpc.Ok(const Cmd, ArgsJson: string): string;
var
  R: TJsonObject;
begin
  R := Invocar(Cmd, ArgsJson);
  try
    if not R['ok'].AsBoolean then
      Fail(Cmd + ' falhou: ' + R['error'].AsObject['code'].AsString + ' ' +
        R['error'].AsObject['message'].AsString);
    Result := R['result'].Stringify;
  finally
    R.Free;
  end;
end;

function TTesteComIpc.Erro(const Cmd, ArgsJson: string): string;
var
  R: TJsonObject;
begin
  R := Invocar(Cmd, ArgsJson);
  try
    CheckFalse(R['ok'].AsBoolean, Cmd + ' deveria falhar');
    Result := R['error'].AsObject['code'].AsString;
  finally
    R.Free;
  end;
end;

{ TPluginEco }

function TPluginEco.Name: string;
begin
  Result := 'eco';
end;

procedure TPluginEco.Install;
begin
  Command('agora', CmdAgora);
  CommandLater('depois', CmdDepois);
  CommandLater('falharDepois', CmdFalharDepois);
end;

procedure TPluginEco.CmdAgora(Call: TBorionCall);
begin
  Call.Result.AsString := 'agora';
end;

procedure TPluginEco.CmdDepois(Call: TBorionCall);
begin
  Call.Result.AsString := 'depois:' + Call.ArgStr('x');
end;

procedure TPluginEco.CmdFalharDepois(Call: TBorionCall);
begin
  raise EBorionError.Create('DEPOIS', 'falhou depois');
end;

{ TTestPluginInfra }

procedure TTestPluginInfra.TestComandosComPrefixo;
begin
  FIpc.AddPlugin(TPluginEco.Create);
  CheckEquals('"agora"', Ok('eco:agora', ''));
  CheckEquals('UNKNOWN_COMMAND', Erro('agora', ''), 'o comando só existe com o prefixo');
end;

procedure TTestPluginInfra.TestPluginDuplicadoRecusado;
var
  P: TPluginEco;
begin
  FIpc.AddPlugin(TPluginEco.Create);
  P := TPluginEco.Create;
  try
    try
      FIpc.AddPlugin(P);
      Fail('deveria recusar o segundo plugin "eco"');
    except
      on E: EBorionError do
        CheckEquals('PLUGIN', E.Code);
    end;
  finally
    P.Free;
  end;
end;

procedure TTestPluginInfra.TestFindPlugin;
var
  P: TBorionPlugin;
begin
  P := FIpc.AddPlugin(TPluginEco.Create);
  Check(FIpc.FindPlugin('eco') = P);
  Check(FIpc.FindPlugin('ECO') = P);
  Check(FIpc.FindPlugin('outro') = nil);
  Check(P.Ipc = FIpc);
end;

procedure TTestPluginInfra.TestLaterSoRespondeDepoisDoCallback;
begin
  FIpc.AddPlugin(TPluginEco.Create);
  FIpc.ProcessMessage('{"__borion":1,"kind":"invoke","id":5,"cmd":"eco:depois","args":{"x":"1"}}', ORIGEM);
  CheckEquals(0, FPosts.Count, 'Later não pode responder dentro do callback');
  Bombear(1);
  CheckEquals(1, FPosts.Count);
  Check(Pos('"result":"depois:1"', FPosts[0]) > 0, FPosts[0]);
end;

procedure TTestPluginInfra.TestLaterComExcecao;
begin
  FIpc.AddPlugin(TPluginEco.Create);
  CheckEquals('DEPOIS', Erro('eco:falharDepois', ''));
end;

{ TTestBorionScope }

procedure TTestBorionScope.SetUp;
begin
  FScope := TBorionScope.Create('BorionTestes');
end;

procedure TTestBorionScope.TearDown;
begin
  FScope.Free;
end;

procedure TTestBorionScope.EsperarErro(const Path, Codigo: string);
begin
  try
    BorionNormalizePath(Path);
    Fail('deveria recusar: ' + Path);
  except
    on E: EBorionError do
      CheckEquals(Codigo, E.Code, Path);
  end;
end;

procedure TTestBorionScope.TestNormalizaPontosEBarras;
begin
  CheckEquals('C:\app\dados\x.txt', BorionNormalizePath('C:/app/./lixo/../dados/x.txt'));
  CheckEquals('C:\app', BorionNormalizePath('C:\app\'));
  CheckEquals('C:\', BorionNormalizePath('C:\'));
end;

procedure TTestBorionScope.TestRecusaRelativo;
begin
  EsperarErro('dados\x.txt', 'INVALID_PATH');
  EsperarErro('\dados\x.txt', 'INVALID_PATH');
  EsperarErro('C:dados', 'INVALID_PATH');
  EsperarErro('', 'INVALID_PATH');
end;

procedure TTestBorionScope.TestRecusaDispositivosEStreams;
begin
  EsperarErro('\\?\C:\app\x.txt', 'INVALID_PATH');
  EsperarErro('\\.\PhysicalDrive0', 'INVALID_PATH');
  EsperarErro('C:\app\x.txt:segredo', 'INVALID_PATH');
  EsperarErro('C:\app\x.txt::$DATA', 'INVALID_PATH');
end;

procedure TTestBorionScope.TestRecusaNomesReservados;
begin
  EsperarErro('C:\app\NUL', 'INVALID_PATH');
  EsperarErro('C:\app\con.txt', 'INVALID_PATH');
  EsperarErro('C:\app\COM1\x', 'INVALID_PATH');
  EsperarErro('C:\app\lpt9.log', 'INVALID_PATH');
  CheckEquals('C:\app\console.txt', BorionNormalizePath('C:\app\console.txt'), 'só o nome exato é reservado');
  CheckEquals('C:\app\COM10', BorionNormalizePath('C:\app\COM10'));
end;

procedure TTestBorionScope.TestRecusaCaracteresInvalidos;
begin
  EsperarErro('C:\app\a*.txt', 'INVALID_PATH');
  EsperarErro('C:\app\a?.txt', 'INVALID_PATH');
  EsperarErro('C:\app\a|b', 'INVALID_PATH');
  EsperarErro('C:\app\a"b', 'INVALID_PATH');
  EsperarErro('C:\app\a'#1'b', 'INVALID_PATH');
end;

procedure TTestBorionScope.TestPastaRecursiva;
begin
  FScope.AllowDir('C:\app\dados');
  Check(FScope.IsAllowed('C:\app\dados'), 'a própria pasta');
  Check(FScope.IsAllowed('C:\app\dados\x.txt'));
  Check(FScope.IsAllowed('C:\APP\Dados\sub\y.txt'), 'sem diferenciar maiúsculas');
  CheckFalse(FScope.IsAllowed('C:\app'));
  CheckFalse(FScope.IsAllowed('C:\app\outra\x.txt'));
end;

procedure TTestBorionScope.TestPrefixoVizinhoNegado;
begin
  FScope.AllowDir('C:\app\dados');
  CheckFalse(FScope.IsAllowed('C:\app\dados2\x.txt'));
  CheckFalse(FScope.IsAllowed('C:\app\dados.bak'));
end;

procedure TTestBorionScope.TestEscapePorPontosNegado;
begin
  FScope.AllowDir('C:\app\dados');
  try
    FScope.Check('C:\app\dados\..\segredo.txt');
    Fail('".." não pode sair da pasta');
  except
    on E: EBorionError do
      CheckEquals('FORBIDDEN_PATH', E.Code);
  end;
end;

procedure TTestBorionScope.TestPastaNaoRecursiva;
begin
  FScope.AllowDir('C:\app\dados', False);
  Check(FScope.IsAllowed('C:\app\dados\x.txt'));
  CheckFalse(FScope.IsAllowed('C:\app\dados\sub\x.txt'));
end;

procedure TTestBorionScope.TestArquivoUnico;
begin
  FScope.AllowFile('C:\app\config.ini');
  Check(FScope.IsAllowed('C:\APP\CONFIG.INI'));
  CheckFalse(FScope.IsAllowed('C:\app\outro.ini'));
  CheckFalse(FScope.IsAllowed('C:\app'));
end;

procedure TTestBorionScope.TestRaizDoDrive;
begin
  FScope.AllowDir('C:\');
  Check(FScope.IsAllowed('C:\qualquer\coisa.txt'));
  CheckFalse(FScope.IsAllowed('D:\x.txt'));
end;

procedure TTestBorionScope.TestVariaveis;
begin
  FScope.AllowDir('$TEMP\borion');
  CheckEquals(BorionNormalizePath(BorionBaseDirPath(bdTemp, '') + '\borion'), FScope.Dirs[0]);
  Check(Pos('\BorionTestes', BorionBaseDirPath(bdAppData, 'BorionTestes')) > 0, 'AppData inclui o nome do app');
  try
    FScope.AllowDir('$NAOEXISTE\x');
    Fail('variável desconhecida');
  except
    on E: EBorionError do
      CheckEquals('INVALID_PATH', E.Code);
  end;
end;

procedure TTestBorionScope.TestBaseDir;
var
  Temp: string;
begin
  Temp := BorionBaseDirPath(bdTemp, '');
  CheckEquals(BorionNormalizePath(Temp + '\a\b.txt'), FScope.Resolve('a/b.txt', bdTemp));
  try
    FScope.Resolve('C:\x.txt', bdTemp);
    Fail('com baseDir o caminho deve ser relativo');
  except
    on E: EBorionError do
      CheckEquals('INVALID_PATH', E.Code);
  end;
  FScope.AllowDir('$TEMP\borion');
  try
    FScope.Check('borion\..\fora.txt', 'temp');
    Fail('".." a partir do baseDir não pode sair do escopo');
  except
    on E: EBorionError do
      CheckEquals('FORBIDDEN_PATH', E.Code);
  end;
end;

procedure TTestBorionScope.TestBaseDirFromName;
begin
  Check(BorionBaseDirFromName('') = bdNone);
  Check(BorionBaseDirFromName('appData') = bdAppData);
  Check(BorionBaseDirFromName('DOCUMENT') = bdDocument);
  try
    BorionBaseDirFromName('windows');
    Fail('baseDir desconhecido');
  except
    on E: EBorionError do
      CheckEquals('INVALID_BASE_DIR', E.Code);
  end;
end;

{ TTestBorionFs }

procedure TTestBorionFs.SetUp;
var
  Scope: TBorionScope;
begin
  inherited;
  FRaiz := PastaTestes('fs');
  FFora := PastaTestes('fora');
  ApagarTudo(FRaiz);
  ApagarTudo(FFora);
  ForceDirectories(FRaiz);
  ForceDirectories(FFora);
  Scope := TBorionScope.Create('BorionTestes');
  Scope.AllowDir(FRaiz);
  Scope.AllowDir('$TEMP\BorionTestesFs');
  FIpc.AddPlugin(TBorionFsPlugin.Create(Scope));
end;

procedure TTestBorionFs.TearDown;
begin
  inherited;
  ApagarTudo(FRaiz);
  ApagarTudo(FFora);
  ApagarTudo(BorionBaseDirPath(bdTemp, '') + '\BorionTestesFs');
end;

function TTestBorionFs.Q(const Relativo: string): string;
begin
  Result := JsonQuote(FRaiz + '\' + Relativo);
end;

function TTestBorionFs.Arg(const Relativo, Extra: string): string;
begin
  Result := '{"path":' + Q(Relativo);
  if Extra <> '' then
    Result := Result + ',' + Extra;
  Result := Result + '}';
end;

procedure TTestBorionFs.Criar(const Caminho, Conteudo: string);
var
  F: TFileStream;
begin
  ForceDirectories(ExtractFilePath(Caminho));
  F := TFileStream.Create(Caminho, fmCreate);
  try
    if Conteudo <> '' then
      F.WriteBuffer(Conteudo[1], Length(Conteudo));
  finally
    F.Free;
  end;
end;

function TTestBorionFs.Ler(const Caminho: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(Caminho, fmOpenRead);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

procedure TTestBorionFs.TestTextoUtf8IdaEVolta;
const
  Texto = 'Ação: “ok” — €';
begin
  Ok('fs:writeTextFile', Arg('a.txt', '"contents":' + JsonQuote(Texto)));
  CheckEquals(AnsiToUtf8(Texto), Ler(FRaiz + '\a.txt'), 'gravado em UTF-8, sem BOM');
  CheckEquals(JsonQuote(Texto), Ok('fs:readTextFile', Arg('a.txt')));
end;

procedure TTestBorionFs.TestTextoLeComBom;
begin
  Criar(FRaiz + '\bom.txt', #$EF#$BB#$BF + AnsiToUtf8('ção'));
  CheckEquals(JsonQuote('ção'), Ok('fs:readTextFile', Arg('bom.txt')));
end;

procedure TTestBorionFs.TestTextoAnsi;
begin
  Ok('fs:writeTextFile', Arg('ansi.txt', '"contents":"ção","encoding":"ansi"'));
  CheckEquals('ção', Ler(FRaiz + '\ansi.txt'));
  CheckEquals(JsonQuote('ção'), Ok('fs:readTextFile', Arg('ansi.txt', '"encoding":"ansi"')));
  CheckEquals('INVALID_ARGS', Erro('fs:readTextFile', Arg('ansi.txt', '"encoding":"ebcdic"')));
end;

procedure TTestBorionFs.TestAppend;
begin
  Ok('fs:writeTextFile', Arg('log.txt', '"contents":"a"'));
  Ok('fs:writeTextFile', Arg('log.txt', '"contents":"b","append":true'));
  Ok('fs:writeTextFile', Arg('log.txt', '"contents":"c","append":true'));
  CheckEquals('abc', Ler(FRaiz + '\log.txt'));
end;

procedure TTestBorionFs.TestBinarioBase64;
var
  Bytes: string;
  I: Integer;
begin
  SetLength(Bytes, 256);
  for I := 0 to 255 do
    Bytes[I + 1] := Chr(I);
  Ok('fs:writeFile', Arg('bin.dat', '"data":' + JsonQuote(BorionBase64Encode(Bytes))));
  CheckEquals(Bytes, Ler(FRaiz + '\bin.dat'));
  CheckEquals(JsonQuote(BorionBase64Encode(Bytes)), Ok('fs:readFile', Arg('bin.dat')));
end;

procedure TTestBorionFs.TestExistsEStat;
var
  R: TJsonObject;
begin
  Criar(FRaiz + '\e.txt', '12345');
  CheckEquals('true', Ok('fs:exists', Arg('e.txt')));
  CheckEquals('false', Ok('fs:exists', Arg('nao.txt')));
  CheckEquals('true', Ok('fs:exists', '{"path":' + JsonQuote(FRaiz) + '}'));
  R := TJsonObject.Create;
  try
    R.Parse(Ok('fs:stat', Arg('e.txt')));
    CheckTrue(R['isFile'].AsBoolean);
    CheckFalse(R['isDirectory'].AsBoolean);
    CheckEquals(5, R['size'].AsInteger);
    CheckEquals(19, Length(R['modified'].AsString), 'yyyy-mm-ddThh:nn:ss');
  finally
    R.Free;
  end;
end;

procedure TTestBorionFs.TestReadDir;
var
  A: TJsonArray;
  Nomes: TStringList;
  I: Integer;
begin
  Criar(FRaiz + '\d\um.txt', '1');
  Criar(FRaiz + '\d\dois.txt', '22');
  ForceDirectories(FRaiz + '\d\sub');
  A := TJsonArray.Create;
  Nomes := TStringList.Create;
  try
    A.Parse(Ok('fs:readDir', Arg('d')));
    CheckEquals(3, A.Count);
    for I := 0 to A.Count - 1 do
      Nomes.Add(A[I].AsObject['name'].AsString + '=' + A[I].AsObject['isDirectory'].AsString);
    Nomes.Sort;
    CheckEquals('dois.txt=false,sub=true,um.txt=false', StringReplace(Trim(Nomes.Text), #13#10, ',', [rfReplaceAll]));
  finally
    Nomes.Free;
    A.Free;
  end;
end;

procedure TTestBorionFs.TestMkdirERemove;
begin
  CheckEquals('NOT_FOUND', Erro('fs:mkdir', Arg('x\y\z')), 'sem recursive, o pai precisa existir');
  Ok('fs:mkdir', Arg('x\y\z', '"recursive":true'));
  Check(DirectoryExists(FRaiz + '\x\y\z'));
  CheckEquals('ALREADY_EXISTS', Erro('fs:mkdir', Arg('x')));
  Criar(FRaiz + '\x\y\z\f.txt', 'f');
  Ok('fs:remove', Arg('x\y\z\f.txt'));
  CheckFalse(FileExists(FRaiz + '\x\y\z\f.txt'));
  Ok('fs:remove', Arg('x', '"recursive":true'));
  CheckFalse(DirectoryExists(FRaiz + '\x'));
end;

procedure TTestBorionFs.TestRemovePastaCheiaSemRecursiveFalha;
begin
  Criar(FRaiz + '\cheia\f.txt', 'f');
  CheckEquals('IO_ERROR', Erro('fs:remove', Arg('cheia')));
  Check(FileExists(FRaiz + '\cheia\f.txt'));
end;

procedure TTestBorionFs.TestRemoveNaoSegueJuncao;
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  Cmd: string;
begin
  { junção dentro do escopo apontando para uma pasta de fora }
  Criar(FFora + '\precioso.txt', 'não apague');
  ForceDirectories(FRaiz + '\com-link');
  Cmd := 'cmd.exe /c mklink /J "' + FRaiz + '\com-link\atalho" "' + FFora + '"';
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESHOWWINDOW;
  SI.wShowWindow := SW_HIDE;
  Check(CreateProcess(nil, PChar(Cmd), nil, nil, False, 0, nil, nil, SI, PI), 'mklink');
  WaitForSingleObject(PI.hProcess, 10000);
  CloseHandle(PI.hThread);
  CloseHandle(PI.hProcess);
  Check(FileExists(FRaiz + '\com-link\atalho\precioso.txt'), 'a junção deveria existir');

  Ok('fs:remove', Arg('com-link', '"recursive":true'));
  CheckFalse(DirectoryExists(FRaiz + '\com-link'));
  Check(FileExists(FFora + '\precioso.txt'), 'o remove seguiu a junção e apagou fora do escopo!');
end;

procedure TTestBorionFs.TestRenameECopy;
begin
  Criar(FRaiz + '\orig.txt', 'conteudo');
  Ok('fs:copyFile', '{"from":' + Q('orig.txt') + ',"to":' + Q('copia.txt') + '}');
  CheckEquals('conteudo', Ler(FRaiz + '\copia.txt'));
  Ok('fs:rename', '{"from":' + Q('copia.txt') + ',"to":' + Q('novo.txt') + '}');
  CheckFalse(FileExists(FRaiz + '\copia.txt'));
  CheckEquals('conteudo', Ler(FRaiz + '\novo.txt'));
  CheckEquals('FORBIDDEN_PATH', Erro('fs:rename',
    '{"from":' + Q('novo.txt') + ',"to":' + JsonQuote(FFora + '\roubado.txt') + '}'));
  CheckEquals('FORBIDDEN_PATH', Erro('fs:copyFile',
    '{"from":' + JsonQuote(FFora + '\x.txt') + ',"to":' + Q('y.txt') + '}'));
end;

procedure TTestBorionFs.TestForaDoEscopo;
begin
  Criar(FFora + '\segredo.txt', 'segredo');
  CheckEquals('FORBIDDEN_PATH', Erro('fs:readTextFile', '{"path":' + JsonQuote(FFora + '\segredo.txt') + '}'));
  CheckEquals('FORBIDDEN_PATH', Erro('fs:exists', '{"path":' + JsonQuote(FFora + '\segredo.txt') + '}'),
    'nem a existência pode vazar');
  CheckEquals('FORBIDDEN_PATH', Erro('fs:writeTextFile', '{"path":"C:\\Windows\\x.txt","contents":"x"}'));
  CheckEquals('FORBIDDEN_PATH', Erro('fs:readDir', '{"path":' + JsonQuote(FFora) + '}'));
end;

procedure TTestBorionFs.TestEscapePorPontos;
begin
  Criar(FFora + '\segredo.txt', 'segredo');
  CheckEquals('FORBIDDEN_PATH', Erro('fs:readTextFile', Arg('..\fora\segredo.txt')));
  CheckEquals('INVALID_PATH', Erro('fs:readTextFile', Arg('a.txt:stream')));
end;

procedure TTestBorionFs.TestNaoEncontrado;
begin
  CheckEquals('NOT_FOUND', Erro('fs:readTextFile', Arg('nao-existe.txt')));
  CheckEquals('NOT_FOUND', Erro('fs:stat', Arg('nao-existe.txt')));
  CheckEquals('NOT_FOUND', Erro('fs:readDir', Arg('nao-existe')));
end;

procedure TTestBorionFs.TestArgumentoObrigatorio;
begin
  CheckEquals('INVALID_ARGS', Erro('fs:readTextFile', '{}'));
  CheckEquals('INVALID_ARGS', Erro('fs:rename', '{"from":' + Q('a') + '}'));
end;

procedure TTestBorionFs.TestBaseDir;
begin
  Ok('fs:mkdir', '{"path":"BorionTestesFs","baseDir":"temp"}');
  Ok('fs:writeTextFile', '{"path":"BorionTestesFs/nota.txt","baseDir":"temp","contents":"oi"}');
  CheckEquals('"oi"', Ok('fs:readTextFile', '{"path":"BorionTestesFs/nota.txt","baseDir":"temp"}'));
  CheckEquals('FORBIDDEN_PATH', Erro('fs:readTextFile', '{"path":"outro.txt","baseDir":"temp"}'));
  CheckEquals('INVALID_BASE_DIR', Erro('fs:readTextFile', '{"path":"x","baseDir":"system32"}'));
end;

procedure TTestBorionFs.TestBase64;
begin
  CheckEquals('', BorionBase64Encode(''));
  CheckEquals('Zg==', BorionBase64Encode('f'));
  CheckEquals('Zm8=', BorionBase64Encode('fo'));
  CheckEquals('Zm9vYmFy', BorionBase64Encode('foobar'));
  CheckEquals('foobar', BorionBase64Decode('Zm9vYmFy'));
  CheckEquals('fo', BorionBase64Decode('Zm8='));
  CheckEquals(#$FB#$FF, BorionBase64Decode('-_8='), 'variante URL-safe');
  try
    BorionBase64Decode('Zm9v!');
    Fail('base64 inválido');
  except
    on E: EBorionError do
      CheckEquals('INVALID_BASE64', E.Code);
  end;
end;

{ TTestBorionDialog }

procedure TTestBorionDialog.TestFiltro;
var
  A: TJsonArray;
begin
  A := TJsonArray.Create;
  try
    A.Parse('[{"name":"Texto","extensions":["txt",".md","*.log"]},{"name":"Tudo","extensions":["*"]},{"extensions":[]}]');
    CheckEquals('Texto (*.txt;*.md;*.log)'#0'*.txt;*.md;*.log'#0'Tudo (*.*)'#0'*.*'#0#0, BorionDialogFilter(A));
  finally
    A.Free;
  end;
end;

procedure TTestBorionDialog.TestFiltroVazio;
begin
  CheckEquals('Todos os arquivos (*.*)'#0'*.*'#0#0, BorionDialogFilter(nil));
end;

procedure TTestBorionDialog.TestMultiSelect;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    BorionSplitMultiSelect('C:\pasta\a.txt'#0#0, L);
    CheckEquals(1, L.Count);
    CheckEquals('C:\pasta\a.txt', L[0]);
    BorionSplitMultiSelect('C:\pasta'#0'a.txt'#0'b.txt'#0#0, L);
    CheckEquals(2, L.Count);
    CheckEquals('C:\pasta\a.txt', L[0]);
    CheckEquals('C:\pasta\b.txt', L[1]);
    BorionSplitMultiSelect('C:\'#0'a.txt'#0'b.txt'#0#0, L);
    CheckEquals('C:\a.txt', L[0], 'raiz do drive já termina com barra');
  finally
    L.Free;
  end;
end;

{ TTestBorionShell }

procedure TTestBorionShell.SetUp;
var
  Scope: TBorionScope;
begin
  inherited;
  FPasta := PastaTestes('shell');
  ApagarTudo(FPasta);
  ForceDirectories(FPasta);
  FExecutados := TStringList.Create;
  Scope := TBorionScope.Create('BorionTestes');
  Scope.AllowDir(FPasta);
  FIpc.AddPlugin(TBorionFsPlugin.Create(Scope));  { dono do escopo }
  FShell := TBorionShellPlugin(FIpc.AddPlugin(TBorionShellPlugin.Create(Scope)));
  FShell.OnExecute := Executou;  { nada é aberto de verdade }
end;

procedure TTestBorionShell.TearDown;
begin
  inherited;
  FExecutados.Free;
  ApagarTudo(FPasta);
end;

procedure TTestBorionShell.Executou(const Verb, Target, Params: string);
begin
  FExecutados.Add(Verb + '|' + Target + '|' + Params);
end;

function TTestBorionShell.Recusa(const Alvo: string): string;
var
  IsUrl: Boolean;
begin
  Result := '';
  try
    FShell.CheckTarget(Alvo, IsUrl);
  except
    on E: EBorionError do
      Result := E.Code;
  end;
end;

procedure TTestBorionShell.TestUrlsPermitidas;
var
  IsUrl: Boolean;
begin
  CheckEquals('https://example.com/a?b=1', FShell.CheckTarget('https://example.com/a?b=1', IsUrl));
  Check(IsUrl);
  CheckEquals('', Recusa('HTTP://example.com'));
  CheckEquals('', Recusa('mailto:alguem@example.com'));
end;

procedure TTestBorionShell.TestEsquemasRecusados;
begin
  CheckEquals('FORBIDDEN_URL', Recusa('file:///C:/Windows/System32/calc.exe'));
  CheckEquals('FORBIDDEN_URL', Recusa('javascript:alert(1)'));
  CheckEquals('FORBIDDEN_URL', Recusa('ms-settings:privacy'));
  CheckEquals('FORBIDDEN_URL', Recusa('search-ms:query=x'));
  CheckEquals('FORBIDDEN_URL', Recusa('https:example.com'), 'http(s) exige //');
  CheckEquals('FORBIDDEN_URL', Recusa('https://example.com/'#10'x'));
  CheckEquals('INVALID_ARGS', Recusa('  '));
end;

procedure TTestBorionShell.TestArquivoNoEscopo;
var
  IsUrl: Boolean;
begin
  CheckEquals(FPasta + '\relatorio.pdf', FShell.CheckTarget(FPasta + '/relatorio.pdf', IsUrl));
  CheckFalse(IsUrl);
end;

procedure TTestBorionShell.TestExecutavelRecusado;
begin
  CheckEquals('FORBIDDEN_FILE_TYPE', Recusa(FPasta + '\virus.exe'));
  CheckEquals('FORBIDDEN_FILE_TYPE', Recusa(FPasta + '\script.PS1'));
  CheckEquals('FORBIDDEN_FILE_TYPE', Recusa(FPasta + '\a.js'));
  CheckEquals('FORBIDDEN_FILE_TYPE', Recusa(FPasta + '\atalho.lnk'));
  CheckEquals('FORBIDDEN_FILE_TYPE', Recusa(FPasta + '\truque.exe.'), 'ponto final é ignorado pelo Windows');
  Check(BorionIsExecutableFile('C:\x\setup.MSI'));
  CheckFalse(BorionIsExecutableFile('C:\x\nota.txt'));
end;

procedure TTestBorionShell.TestArquivoForaDoEscopo;
begin
  CheckEquals('FORBIDDEN_PATH', Recusa('C:\Windows\win.ini'));
  CheckEquals('INVALID_PATH', Recusa('relativo.txt'));
  FShell.Scope := nil;
  CheckEquals('FORBIDDEN_PATH', Recusa(FPasta + '\nota.txt'), 'sem escopo, nenhum arquivo');
end;

procedure TTestBorionShell.TestOpenPeloIpc;
var
  Arquivo: string;
  F: TFileStream;
begin
  Ok('shell:open', '{"target":"https://borion.dev/docs"}');
  CheckEquals('open|https://borion.dev/docs|', FExecutados[0]);
  Arquivo := FPasta + '\nota.txt';
  F := TFileStream.Create(Arquivo, fmCreate);
  F.Free;
  Ok('shell:open', '{"target":' + JsonQuote(Arquivo) + '}');
  CheckEquals('open|' + Arquivo + '|', FExecutados[1]);
  CheckEquals('NOT_FOUND', Erro('shell:open', '{"target":' + JsonQuote(FPasta + '\nao.txt') + '}'));
  CheckEquals('FORBIDDEN_URL', Erro('shell:open', '{"target":"file:///C:/x"}'));
  CheckEquals(2, FExecutados.Count, 'recusas não podem executar nada');
end;

procedure TTestBorionShell.TestShowInFolder;
var
  F: TFileStream;
begin
  F := TFileStream.Create(FPasta + '\x.txt', fmCreate);
  F.Free;
  Ok('shell:showInFolder', '{"path":' + JsonQuote(FPasta + '\x.txt') + '}');
  CheckEquals('open|explorer.exe|/select,"' + FPasta + '\x.txt"', FExecutados[0]);
  CheckEquals('FORBIDDEN_PATH', Erro('shell:showInFolder', '{"path":"C:\\Windows\\win.ini"}'));
end;

procedure TTestBorionShell.TestEsquemaPersonalizado;
begin
  CheckEquals('FORBIDDEN_URL', Recusa('meuapp://abrir/7'));
  FShell.AllowedSchemes.Add('meuapp');
  CheckEquals('', Recusa('meuapp://abrir/7'));
  FShell.AllowedSchemes.Clear;
  CheckEquals('FORBIDDEN_URL', Recusa('https://example.com'));
end;

initialization
  RegisterTest('Plugins', TTestPluginInfra.Suite);
  RegisterTest('BorionScope', TTestBorionScope.Suite);
  RegisterTest('BorionFs', TTestBorionFs.Suite);
  RegisterTest('BorionDialog', TTestBorionDialog.Suite);
  RegisterTest('BorionShell', TTestBorionShell.Suite);

end.
