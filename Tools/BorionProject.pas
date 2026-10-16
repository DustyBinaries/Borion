unit BorionProject;

(*
  Borion — Native Application Engine
  Projeto Borion visto pela CLI (borion build / borion dev), por convenção,
  sem arquivo de configuração:

    programa     o único .dpr da pasta
    frontend     frontend\package.json -> npm (build: frontend\dist)
                 web\                  -> estático (a própria pasta)
    assets       o {$R xxx.res} do .dpr que não é o *.res do projeto
    search path  o SearchPath do .dof (o mesmo que a IDE usa)
    porta (dev)  o "port:" do frontend\vite.config.js (padrão 5173)
    Delphi       %DELPHI%, ou o RootDir do Delphi 7 no registro

  É a estrutura que o "borion new" gera e que os exemplos usam.
*)

interface

uses
  Windows, SysUtils, Classes, Registry;

type
  EBorionProject = class(Exception);

  TBorionFrontendKind = (fkNone, fkStatic, fkNpm);

  TBorionProject = class
  private
    FDir: string;
    FProgramName: string;
    FKind: TBorionFrontendKind;
    FFrontendDir: string;
    FAssetsRes: string;
    FDevPort: Integer;
    FSearchPath: TStringList;
    FUsesBorionApi: Boolean;
    procedure LerDpr;
    procedure LerDof;
    procedure LerViteConfig;
  public
    { Dir: pasta do projeto. Levanta EBorionProject se não achar um .dpr só. }
    constructor Create(const Dir: string);
    destructor Destroy; override;
    function DprFile: string;
    function RcFile: string;
    function ResFile: string;
    function ExeFile: string;
    { Pasta que vai para o pacote de assets (web\ ou frontend\dist) }
    function DistDir: string;
    { O search path com os caminhos relativos expandidos, separados por ';' }
    function SearchPathText: string;
    { Primeira pasta do search path que tem o arquivo; '' se nenhuma }
    function FindInSearchPath(const FileName: string): string;
    property Dir: string read FDir;
    property ProgramName: string read FProgramName;
    property Kind: TBorionFrontendKind read FKind;
    { web\ ou frontend\ }
    property FrontendDir: string read FFrontendDir;
    { Nome do .res com o frontend ('' se o .dpr não incluir um) }
    property AssetsRes: string read FAssetsRes;
    property DevPort: Integer read FDevPort write FDevPort;
    property SearchPath: TStringList read FSearchPath;
    { Estático: o index.html usa o @borion/api copiado em web\borion-api\ }
    property UsesBorionApi: Boolean read FUsesBorionApi;
  end;

{ Pasta do Delphi 7: %DELPHI%, o registro (HKLM e HKCU) ou os caminhos padrão.
  Levanta EBorionProject se não achar o dcc32.exe. }
function BorionFindDelphi: string;
{ Data de modificação mais recente entre os arquivos (máscaras separadas por ';') da pasta }
function BorionNewestFile(const Dir, Masks: string): TDateTime;
{ True se Target não existe ou é mais antigo que Source }
function BorionIsStale(const Target, Source: string): Boolean;

implementation

function LerTexto(const Arquivo: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(Arquivo, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

function Idade(const Arquivo: string): TDateTime;
var
  Dia: Integer;
begin
  Dia := FileAge(Arquivo);
  if Dia = -1 then
    Result := 0
  else
    Result := FileDateToDateTime(Dia);
end;

function BorionIsStale(const Target, Source: string): Boolean;
begin
  Result := not FileExists(Target) or (Idade(Source) > Idade(Target));
end;

function BorionNewestFile(const Dir, Masks: string): TDateTime;
var
  Lista: TStringList;
  I: Integer;
  R: TSearchRec;
  T: TDateTime;
begin
  Result := 0;
  Lista := TStringList.Create;
  try
    Lista.Text := StringReplace(Masks, ';', #13#10, [rfReplaceAll]);
    for I := 0 to Lista.Count - 1 do
      if FindFirst(IncludeTrailingPathDelimiter(Dir) + Lista[I], faAnyFile and not faDirectory, R) = 0 then
      begin
        repeat
          T := FileDateToDateTime(R.Time);
          if T > Result then
            Result := T;
        until FindNext(R) <> 0;
        FindClose(R);
      end;
  finally
    Lista.Free;
  end;
end;

function BorionFindDelphi: string;
const
  CHAVE = 'Software\Borland\Delphi\7.0';
  PADROES: array[0..2] of string = ('C:\Program Files (x86)\Borland\Delphi7',
    'C:\Program Files\Borland\Delphi7', 'C:\Borland\Delphi7');
var
  R: TRegistry;
  Raiz: Integer;
  I: Integer;
begin
  Result := GetEnvironmentVariable('DELPHI');
  if (Result <> '') and FileExists(IncludeTrailingPathDelimiter(Result) + 'Bin\dcc32.exe') then
  begin
    Result := ExcludeTrailingPathDelimiter(Result);
    Exit;
  end;
  { o processo é 32 bits: HKLM\Software cai sozinho no WOW6432Node }
  R := TRegistry.Create(KEY_READ);
  try
    for Raiz := 0 to 1 do
    begin
      if Raiz = 0 then
        R.RootKey := HKEY_LOCAL_MACHINE
      else
        R.RootKey := HKEY_CURRENT_USER;
      if R.OpenKeyReadOnly(CHAVE) then
      begin
        if R.ValueExists('RootDir') then
          Result := ExcludeTrailingPathDelimiter(R.ReadString('RootDir'));
        R.CloseKey;
        if (Result <> '') and FileExists(Result + '\Bin\dcc32.exe') then
          Exit;
      end;
    end;
  finally
    R.Free;
  end;
  for I := Low(PADROES) to High(PADROES) do
    if FileExists(PADROES[I] + '\Bin\dcc32.exe') then
    begin
      Result := PADROES[I];
      Exit;
    end;
  raise EBorionProject.Create('Delphi 7 não encontrado (defina a variável DELPHI com a pasta dele)');
end;

{ TBorionProject }

constructor TBorionProject.Create(const Dir: string);
var
  R: TSearchRec;
  Dprs: TStringList;
begin
  inherited Create;
  FDir := ExcludeTrailingPathDelimiter(ExpandFileName(Dir));
  FSearchPath := TStringList.Create;
  FDevPort := 5173;
  if not DirectoryExists(FDir) then
    raise EBorionProject.CreateFmt('pasta não encontrada: %s', [FDir]);
  Dprs := TStringList.Create;
  try
    if FindFirst(FDir + '\*.dpr', faAnyFile, R) = 0 then
    begin
      repeat
        Dprs.Add(ChangeFileExt(R.Name, ''));
      until FindNext(R) <> 0;
      FindClose(R);
    end;
    if Dprs.Count = 0 then
      raise EBorionProject.CreateFmt('nenhum .dpr em %s (rode na pasta do projeto, ou crie um com "borion new")', [FDir]);
    if Dprs.Count > 1 then
      raise EBorionProject.CreateFmt('mais de um .dpr em %s: %s', [FDir, Dprs.CommaText]);
    FProgramName := Dprs[0];
  finally
    Dprs.Free;
  end;

  if FileExists(FDir + '\frontend\package.json') then
  begin
    FKind := fkNpm;
    FFrontendDir := FDir + '\frontend';
  end
  else if DirectoryExists(FDir + '\web') then
  begin
    FKind := fkStatic;
    FFrontendDir := FDir + '\web';
    FUsesBorionApi := FileExists(FFrontendDir + '\index.html') and
      (Pos('borion-api/', LerTexto(FFrontendDir + '\index.html')) > 0);
  end
  else
    FKind := fkNone;

  LerDpr;
  LerDof;
  if FKind = fkNpm then
    LerViteConfig;
end;

destructor TBorionProject.Destroy;
begin
  FSearchPath.Free;
  inherited;
end;

procedure TBorionProject.LerDpr;
var
  S, Nome: string;
  P, Q: Integer;
begin
  // {$R web.res} / {$R app.res}: o primeiro .res que não é o *.res do projeto
  S := LerTexto(DprFile);
  P := Pos('{$R ', UpperCase(S));
  while P > 0 do
  begin
    Q := P + 4;
    while (Q <= Length(S)) and (S[Q] <> '}') do
      Inc(Q);
    Nome := Trim(Copy(S, P + 4, Q - P - 4));
    if (Nome <> '') and (Nome[1] <> '*') and SameText(ExtractFileExt(Nome), '.res') then
    begin
      FAssetsRes := Nome;
      Exit;
    end;
    S := Copy(S, Q, MaxInt);
    P := Pos('{$R ', UpperCase(S));
  end;
end;

procedure TBorionProject.LerDof;
var
  Linhas, Partes: TStringList;
  I: Integer;
  Pasta: string;
begin
  if not FileExists(FDir + '\' + FProgramName + '.dof') then
    Exit;
  Linhas := TStringList.Create;
  Partes := TStringList.Create;
  try
    Linhas.LoadFromFile(FDir + '\' + FProgramName + '.dof');
    for I := 0 to Linhas.Count - 1 do
      if SameText(Copy(Linhas[I], 1, 11), 'SearchPath=') then
      begin
        { separa só no ';' (DelimitedText também separaria nos espaços) }
        Partes.Text := StringReplace(Copy(Linhas[I], 12, MaxInt), ';', #13#10, [rfReplaceAll]);
        Break;
      end;
    for I := 0 to Partes.Count - 1 do
    begin
      Pasta := Trim(Partes[I]);
      if Pasta = '' then
        Continue;
      { relativo à pasta do projeto, como na IDE }
      if not ((Length(Pasta) > 1) and ((Pasta[2] = ':') or (Pasta[1] = '\'))) then
        Pasta := FDir + '\' + Pasta;
      FSearchPath.Add(ExcludeTrailingPathDelimiter(ExpandFileName(Pasta)));
    end;
  finally
    Partes.Free;
    Linhas.Free;
  end;
end;

procedure TBorionProject.LerViteConfig;
var
  S: string;
  P, Q: Integer;
begin
  if not FileExists(FFrontendDir + '\vite.config.js') then
    Exit;
  S := LerTexto(FFrontendDir + '\vite.config.js');
  P := Pos('port:', S);
  if P = 0 then
    Exit;
  Q := P + 5;
  while (Q <= Length(S)) and (S[Q] = ' ') do
    Inc(Q);
  P := Q;
  while (Q <= Length(S)) and (S[Q] in ['0'..'9']) do
    Inc(Q);
  FDevPort := StrToIntDef(Copy(S, P, Q - P), FDevPort);
end;

function TBorionProject.DprFile: string;
begin
  Result := FDir + '\' + FProgramName + '.dpr';
end;

function TBorionProject.RcFile: string;
begin
  Result := FDir + '\' + FProgramName + '.rc';
end;

function TBorionProject.ResFile: string;
begin
  Result := FDir + '\' + FProgramName + '.res';
end;

function TBorionProject.ExeFile: string;
begin
  Result := FDir + '\' + FProgramName + '.exe';
end;

function TBorionProject.DistDir: string;
begin
  case FKind of
    fkNpm: Result := FFrontendDir + '\dist';
    fkStatic: Result := FFrontendDir;
  else
    Result := '';
  end;
end;

function TBorionProject.SearchPathText: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to FSearchPath.Count - 1 do
  begin
    if Result <> '' then
      Result := Result + ';';
    Result := Result + FSearchPath[I];
  end;
end;

function TBorionProject.FindInSearchPath(const FileName: string): string;
var
  I: Integer;
begin
  for I := 0 to FSearchPath.Count - 1 do
    if FileExists(FSearchPath[I] + '\' + FileName) then
    begin
      Result := FSearchPath[I];
      Exit;
    end;
  Result := '';
end;

end.
