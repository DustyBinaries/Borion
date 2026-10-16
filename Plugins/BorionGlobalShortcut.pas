unit BorionGlobalShortcut;

(*
  Borion — Native Application Engine
  Plugin "global-shortcut": atalhos de teclado globais, que funcionam com o app
  em segundo plano (como o global-shortcut do Tauri).

    Ipc.AddPlugin(TBorionGlobalShortcutPlugin.Create);

  Comandos:
    global-shortcut:register     {shortcut}  -> o atalho normalizado ('Ctrl+Shift+K')
    global-shortcut:unregister   {shortcut}  -> o atalho normalizado
    global-shortcut:unregisterAll
    global-shortcut:isRegistered {shortcut}  -> boolean
  Evento:
    global-shortcut:pressed {shortcut, state: 'pressed'}

  Sintaxe: modificadores + tecla, separados por '+', sem diferenciar
  maiúsculas: Ctrl (Control, CmdOrCtrl, CommandOrControl), Alt (Option),
  Shift, Win (Super, Meta, Cmd). Teclas: A-Z, 0-9, F1-F24, Space, Enter, Tab,
  Escape, Backspace, Delete, Insert, Home, End, PageUp, PageDown, Up, Down,
  Left, Right, PrintScreen, Pause, Plus, Minus, Comma, Period, Num0-Num9,
  MediaPlayPause, MediaNext, MediaPrevious, VolumeUp, VolumeDown, VolumeMute.

  Letras, números e teclas de digitação exigem um modificador: um atalho global
  'A' capturaria a letra A no sistema inteiro. Teclas F, de mídia, PrintScreen e
  Pause podem ser sozinhas.

  Registrar de novo um atalho que já é deste app não é erro (a página pode ter
  sido recarregada).

  Erros: INVALID_SHORTCUT, ALREADY_REGISTERED (em uso por outro programa).
*)

interface

uses
  Windows, Messages, SysUtils, Classes, Jsons, BorionIpc;

type
  TBorionShortcutEvent = procedure(Sender: TObject; const Shortcut: string) of object;

  TBorionGlobalShortcutPlugin = class(TBorionPlugin)
  private
    FWindow: HWND;
    FAtalhos: TStringList;  { normalizado -> id do RegisterHotKey (em Objects) }
    FProximoId: Integer;
    FOnShortcut: TBorionShortcutEvent;
    procedure WndProc(var Message: TMessage);
    procedure CmdRegister(Call: TBorionCall);
    procedure CmdUnregister(Call: TBorionCall);
    procedure CmdUnregisterAll(Call: TBorionCall);
    procedure CmdIsRegistered(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    constructor Create;
    destructor Destroy; override;
    function Name: string; override;
    { Devolve o atalho normalizado; se já for deste app, não faz nada }
    function Register(const Shortcut: string): string;
    procedure Unregister(const Shortcut: string);
    procedure UnregisterAll;
    function IsRegistered(const Shortcut: string): Boolean;
    { O atalho de Id foi pressionado (chamado pelo WM_HOTKEY; público para testes) }
    procedure Pressed(Id: Integer);
    property Window: HWND read FWindow;
    property OnShortcut: TBorionShortcutEvent read FOnShortcut write FOnShortcut;
  end;

{ Interpreta o atalho. Levanta EBorionError('INVALID_SHORTCUT') se inválido. }
procedure BorionParseShortcut(const Shortcut: string; out Modifiers, Key: Cardinal; out Normalized: string);

implementation

uses
  BorionJson;

const
  MOD_ALT_ = $0001;
  MOD_CONTROL_ = $0002;
  MOD_SHIFT_ = $0004;
  MOD_WIN_ = $0008;
  MOD_NOREPEAT = $4000;  { segurar a tecla não repete o evento (Windows 7+) }
  ERROR_HOTKEY_ALREADY_REGISTERED = 1409;

type
  TTecla = record
    Nome: string;
    VK: Cardinal;
    Sozinha: Boolean;  { pode ser registrada sem modificador }
  end;

const
  TECLAS: array[0..33] of TTecla = (
    (Nome: 'Space'; VK: VK_SPACE; Sozinha: False), (Nome: 'Enter'; VK: VK_RETURN; Sozinha: False), (Nome: 'Tab'; VK: VK_TAB; Sozinha: False),
    (Nome: 'Escape'; VK: VK_ESCAPE; Sozinha: False), (Nome: 'Backspace'; VK: VK_BACK; Sozinha: False), (Nome: 'Delete'; VK: VK_DELETE; Sozinha: False),
    (Nome: 'Insert'; VK: VK_INSERT; Sozinha: False), (Nome: 'Home'; VK: VK_HOME; Sozinha: False), (Nome: 'End'; VK: VK_END; Sozinha: False),
    (Nome: 'PageUp'; VK: VK_PRIOR; Sozinha: False), (Nome: 'PageDown'; VK: VK_NEXT; Sozinha: False), (Nome: 'Up'; VK: VK_UP; Sozinha: False),
    (Nome: 'Down'; VK: VK_DOWN; Sozinha: False), (Nome: 'Left'; VK: VK_LEFT; Sozinha: False), (Nome: 'Right'; VK: VK_RIGHT; Sozinha: False),
    (Nome: 'PrintScreen'; VK: VK_SNAPSHOT; Sozinha: True), (Nome: 'Pause'; VK: VK_PAUSE; Sozinha: True),
    (Nome: 'Plus'; VK: $BB; Sozinha: False), (Nome: 'Minus'; VK: $BD; Sozinha: False), (Nome: 'Comma'; VK: $BC; Sozinha: False), (Nome: 'Period'; VK: $BE; Sozinha: False),
    (Nome: 'MediaPlayPause'; VK: $B3; Sozinha: True), (Nome: 'MediaNext'; VK: $B0; Sozinha: True),
    (Nome: 'MediaPrevious'; VK: $B1; Sozinha: True), (Nome: 'MediaStop'; VK: $B2; Sozinha: True),
    (Nome: 'VolumeUp'; VK: $AF; Sozinha: True), (Nome: 'VolumeDown'; VK: $AE; Sozinha: True),
    (Nome: 'VolumeMute'; VK: $AD; Sozinha: True),
    { apelidos }
    (Nome: 'Return'; VK: VK_RETURN; Sozinha: False), (Nome: 'Esc'; VK: VK_ESCAPE; Sozinha: False), (Nome: 'Del'; VK: VK_DELETE; Sozinha: False),
    (Nome: 'ArrowUp'; VK: VK_UP; Sozinha: False), (Nome: 'ArrowDown'; VK: VK_DOWN; Sozinha: False), (Nome: 'ArrowLeft'; VK: VK_LEFT; Sozinha: False));

procedure Invalido(const Shortcut, Motivo: string);
begin
  raise EBorionError.Create('INVALID_SHORTCUT', 'atalho inválido "' + Shortcut + '": ' + Motivo);
end;

{ nome canônico de uma tecla de TECLAS (os apelidos apontam para o primeiro com o mesmo VK) }
function NomeCanonico(VK: Cardinal): string;
var
  I: Integer;
begin
  for I := Low(TECLAS) to High(TECLAS) do
    if TECLAS[I].VK = VK then
    begin
      Result := TECLAS[I].Nome;
      Exit;
    end;
  Result := '';
end;

procedure BorionParseShortcut(const Shortcut: string; out Modifiers, Key: Cardinal; out Normalized: string);
var
  Partes: TStringList;
  I, J: Integer;
  N: Cardinal;
  P, Nome: string;
  Sozinha: Boolean;
begin
  Modifiers := 0;
  Key := 0;
  Sozinha := False;
  Nome := '';
  Partes := TStringList.Create;
  try
    { 'Ctrl+Plus' usa o nome; um '+' literal no fim não é aceito }
    P := Trim(Shortcut);
    if (P = '') or (P[Length(P)] = '+') then
      Invalido(Shortcut, 'vazio ou terminado em +');
    while P <> '' do
    begin
      I := Pos('+', P);
      if I = 0 then
      begin
        Partes.Add(Trim(P));
        P := '';
      end
      else
      begin
        Partes.Add(Trim(Copy(P, 1, I - 1)));
        Delete(P, 1, I);
      end;
    end;
    for I := 0 to Partes.Count - 1 do
    begin
      P := LowerCase(Partes[I]);
      if P = '' then
        Invalido(Shortcut, 'parte vazia');
      if I < Partes.Count - 1 then
      begin
        { modificador }
        if (P = 'ctrl') or (P = 'control') or (P = 'cmdorctrl') or (P = 'commandorcontrol') or (P = 'cmdorcontrol') then
          N := MOD_CONTROL_
        else if (P = 'alt') or (P = 'option') then
          N := MOD_ALT_
        else if P = 'shift' then
          N := MOD_SHIFT_
        else if (P = 'win') or (P = 'super') or (P = 'meta') or (P = 'cmd') or (P = 'command') then
          N := MOD_WIN_
        else
        begin
          Invalido(Shortcut, 'modificador desconhecido "' + Partes[I] + '"');
          N := 0;
        end;
        if Modifiers and N <> 0 then
          Invalido(Shortcut, 'modificador repetido');
        Modifiers := Modifiers or N;
        Continue;
      end;
      { tecla }
      if (Length(P) = 1) and (P[1] in ['a'..'z', '0'..'9']) then
      begin
        Key := Ord(UpCase(P[1]));
        Nome := UpperCase(P);
      end
      else if (Length(P) in [2, 3]) and (P[1] = 'f') and (StrToIntDef(Copy(P, 2, 2), 0) in [1..24]) then
      begin
        Key := VK_F1 + Cardinal(StrToInt(Copy(P, 2, 2))) - 1;
        Nome := 'F' + Copy(P, 2, 2);
        Sozinha := True;
      end
      else if (Length(P) = 4) and (Copy(P, 1, 3) = 'num') and (P[4] in ['0'..'9']) then
      begin
        Key := VK_NUMPAD0 + Cardinal(Ord(P[4]) - Ord('0'));
        Nome := 'Num' + P[4];
      end
      else
      begin
        for J := Low(TECLAS) to High(TECLAS) do
          if LowerCase(TECLAS[J].Nome) = P then
          begin
            Key := TECLAS[J].VK;
            Nome := NomeCanonico(Key);
            Sozinha := TECLAS[J].Sozinha;
            Break;
          end;
        if Key = 0 then
          Invalido(Shortcut, 'tecla desconhecida "' + Partes[I] + '"');
      end;
    end;
    if (Modifiers = 0) and not Sozinha then
      Invalido(Shortcut, 'esta tecla precisa de um modificador (Ctrl, Alt, Shift ou Win)');
    Normalized := '';
    if Modifiers and MOD_CONTROL_ <> 0 then Normalized := Normalized + 'Ctrl+';
    if Modifiers and MOD_ALT_ <> 0 then Normalized := Normalized + 'Alt+';
    if Modifiers and MOD_SHIFT_ <> 0 then Normalized := Normalized + 'Shift+';
    if Modifiers and MOD_WIN_ <> 0 then Normalized := Normalized + 'Win+';
    Normalized := Normalized + Nome;
  finally
    Partes.Free;
  end;
end;

{ TBorionGlobalShortcutPlugin }

constructor TBorionGlobalShortcutPlugin.Create;
begin
  inherited Create;
  FAtalhos := TStringList.Create;
  FAtalhos.Sorted := True;
  FWindow := Classes.AllocateHWnd(WndProc);
end;

destructor TBorionGlobalShortcutPlugin.Destroy;
begin
  UnregisterAll;
  Classes.DeallocateHWnd(FWindow);
  FAtalhos.Free;
  inherited;
end;

function TBorionGlobalShortcutPlugin.Name: string;
begin
  Result := 'global-shortcut';
end;

procedure TBorionGlobalShortcutPlugin.Install;
begin
  Command('register', CmdRegister);
  Command('unregister', CmdUnregister);
  Command('unregisterAll', CmdUnregisterAll);
  Command('isRegistered', CmdIsRegistered);
end;

function TBorionGlobalShortcutPlugin.Register(const Shortcut: string): string;
var
  Mods, Key: Cardinal;
  Ok: Boolean;
begin
  BorionParseShortcut(Shortcut, Mods, Key, Result);
  { já é deste app: nada a fazer (a página pode ter sido recarregada e registrar de novo) }
  if FAtalhos.IndexOf(Result) >= 0 then
    Exit;
  Inc(FProximoId);
  Ok := RegisterHotKey(FWindow, FProximoId, Mods or MOD_NOREPEAT, Key);
  if not Ok and (GetLastError <> ERROR_HOTKEY_ALREADY_REGISTERED) then
    Ok := RegisterHotKey(FWindow, FProximoId, Mods, Key);  { Windows antigo: sem MOD_NOREPEAT }
  if not Ok then
  begin
    if GetLastError = ERROR_HOTKEY_ALREADY_REGISTERED then
      raise EBorionError.Create('ALREADY_REGISTERED', Result + ' já está em uso por outro programa')
    else
      raise EBorionError.Create('REGISTER_FAILED', Result + ': ' + SysErrorMessage(GetLastError));
  end;
  FAtalhos.AddObject(Result, TObject(FProximoId));
end;

procedure TBorionGlobalShortcutPlugin.Unregister(const Shortcut: string);
var
  Mods, Key: Cardinal;
  Normalizado: string;
  I: Integer;
begin
  BorionParseShortcut(Shortcut, Mods, Key, Normalizado);
  I := FAtalhos.IndexOf(Normalizado);
  if I < 0 then
    Exit;
  UnregisterHotKey(FWindow, Integer(FAtalhos.Objects[I]));
  FAtalhos.Delete(I);
end;

procedure TBorionGlobalShortcutPlugin.UnregisterAll;
var
  I: Integer;
begin
  for I := 0 to FAtalhos.Count - 1 do
    UnregisterHotKey(FWindow, Integer(FAtalhos.Objects[I]));
  FAtalhos.Clear;
end;

function TBorionGlobalShortcutPlugin.IsRegistered(const Shortcut: string): Boolean;
var
  Mods, Key: Cardinal;
  Normalizado: string;
begin
  BorionParseShortcut(Shortcut, Mods, Key, Normalizado);
  Result := FAtalhos.IndexOf(Normalizado) >= 0;
end;

procedure TBorionGlobalShortcutPlugin.Pressed(Id: Integer);
var
  I: Integer;
begin
  for I := 0 to FAtalhos.Count - 1 do
    if Integer(FAtalhos.Objects[I]) = Id then
    begin
      if Ipc <> nil then
        Ipc.EmitJson('global-shortcut:pressed', '{"shortcut":' + JsonQuote(FAtalhos[I]) + ',"state":"pressed"}');
      if Assigned(FOnShortcut) then
        FOnShortcut(Self, FAtalhos[I]);
      Exit;
    end;
end;

procedure TBorionGlobalShortcutPlugin.WndProc(var Message: TMessage);
begin
  if Message.Msg = WM_HOTKEY then
    Pressed(Message.WParam)
  else
    Message.Result := DefWindowProc(FWindow, Message.Msg, Message.WParam, Message.LParam);
end;

procedure TBorionGlobalShortcutPlugin.CmdRegister(Call: TBorionCall);
begin
  Call.Result.AsString := Register(Call.ArgStr('shortcut'));
end;

procedure TBorionGlobalShortcutPlugin.CmdUnregister(Call: TBorionCall);
var
  M, K: Cardinal;
  Normalizado: string;
begin
  BorionParseShortcut(Call.ArgStr('shortcut'), M, K, Normalizado);
  Unregister(Normalizado);
  Call.Result.AsString := Normalizado;
end;

procedure TBorionGlobalShortcutPlugin.CmdUnregisterAll(Call: TBorionCall);
begin
  UnregisterAll;
end;

procedure TBorionGlobalShortcutPlugin.CmdIsRegistered(Call: TBorionCall);
begin
  Call.Result.AsBoolean := IsRegistered(Call.ArgStr('shortcut'));
end;

end.
