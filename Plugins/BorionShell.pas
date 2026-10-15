unit BorionShell;

(*
  Borion — Native Application Engine
  Plugin "shell": abrir URLs e arquivos no programa padrão do Windows.

    Ipc.AddPlugin(TBorionShellPlugin.Create(Scope));   // Scope: opcional

  Comandos:
    shell:open         {target}           URL ou arquivo
    shell:showInFolder {path, baseDir?}   abre o Explorer com o item selecionado

  Política (o JS da página não deve conseguir executar programas):
    - URLs: só esquemas de AllowedSchemes (padrão: https, http, mailto).
    - Arquivos e pastas: só dentro do escopo (sem escopo, nenhum), e nunca
      executáveis ou scripts (.exe, .bat, .ps1, .js, .lnk, .msi...).
    Recusas: FORBIDDEN_URL, FORBIDDEN_PATH, FORBIDDEN_FILE_TYPE.
*)

interface

uses
  Windows, SysUtils, Classes, BorionIpc, BorionScope;

type
  { Quem executa de fato (trocável nos testes). Verb '' = padrão. }
  TBorionShellExecute = procedure(const Verb, Target, Params: string) of object;

  TBorionShellPlugin = class(TBorionPlugin)
  private
    FScope: TBorionScope;
    FAllowedSchemes: TStringList;
    FOnExecute: TBorionShellExecute;
    procedure Executar(const Verb, Target, Params: string);
    procedure CmdOpen(Call: TBorionCall);
    procedure CmdShowInFolder(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    { AScope não é liberado pelo plugin (normalmente é o do TBorionFsPlugin) }
    constructor Create(AScope: TBorionScope = nil);
    destructor Destroy; override;
    function Name: string; override;
    { Levanta EBorionError se o alvo não puder ser aberto; devolve o alvo normalizado }
    function CheckTarget(const Target: string; out IsUrl: Boolean): string;
    property AllowedSchemes: TStringList read FAllowedSchemes;
    property Scope: TBorionScope read FScope write FScope;
    property OnExecute: TBorionShellExecute read FOnExecute write FOnExecute;
  end;

{ Extensão que executa código ao ser aberta (.exe, .bat, .js, .lnk...) }
function BorionIsExecutableFile(const Path: string): Boolean;
{ 'https://x' -> 'https'; '' se não houver esquema (ou for uma letra de drive) }
function BorionUrlScheme(const Target: string): string;

implementation

uses
  ShellAPI;

const
  EXECUTAVEIS: array[0..35] of string = ('.exe', '.com', '.bat', '.cmd', '.ps1', '.psm1', '.psd1',
    '.vbs', '.vbe', '.js', '.jse', '.wsf', '.wsh', '.msi', '.msp', '.mst', '.scr', '.pif', '.lnk',
    '.url', '.hta', '.cpl', '.reg', '.jar', '.application', '.appref-ms', '.gadget', '.inf',
    '.sct', '.chm', '.dll', '.sys', '.ocx', '.msc', '.settingcontent-ms', '.library-ms');

function BorionIsExecutableFile(const Path: string): Boolean;
var
  S, Ext: string;
  I: Integer;
begin
  { pontos e espaços no fim são ignorados pelo Windows ('a.exe. ' abre a.exe) }
  S := StringReplace(Path, '/', '\', [rfReplaceAll]);
  while (S <> '') and (S[Length(S)] in ['.', ' ']) do
    Delete(S, Length(S), 1);
  Ext := LowerCase(ExtractFileExt(S));
  for I := Low(EXECUTAVEIS) to High(EXECUTAVEIS) do
    if Ext = EXECUTAVEIS[I] then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

function BorionUrlScheme(const Target: string): string;
var
  I: Integer;
begin
  Result := '';
  I := Pos(':', Target);
  if I <= 2 then
    Exit;  { sem ':' ou 'C:' (drive) }
  Result := LowerCase(Copy(Target, 1, I - 1));
  for I := 1 to Length(Result) do
    if not (Result[I] in ['a'..'z', '0'..'9', '+', '-', '.']) then
    begin
      Result := '';
      Exit;
    end;
end;

{ TBorionShellPlugin }

constructor TBorionShellPlugin.Create(AScope: TBorionScope);
begin
  inherited Create;
  FScope := AScope;
  FAllowedSchemes := TStringList.Create;
  FAllowedSchemes.Add('https');
  FAllowedSchemes.Add('http');
  FAllowedSchemes.Add('mailto');
end;

destructor TBorionShellPlugin.Destroy;
begin
  FAllowedSchemes.Free;
  inherited Destroy;
end;

function TBorionShellPlugin.Name: string;
begin
  Result := 'shell';
end;

procedure TBorionShellPlugin.Install;
begin
  Command('open', CmdOpen);
  Command('showInFolder', CmdShowInFolder);
end;

procedure TBorionShellPlugin.Executar(const Verb, Target, Params: string);
var
  R: HINST;
  V, P: PChar;
begin
  if Assigned(FOnExecute) then
  begin
    FOnExecute(Verb, Target, Params);
    Exit;
  end;
  V := nil;
  if Verb <> '' then
    V := PChar(Verb);
  P := nil;
  if Params <> '' then
    P := PChar(Params);
  R := ShellExecute(0, V, PChar(Target), P, nil, SW_SHOWNORMAL);
  if R <= 32 then
    raise EBorionError.Create('IO_ERROR', Format('não foi possível abrir "%s" (código %d)', [Target, R]));
end;

function TBorionShellPlugin.CheckTarget(const Target: string; out IsUrl: Boolean): string;
var
  Esquema: string;
  I: Integer;
begin
  Result := Trim(Target);
  if Result = '' then
    raise EBorionError.Create('INVALID_ARGS', 'alvo vazio');
  for I := 1 to Length(Result) do
    if Result[I] < ' ' then
      raise EBorionError.Create('FORBIDDEN_URL', 'caractere de controle no alvo');
  Esquema := BorionUrlScheme(Result);
  IsUrl := Esquema <> '';
  if IsUrl then
  begin
    if FAllowedSchemes.IndexOf(Esquema) < 0 then
      raise EBorionError.Create('FORBIDDEN_URL', 'esquema não permitido: ' + Esquema);
    if ((Esquema = 'http') or (Esquema = 'https')) and (Copy(Result, Length(Esquema) + 2, 2) <> '//') then
      raise EBorionError.Create('FORBIDDEN_URL', 'URL inválida: ' + Result);
    Exit;
  end;
  { arquivo ou pasta }
  if FScope = nil then
    raise EBorionError.Create('FORBIDDEN_PATH', 'abrir arquivos exige um escopo');
  Result := FScope.Check(Result);
  if BorionIsExecutableFile(Result) then
    raise EBorionError.Create('FORBIDDEN_FILE_TYPE', 'tipo de arquivo executável: ' + ExtractFileName(Result));
end;

procedure TBorionShellPlugin.CmdOpen(Call: TBorionCall);
var
  Alvo: string;
  IsUrl: Boolean;
begin
  Alvo := CheckTarget(Call.ArgStr('target'), IsUrl);
  if not IsUrl and not FileExists(Alvo) and not DirectoryExists(Alvo) then
    raise EBorionError.Create('NOT_FOUND', 'não encontrado: ' + Alvo);
  Executar('open', Alvo, '');
end;

procedure TBorionShellPlugin.CmdShowInFolder(Call: TBorionCall);
var
  Path: string;
begin
  if FScope = nil then
    raise EBorionError.Create('FORBIDDEN_PATH', 'showInFolder exige um escopo');
  Path := FScope.Check(Call.ArgStr('path'), Call.ArgStr('baseDir'));
  if not FileExists(Path) and not DirectoryExists(Path) then
    raise EBorionError.Create('NOT_FOUND', 'não encontrado: ' + Path);
  { o caminho já foi validado (sem aspas nem caracteres especiais) }
  Executar('open', 'explorer.exe', '/select,"' + Path + '"');
end;

end.
