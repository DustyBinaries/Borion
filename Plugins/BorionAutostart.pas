unit BorionAutostart;

(*
  Borion — Native Application Engine
  Plugin "autostart": iniciar o app junto com o Windows (como o autostart do Tauri).

    Ipc.AddPlugin(TBorionAutostartPlugin.Create);                     // nome: Application.Title
    Ipc.AddPlugin(TBorionAutostartPlugin.Create('Meu App', '--min'));  // nome e argumentos

  Comandos:
    autostart:enable            grava em HKCU\...\CurrentVersion\Run
    autostart:disable
    autostart:isEnabled         -> boolean
    autostart:launchedAtLogin   -> boolean (esta execução veio do login)

  O Windows deixa o usuário desligar a inicialização pelo Gerenciador de
  Tarefas (aba Inicializar) sem apagar o valor do Run: o isEnabled leva isso em
  conta, e o enable volta a ligar.
*)

interface

uses
  Windows, SysUtils, Classes, Forms, Jsons, BorionIpc;

type
  TBorionAutostartPlugin = class(TBorionPlugin)
  private
    FAppName: string;
    FArgs: string;
    FExePath: WideString;
    procedure CmdEnable(Call: TBorionCall);
    procedure CmdDisable(Call: TBorionCall);
    procedure CmdIsEnabled(Call: TBorionCall);
    procedure CmdLaunchedAtLogin(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    { AppName: nome do valor no Run (e na aba Inicializar); Args: acrescentados ao
      exe na inicialização, para o app saber que veio do login }
    constructor Create(const AppName: string = ''; const Args: string = '--autostart');
    function Name: string; override;
    procedure Enable;
    procedure Disable;
    function IsEnabled: Boolean;
    { True se esta execução tem os Args do autostart }
    function LaunchedAtLogin: Boolean;
    property AppName: string read FAppName;
    property Args: string read FArgs;
    property ExePath: WideString read FExePath write FExePath;
  end;

const
  BORION_RUN_KEY = 'Software\Microsoft\Windows\CurrentVersion\Run';
  BORION_STARTUP_APPROVED_KEY = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';

implementation

uses
  BorionRegistry, BorionSingleInstance;

constructor TBorionAutostartPlugin.Create(const AppName, Args: string);
begin
  inherited Create;
  FAppName := AppName;
  if FAppName = '' then
    FAppName := Application.Title;
  if Trim(FAppName) = '' then
    raise EBorionError.Create('INVALID_ARGS', 'o autostart precisa de um nome');
  FArgs := Args;
  FExePath := BorionExePathW;
end;

function TBorionAutostartPlugin.Name: string;
begin
  Result := 'autostart';
end;

procedure TBorionAutostartPlugin.Install;
begin
  Command('enable', CmdEnable);
  Command('disable', CmdDisable);
  Command('isEnabled', CmdIsEnabled);
  Command('launchedAtLogin', CmdLaunchedAtLogin);
end;

procedure TBorionAutostartPlugin.Enable;
var
  Comando: WideString;
  Ligado: string;
begin
  Comando := '"' + FExePath + '"';
  if FArgs <> '' then
    Comando := Comando + ' ' + FArgs;
  try
    BorionRegWrite(HKEY_CURRENT_USER, BORION_RUN_KEY, FAppName, Comando);
    { desfaz um "Desabilitado" do Gerenciador de Tarefas: 02 seguido de zeros = habilitado }
    Ligado := #2 + StringOfChar(#0, 11);
    BorionRegWriteBinary(HKEY_CURRENT_USER, BORION_STARTUP_APPROVED_KEY, FAppName, Ligado);
  except
    on E: Exception do
      raise EBorionError.Create('AUTOSTART_FAILED', 'não foi possível ligar a inicialização: ' + E.Message);
  end;
end;

procedure TBorionAutostartPlugin.Disable;
begin
  BorionRegDeleteValue(HKEY_CURRENT_USER, BORION_RUN_KEY, FAppName);
  BorionRegDeleteValue(HKEY_CURRENT_USER, BORION_STARTUP_APPROVED_KEY, FAppName);
end;

function TBorionAutostartPlugin.IsEnabled: Boolean;
var
  Comando: WideString;
  Aprovado: string;
begin
  Result := BorionRegRead(HKEY_CURRENT_USER, BORION_RUN_KEY, FAppName, Comando) and
    (Pos(WideLowerCase('"' + FExePath + '"'), WideLowerCase(Comando)) = 1);
  { primeiro byte ímpar (03, 07...) = desligado no Gerenciador de Tarefas }
  if Result and BorionRegReadBinary(HKEY_CURRENT_USER, BORION_STARTUP_APPROVED_KEY, FAppName, Aprovado) and
    (Aprovado <> '') and Odd(Ord(Aprovado[1])) then
    Result := False;
end;

function TBorionAutostartPlugin.LaunchedAtLogin: Boolean;
var
  A: TBorionArgs;
  I: Integer;
begin
  Result := False;
  A := nil;
  if FArgs = '' then
    Exit;
  A := BorionCommandLineArgs;
  for I := 0 to High(A) do
    if WideSameText(A[I], FArgs) then
    begin
      Result := True;
      Exit;
    end;
end;

procedure TBorionAutostartPlugin.CmdEnable(Call: TBorionCall);
begin
  Enable;
end;

procedure TBorionAutostartPlugin.CmdDisable(Call: TBorionCall);
begin
  Disable;
end;

procedure TBorionAutostartPlugin.CmdIsEnabled(Call: TBorionCall);
begin
  Call.Result.AsBoolean := IsEnabled;
end;

procedure TBorionAutostartPlugin.CmdLaunchedAtLogin(Call: TBorionCall);
begin
  Call.Result.AsBoolean := LaunchedAtLogin;
end;

end.
