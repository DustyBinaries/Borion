unit TestBorionTools;

{ Testes dos plugins global-shortcut e log. Os atalhos usam teclas que ninguém
  usa (F13-F24) e o WM_HOTKEY é simulado; o log grava em Tests\out\log. }

interface

uses
  Windows, Messages, SysUtils, Classes, TestFramework, Jsons,
  BorionJson, BorionIpc, BorionGlobalShortcut, BorionLog, TestBorionPlugins;

type
  TTestBorionGlobalShortcut = class(TTesteComIpc)
  private
    FAtalhos: TBorionGlobalShortcutPlugin;
    procedure Normaliza(const Entrada, Esperado: string);
    procedure Recusa(const Entrada: string);
  protected
    procedure SetUp; override;
  published
    procedure TestNormalizacao;
    procedure TestAtalhosInvalidos;
    procedure TestRegistraEDesregistra;
    procedure TestRepetidoNoMesmoApp;
    procedure TestEmUsoPorOutroPrograma;
    procedure TestPressionadoEmiteEvento;
  end;

  TTestBorionLog = class(TTesteComIpc)
  private
    FLog: TBorionLogPlugin;
    FDir: string;
    function Conteudo(const Nome: string = 'BorionTests.log'): string;
    function Linhas(const Nome: string = 'BorionTests.log'): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEscreveDoJsEDoDelphi;
    procedure TestNivelMinimo;
    procedure TestArgsInvalidos;
    procedure TestRotacao;
    procedure TestAttachEmiteEventos;
    procedure TestVariasThreads;
    procedure TestNomeDoArquivo;
  end;

implementation

{ TTestBorionGlobalShortcut }

procedure TTestBorionGlobalShortcut.SetUp;
begin
  inherited;
  FAtalhos := TBorionGlobalShortcutPlugin(FIpc.AddPlugin(TBorionGlobalShortcutPlugin.Create));
end;

procedure TTestBorionGlobalShortcut.Normaliza(const Entrada, Esperado: string);
var
  M, K: Cardinal;
  N: string;
begin
  BorionParseShortcut(Entrada, M, K, N);
  CheckEquals(Esperado, N, Entrada);
end;

procedure TTestBorionGlobalShortcut.Recusa(const Entrada: string);
var
  M, K: Cardinal;
  N: string;
begin
  try
    BorionParseShortcut(Entrada, M, K, N);
    Fail('devia recusar: ' + Entrada);
  except
    on E: EBorionError do
      CheckEquals('INVALID_SHORTCUT', E.Code, Entrada);
  end;
end;

procedure TTestBorionGlobalShortcut.TestNormalizacao;
var
  M, K: Cardinal;
  N: string;
begin
  Normaliza('ctrl+shift+k', 'Ctrl+Shift+K');
  Normaliza('Shift+CommandOrControl+K', 'Ctrl+Shift+K');
  Normaliza('CmdOrCtrl+Alt+Super+1', 'Ctrl+Alt+Win+1');
  Normaliza(' Control + Option + F5 ', 'Ctrl+Alt+F5');
  Normaliza('F13', 'F13');
  Normaliza('Ctrl+Return', 'Ctrl+Enter');
  Normaliza('alt+arrowup', 'Alt+Up');
  Normaliza('Win+Num5', 'Win+Num5');
  Normaliza('MediaPlayPause', 'MediaPlayPause');
  Normaliza('Ctrl+Plus', 'Ctrl+Plus');
  BorionParseShortcut('Ctrl+Shift+F24', M, K, N);
  CheckEquals(VK_F24, K);
  CheckEquals($0002 or $0004, M);
end;

procedure TTestBorionGlobalShortcut.TestAtalhosInvalidos;
begin
  Recusa('');
  Recusa('A');           { letra sozinha capturaria a digitação }
  Recusa('Enter');
  Recusa('Ctrl+');
  Recusa('Ctrl++');
  Recusa('Ctrl+Ctrl+A');
  Recusa('Hyper+A');
  Recusa('Ctrl+Banana');
  Recusa('Ctrl+F25');
  Recusa('Ctrl+A+B');    { 'A' não é modificador }
end;

procedure TTestBorionGlobalShortcut.TestRegistraEDesregistra;
begin
  CheckEquals('"Ctrl+Alt+Shift+F24"', Ok('global-shortcut:register', '{"shortcut":"shift+alt+ctrl+f24"}'));
  CheckEquals('true', Ok('global-shortcut:isRegistered', '{"shortcut":"Ctrl+Shift+Alt+F24"}'));
  Ok('global-shortcut:unregister', '{"shortcut":"Ctrl+Alt+Shift+F24"}');
  CheckEquals('false', Ok('global-shortcut:isRegistered', '{"shortcut":"Ctrl+Alt+Shift+F24"}'));
  { liberado de verdade: dá para registrar de novo }
  Ok('global-shortcut:register', '{"shortcut":"Ctrl+Alt+Shift+F24"}');
  Ok('global-shortcut:register', '{"shortcut":"Ctrl+Alt+Shift+F23"}');
  Ok('global-shortcut:unregisterAll', '');
  CheckEquals('false', Ok('global-shortcut:isRegistered', '{"shortcut":"Ctrl+Alt+Shift+F23"}'));
  CheckEquals('INVALID_SHORTCUT', Erro('global-shortcut:register', '{"shortcut":"Q"}'));
end;

procedure TTestBorionGlobalShortcut.TestRepetidoNoMesmoApp;
begin
  Ok('global-shortcut:register', '{"shortcut":"Ctrl+Alt+Shift+F22"}');
  { página recarregada registrando de novo: não é erro }
  CheckEquals('"Ctrl+Alt+Shift+F22"', Ok('global-shortcut:register', '{"shortcut":"Shift+Ctrl+Alt+F22"}'));
  CheckEquals('"Ctrl+Alt+Shift+F22"', Ok('global-shortcut:unregister', '{"shortcut":"alt+shift+ctrl+F22"}'));
  CheckEquals('false', Ok('global-shortcut:isRegistered', '{"shortcut":"Ctrl+Alt+Shift+F22"}'), 'um unregister basta');
end;

procedure TTestBorionGlobalShortcut.TestEmUsoPorOutroPrograma;
var
  Outra: HWND;
begin
  { "outro programa": outra janela registrando a mesma combinação antes }
  Outra := Classes.AllocateHWnd(nil);
  try
    Check(RegisterHotKey(Outra, 1, MOD_CONTROL or MOD_ALT or MOD_SHIFT, VK_F21));
    CheckEquals('ALREADY_REGISTERED', Erro('global-shortcut:register', '{"shortcut":"Ctrl+Alt+Shift+F21"}'));
    UnregisterHotKey(Outra, 1);
  finally
    Classes.DeallocateHWnd(Outra);
  end;
  Ok('global-shortcut:register', '{"shortcut":"Ctrl+Alt+Shift+F21"}');
end;

procedure TTestBorionGlobalShortcut.TestPressionadoEmiteEvento;
var
  Antes: Integer;
begin
  Ok('global-shortcut:register', '{"shortcut":"Ctrl+Alt+Shift+F20"}');
  Ok('global-shortcut:register', '{"shortcut":"Win+F19"}');
  FPosts.Clear;
  { o que o Windows manda quando a combinação é pressionada }
  PostMessage(FAtalhos.Window, WM_HOTKEY, 2, 0);
  Antes := FPosts.Count;
  Bombear(Antes + 1);
  CheckEquals('{"__borion":1,"kind":"event","event":"global-shortcut:pressed","payload":' +
    '{"shortcut":"Win+F19","state":"pressed"}}', FPosts[FPosts.Count - 1]);
end;

{ TTestBorionLog }

procedure TTestBorionLog.SetUp;
var
  R: TSearchRec;
begin
  inherited;
  FDir := ExtractFilePath(ParamStr(0)) + 'out\log';
  ForceDirectories(FDir);
  if FindFirst(FDir + '\*', faAnyFile, R) = 0 then
  begin
    repeat
      if (R.Attr and faDirectory) = 0 then
        DeleteFile(FDir + '\' + R.Name);
    until FindNext(R) <> 0;
    FindClose(R);
  end;
  FLog := TBorionLogPlugin(FIpc.AddPlugin(TBorionLogPlugin.Create('BorionTests')));
  FLog.Dir := FDir;
end;

procedure TTestBorionLog.TearDown;
begin
  inherited;
end;

function TTestBorionLog.Conteudo(const Nome: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(FDir + '\' + Nome, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

function TTestBorionLog.Linhas(const Nome: string): Integer;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Text := Conteudo(Nome);
    Result := L.Count;
  finally
    L.Free;
  end;
end;

procedure TTestBorionLog.TestEscreveDoJsEDoDelphi;
var
  S: string;
begin
  Ok('log:write', '{"level":"info","message":"\"ol\\u00e1 \\ud83d\\ude00\""}');
  Ok('log:write', '{"level":"error","message":"\"falhou\"","target":"editor"}');
  FLog.Warn(WideString('do Delphi: ') + WideChar($E9));
  S := Conteudo;
  Check(Pos('[INFO ] [js] ol'#$C3#$A1' '#$F0#$9F#$98#$80#13#10, S) > 0, 'UTF-8 com emoji: ' + S);
  Check(Pos('[ERROR] [editor] falhou'#13#10, S) > 0, S);
  Check(Pos('[WARN ] [delphi] do Delphi: '#$C3#$A9#13#10, S) > 0, S);
  CheckEquals(3, Linhas);
  Check(Copy(S, 5, 1) = '-', 'começa com a data: ' + Copy(S, 1, 30));
end;

procedure TTestBorionLog.TestNivelMinimo;
begin
  Ok('log:write', '{"level":"debug","message":"\"some\""}');
  Ok('log:write', '{"level":"trace","message":"\"some\""}');
  Check(not FileExists(FDir + '\BorionTests.log') or (Linhas = 0), 'debug e trace ignorados por padrão');
  FLog.MinLevel := llTrace;
  Ok('log:write', '{"level":"TRACE","message":"\"agora vai\""}');
  CheckEquals(1, Linhas);
end;

procedure TTestBorionLog.TestArgsInvalidos;
begin
  CheckEquals('INVALID_ARGS', Erro('log:write', '{"level":"fatal","message":"\"x\""}'));
  CheckEquals('INVALID_ARGS', Erro('log:write', '{"level":"info","message":"sem aspas"}'));
  CheckEquals('INVALID_ARGS', Erro('log:write', '{"level":"info"}'));
  { quebra de linha no target não cria uma linha falsa }
  Ok('log:write', '{"level":"info","message":"\"x\"","target":"a\r\n2026-01-01 [ERROR] falso"}');
  CheckEquals(1, Linhas);
end;

procedure TTestBorionLog.TestRotacao;
var
  I: Integer;
begin
  FLog.MaxFileSize := 300;
  FLog.KeepFiles := 2;
  for I := 1 to 40 do
    FLog.Info(Format('linha %.2d com algum texto para encher', [I]));
  Check(FileExists(FDir + '\BorionTests.log.1'), '.1');
  Check(FileExists(FDir + '\BorionTests.log.2'), '.2');
  Check(not FileExists(FDir + '\BorionTests.log.3'), 'só KeepFiles arquivos antigos');
  Check(Length(Conteudo) <= 300, 'o atual não passa do limite');
  Check(Pos('linha 40', Conteudo) > 0, 'a última linha está no atual');
end;

procedure TTestBorionLog.TestAttachEmiteEventos;
begin
  FPosts.Clear;
  FLog.Info('antes');
  CheckEquals(0, FPosts.Count, 'sem attach, nada vai para a página');
  Ok('log:attach', '');
  FPosts.Clear;
  FLog.Error(WideString('depois ') + WideChar($E9));
  CheckEquals(1, FPosts.Count);
  Check(Pos('"event":"log:entry","payload":{"level":"error","message":"\"depois \\u00e9\"","target":"delphi","time":"',
    FPosts[0]) > 0, FPosts[0]);
  Ok('log:detach', '');
  FPosts.Clear;
  FLog.Info('de novo sem');
  CheckEquals(0, FPosts.Count);
end;

type
  TEscritora = class(TThread)
  private
    FLog: TBorionLogPlugin;
    FN: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(Log: TBorionLogPlugin; N: Integer);
  end;

constructor TEscritora.Create(Log: TBorionLogPlugin; N: Integer);
begin
  FLog := Log;
  FN := N;
  inherited Create(False);
end;

procedure TEscritora.Execute;
var
  I: Integer;
begin
  for I := 1 to 50 do
    FLog.Info(Format('thread %d linha %d', [FN, I]));
end;

procedure TTestBorionLog.TestVariasThreads;
var
  T: array[1..4] of TEscritora;
  I: Integer;
  L: TStringList;
begin
  for I := 1 to 4 do
    T[I] := TEscritora.Create(FLog, I);
  for I := 1 to 4 do
  begin
    T[I].WaitFor;
    T[I].Free;
  end;
  L := TStringList.Create;
  try
    L.Text := Conteudo;
    CheckEquals(200, L.Count);
    for I := 0 to L.Count - 1 do
      Check(Pos('[INFO ] [delphi] thread ', L[I]) = 25, 'linha inteira, sem mistura: ' + L[I]);
  finally
    L.Free;
  end;
end;

procedure TTestBorionLog.TestNomeDoArquivo;
var
  P: TBorionLogPlugin;
begin
  CheckEquals(JsonQuote(WideToJsonLiteral(FDir + '\BorionTests.log')), Ok('log:path', ''));
  P := TBorionLogPlugin.Create('Borion: menu?');
  try
    Check(Pos('\Borion_ menu_\logs\Borion_ menu_.log', string(P.FileName)) > 0, string(P.FileName));
  finally
    P.Free;
  end;
end;

initialization
  RegisterTest('Plugins', TTestBorionGlobalShortcut.Suite);
  RegisterTest('Plugins', TTestBorionLog.Suite);

end.
