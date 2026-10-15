unit BorionDialog;

(*
  Borion — Native Application Engine
  Plugin "dialog": diálogos nativos do Windows.

    Ipc.AddPlugin(TBorionDialogPlugin.Create(Scope));   // Scope: opcional

  Comandos:
    dialog:open    {title?, multiple?, directory?, filters?, defaultPath?}
                   -> caminho, [caminhos] (multiple) ou null (cancelado)
    dialog:save    {title?, filters?, defaultPath?}       -> caminho ou null
    dialog:message {message, title?, kind?}                -> null
    dialog:confirm {message, title?, kind?, buttons?}      -> boolean

    filters: [{name: 'Texto', extensions: ['txt', 'md']}, ...]
    kind:    'info' (padrão), 'warning', 'error'
    buttons: 'okCancel' (padrão) ou 'yesNo'

  Com um TBorionScope, o que o usuário escolhe no diálogo passa a ser permitido
  (como no Tauri): arquivo aberto/salvo -> AllowFile; pasta -> AllowDir. Assim o
  app só lê ou grava fora do escopo fixo o que o próprio usuário apontou.

  Os comandos rodam com Ipc.Later: o diálogo abre depois que o callback do
  WebView2 retorna, nunca dentro dele.
*)

interface

uses
  Windows, SysUtils, Classes, Jsons, BorionIpc, BorionScope;

type
  TBorionDialogPlugin = class(TBorionPlugin)
  private
    FScope: TBorionScope;
    FOwnerWindow: HWND;
    function Dono: HWND;
    procedure CmdOpen(Call: TBorionCall);
    procedure CmdSave(Call: TBorionCall);
    procedure CmdMessage(Call: TBorionCall);
    procedure CmdConfirm(Call: TBorionCall);
    procedure Permitir(const Path: string; Pasta: Boolean);
  protected
    procedure Install; override;
  public
    { AScope não é liberado pelo plugin (normalmente é o do TBorionFsPlugin) }
    constructor Create(AScope: TBorionScope = nil);
    function Name: string; override;
    { Janela dona dos diálogos; 0 = a janela do browser do Ipc }
    property OwnerWindow: HWND read FOwnerWindow write FOwnerWindow;
    property Scope: TBorionScope read FScope write FScope;
  end;

{ Filtro no formato do GetOpenFileName ('Nome (*.a;*.b)'#0'*.a;*.b'#0 ... #0).
  Filters nil ou vazio -> 'Todos os arquivos'. }
function BorionDialogFilter(Filters: TJsonArray): string;
{ Buffer de um GetOpenFileName com múltipla seleção ('pasta'#0'a'#0'b'#0#0 ou
  'caminho'#0#0) -> caminhos completos }
procedure BorionSplitMultiSelect(const Buffer: string; Paths: TStrings);

implementation

uses
  Messages, CommDlg, ShlObj, ActiveX, WebView2Browser;

function GetAncestor_(Wnd: HWND; Flags: UINT): HWND; stdcall;
  external user32 name 'GetAncestor';

const
  TAMANHO_BUFFER = 65536;
  BIF_NEWDIALOGSTYLE_ = $0040;
  BFFM_INITIALIZED_ = 1;
  BFFM_SETSELECTIONA_ = WM_USER + 102;

function BorionDialogFilter(Filters: TJsonArray): string;
var
  I, J: Integer;
  F: TJsonObject;
  Nome, Padrao, Ext: string;
  Exts: TJsonArray;
begin
  Result := '';
  if Filters <> nil then
    for I := 0 to Filters.Count - 1 do
    begin
      if Filters[I].ValueType <> jvObject then
        Continue;
      F := Filters[I].AsObject;
      Padrao := '';
      if (F.Find('extensions') >= 0) and (F['extensions'].ValueType = jvArray) then
      begin
        Exts := F['extensions'].AsArray;
        for J := 0 to Exts.Count - 1 do
        begin
          Ext := Trim(Exts[J].AsString);
          if (Ext = '*') or (Ext = '.*') or (Ext = '*.*') then
            Ext := '*'  { todos os arquivos }
          else
            while (Ext <> '') and (Ext[1] in ['.', '*']) do
              Delete(Ext, 1, 1);
          if Ext = '' then
            Continue;
          if Padrao <> '' then
            Padrao := Padrao + ';';
          Padrao := Padrao + '*.' + Ext;
        end;
      end;
      if Padrao = '' then
        Continue;
      Nome := '';
      if F.Find('name') >= 0 then
        Nome := F['name'].AsString;
      if Nome = '' then
        Nome := Padrao;
      Result := Result + Nome + ' (' + Padrao + ')'#0 + Padrao + #0;
    end;
  if Result = '' then
    Result := 'Todos os arquivos (*.*)'#0'*.*'#0;
  Result := Result + #0;
end;

procedure BorionSplitMultiSelect(const Buffer: string; Paths: TStrings);
var
  Partes: TStringList;
  I, Ini: Integer;
begin
  Paths.Clear;
  Partes := TStringList.Create;
  try
    Ini := 1;
    for I := 1 to Length(Buffer) do
      if Buffer[I] = #0 then
      begin
        if I = Ini then
          Break;  { #0#0: fim da lista }
        Partes.Add(Copy(Buffer, Ini, I - Ini));
        Ini := I + 1;
      end;
    if Partes.Count = 1 then
      Paths.Add(Partes[0])
    else
      for I := 1 to Partes.Count - 1 do
        Paths.Add(IncludeTrailingPathDelimiter(Partes[0]) + Partes[I]);
  finally
    Partes.Free;
  end;
end;

function PrimeiraExtensao(Filters: TJsonArray): string;
var
  F: string;
  I, Fim: Integer;
begin
  { do filtro montado: primeiro '*.ext' }
  Result := '';
  F := BorionDialogFilter(Filters);
  I := Pos('*.', F);
  if I = 0 then
    Exit;
  Fim := I + 2;
  while (Fim <= Length(F)) and not (F[Fim] in [';', #0, ')']) do
    Inc(Fim);
  Result := Copy(F, I + 2, Fim - I - 2);
  if Result = '*' then
    Result := '';
end;

function ArgArray(Call: TBorionCall; const Nome: string): TJsonArray;
var
  V: TJsonValue;
begin
  V := Call.Arg(Nome);
  if (V <> nil) and (V.ValueType = jvArray) then
    Result := V.AsArray
  else
    Result := nil;
end;

{ TBorionDialogPlugin }

constructor TBorionDialogPlugin.Create(AScope: TBorionScope);
begin
  inherited Create;
  FScope := AScope;
end;

function TBorionDialogPlugin.Name: string;
begin
  Result := 'dialog';
end;

procedure TBorionDialogPlugin.Install;
begin
  CommandLater('open', CmdOpen);
  CommandLater('save', CmdSave);
  CommandLater('message', CmdMessage);
  CommandLater('confirm', CmdConfirm);
end;

function TBorionDialogPlugin.Dono: HWND;
const
  GA_ROOT_ = 2;
begin
  Result := FOwnerWindow;
  if (Result = 0) and (Ipc <> nil) and (Ipc.Browser <> nil) and Ipc.Browser.HandleAllocated then
    Result := GetAncestor_(Ipc.Browser.Handle, GA_ROOT_);
  if Result = 0 then
    Result := GetActiveWindow;
end;

procedure TBorionDialogPlugin.Permitir(const Path: string; Pasta: Boolean);
begin
  if FScope = nil then
    Exit;
  if Pasta then
    FScope.AllowDir(Path, True)
  else
    FScope.AllowFile(Path);
end;

function BrowseCallback(Wnd: HWND; Msg: UINT; LParam, Data: LPARAM): Integer; stdcall;
begin
  if (Msg = BFFM_INITIALIZED_) and (Data <> 0) then
    SendMessage(Wnd, BFFM_SETSELECTIONA_, 1, Data);
  Result := 0;
end;

function EscolherPasta(Dono: HWND; const Titulo, Inicial: string): string;
var
  Info: TBrowseInfo;
  Lista: PItemIDList;
  Buf: array[0..MAX_PATH] of Char;
begin
  Result := '';
  FillChar(Info, SizeOf(Info), 0);
  Info.hwndOwner := Dono;
  Info.lpszTitle := PChar(Titulo);
  Info.ulFlags := BIF_RETURNONLYFSDIRS or BIF_NEWDIALOGSTYLE_;
  if Inicial <> '' then
  begin
    Info.lpfn := @BrowseCallback;
    Info.lParam := LPARAM(PChar(Inicial));
  end;
  Lista := SHBrowseForFolder(Info);
  if Lista = nil then
    Exit;
  try
    if SHGetPathFromIDList(Lista, Buf) then
      Result := Buf;
  finally
    CoTaskMemFree(Lista);
  end;
end;

procedure PrepararArquivo(var OFN: TOpenFilename; Dono: HWND; Call: TBorionCall;
  var Buffer, Filtro, Titulo, PastaInicial, Extensao: string);
var
  Padrao: string;
begin
  SetLength(Buffer, TAMANHO_BUFFER);
  FillChar(Buffer[1], TAMANHO_BUFFER, 0);
  Filtro := BorionDialogFilter(ArgArray(Call, 'filters'));
  Titulo := Call.ArgStr('title');
  Extensao := PrimeiraExtensao(ArgArray(Call, 'filters'));
  Padrao := Call.ArgStr('defaultPath');
  PastaInicial := '';
  if Padrao <> '' then
  begin
    if DirectoryExists(Padrao) then
      PastaInicial := Padrao
    else
    begin
      PastaInicial := ExtractFilePath(Padrao);
      Move(PChar(ExtractFileName(Padrao))^, Buffer[1], Length(ExtractFileName(Padrao)));
    end;
  end;
  FillChar(OFN, SizeOf(OFN), 0);
  OFN.lStructSize := SizeOf(OFN);
  OFN.hWndOwner := Dono;
  OFN.lpstrFilter := PChar(Filtro);
  OFN.nFilterIndex := 1;
  OFN.lpstrFile := PChar(Buffer);
  OFN.nMaxFile := TAMANHO_BUFFER;
  if Titulo <> '' then
    OFN.lpstrTitle := PChar(Titulo);
  if PastaInicial <> '' then
    OFN.lpstrInitialDir := PChar(PastaInicial);
  if Extensao <> '' then
    OFN.lpstrDefExt := PChar(Extensao);
end;

procedure TBorionDialogPlugin.CmdOpen(Call: TBorionCall);
var
  OFN: TOpenFilename;
  Buffer, Filtro, Titulo, PastaInicial, Extensao, Pasta: string;
  Caminhos: TStringList;
  I: Integer;
  Multiplo: Boolean;
begin
  if Call.ArgBool('directory') then
  begin
    Pasta := EscolherPasta(Dono, Call.ArgStr('title', 'Escolha uma pasta'), Call.ArgStr('defaultPath'));
    if Pasta = '' then
      Exit;  { cancelado: null }
    Permitir(Pasta, True);
    Call.Result.AsString := Pasta;
    Exit;
  end;

  Multiplo := Call.ArgBool('multiple');
  PrepararArquivo(OFN, Dono, Call, Buffer, Filtro, Titulo, PastaInicial, Extensao);
  OFN.Flags := OFN_EXPLORER or OFN_FILEMUSTEXIST or OFN_PATHMUSTEXIST or OFN_HIDEREADONLY;
  if Multiplo then
    OFN.Flags := OFN.Flags or OFN_ALLOWMULTISELECT;
  if not GetOpenFileName(OFN) then
    Exit;  { cancelado: null }

  Caminhos := TStringList.Create;
  try
    BorionSplitMultiSelect(Buffer, Caminhos);
    for I := 0 to Caminhos.Count - 1 do
      Permitir(Caminhos[I], False);
    if Multiplo then
      for I := 0 to Caminhos.Count - 1 do
        Call.Result.AsArray.Put(Caminhos[I])
    else if Caminhos.Count > 0 then
      Call.Result.AsString := Caminhos[0];
  finally
    Caminhos.Free;
  end;
end;

procedure TBorionDialogPlugin.CmdSave(Call: TBorionCall);
var
  OFN: TOpenFilename;
  Buffer, Filtro, Titulo, PastaInicial, Extensao: string;
begin
  PrepararArquivo(OFN, Dono, Call, Buffer, Filtro, Titulo, PastaInicial, Extensao);
  OFN.Flags := OFN_EXPLORER or OFN_OVERWRITEPROMPT or OFN_PATHMUSTEXIST or OFN_HIDEREADONLY;
  if not GetSaveFileName(OFN) then
    Exit;  { cancelado: null }
  Buffer := PChar(Buffer);
  Permitir(Buffer, False);
  Call.Result.AsString := Buffer;
end;

function Icone(Call: TBorionCall): UINT;
var
  Tipo: string;
begin
  Tipo := LowerCase(Call.ArgStr('kind', 'info'));
  if Tipo = 'warning' then
    Result := MB_ICONWARNING
  else if Tipo = 'error' then
    Result := MB_ICONERROR
  else
    Result := MB_ICONINFORMATION;
end;

{ title, ou o texto da janela dona, ou o nome do exe }
function Titulo(Call: TBorionCall; Dono: HWND): string;
var
  Buf: array[0..255] of Char;
begin
  Result := Call.ArgStr('title');
  if (Result = '') and (Dono <> 0) and (GetWindowText(Dono, Buf, SizeOf(Buf)) > 0) then
    Result := Buf;
  if Result = '' then
    Result := ChangeFileExt(ExtractFileName(ParamStr(0)), '');
end;

procedure TBorionDialogPlugin.CmdMessage(Call: TBorionCall);
var
  Janela: HWND;
begin
  Janela := Dono;
  MessageBox(Janela, PChar(Call.ArgStr('message')), PChar(Titulo(Call, Janela)), MB_OK or Icone(Call));
end;

procedure TBorionDialogPlugin.CmdConfirm(Call: TBorionCall);
var
  Botoes: UINT;
  R: Integer;
  Janela: HWND;
begin
  if SameText(Call.ArgStr('buttons'), 'yesNo') then
    Botoes := MB_YESNO
  else
    Botoes := MB_OKCANCEL;
  Janela := Dono;
  R := MessageBox(Janela, PChar(Call.ArgStr('message')), PChar(Titulo(Call, Janela)), Botoes or Icone(Call));
  Call.Result.AsBoolean := (R = IDOK) or (R = IDYES);
end;

end.
