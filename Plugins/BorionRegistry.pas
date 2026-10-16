unit BorionRegistry;

{ Borion — Native Application Engine
  Registro do Windows com Unicode (APIs W): o TRegistry do Delphi 7 é ANSI e
  estragaria um caminho de exe com caracteres fora da página de código.
  Usado pelos plugins deep-link e autostart. }

interface

uses
  Windows, SysUtils;

{ False se a chave ou o valor não existir }
function BorionRegRead(Root: HKEY; const Key, Name: WideString; out Value: WideString): Boolean;
{ REG_SZ; cria a chave se preciso. Levanta EOSError se falhar. }
procedure BorionRegWrite(Root: HKEY; const Key, Name, Value: WideString);
function BorionRegReadBinary(Root: HKEY; const Key, Name: WideString; out Data: string): Boolean;
procedure BorionRegWriteBinary(Root: HKEY; const Key, Name: WideString; const Data: string);
{ True se apagou }
function BorionRegDeleteValue(Root: HKEY; const Key, Name: WideString): Boolean;
{ Apaga a chave e tudo abaixo dela; True se apagou }
function BorionRegDeleteTree(Root: HKEY; const Key: WideString): Boolean;
function BorionRegKeyExists(Root: HKEY; const Key: WideString): Boolean;
{ Caminho completo do exe, com Unicode }
function BorionExePathW: WideString;

implementation

function SHDeleteKeyW(Key: HKEY; SubKey: PWideChar): DWORD; stdcall; external 'shlwapi.dll';

function Abrir(Root: HKEY; const Key: WideString; Acesso: REGSAM; out H: HKEY): Boolean;
begin
  Result := RegOpenKeyExW(Root, PWideChar(Key), 0, Acesso, H) = ERROR_SUCCESS;
end;

function Criar(Root: HKEY; const Key: WideString): HKEY;
var
  R: Longint;
begin
  R := RegCreateKeyExW(Root, PWideChar(Key), 0, nil, 0, KEY_WRITE, nil, Result, nil);
  if R <> ERROR_SUCCESS then
    raise EOSError.Create(SysErrorMessage(R));
end;

function BorionRegRead(Root: HKEY; const Key, Name: WideString; out Value: WideString): Boolean;
var
  H: HKEY;
  Tipo, Tamanho: DWORD;
begin
  Value := '';
  Result := False;
  if not Abrir(Root, Key, KEY_READ, H) then
    Exit;
  try
    Tamanho := 0;
    if (RegQueryValueExW(H, PWideChar(Name), nil, @Tipo, nil, @Tamanho) <> ERROR_SUCCESS) or
      ((Tipo <> REG_SZ) and (Tipo <> REG_EXPAND_SZ)) then
      Exit;
    SetLength(Value, Tamanho div SizeOf(WideChar));
    if (Tamanho > 0) and (RegQueryValueExW(H, PWideChar(Name), nil, nil, PByte(Pointer(Value)), @Tamanho) <> ERROR_SUCCESS) then
      Exit;
    { o valor gravado pode ou não ter o #0 final }
    while (Length(Value) > 0) and (Value[Length(Value)] = #0) do
      SetLength(Value, Length(Value) - 1);
    Result := True;
  finally
    RegCloseKey(H);
  end;
end;

procedure BorionRegWrite(Root: HKEY; const Key, Name, Value: WideString);
var
  H: HKEY;
  R: Longint;
  V: WideString;
begin
  H := Criar(Root, Key);
  try
    V := Value + WideChar(0);
    R := RegSetValueExW(H, PWideChar(Name), 0, REG_SZ, PWideChar(V), Length(V) * SizeOf(WideChar));
    if R <> ERROR_SUCCESS then
      raise EOSError.Create(SysErrorMessage(R));
  finally
    RegCloseKey(H);
  end;
end;

function BorionRegReadBinary(Root: HKEY; const Key, Name: WideString; out Data: string): Boolean;
var
  H: HKEY;
  Tipo, Tamanho: DWORD;
begin
  Data := '';
  Result := False;
  if not Abrir(Root, Key, KEY_READ, H) then
    Exit;
  try
    Tamanho := 0;
    if (RegQueryValueExW(H, PWideChar(Name), nil, @Tipo, nil, @Tamanho) <> ERROR_SUCCESS) or
      (Tipo <> REG_BINARY) then
      Exit;
    SetLength(Data, Tamanho);
    Result := (Tamanho = 0) or
      (RegQueryValueExW(H, PWideChar(Name), nil, nil, PByte(Pointer(Data)), @Tamanho) = ERROR_SUCCESS);
  finally
    RegCloseKey(H);
  end;
end;

procedure BorionRegWriteBinary(Root: HKEY; const Key, Name: WideString; const Data: string);
var
  H: HKEY;
  R: Longint;
begin
  H := Criar(Root, Key);
  try
    R := RegSetValueExW(H, PWideChar(Name), 0, REG_BINARY, Pointer(Data), Length(Data));
    if R <> ERROR_SUCCESS then
      raise EOSError.Create(SysErrorMessage(R));
  finally
    RegCloseKey(H);
  end;
end;

function BorionRegDeleteValue(Root: HKEY; const Key, Name: WideString): Boolean;
var
  H: HKEY;
begin
  Result := False;
  if not Abrir(Root, Key, KEY_WRITE, H) then
    Exit;
  try
    Result := RegDeleteValueW(H, PWideChar(Name)) = ERROR_SUCCESS;
  finally
    RegCloseKey(H);
  end;
end;

function BorionRegDeleteTree(Root: HKEY; const Key: WideString): Boolean;
begin
  Result := SHDeleteKeyW(Root, PWideChar(Key)) = ERROR_SUCCESS;
end;

function BorionRegKeyExists(Root: HKEY; const Key: WideString): Boolean;
var
  H: HKEY;
begin
  Result := Abrir(Root, Key, KEY_READ, H);
  if Result then
    RegCloseKey(H);
end;

function BorionExePathW: WideString;
var
  Buf: array[0..32767] of WideChar;
  N: DWORD;
begin
  N := GetModuleFileNameW(0, Buf, Length(Buf));
  SetString(Result, Buf, N);
end;

end.
