unit BorionMenu;

(*
  Borion — Native Application Engine
  Plugin "menu": barra de menu da janela e menus de contexto nativos.

    Ipc.AddPlugin(TBorionMenuPlugin.Create);   // usa o form do browser

  Comandos:
    menu:setMenu {items}     monta a barra de menu (items vazio remove a barra)
    menu:update  {id, enabled?, checked?, label?, accelerator?}
    menu:clear
    menu:popup   {items, x?, y?}  -> id escolhido ou null (abre no cursor ou em x,y da página)
  Evento:
    menu:click   {id, checked?}   clique num item da barra (ou atalho de teclado)

  Item: {id, label, type?: 'normal' | 'checkbox' | 'separator', enabled?, checked?,
         accelerator?: 'Ctrl+S', items?: [...submenu]}

  Atalhos: com o foco na página, o teclado vai direto para o processo do WebView2
  e a VCL não vê o Ctrl+S. O plugin escuta o OnAcceleratorKeyPressed do browser,
  acha o item com aquele atalho, dispara o clique e impede a página de receber a tecla.
*)

interface

uses
  Windows, Messages, SysUtils, Classes, Controls, Forms, Menus, Jsons,
  WebView2, WebView2Browser, BorionIpc;

type
  TBorionMenuPlugin = class(TBorionPlugin)
  private
    FForm: TCustomForm;
    FMainMenu: TMainMenu;
    FIds: TStringList;  { id -> TMenuItem }
    FPrevKey: TWV2AcceleratorKeyEvent;
    FHooked: Boolean;
    function Formulario: TCustomForm;
    procedure AddItems(Parent: TMenuItem; Items: TJsonArray);
    procedure ItemClick(Sender: TObject);
    procedure KeyPressed(Sender: TObject; KeyEventKind, VirtualKey: Integer; var Handled: Boolean);
    procedure CmdSetMenu(Call: TBorionCall);
    procedure CmdUpdate(Call: TBorionCall);
    procedure CmdClear(Call: TBorionCall);
    procedure CmdPopup(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    { AForm nil: o form do browser do Ipc }
    constructor Create(AForm: TCustomForm = nil);
    destructor Destroy; override;
    function Name: string; override;
    { Monta a barra (o mesmo que menu:setMenu); Items nil ou vazio remove a barra }
    procedure BuildMenu(Items: TJsonArray);
    procedure Clear;
    function FindItem(const Id: string): TMenuItem;
    function IdOf(Item: TMenuItem): string;
    { Item habilitado (com os pais) que tem esse atalho; nil se nenhum }
    function ItemForShortCut(ShortCut: TShortCut): TMenuItem;
    { Trata uma tecla como o OnAcceleratorKeyPressed: True se disparou um item }
    function HandleKey(VirtualKey: Word; Ctrl, Shift, Alt: Boolean): Boolean;
    property MainMenu: TMainMenu read FMainMenu;
    property Form: TCustomForm read FForm write FForm;
  end;

{ Menu popup Win32 a partir dos itens; Ids recebe o id de cada comando (comando = índice + 1) }
function BorionBuildPopupMenu(Items: TJsonArray; Ids: TStrings): HMENU;
{ 'Ctrl+Shift+S' -> TShortCut; levanta EBorionError('INVALID_MENU') se inválido }
function BorionParseAccelerator(const Text: string): TShortCut;

implementation

uses
  BorionJson;

const
  TIPO_CHECKBOX = 1;

function Str(O: TJsonObject; const Nome, Padrao: string): string;
var
  I: Integer;
begin
  I := O.Find(Nome);
  if (I >= 0) and not (O.Items[I].Value.ValueType in [jvNone, jvNull]) then
    Result := O.Items[I].Value.AsString
  else
    Result := Padrao;
end;

function Bool(O: TJsonObject; const Nome: string; Padrao: Boolean): Boolean;
var
  I: Integer;
begin
  I := O.Find(Nome);
  if (I >= 0) and (O.Items[I].Value.ValueType = jvBoolean) then
    Result := O.Items[I].Value.AsBoolean
  else
    Result := Padrao;
end;

function Filhos(O: TJsonObject): TJsonArray;
var
  I: Integer;
begin
  I := O.Find('items');
  if (I >= 0) and (O.Items[I].Value.ValueType = jvArray) then
    Result := O.Items[I].Value.AsArray
  else
    Result := nil;
end;

function BorionParseAccelerator(const Text: string): TShortCut;
begin
  Result := 0;
  if Trim(Text) = '' then
    Exit;
  Result := TextToShortCut(Trim(Text));
  if Result = 0 then
    raise EBorionError.Create('INVALID_MENU', 'atalho inválido: ' + Text);
end;

procedure AdicionarPopup(Menu: HMENU; Items: TJsonArray; Ids: TStrings);
var
  I: Integer;
  O: TJsonObject;
  Flags: UINT;
  Texto, Atalho: string;
  Sub: HMENU;
  Itens: TJsonArray;
begin
  if Items = nil then
    Exit;
  for I := 0 to Items.Count - 1 do
  begin
    if Items[I].ValueType <> jvObject then
      Continue;
    O := Items[I].AsObject;
    if Str(O, 'type', 'normal') = 'separator' then
    begin
      AppendMenu(Menu, MF_SEPARATOR, 0, nil);
      Continue;
    end;
    Texto := Str(O, 'label', Str(O, 'id', ''));
    Atalho := Str(O, 'accelerator', '');
    if Atalho <> '' then
      Texto := Texto + #9 + Atalho;  { só exibido: o popup é modal }
    Flags := MF_STRING;
    if not Bool(O, 'enabled', True) then
      Flags := Flags or MF_GRAYED;
    if Bool(O, 'checked', False) then
      Flags := Flags or MF_CHECKED;
    Itens := Filhos(O);
    if Itens <> nil then
    begin
      Sub := CreatePopupMenu;
      AdicionarPopup(Sub, Itens, Ids);
      AppendMenu(Menu, Flags or MF_POPUP, Sub, PChar(Texto));
    end
    else
    begin
      Ids.Add(Str(O, 'id', ''));
      AppendMenu(Menu, Flags, Ids.Count, PChar(Texto));
    end;
  end;
end;

function BorionBuildPopupMenu(Items: TJsonArray; Ids: TStrings): HMENU;
begin
  Ids.Clear;
  Result := CreatePopupMenu;
  AdicionarPopup(Result, Items, Ids);
end;

{ TBorionMenuPlugin }

constructor TBorionMenuPlugin.Create(AForm: TCustomForm);
begin
  inherited Create;
  FForm := AForm;
  FMainMenu := TMainMenu.Create(nil);
  FIds := TStringList.Create;
  FIds.CaseSensitive := True;
end;

destructor TBorionMenuPlugin.Destroy;
begin
  if FHooked and (Ipc <> nil) and (Ipc.Browser <> nil) then
    Ipc.Browser.OnAcceleratorKeyPressed := FPrevKey;
  FIds.Free;
  FMainMenu.Free;  { o form é avisado (FreeNotification) e solta a barra }
  inherited Destroy;
end;

function TBorionMenuPlugin.Name: string;
begin
  Result := 'menu';
end;

procedure TBorionMenuPlugin.Install;
begin
  Command('setMenu', CmdSetMenu);
  Command('update', CmdUpdate);
  Command('clear', CmdClear);
  CommandLater('popup', CmdPopup);
  if Ipc.Browser <> nil then
  begin
    FPrevKey := Ipc.Browser.OnAcceleratorKeyPressed;
    Ipc.Browser.OnAcceleratorKeyPressed := KeyPressed;
    FHooked := True;
  end;
end;

function TBorionMenuPlugin.Formulario: TCustomForm;
begin
  if (FForm = nil) and (Ipc <> nil) and (Ipc.Browser <> nil) then
    FForm := GetParentForm(Ipc.Browser);
  Result := FForm;
end;

procedure TBorionMenuPlugin.AddItems(Parent: TMenuItem; Items: TJsonArray);
var
  I: Integer;
  O: TJsonObject;
  Item: TMenuItem;
  Id: string;
  Sub: TJsonArray;
begin
  if Items = nil then
    Exit;
  for I := 0 to Items.Count - 1 do
  begin
    if Items[I].ValueType <> jvObject then
      raise EBorionError.Create('INVALID_MENU', 'cada item deve ser um objeto');
    O := Items[I].AsObject;
    Item := TMenuItem.Create(FMainMenu);
    Parent.Add(Item);
    if Str(O, 'type', 'normal') = 'separator' then
    begin
      Item.Caption := '-';
      Continue;
    end;
    Id := Str(O, 'id', '');
    Item.Caption := Str(O, 'label', Id);
    Item.Enabled := Bool(O, 'enabled', True);
    Item.Checked := Bool(O, 'checked', False);
    if Str(O, 'type', 'normal') = 'checkbox' then
      Item.Tag := TIPO_CHECKBOX;
    Item.ShortCut := BorionParseAccelerator(Str(O, 'accelerator', ''));
    Sub := Filhos(O);
    if Sub <> nil then
      AddItems(Item, Sub)
    else
    begin
      if Id = '' then
        raise EBorionError.Create('INVALID_MENU', 'item sem id: ' + Item.Caption);
      Item.OnClick := ItemClick;
    end;
    if Id <> '' then
    begin
      if FIds.IndexOf(Id) >= 0 then
        raise EBorionError.Create('INVALID_MENU', 'id repetido: ' + Id);
      FIds.AddObject(Id, Item);
    end;
  end;
end;

procedure TBorionMenuPlugin.BuildMenu(Items: TJsonArray);
var
  F: TCustomForm;
begin
  Clear;
  if (Items = nil) or (Items.Count = 0) then
    Exit;
  try
    AddItems(FMainMenu.Items, Items);
  except
    Clear;  { nada de barra pela metade }
    raise;
  end;
  F := Formulario;
  if F <> nil then
    TForm(F).Menu := FMainMenu;
end;

procedure TBorionMenuPlugin.Clear;
var
  F: TCustomForm;
begin
  F := Formulario;
  if (F <> nil) and (TForm(F).Menu = FMainMenu) then
    TForm(F).Menu := nil;
  FMainMenu.Items.Clear;
  FIds.Clear;
end;

function TBorionMenuPlugin.FindItem(const Id: string): TMenuItem;
var
  I: Integer;
begin
  I := FIds.IndexOf(Id);
  if I >= 0 then
    Result := TMenuItem(FIds.Objects[I])
  else
    Result := nil;
end;

function TBorionMenuPlugin.IdOf(Item: TMenuItem): string;
var
  I: Integer;
begin
  I := FIds.IndexOfObject(Item);
  if I >= 0 then
    Result := FIds[I]
  else
    Result := '';
end;

procedure TBorionMenuPlugin.ItemClick(Sender: TObject);
var
  Item: TMenuItem;
  Json: string;
begin
  Item := TMenuItem(Sender);
  if Item.Tag = TIPO_CHECKBOX then
    Item.Checked := not Item.Checked;
  Json := '{"id":' + JsonQuote(IdOf(Item));
  if Item.Tag = TIPO_CHECKBOX then
    Json := Json + ',"checked":' + LowerCase(BoolToStr(Item.Checked, True));
  Ipc.EmitJson('menu:click', Json + '}');
end;

function TBorionMenuPlugin.ItemForShortCut(ShortCut: TShortCut): TMenuItem;

  function Buscar(Pai: TMenuItem): TMenuItem;
  var
    I: Integer;
  begin
    Result := nil;
    for I := 0 to Pai.Count - 1 do
    begin
      if not Pai.Items[I].Enabled or not Pai.Items[I].Visible then
        Continue;  { item (ou submenu) desabilitado: o atalho não vale }
      if (Pai.Items[I].ShortCut = ShortCut) and (Pai.Items[I].Count = 0) then
      begin
        Result := Pai.Items[I];
        Exit;
      end;
      Result := Buscar(Pai.Items[I]);
      if Result <> nil then
        Exit;
    end;
  end;

begin
  Result := nil;
  if ShortCut <> 0 then
    Result := Buscar(FMainMenu.Items);
end;

function TBorionMenuPlugin.HandleKey(VirtualKey: Word; Ctrl, Shift, Alt: Boolean): Boolean;
var
  Estado: TShiftState;
  Item: TMenuItem;
begin
  Estado := [];
  if Ctrl then Include(Estado, ssCtrl);
  if Shift then Include(Estado, ssShift);
  if Alt then Include(Estado, ssAlt);
  Item := ItemForShortCut(Menus.ShortCut(VirtualKey, Estado));
  Result := Item <> nil;
  if Result then
    Item.Click;
end;

procedure TBorionMenuPlugin.KeyPressed(Sender: TObject; KeyEventKind, VirtualKey: Integer;
  var Handled: Boolean);
begin
  if Assigned(FPrevKey) then
    FPrevKey(Sender, KeyEventKind, VirtualKey, Handled);
  if Handled then
    Exit;
  if (KeyEventKind <> COREWEBVIEW2_KEY_EVENT_KIND_KEY_DOWN) and
    (KeyEventKind <> COREWEBVIEW2_KEY_EVENT_KIND_SYSTEM_KEY_DOWN) then
    Exit;
  { estado físico: esta thread não recebe as mensagens de teclado do WebView2 }
  Handled := HandleKey(VirtualKey, GetAsyncKeyState(VK_CONTROL) < 0,
    GetAsyncKeyState(VK_SHIFT) < 0, GetAsyncKeyState(VK_MENU) < 0);
end;

{ --- comandos ---------------------------------------------------------------- }

procedure TBorionMenuPlugin.CmdSetMenu(Call: TBorionCall);
var
  V: TJsonValue;
begin
  V := Call.Arg('items');
  if (V <> nil) and (V.ValueType = jvArray) then
    BuildMenu(V.AsArray)
  else if (V = nil) or (V.ValueType = jvNull) then
    Clear
  else
    raise EBorionError.Create('INVALID_MENU', 'items deve ser uma lista');
end;

procedure TBorionMenuPlugin.CmdUpdate(Call: TBorionCall);
var
  Item: TMenuItem;
begin
  Item := FindItem(Call.ArgStr('id'));
  if Item = nil then
    raise EBorionError.Create('NOT_FOUND', 'item de menu não encontrado: ' + Call.ArgStr('id'));
  if Call.HasArg('enabled') then
    Item.Enabled := Call.ArgBool('enabled');
  if Call.HasArg('checked') then
    Item.Checked := Call.ArgBool('checked');
  if Call.HasArg('label') then
    Item.Caption := Call.ArgStr('label');
  if Call.HasArg('accelerator') then
    Item.ShortCut := BorionParseAccelerator(Call.ArgStr('accelerator'));
end;

procedure TBorionMenuPlugin.CmdClear(Call: TBorionCall);
begin
  Clear;
end;

procedure TBorionMenuPlugin.CmdPopup(Call: TBorionCall);
var
  V: TJsonValue;
  Menu: HMENU;
  Ids: TStringList;
  P: TPoint;
  Dono: HWND;
  F: TCustomForm;
  Cmd: Integer;
begin
  V := Call.Arg('items');
  if (V = nil) or (V.ValueType <> jvArray) then
    raise EBorionError.Create('INVALID_MENU', 'items deve ser uma lista');
  F := Formulario;
  if F = nil then
    raise EBorionError.Create('NO_WINDOW', 'menu:popup exige uma janela');
  Dono := F.Handle;
  if Call.HasArg('x') and Call.HasArg('y') and (Ipc.Browser <> nil) then
    P := Ipc.Browser.ClientToScreen(Point(Call.ArgInt('x'), Call.ArgInt('y')))
  else
    GetCursorPos(P);
  Ids := TStringList.Create;
  Menu := BorionBuildPopupMenu(V.AsArray, Ids);
  try
    SetForegroundWindow(Dono);
    Cmd := Integer(TrackPopupMenu(Menu, TPM_RETURNCMD or TPM_RIGHTBUTTON or TPM_NONOTIFY,
      P.X, P.Y, 0, Dono, nil));
    { o SetForegroundWindow tirou o foco do documento: devolve, para a pagina
      continuar recebendo teclas e poder usar a Clipboard API logo em seguida }
    if (Ipc.Browser <> nil) and (Ipc.Browser.Controller <> nil) then
      Ipc.Browser.Controller.MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
    if (Cmd > 0) and (Cmd <= Ids.Count) then
      Call.Result.AsString := Ids[Cmd - 1];  { senão: null (fechou sem escolher) }
  finally
    DestroyMenu(Menu);
    Ids.Free;
  end;
end;

end.
