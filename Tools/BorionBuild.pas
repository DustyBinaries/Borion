unit BorionBuild;

(*
  Borion — Native Application Engine
  borion build / borion dev: as etapas, sobre um TBorionProject.

  build: frontend (npm run build, ou a cópia do @borion/api para web\) ->
         pacote de assets (o .res do .dpr) -> .rc com brcc32 (se mudou) ->
         dcc32 -> WebView2Loader.dll ao lado do exe.
  dev:   o mesmo Delphi, mas o frontend vem do servidor do Vite (--dev-url) ou
         direto da pasta web\ (--dev-dir, com recarga automática). Se um .pas,
         .dpr ou .rc mudar, fecha o app, recompila e abre de novo. Fechar o app
         encerra o dev (e o Vite).

  Os processos filhos (npm, Vite, o app) ficam num Job Object do Windows: se a
  CLI terminar (Ctrl+C, fechar o console), eles terminam junto.
*)

interface

uses
  Windows, SysUtils, Classes, BorionProject;

type
  TBorionOutput = procedure(const Line: string);

  TBorionDevOptions = record
    Port: Integer;      { 0 = a do projeto (vite.config.js) }
    Watch: Boolean;     { recompilar e reabrir quando o Delphi mudar }
  end;

var
  { Saída das etapas (a CLI troca pela que converte para o console) }
  BorionOut: TBorionOutput;

{ Compila o projeto inteiro. Levanta EBorionProject se uma etapa falhar. }
procedure BorionBuildProject(P: TBorionProject; const BorionHome: string);
{ Modo dev; volta quando o app é fechado. }
procedure BorionDevProject(P: TBorionProject; const BorionHome: string; const Options: TBorionDevOptions);
{ Só a parte Delphi (brcc32 + dcc32 + loader) }
procedure BorionCompileDelphi(P: TBorionProject; const BorionHome: string);
{ Empacota a pasta no .res de assets do projeto }
procedure BorionPackAssets(const Pasta, Saida: string);
{ Copia os módulos do @borion/api (BorionHome\js\*.js) para web\borion-api\ }
procedure BorionCopyApi(P: TBorionProject; const BorionHome: string);

implementation

uses
  WinInet, BorionPack;

{ --- Job Object: os filhos morrem com a CLI ------------------------------------ }

type
  TJobBasicLimit = packed record
    PerProcessUserTimeLimit: Int64;
    PerJobUserTimeLimit: Int64;
    LimitFlags: DWORD;
    MinimumWorkingSetSize: DWORD;
    MaximumWorkingSetSize: DWORD;
    ActiveProcessLimit: DWORD;
    Affinity: DWORD;
    PriorityClass: DWORD;
    SchedulingClass: DWORD;
    Pad: DWORD;  { a struct do Windows termina alinhada em 8 }
  end;

  TJobExtendedLimit = packed record
    Basic: TJobBasicLimit;
    IoInfo: array[0..5] of Int64;
    ProcessMemoryLimit: DWORD;
    JobMemoryLimit: DWORD;
    PeakProcessMemoryUsed: DWORD;
    PeakJobMemoryUsed: DWORD;
  end;

const
  JobObjectExtendedLimitInformation = 9;
  JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = $2000;

function CreateJobObjectA_(Attrs: Pointer; Name: PChar): THandle; stdcall;
  external kernel32 name 'CreateJobObjectA';
function SetInformationJobObject_(Job: THandle; InfoClass: Integer; Info: Pointer;
  Size: DWORD): BOOL; stdcall; external kernel32 name 'SetInformationJobObject';
function AssignProcessToJobObject_(Job, Process: THandle): BOOL; stdcall;
  external kernel32 name 'AssignProcessToJobObject';

function CriarJob: THandle;
var
  L: TJobExtendedLimit;
begin
  Result := CreateJobObjectA_(nil, nil);
  if Result = 0 then
    Exit;
  FillChar(L, SizeOf(L), 0);
  L.Basic.LimitFlags := JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  SetInformationJobObject_(Result, JobObjectExtendedLimitInformation, @L, SizeOf(L));
end;

procedure Out(const S: string);
begin
  if Assigned(BorionOut) then
    BorionOut(S);
end;

procedure Etapa(const S: string);
begin
  Out('=== ' + S);
end;

{ Inicia CmdLine em Dir, no console da CLI. Job <> 0: entra no job. }
function Iniciar(const CmdLine, Dir: string; Job: THandle): TProcessInformation;
var
  SI: TStartupInfo;
  C: string;
begin
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  C := CmdLine;
  UniqueString(C);
  if not CreateProcess(nil, PChar(C), nil, nil, True, CREATE_SUSPENDED, nil, PChar(Dir), SI, Result) then
    raise EBorionProject.CreateFmt('não foi possível executar %s: %s', [CmdLine, SysErrorMessage(GetLastError)]);
  if Job <> 0 then
    AssignProcessToJobObject_(Job, Result.hProcess);  { falha num job aninhado (Windows 7): segue sem }
  ResumeThread(Result.hThread);
  CloseHandle(Result.hThread);
end;

{ Executa e espera; devolve o código de saída }
function Executar(const CmdLine, Dir: string; Job: THandle = 0): DWORD;
var
  PI: TProcessInformation;
begin
  PI := Iniciar(CmdLine, Dir, Job);
  try
    WaitForSingleObject(PI.hProcess, INFINITE);
    GetExitCodeProcess(PI.hProcess, Result);
  finally
    CloseHandle(PI.hProcess);
  end;
end;

procedure ExecutarOuFalhar(const CmdLine, Dir, Etapa: string; Job: THandle = 0);
begin
  if Executar(CmdLine, Dir, Job) <> 0 then
    raise EBorionProject.Create(Etapa + ' falhou');
end;

function Aspas(const S: string): string;
begin
  Result := '"' + S + '"';
end;

{ --- etapas -------------------------------------------------------------------- }

procedure BorionPackAssets(const Pasta, Saida: string);
var
  Op: TBorionPackOptions;
  M: TMemoryStream;
  N: Integer;
begin
  Op.Compress := True;
  M := TMemoryStream.Create;
  try
    N := BorionPackFolder(Pasta, M, Op);
    BorionWriteRes(Saida, BORION_PACK_RESOURCE, M);
    Out(Format('%d arquivo(s) de %s -> %s (%d KB)', [N, ExtractFileName(Pasta), ExtractFileName(Saida),
      (M.Size + 1023) div 1024]));
  finally
    M.Free;
  end;
end;

procedure BorionCopyApi(P: TBorionProject; const BorionHome: string);
var
  R: TSearchRec;
  Destino: string;
begin
  Destino := P.FrontendDir + '\borion-api';
  ForceDirectories(Destino);
  if FindFirst(BorionHome + '\js\*.js', faAnyFile, R) = 0 then
  begin
    repeat
      if not CopyFile(PChar(BorionHome + '\js\' + R.Name), PChar(Destino + '\' + R.Name), False) then
        raise EBorionProject.CreateFmt('não foi possível copiar %s', [R.Name]);
    until FindNext(R) <> 0;
    FindClose(R);
  end
  else
    raise EBorionProject.CreateFmt('@borion/api não encontrado em %s\js', [BorionHome]);
end;

procedure NpmInstall(P: TBorionProject; Job: THandle);
begin
  if not DirectoryExists(P.FrontendDir + '\node_modules') then
  begin
    Etapa('npm install');
    ExecutarOuFalhar('cmd.exe /c npm install', P.FrontendDir, 'npm install (o Node.js está instalado?)', Job);
  end;
end;

procedure CopiarLoader(P: TBorionProject; const BorionHome: string);
var
  Origem: string;
begin
  if FileExists(P.Dir + '\WebView2Loader.dll') then
    Exit;
  Origem := P.FindInSearchPath('WebView2Loader.dll');
  if Origem = '' then
    Origem := ExpandFileName(BorionHome + '\..\WebView2');
  if not CopyFile(PChar(Origem + '\WebView2Loader.dll'), PChar(P.Dir + '\WebView2Loader.dll'), False) then
    Out('aviso: WebView2Loader.dll não encontrado (ponha a pasta do WebView2 no search path do .dof)');
end;

procedure BorionCompileDelphi(P: TBorionProject; const BorionHome: string);
var
  Delphi, Caminhos: string;
begin
  Delphi := BorionFindDelphi;
  if FileExists(P.RcFile) and BorionIsStale(P.ResFile, P.RcFile) then
  begin
    Etapa('Recursos (' + ExtractFileName(P.RcFile) + ')');
    ExecutarOuFalhar(Aspas(Delphi + '\Bin\brcc32.exe') + ' -fo' + Aspas(P.ResFile) + ' ' + Aspas(P.RcFile),
      P.Dir, 'brcc32');
  end;
  Etapa('Delphi (' + ExtractFileName(P.DprFile) + ')');
  Caminhos := P.SearchPathText;
  ExecutarOuFalhar(Aspas(Delphi + '\Bin\dcc32.exe') + ' -B -Q ' + Aspas('-U' + Caminhos) + ' ' +
    Aspas('-I' + Caminhos) + ' ' + Aspas('-R' + Caminhos) + ' ' + Aspas(ExtractFileName(P.DprFile)),
    P.Dir, 'dcc32');
  CopiarLoader(P, BorionHome);
end;

procedure BorionBuildProject(P: TBorionProject; const BorionHome: string);
var
  Inicio: Cardinal;
  Job: THandle;
begin
  Inicio := GetTickCount;
  Job := CriarJob;
  try
    case P.Kind of
      fkNpm:
        begin
          NpmInstall(P, Job);
          Etapa('Frontend (npm run build)');
          ExecutarOuFalhar('cmd.exe /c npm run build', P.FrontendDir, 'npm run build', Job);
        end;
      fkStatic:
        if P.UsesBorionApi then
        begin
          Etapa('Frontend (@borion/api para web\borion-api)');
          BorionCopyApi(P, BorionHome);
        end;
    end;
    if P.Kind <> fkNone then
    begin
      if P.AssetsRes = '' then
        Out('aviso: o .dpr não inclui um {$R ....res} de assets; a interface não vai dentro do exe')
      else
      begin
        Etapa('Assets (borion pack)');
        if not DirectoryExists(P.DistDir) then
          raise EBorionProject.CreateFmt('pasta %s não encontrada', [P.DistDir]);
        BorionPackAssets(P.DistDir, P.Dir + '\' + P.AssetsRes);
      end;
    end;
    BorionCompileDelphi(P, BorionHome);
  finally
    if Job <> 0 then
      CloseHandle(Job);
  end;
  Out(Format('OK: %s (%.1f s)', [ExtractFileName(P.ExeFile), (GetTickCount - Inicio) / 1000]));
end;

{ --- dev ----------------------------------------------------------------------- }

function Respondendo(const Url: string): Boolean;
var
  Net, Req: HINTERNET;
  T: DWORD;
begin
  Result := False;
  Net := InternetOpen('borion dev', INTERNET_OPEN_TYPE_DIRECT, nil, nil, 0);
  if Net = nil then
    Exit;
  try
    T := 1000;
    InternetSetOption(Net, INTERNET_OPTION_CONNECT_TIMEOUT, @T, SizeOf(T));
    Req := InternetOpenUrl(Net, PChar(Url), nil, 0, INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE, 0);
    Result := Req <> nil;
    if Req <> nil then
      InternetCloseHandle(Req);
  finally
    InternetCloseHandle(Net);
  end;
end;

{ data do Delphi mais recente (o que, mudando, pede recompilar) }
function FontesDelphi(P: TBorionProject): TDateTime;
begin
  Result := BorionNewestFile(P.Dir, '*.dpr;*.pas;*.rc;*.inc');
end;

{ o .res de assets precisa existir para compilar; no dev ele não é usado }
procedure GarantirAssets(P: TBorionProject);
var
  Temp: string;
  F: TStringList;
begin
  if (P.AssetsRes = '') or FileExists(P.Dir + '\' + P.AssetsRes) then
    Exit;
  if P.Kind = fkStatic then
  begin
    BorionPackAssets(P.DistDir, P.Dir + '\' + P.AssetsRes);
    Exit;
  end;
  { npm sem build ainda: um pacote provisório (o "borion build" gera o de verdade) }
  Temp := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) + 'borion-dev-' + IntToStr(GetCurrentProcessId);
  ForceDirectories(Temp);
  F := TStringList.Create;
  try
    F.Text := '<!doctype html><meta charset="utf-8"><p>Interface não empacotada: rode <code>borion build</code>.</p>';
    F.SaveToFile(Temp + '\index.html');
    BorionPackAssets(Temp, P.Dir + '\' + P.AssetsRes);
  finally
    F.Free;
    DeleteFile(Temp + '\index.html');
    RemoveDir(Temp);
  end;
end;

procedure BorionDevProject(P: TBorionProject; const BorionHome: string; const Options: TBorionDevOptions);
var
  Job: THandle;
  Vite, App: TProcessInformation;
  Porta: Integer;
  Url, ArgDev: string;
  Inicio: Cardinal;
  Base, Agora: TDateTime;
  AppAberto: Boolean;

  procedure Compilar;
  begin
    GarantirAssets(P);
    BorionCompileDelphi(P, BorionHome);
  end;

  procedure AbrirApp;
  begin
    App := Iniciar(Aspas(P.ExeFile) + ArgDev, P.Dir, Job);
    AppAberto := True;
  end;

begin
  Porta := Options.Port;
  if Porta = 0 then
    Porta := P.DevPort;
  Job := CriarJob;
  FillChar(Vite, SizeOf(Vite), 0);
  AppAberto := False;
  try
    { frontend }
    case P.Kind of
      fkNpm:
        begin
          NpmInstall(P, Job);
          Url := Format('http://localhost:%d', [Porta]);
          Etapa('Vite em ' + Url);
          Vite := Iniciar(Format('cmd.exe /c npm run dev -- --port %d --strictPort', [Porta]), P.FrontendDir, Job);
          ArgDev := ' --dev-url=' + Url;
        end;
      fkStatic:
        begin
          if P.UsesBorionApi then
            BorionCopyApi(P, BorionHome);
          ArgDev := ' ' + Aspas('--dev-dir=' + P.FrontendDir);
        end;
    else
      ArgDev := '';
    end;

    { Delphi: só se mudou desde o último build }
    if not FileExists(P.ExeFile) or (FontesDelphi(P) > FileDateToDateTime(FileAge(P.ExeFile))) or
      ((P.AssetsRes <> '') and not FileExists(P.Dir + '\' + P.AssetsRes)) then
      Compilar
    else
      CopiarLoader(P, BorionHome);

    if P.Kind = fkNpm then
    begin
      Inicio := GetTickCount;
      while not Respondendo(Url + '/') do
      begin
        if WaitForSingleObject(Vite.hProcess, 0) = WAIT_OBJECT_0 then
          raise EBorionProject.Create('o Vite terminou sem subir (a porta está em uso? veja a saída acima)');
        if GetTickCount - Inicio > 60000 then
          raise EBorionProject.Create('o Vite não respondeu em ' + Url);
        Sleep(300);
      end;
    end;

    Etapa('App em modo dev');
    if P.Kind = fkStatic then
      Out('edite os arquivos de web\: a página recarrega sozinha');
    if Options.Watch then
      Out('mudou um .pas/.dpr? o app é recompilado e reaberto; feche o app para encerrar')
    else
      Out('feche o app para encerrar');
    AbrirApp;
    Base := FontesDelphi(P);
    repeat
      if AppAberto and (WaitForSingleObject(App.hProcess, 500) = WAIT_OBJECT_0) then
      begin
        CloseHandle(App.hProcess);
        AppAberto := False;
        Break;  { fechado pelo usuário: fim do dev }
      end;
      if not AppAberto then
        Sleep(500);
      if (P.Kind = fkNpm) and (WaitForSingleObject(Vite.hProcess, 0) = WAIT_OBJECT_0) then
        raise EBorionProject.Create('o Vite parou');
      if not Options.Watch then
        Continue;
      Agora := FontesDelphi(P);
      if Agora > Base then
      begin
        Sleep(300);  { o editor pode estar gravando vários arquivos }
        Base := FontesDelphi(P);
        Out('');
        Etapa('O Delphi mudou: recompilando');
        if AppAberto then
        begin
          TerminateProcess(App.hProcess, 0);
          WaitForSingleObject(App.hProcess, 5000);
          CloseHandle(App.hProcess);
          AppAberto := False;
        end;
        try
          BorionCompileDelphi(P, BorionHome);
          AbrirApp;
        except
          on E: Exception do
            Out('erro: ' + E.Message + ' (corrija e salve: o dev tenta de novo)');
        end;
      end;
    until False;
  finally
    if AppAberto then
    begin
      TerminateProcess(App.hProcess, 0);
      CloseHandle(App.hProcess);
    end;
    if Vite.hProcess <> 0 then
      CloseHandle(Vite.hProcess);
    if Job <> 0 then
      CloseHandle(Job);  { KILL_ON_JOB_CLOSE: o Vite (e o npm) terminam aqui }
  end;
  Out('dev encerrado');
end;

end.
