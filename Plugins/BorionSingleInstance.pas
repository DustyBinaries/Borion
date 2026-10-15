unit BorionSingleInstance;

(*
  Borion — Native Application Engine
  Plugin "single-instance": o app roda uma vez só. Abrir de novo traz a janela
  que já está aberta para frente e entrega a ela os argumentos da nova execução
  (por exemplo, o arquivo que o usuário abriu com o app).

  No .dpr, antes de criar o form (assim a segunda execução nem chega a criar
  janela):

    begin
      if BorionIsSecondInstance('Empresa.MeuApp') then
        Exit;  { já havia uma instância: os argumentos foram para ela }
      Application.Initialize;
      ...

  No form:

    Ipc.AddPlugin(TBorionSingleInstancePlugin.Create);

  Evento:
    single-instance:second {args, cwd}   outra execução do app foi aberta
  Comando:
    single-instance:args   -> {args, cwd} desta execução (para tratar a
                              primeira abertura do mesmo jeito)

  args não inclui o caminho do exe. args e cwd são literais JSON só com ASCII
  (Unicode completo; o @borion/api/single-instance decodifica).

  Escopo: por sessão do Windows (dois usuários logados têm uma instância cada).
*)

interface

uses
  Windows, Messages, SysUtils, Classes, Forms, Jsons, BorionIpc;

type
  TBorionArgs = array of WideString;

  TBorionSecondInstanceEvent = procedure(Sender: TObject; const Args: TBorionArgs;
    const Cwd: WideString) of object;

  TBorionSingleInstancePlugin = class(TBorionPlugin)
  private
    FFocus: Boolean;
    FOnSecondInstance: TBorionSecondInstanceEvent;
    procedure CmdArgs(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    { AppId vazio: o do BorionIsSecondInstance chamado no .dpr ou, se ele não foi
      chamado, o Application.Title. Se esta for uma segunda execução, o app
      termina sem mostrar a janela. }
    constructor Create(const AppId: string = '');
    destructor Destroy; override;
    function Name: string; override;
    { Chamado pela janela de mensagens quando chega outra execução }
    procedure SecondInstance(const Args: TBorionArgs; const Cwd: WideString);
    { Trazer a janela para frente quando outra execução abrir (padrão: True) }
    property FocusOnSecondInstance: Boolean read FFocus write FFocus;
    property OnSecondInstance: TBorionSecondInstanceEvent read FOnSecondInstance write FOnSecondInstance;
  end;

{ True se o app já está aberto: os argumentos desta execução foram entregues a
  ele, e esta deve terminar. False: esta é a primeira (e passa a escutar). }
function BorionIsSecondInstance(const AppId: string): Boolean;
{ Argumentos desta execução, sem o exe, com Unicode (CommandLineToArgvW) }
function BorionCommandLineArgs: TBorionArgs;
// {"args":[...],"cwd":...} com cada texto como literal JSON só com ASCII
function BorionArgsJson(const Args: TBorionArgs; const Cwd: WideString): string;
{ Entrega Args e Cwd à instância aberta de AppId; False se não houver nenhuma }
function BorionSingleInstanceSend(const AppId: string; const Args: TBorionArgs;
  const Cwd: WideString; TimeoutMs: Cardinal = 3000): Boolean;

implementation

uses
  BorionJson, BorionApp;

const
  MAGICO = $B0510001;
  HWND_MESSAGE = HWND(-3);
  ASFW_ANY = DWORD(-1);
  WM_BORION_SEGUNDA = WM_USER + 50;

function AllowSetForegroundWindow_(ProcessId: DWORD): BOOL; stdcall;
  external user32 name 'AllowSetForegroundWindow';

type
  TCommandLineToArgvW = function(CmdLine: PWideChar; var Argc: Integer): PPWideChar; stdcall;

  PChegada = ^TChegada;
  TChegada = record
    Args: TBorionArgs;
    Cwd: WideString;
  end;

var
  Mutex: THandle;
  Janela: HWND;
  ClasseRegistrada: string;
  Plugin: TBorionSingleInstancePlugin;
  Pendentes: TList;  { chegadas antes de o plugin existir }

function NomeSeguro(const AppId: string): string;
var
  I: Integer;
begin
  Result := AppId;
  for I := 1 to Length(Result) do
    if not (Result[I] in ['A'..'Z', 'a'..'z', '0'..'9', '.', '_', '-']) then
      Result[I] := '_';
  if Result = '' then
    Result := 'App';
end;

function NomeDaClasse(const AppId: string): string;
begin
  Result := 'Borion.SingleInstance.' + NomeSeguro(AppId);
end;

function BorionCommandLineArgs: TBorionArgs;
var
  F: TCommandLineToArgvW;
  Lista: PPWideChar;
  P: ^PWideChar;
  N, I: Integer;
begin
  Result := nil;
  @F := GetProcAddress(LoadLibrary('shell32.dll'), 'CommandLineToArgvW');
  if not Assigned(F) then
    Exit;
  Lista := F(GetCommandLineW, N);
  if Lista = nil then
    Exit;
  try
    if N > 1 then
    begin
      SetLength(Result, N - 1);
      P := Pointer(Lista);
      Inc(P);  { pula o exe }
      for I := 0 to N - 2 do
      begin
        Result[I] := P^;
        Inc(P);
      end;
    end;
  finally
    LocalFree(HLOCAL(Lista));
  end;
end;

function DiretorioAtual: WideString;
var
  Buf: array[0..MAX_PATH * 2] of WideChar;
begin
  if GetCurrentDirectoryW(Length(Buf), Buf) > 0 then
    Result := Buf
  else
    Result := '';
end;

function BorionArgsJson(const Args: TBorionArgs; const Cwd: WideString): string;
var
  I: Integer;
begin
  Result := '{"args":[';
  for I := 0 to High(Args) do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + JsonQuote(WideToJsonLiteral(Args[I]));
  end;
  Result := Result + '],"cwd":' + JsonQuote(WideToJsonLiteral(Cwd)) + '}';
end;

{ formato do WM_COPYDATA: cwd #0 arg1 #0 arg2 #0 ... (UTF-16) }
function Empacotar(const Args: TBorionArgs; const Cwd: WideString): WideString;
var
  I: Integer;
begin
  Result := Cwd + WideChar(0);
  for I := 0 to High(Args) do
    Result := Result + Args[I] + WideChar(0);
end;

procedure Desempacotar(P: PWideChar; Bytes: Integer; var C: TChegada);
var
  Tudo: WideString;
  I, Inicio: Integer;
  Primeiro: Boolean;
begin
  SetString(Tudo, P, Bytes div SizeOf(WideChar));
  C.Args := nil;
  C.Cwd := '';
  Primeiro := True;
  Inicio := 1;
  for I := 1 to Length(Tudo) do
    if Tudo[I] = #0 then
    begin
      if Primeiro then
        C.Cwd := Copy(Tudo, Inicio, I - Inicio)
      else
      begin
        SetLength(C.Args, Length(C.Args) + 1);
        C.Args[High(C.Args)] := Copy(Tudo, Inicio, I - Inicio);
      end;
      Primeiro := False;
      Inicio := I + 1;
    end;
end;

procedure Entregar(C: PChegada);
begin
  if Plugin <> nil then
  begin
    try
      Plugin.SecondInstance(C.Args, C.Cwd);
    finally
      Dispose(C);
    end;
  end
  else
    Pendentes.Add(C);
end;

function ProcJanela(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  Dados: PCopyDataStruct;
  C: PChegada;
begin
  if Msg = WM_COPYDATA then
  begin
    Dados := PCopyDataStruct(LParam);
    if (Dados <> nil) and (Dados.dwData = MAGICO) then
    begin
      New(C);
      Desempacotar(Dados.lpData, Dados.cbData, C^);
      { responde já: quem enviou está esperando; o resto roda depois }
      PostMessage(Wnd, WM_BORION_SEGUNDA, 0, Windows.LPARAM(C));
      Result := 1;
      Exit;
    end;
  end
  else if Msg = WM_BORION_SEGUNDA then
  begin
    Entregar(PChegada(LParam));
    Result := 0;
    Exit;
  end;
  Result := DefWindowProc(Wnd, Msg, WParam, LParam);
end;

procedure CriarJanela(const AppId: string);
var
  Classe: TWndClass;
begin
  ClasseRegistrada := NomeDaClasse(AppId);
  FillChar(Classe, SizeOf(Classe), 0);
  Classe.lpfnWndProc := @ProcJanela;
  Classe.hInstance := HInstance;
  Classe.lpszClassName := PChar(ClasseRegistrada);
  Windows.RegisterClass(Classe);
  { janela só de mensagens: invisível, fora do Alt+Tab }
  Janela := CreateWindowEx(0, PChar(ClasseRegistrada), PChar(ClasseRegistrada), 0, 0, 0, 0, 0,
    HWND_MESSAGE, 0, HInstance, nil);
end;

function BorionSingleInstanceSend(const AppId: string; const Args: TBorionArgs;
  const Cwd: WideString; TimeoutMs: Cardinal): Boolean;
var
  Destino: HWND;
  Dados: TCopyDataStruct;
  Pacote: WideString;
  Resposta: DWORD;
  Inicio: Cardinal;
begin
  { a primeira instância pode estar abrindo ainda: espera a janela aparecer }
  Inicio := GetTickCount;
  repeat
    Destino := FindWindowEx(HWND_MESSAGE, 0, PChar(NomeDaClasse(AppId)), nil);
    if Destino <> 0 then
      Break;
    Sleep(50);
  until GetTickCount - Inicio > TimeoutMs;
  Result := Destino <> 0;
  if not Result then
    Exit;
  Pacote := Empacotar(Args, Cwd);
  Dados.dwData := MAGICO;
  Dados.cbData := Length(Pacote) * SizeOf(WideChar);
  Dados.lpData := PWideChar(Pacote);
  { deixa a outra instância vir para frente (o Windows só permite a quem tem o foco) }
  AllowSetForegroundWindow_(ASFW_ANY);
  Result := SendMessageTimeout(Destino, WM_COPYDATA, 0, LPARAM(@Dados),
    SMTO_ABORTIFHUNG, TimeoutMs, Resposta) <> 0;
end;

function BorionIsSecondInstance(const AppId: string): Boolean;
begin
  if Mutex <> 0 then
  begin
    Result := False;  { já chamado nesta execução }
    Exit;
  end;
  Mutex := CreateMutex(nil, False, PChar('Local\' + NomeDaClasse(AppId)));
  if (Mutex <> 0) and (GetLastError = ERROR_ALREADY_EXISTS) then
  begin
    BorionSingleInstanceSend(AppId, BorionCommandLineArgs, DiretorioAtual);
    Result := True;  { mesmo sem conseguir entregar: há outra instância }
    Exit;
  end;
  CriarJanela(AppId);
  Result := False;
end;

{ TBorionSingleInstancePlugin }

constructor TBorionSingleInstancePlugin.Create(const AppId: string);
var
  Id: string;
begin
  inherited Create;
  FFocus := True;
  if Mutex = 0 then
  begin
    { o .dpr não chamou BorionIsSecondInstance: faz aqui (a janela já foi criada,
      mas ainda não apareceu) }
    Id := AppId;
    if Id = '' then
      Id := Application.Title;
    if BorionIsSecondInstance(Id) then
    begin
      Application.ShowMainForm := False;
      Application.Terminate;
    end;
  end;
  Plugin := Self;
end;

destructor TBorionSingleInstancePlugin.Destroy;
begin
  if Plugin = Self then
    Plugin := nil;
  inherited;
end;

function TBorionSingleInstancePlugin.Name: string;
begin
  Result := 'single-instance';
end;

procedure TBorionSingleInstancePlugin.Install;
var
  I: Integer;
begin
  Command('args', CmdArgs);
  { o que chegou antes de o plugin existir }
  if Pendentes.Count > 0 then
  begin
    for I := 0 to Pendentes.Count - 1 do
      PostMessage(Janela, WM_BORION_SEGUNDA, 0, LPARAM(Pendentes[I]));
    Pendentes.Clear;
  end;
end;

procedure TBorionSingleInstancePlugin.SecondInstance(const Args: TBorionArgs; const Cwd: WideString);
begin
  if FFocus then
    BorionShowMainWindow(Ipc);
  if Ipc <> nil then
    Ipc.EmitJson('single-instance:second', BorionArgsJson(Args, Cwd));
  if Assigned(FOnSecondInstance) then
    FOnSecondInstance(Self, Args, Cwd);
end;

procedure TBorionSingleInstancePlugin.CmdArgs(Call: TBorionCall);
var
  O: TJsonObject;
begin
  O := TJsonObject.Create;
  try
    O.Parse(BorionArgsJson(BorionCommandLineArgs, DiretorioAtual));  { só ASCII: o Parse não perde nada }
    Call.Result.AsObject := O;
  finally
    O.Free;
  end;
end;

initialization
  Pendentes := TList.Create;

finalization
  while Pendentes.Count > 0 do
  begin
    Dispose(PChegada(Pendentes[0]));
    Pendentes.Delete(0);
  end;
  Pendentes.Free;
  if Janela <> 0 then
    DestroyWindow(Janela);
  if Mutex <> 0 then
    CloseHandle(Mutex);

end.
