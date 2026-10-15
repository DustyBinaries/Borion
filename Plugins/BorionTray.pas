unit BorionTray;

(*
  Borion — Native Application Engine
  Plugin "tray": ícone na área de notificação (bandeja) do Windows.

    Tray := TBorionTrayPlugin(Ipc.AddPlugin(TBorionTrayPlugin.Create));
    Tray.MinimizeToTray := True;   // opcional: minimizar esconde a janela na bandeja

  Comandos:
    tray:show       {tooltip?}       mostra o ícone
    tray:hide                        tira o ícone
    tray:setTooltip {tooltip}
    tray:setMenu    {items}          menu do clique direito (mesmo formato do plugin menu)
    tray:notify     {title?, message, kind?: 'info'|'warning'|'error'|'none'}
                                     notificação em balão (toast no Windows 10/11)
  Eventos:
    tray:click, tray:doubleClick     (clique simples também restaura a janela, se RestoreOnClick)
    tray:menu {id}                   item escolhido no menu do ícone
    tray:balloonClick                clicou na notificação

  O ícone é o do executável (recurso MAINICON) ou o padrão do Windows; troque
  pela propriedade Icon. A página não escolhe o ícone. Se o Explorer reiniciar,
  o ícone é recolocado sozinho.
*)

interface

uses
  Windows, Messages, SysUtils, Classes, Controls, Forms, Jsons, BorionIpc;

type
  { NOTIFYICONDATAA, versão 2 (com os campos de balão; o do Delphi 7 é a versão 1) }
  TBorionNotifyIconData = record
    cbSize: DWORD;
    Wnd: HWND;
    uID: UINT;
    uFlags: UINT;
    uCallbackMessage: UINT;
    hIcon: HICON;
    szTip: array[0..127] of AnsiChar;
    dwState: DWORD;
    dwStateMask: DWORD;
    szInfo: array[0..255] of AnsiChar;
    uTimeoutOrVersion: UINT;
    szInfoTitle: array[0..63] of AnsiChar;
    dwInfoFlags: DWORD;
  end;

  { Quem chama o Shell_NotifyIcon (trocável nos testes) }
  TBorionTrayNotify = function(Msg: DWORD; var Data: TBorionNotifyIconData): Boolean of object;

  TBorionTrayPlugin = class(TBorionPlugin)
  private
    FWindow: HWND;
    FIcon: HICON;
    FTooltip: string;
    FVisible: Boolean;
    FMenuJson: string;
    FRestoreOnClick: Boolean;
    FMinimizeToTray: Boolean;
    FHiddenByMinimize: Boolean;
    FPrevMinimize: TNotifyEvent;
    FTaskbarCreated: UINT;
    FOnNotify: TBorionTrayNotify;
    procedure WndProc(var Message: TMessage);
    function Enviar(Msg: DWORD; Flags: UINT; const Titulo, Texto: string; InfoFlags: DWORD): Boolean;
    function ShellNotify(Msg: DWORD; var Data: TBorionNotifyIconData): Boolean;
    procedure MostrarMenu;
    procedure AppMinimize(Sender: TObject);
    procedure SetMinimizeToTray(Value: Boolean);
    procedure CmdShow(Call: TBorionCall);
    procedure CmdHide(Call: TBorionCall);
    procedure CmdSetTooltip(Call: TBorionCall);
    procedure CmdSetMenu(Call: TBorionCall);
    procedure CmdNotify(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    constructor Create;
    destructor Destroy; override;
    function Name: string; override;
    procedure Show;
    procedure Hide;
    procedure SetTooltip(const Text: string);
    procedure Notify(const Title, Text: string; const Kind: string = 'info');
    { Mostra a janela do app (sai da bandeja, se estava escondida nela) }
    procedure RestoreWindow;
    property Visible: Boolean read FVisible;
    property Tooltip: string read FTooltip;
    { Ícone mostrado; padrão: MAINICON do exe ou o ícone padrão do Windows }
    property Icon: HICON read FIcon write FIcon;
    { Clique simples no ícone restaura a janela (padrão: True) }
    property RestoreOnClick: Boolean read FRestoreOnClick write FRestoreOnClick;
    { Minimizar esconde a janela e mostra o ícone (padrão: False) }
    property MinimizeToTray: Boolean read FMinimizeToTray write SetMinimizeToTray;
    property Window: HWND read FWindow;
    property OnNotify: TBorionTrayNotify read FOnNotify write FOnNotify;
  end;

const
  WM_BORION_TRAY = WM_USER + 20;
  NIN_BALLOONUSERCLICK_ = WM_USER + 5;

implementation

uses
  ShellAPI, BorionJson, BorionMenu;

const
  NIF_INFO_ = $10;
  NIIF_NONE_ = 0;
  NIIF_INFO_ = 1;
  NIIF_WARNING_ = 2;
  NIIF_ERROR_ = 3;

function Shell_NotifyIconA_(dwMessage: DWORD; var Data: TBorionNotifyIconData): BOOL; stdcall;
  external 'shell32.dll' name 'Shell_NotifyIconA';

procedure CopiarTexto(var Destino: array of AnsiChar; const Texto: string);
var
  N: Integer;
begin
  FillChar(Destino[0], Length(Destino), 0);
  N := Length(Texto);
  if N > High(Destino) then
    N := High(Destino);  { deixa espaço para o #0 }
  if N > 0 then
    Move(Texto[1], Destino[0], N);
end;

{ TBorionTrayPlugin }

constructor TBorionTrayPlugin.Create;
begin
  inherited Create;
  FWindow := Classes.AllocateHWnd(WndProc);
  FRestoreOnClick := True;
  FIcon := LoadIcon(HInstance, 'MAINICON');
  if FIcon = 0 then
    FIcon := LoadIcon(0, IDI_APPLICATION);
  FTooltip := Application.Title;
  FTaskbarCreated := RegisterWindowMessage('TaskbarCreated');
end;

destructor TBorionTrayPlugin.Destroy;
begin
  SetMinimizeToTray(False);
  Hide;
  Classes.DeallocateHWnd(FWindow);
  inherited Destroy;
end;

function TBorionTrayPlugin.Name: string;
begin
  Result := 'tray';
end;

procedure TBorionTrayPlugin.Install;
begin
  Command('show', CmdShow);
  Command('hide', CmdHide);
  Command('setTooltip', CmdSetTooltip);
  Command('setMenu', CmdSetMenu);
  Command('notify', CmdNotify);
end;

function TBorionTrayPlugin.ShellNotify(Msg: DWORD; var Data: TBorionNotifyIconData): Boolean;
begin
  if Assigned(FOnNotify) then
    Result := FOnNotify(Msg, Data)
  else
    Result := Shell_NotifyIconA_(Msg, Data);
end;

function TBorionTrayPlugin.Enviar(Msg: DWORD; Flags: UINT; const Titulo, Texto: string;
  InfoFlags: DWORD): Boolean;
var
  D: TBorionNotifyIconData;
begin
  FillChar(D, SizeOf(D), 0);
  D.cbSize := SizeOf(D);
  D.Wnd := FWindow;
  D.uID := 1;
  D.uFlags := Flags;
  D.uCallbackMessage := WM_BORION_TRAY;
  D.hIcon := FIcon;
  CopiarTexto(D.szTip, FTooltip);
  CopiarTexto(D.szInfoTitle, Titulo);
  CopiarTexto(D.szInfo, Texto);
  D.dwInfoFlags := InfoFlags;
  Result := ShellNotify(Msg, D);
end;

procedure TBorionTrayPlugin.Show;
begin
  if FVisible then
    Exit;
  FVisible := Enviar(NIM_ADD, NIF_MESSAGE or NIF_ICON or NIF_TIP, '', '', 0);
end;

procedure TBorionTrayPlugin.Hide;
begin
  if not FVisible then
    Exit;
  Enviar(NIM_DELETE, 0, '', '', 0);
  FVisible := False;
end;

procedure TBorionTrayPlugin.SetTooltip(const Text: string);
begin
  FTooltip := Text;
  if FVisible then
    Enviar(NIM_MODIFY, NIF_TIP, '', '', 0);
end;

procedure TBorionTrayPlugin.Notify(const Title, Text: string; const Kind: string);
var
  Flags: DWORD;
begin
  if Kind = 'warning' then
    Flags := NIIF_WARNING_
  else if Kind = 'error' then
    Flags := NIIF_ERROR_
  else if Kind = 'none' then
    Flags := NIIF_NONE_
  else
    Flags := NIIF_INFO_;
  Show;  { o balão precisa do ícone }
  if not Enviar(NIM_MODIFY, NIF_INFO_, Title, Text, Flags) then
    raise EBorionError.Create('IO_ERROR', 'o Windows recusou a notificação');
end;

procedure TBorionTrayPlugin.RestoreWindow;
var
  F: TCustomForm;
begin
  F := nil;
  if (Ipc <> nil) and (Ipc.Browser <> nil) then
    F := GetParentForm(Ipc.Browser);
  if F = nil then
    F := Application.MainForm;
  if FHiddenByMinimize then
  begin
    FHiddenByMinimize := False;
    ShowWindow(Application.Handle, SW_SHOW);  { volta o botão da barra de tarefas }
    Application.Restore;
  end;
  if F <> nil then
  begin
    F.Show;
    if F.WindowState = wsMinimized then
      F.WindowState := wsNormal;
    SetForegroundWindow(F.Handle);
  end;
end;

procedure TBorionTrayPlugin.AppMinimize(Sender: TObject);
begin
  if Assigned(FPrevMinimize) then
    FPrevMinimize(Sender);
  if not FMinimizeToTray then
    Exit;
  Show;
  FHiddenByMinimize := True;
  ShowWindow(Application.Handle, SW_HIDE);  { tira o botão da barra de tarefas }
end;

procedure TBorionTrayPlugin.SetMinimizeToTray(Value: Boolean);
begin
  if Value = FMinimizeToTray then
    Exit;
  FMinimizeToTray := Value;
  if Value then
  begin
    FPrevMinimize := Application.OnMinimize;
    Application.OnMinimize := AppMinimize;
  end
  else if TMethod(Application.OnMinimize).Data = Self then
    Application.OnMinimize := FPrevMinimize;
end;

procedure TBorionTrayPlugin.MostrarMenu;
var
  Itens: TJsonArray;
  Menu: HMENU;
  Ids: TStringList;
  P: TPoint;
  Cmd: Integer;
begin
  if FMenuJson = '' then
    Exit;
  Itens := TJsonArray.Create;
  Ids := TStringList.Create;
  try
    Itens.Parse(FMenuJson);
    Menu := BorionBuildPopupMenu(Itens, Ids);
    try
      GetCursorPos(P);
      { sem isso o menu da bandeja não fecha ao clicar fora (comportamento documentado) }
      SetForegroundWindow(FWindow);
      Cmd := Integer(TrackPopupMenu(Menu, TPM_RETURNCMD or TPM_RIGHTBUTTON or TPM_NONOTIFY,
        P.X, P.Y, 0, FWindow, nil));
      PostMessage(FWindow, WM_NULL, 0, 0);
    finally
      DestroyMenu(Menu);
    end;
    if (Cmd > 0) and (Cmd <= Ids.Count) and (Ipc <> nil) then
      Ipc.EmitJson('tray:menu', '{"id":' + JsonQuote(Ids[Cmd - 1]) + '}');
  finally
    Ids.Free;
    Itens.Free;
  end;
end;

procedure TBorionTrayPlugin.WndProc(var Message: TMessage);
begin
  if Message.Msg = WM_BORION_TRAY then
  begin
    try
      case Message.LParam of
        WM_LBUTTONUP:
          begin
            if FRestoreOnClick then
              RestoreWindow;
            if Ipc <> nil then
              Ipc.EmitJson('tray:click', 'null');
          end;
        WM_LBUTTONDBLCLK:
          if Ipc <> nil then
            Ipc.EmitJson('tray:doubleClick', 'null');
        WM_RBUTTONUP:
          MostrarMenu;
        NIN_BALLOONUSERCLICK_:
          begin
            RestoreWindow;
            if Ipc <> nil then
              Ipc.EmitJson('tray:balloonClick', 'null');
          end;
      end;
    except
      if Assigned(ApplicationHandleException) then
        ApplicationHandleException(Self);
    end;
    Message.Result := 0;
  end
  else if (FTaskbarCreated <> 0) and (Message.Msg = FTaskbarCreated) then
  begin
    { o Explorer reiniciou: os ícones da bandeja sumiram }
    if FVisible then
    begin
      FVisible := False;
      Show;
    end;
    Message.Result := 0;
  end
  else
    Message.Result := DefWindowProc(FWindow, Message.Msg, Message.WParam, Message.LParam);
end;

{ --- comandos ---------------------------------------------------------------- }

procedure TBorionTrayPlugin.CmdShow(Call: TBorionCall);
begin
  if Call.HasArg('tooltip') then
    FTooltip := Call.ArgStr('tooltip');
  Show;
  if not FVisible then
    raise EBorionError.Create('IO_ERROR', 'o Windows recusou o ícone da bandeja');
end;

procedure TBorionTrayPlugin.CmdHide(Call: TBorionCall);
begin
  Hide;
end;

procedure TBorionTrayPlugin.CmdSetTooltip(Call: TBorionCall);
begin
  SetTooltip(Call.ArgStr('tooltip'));
end;

procedure TBorionTrayPlugin.CmdSetMenu(Call: TBorionCall);
var
  V: TJsonValue;
  Teste: TStringList;
begin
  V := Call.Arg('items');
  if (V = nil) or (V.ValueType = jvNull) then
  begin
    FMenuJson := '';
    Exit;
  end;
  if V.ValueType <> jvArray then
    raise EBorionError.Create('INVALID_MENU', 'items deve ser uma lista');
  { valida agora (montando e descartando), para o erro voltar para quem chamou }
  Teste := TStringList.Create;
  try
    DestroyMenu(BorionBuildPopupMenu(V.AsArray, Teste));
  finally
    Teste.Free;
  end;
  FMenuJson := V.Stringify;
end;

procedure TBorionTrayPlugin.CmdNotify(Call: TBorionCall);
begin
  if Call.ArgStr('message') = '' then
    raise EBorionError.Create('INVALID_ARGS', 'message é obrigatório');
  Notify(Call.ArgStr('title'), Call.ArgStr('message'), Call.ArgStr('kind', 'info'));
end;

end.
