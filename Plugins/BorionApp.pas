unit BorionApp;

(*
  Borion — Native Application Engine
  Plugin "app" (mínimo): controlar a janela e o ciclo de vida do app.

    Ipc.AddPlugin(TBorionAppPlugin.Create);

  Comandos:
    app:exit       fecha a janela principal (passa pelo OnCloseQuery/OnClose do form)
    app:show       mostra e traz a janela para frente (inclusive se estiver na bandeja)
    app:hide       esconde a janela
    app:minimize   minimiza
    app:info       {name, version, identifier, exe, pid} (version e identifier
                   do app.json; sem eles, a versão do exe e '')

  É a parte do plugin "app" do roadmap que os menus e a bandeja precisam (um
  item "Sair" não tem como fechar o app sem ela). Caminhos, reiniciar etc.
  ficam para depois.
*)

interface

uses
  Windows, Messages, SysUtils, Classes, Controls, Forms, Jsons, BorionIpc;

type
  TBorionAppPlugin = class(TBorionPlugin)
  private
    FForm: TCustomForm;
    function Formulario: TCustomForm;
    procedure CmdExit(Call: TBorionCall);
    procedure CmdShow(Call: TBorionCall);
    procedure CmdHide(Call: TBorionCall);
    procedure CmdMinimize(Call: TBorionCall);
    procedure CmdInfo(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    { AForm nil: o form do browser do Ipc (ou o MainForm) }
    constructor Create(AForm: TCustomForm = nil);
    function Name: string; override;
    property Form: TCustomForm read FForm write FForm;
  end;

{ FileVersion do recurso de versão do exe ('' se não houver) }
function BorionExeVersion: string;
{ Mostra a janela do app e a traz para frente: sai da bandeja (plugin tray),
  desfaz o minimizar e o esconder. Form nil: o form do browser do Ipc ou o MainForm. }
procedure BorionShowMainWindow(Ipc: TBorionIpc; Form: TCustomForm = nil);

implementation

uses
  BorionTray, BorionConfig;

function BorionExeVersion: string;
var
  Tamanho, Dummy: DWORD;
  Buffer: Pointer;
  Info: PVSFixedFileInfo;
  Len: UINT;
begin
  Result := '';
  Tamanho := GetFileVersionInfoSize(PChar(ParamStr(0)), Dummy);
  if Tamanho = 0 then
    Exit;
  GetMem(Buffer, Tamanho);
  try
    if GetFileVersionInfo(PChar(ParamStr(0)), 0, Tamanho, Buffer) and
      VerQueryValue(Buffer, '\', Pointer(Info), Len) then
      Result := Format('%d.%d.%d.%d', [HiWord(Info.dwFileVersionMS), LoWord(Info.dwFileVersionMS),
        HiWord(Info.dwFileVersionLS), LoWord(Info.dwFileVersionLS)]);
  finally
    FreeMem(Buffer);
  end;
end;

procedure BorionShowMainWindow(Ipc: TBorionIpc; Form: TCustomForm);
var
  Tray: TBorionPlugin;
begin
  Tray := nil;
  if Ipc <> nil then
    Tray := Ipc.FindPlugin('tray');
  if Tray <> nil then
  begin
    TBorionTrayPlugin(Tray).RestoreWindow;  { sabe sair da bandeja }
    Exit;
  end;
  if (Form = nil) and (Ipc <> nil) and (Ipc.Browser <> nil) then
    Form := GetParentForm(Ipc.Browser);
  if Form = nil then
    Form := Application.MainForm;
  if Form = nil then
    Exit;
  Form.Show;
  { no Delphi 7, o app:minimize minimiza a janela da TApplication, não o form }
  if IsIconic(Application.Handle) then
    Application.Restore;
  if Form.WindowState = wsMinimized then
    Form.WindowState := wsNormal;
  SetForegroundWindow(Form.Handle);
end;

{ TBorionAppPlugin }

constructor TBorionAppPlugin.Create(AForm: TCustomForm);
begin
  inherited Create;
  FForm := AForm;
end;

function TBorionAppPlugin.Name: string;
begin
  Result := 'app';
end;

procedure TBorionAppPlugin.Install;
begin
  Command('exit', CmdExit);
  Command('show', CmdShow);
  Command('hide', CmdHide);
  Command('minimize', CmdMinimize);
  Command('info', CmdInfo);
end;

function TBorionAppPlugin.Formulario: TCustomForm;
begin
  Result := FForm;
  if (Result = nil) and (Ipc <> nil) and (Ipc.Browser <> nil) then
    Result := GetParentForm(Ipc.Browser);
  if Result = nil then
    Result := Application.MainForm;
  if Result = nil then
    raise EBorionError.Create('NO_WINDOW', 'nenhuma janela para controlar');
end;

procedure TBorionAppPlugin.CmdExit(Call: TBorionCall);
begin
  { postado: fechar a janela dentro do callback do WebView2 destruiria o browser no meio dele }
  PostMessage(Formulario.Handle, WM_CLOSE, 0, 0);
end;

procedure TBorionAppPlugin.CmdShow(Call: TBorionCall);
begin
  BorionShowMainWindow(Ipc, Formulario);
end;

procedure TBorionAppPlugin.CmdHide(Call: TBorionCall);
begin
  Formulario.Hide;
end;

procedure TBorionAppPlugin.CmdMinimize(Call: TBorionCall);
begin
  Application.Minimize;
end;

procedure TBorionAppPlugin.CmdInfo(Call: TBorionCall);
var
  O: TJsonObject;
begin
  O := Call.Result.AsObject;
  O.Put('name', Application.Title);
  if BorionAppConfig.Version <> '' then
    O.Put('version', BorionAppConfig.Version)
  else
    O.Put('version', BorionExeVersion);
  O.Put('identifier', BorionAppConfig.Identifier);
  O.Put('exe', ParamStr(0));
  O.Put('pid', Integer(GetCurrentProcessId));
end;

end.
