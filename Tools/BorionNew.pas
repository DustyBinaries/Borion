unit BorionNew;

(*
  Borion — Native Application Engine
  borion new: cria um projeto a partir de um template (Tools\templates).

  Um template é uma pasta com os arquivos do projeto; _comum tem os que valem
  para todos (o .rc, o .dof, o .gitignore). Nos nomes, __PROGRAM__ vira o nome
  do programa; no conteúdo, {{CHAVE}} vira o valor (veja MontarValores).
  Os fontes Delphi e os .bat ficam em cp1252; o resto, em UTF-8.
*)

interface

uses
  Windows, SysUtils, Classes;

type
  EBorionNew = class(Exception);

  TBorionNewOptions = record
    Folder: string;        { pasta do projeto, criada (não pode existir com arquivos) }
    Title: string;         { '' = derivado do nome da pasta }
    Template: string;      { vanilla, vite, react }
    TemplatesDir: string;  { Borion\Tools\templates }
    BorionHome: string;    { pasta Borion (com Borion.pas) }
    WebView2Home: string;  { pasta WebView2 (com WebView2Loader.dll) }
    Json4Delphi: string;   { pasta da Jsons.pas }
    AcbrComum: string;     { pasta do ACBr.inc }
    DevPort: Integer;      { porta do Vite no dev.bat (templates vite e react) }
  end;

{ 'meu-app 2' -> 'MeuApp2': identificador válido para o program (e o exe) }
function BorionProgramName(const Name: string): string;
{ 'meu-app' -> 'Meu App' }
function BorionTitleFromName(const Name: string): string;
{ 'Meu App!' -> 'meu-app' (nome de pacote npm) }
function BorionNpmName(const Name: string): string;
{ Os templates disponíveis (pastas de TemplatesDir, sem o _comum) }
procedure BorionListTemplates(const TemplatesDir: string; List: TStrings);
{ Cria o projeto. Created recebe os arquivos criados (caminhos relativos à pasta). }
procedure BorionNewProject(const Options: TBorionNewOptions; Created: TStrings);

implementation

uses
  StrUtils;

const
  { units que o .dpr gerado usa: o program não pode ter o mesmo nome }
  RESERVADOS: array[0..13] of string = ('Borion', 'BorionIpc', 'BorionDialog', 'BorionJson',
    'BorionAssets', 'BorionScope', 'BorionPack', 'SysUtils', 'Windows', 'Classes', 'Forms',
    'System', 'Jsons', 'WebView2');
  COMUM = '_comum';

{ 'Gestão' -> 'Gestao' (letras acentuadas do cp1252) }
function SemAcento(const S: string): string;
const
  COM = 'ÀÁÂÃÄÅàáâãäåÇçÈÉÊËèéêëÌÍÎÏìíîïÑñÒÓÔÕÖòóôõöÙÚÛÜùúûüÝýÿ';
  SEM = 'AAAAAAaaaaaaCcEEEEeeeeIIIIiiiiNnOOOOOoooooUUUUuuuuYyy';
var
  I, P: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
  begin
    P := Pos(Result[I], COM);
    if P > 0 then
      Result[I] := SEM[P];
  end;
end;

function BorionProgramName(const Name: string): string;
var
  I: Integer;
  Maiuscula: Boolean;
  N: string;
begin
  N := SemAcento(Name);
  Result := '';
  Maiuscula := True;
  for I := 1 to Length(N) do
    if N[I] in ['A'..'Z', 'a'..'z', '0'..'9'] then
    begin
      if Maiuscula then
        Result := Result + UpCase(N[I])
      else
        Result := Result + N[I];
      Maiuscula := False;
    end
    else
      Maiuscula := True;  { '-', '_', espaço, acentos... separam palavras }
  if (Result = '') or (Result[1] in ['0'..'9']) then
    Result := 'App' + Result;
  for I := Low(RESERVADOS) to High(RESERVADOS) do
    if SameText(Result, RESERVADOS[I]) then
    begin
      Result := Result + 'App';
      Break;
    end;
end;

function BorionTitleFromName(const Name: string): string;
var
  I: Integer;
  Inicio: Boolean;
begin
  Result := Trim(StringReplace(StringReplace(Name, '-', ' ', [rfReplaceAll]), '_', ' ', [rfReplaceAll]));
  Inicio := True;
  for I := 1 to Length(Result) do
  begin
    if Inicio and (Result[I] in ['a'..'z']) then
      Result[I] := UpCase(Result[I]);
    Inicio := Result[I] = ' ';
  end;
  if Result = '' then
    Result := 'Meu App';
end;

function BorionNpmName(const Name: string): string;
var
  I: Integer;
  S: string;
begin
  S := LowerCase(SemAcento(Name));
  Result := '';
  for I := 1 to Length(S) do
    if S[I] in ['a'..'z', '0'..'9', '.', '_'] then
      Result := Result + S[I]
    else if (Result <> '') and (Result[Length(Result)] <> '-') then
      Result := Result + '-';
  while (Result <> '') and (Result[Length(Result)] in ['-', '.', '_']) do
    SetLength(Result, Length(Result) - 1);
  while (Result <> '') and (Result[1] in ['.', '_']) do
    Delete(Result, 1, 1);
  if Result = '' then
    Result := 'app';
end;

procedure BorionListTemplates(const TemplatesDir: string; List: TStrings);
var
  R: TSearchRec;
begin
  List.Clear;
  if FindFirst(IncludeTrailingPathDelimiter(TemplatesDir) + '*', faDirectory, R) = 0 then
  begin
    repeat
      if ((R.Attr and faDirectory) <> 0) and (R.Name[1] <> '.') and (R.Name <> COMUM) then
        List.Add(R.Name);
    until FindNext(R) <> 0;
    FindClose(R);
  end;
  TStringList(List).Sort;
end;

{ --- cópia --- }

function EhAnsi(const Arquivo: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(Arquivo));
  Result := (Ext = '.dpr') or (Ext = '.pas') or (Ext = '.rc') or (Ext = '.dof') or (Ext = '.bat');
end;

function Ler(const Arquivo: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(Arquivo, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

procedure Gravar(const Arquivo, Conteudo: string);
var
  F: TFileStream;
begin
  ForceDirectories(ExtractFileDir(Arquivo));
  F := TFileStream.Create(Arquivo, fmCreate);
  try
    if Conteudo <> '' then
      F.WriteBuffer(Conteudo[1], Length(Conteudo));
  finally
    F.Free;
  end;
end;

{ todos os arquivos de Pasta, com o caminho relativo a ela }
procedure Listar(const Pasta, Relativo: string; Arquivos: TStrings);
var
  R: TSearchRec;
begin
  if FindFirst(Pasta + Relativo + '*', faAnyFile, R) = 0 then
  begin
    repeat
      if (R.Name = '.') or (R.Name = '..') then
        Continue;
      if (R.Attr and faDirectory) <> 0 then
        Listar(Pasta, Relativo + R.Name + '\', Arquivos)
      else
        Arquivos.Add(Relativo + R.Name);
    until FindNext(R) <> 0;
    FindClose(R);
  end;
end;

function PastaVazia(const Pasta: string): Boolean;
var
  R: TSearchRec;
begin
  Result := True;
  if FindFirst(IncludeTrailingPathDelimiter(Pasta) + '*', faAnyFile, R) = 0 then
  begin
    repeat
      if (R.Name <> '.') and (R.Name <> '..') then
      begin
        Result := False;
        Break;
      end;
    until FindNext(R) <> 0;
    FindClose(R);
  end;
end;

function Barras(const Caminho: string): string;
begin
  Result := StringReplace(Caminho, '\', '/', [rfReplaceAll]);
end;

function Html(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

{ Texto para dentro de uma string JSON (sem as aspas) }
function Json(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    case S[I] of
      '"', '\': Result := Result + '\' + S[I];
      #0..#31: Result := Result + Format('\u%.4x', [Ord(S[I])]);
    else
      Result := Result + S[I];
    end;
end;

{ Placeholders: Nome=Valor (o valor em ANSI; nos arquivos UTF-8 vai convertido) }
procedure MontarValores(const O: TBorionNewOptions; const Programa, Titulo, Npm: string;
  Valores: TStrings);
var
  Comentario: string;
begin
  Comentario := StringReplace(StringReplace(Titulo, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  Valores.Add('PROGRAM=' + Programa);
  Valores.Add('TITLE=' + Titulo);
  Valores.Add('TITLE_PAS=' + StringReplace(Titulo, '''', '''''', [rfReplaceAll]));
  Valores.Add('TITLE_HTML=' + Html(Titulo));
  Valores.Add('TITLE_RC=' + StringReplace(Titulo, '"', '""', [rfReplaceAll]));
  Valores.Add('TITLE_COMMENT=' + Comentario);
  Valores.Add('TITLE_JS=' + StringReplace(StringReplace(Titulo, '\', '\\', [rfReplaceAll]),
    '''', '\''', [rfReplaceAll]));
  Valores.Add('TITLE_JSON=' + Json(Titulo));
  Valores.Add('NPM_NAME=' + Npm);
  Valores.Add('IDENTIFIER=com.exemplo.' + Npm);
  Valores.Add('BORION_HOME=' + O.BorionHome);
  Valores.Add('WEBVIEW2_HOME=' + O.WebView2Home);
  Valores.Add('JSON4DELPHI=' + O.Json4Delphi);
  Valores.Add('ACBR_COMUM=' + O.AcbrComum);
  Valores.Add('SEARCH_PATH=' + O.Json4Delphi + ';' + O.AcbrComum + ';' + O.BorionHome + ';' +
    IncludeTrailingPathDelimiter(O.BorionHome) + 'Plugins;' + O.WebView2Home);
  Valores.Add('BORION_JS=' + Barras(IncludeTrailingPathDelimiter(O.BorionHome) + 'js'));
  Valores.Add('DEV_PORT=' + IntToStr(O.DevPort));
end;

function Substituir(const Texto: string; Valores: TStrings; Utf8: Boolean; const Arquivo: string): string;
var
  I, P, Q: Integer;
  V: string;
begin
  Result := Texto;
  for I := 0 to Valores.Count - 1 do
  begin
    V := Valores.ValueFromIndex[I];
    if Utf8 then
      V := AnsiToUtf8(V);
    Result := StringReplace(Result, '{{' + Valores.Names[I] + '}}', V, [rfReplaceAll]);
  end;
  // um {{CHAVE}} que sobrou é erro no template
  P := Pos('{{', Result);
  while P > 0 do
  begin
    Q := P + 2;
    while (Q <= Length(Result)) and (Result[Q] in ['A'..'Z', '_']) do
      Inc(Q);
    if (Q > P + 2) and (Copy(Result, Q, 2) = '}}') then
      raise EBorionNew.CreateFmt('placeholder desconhecido %s em %s', [Copy(Result, P, Q - P + 2), Arquivo]);
    P := PosEx('{{', Result, P + 2);
  end;
end;

procedure BorionNewProject(const Options: TBorionNewOptions; Created: TStrings);
var
  Pasta, Nome, Programa, Titulo, Origem, Destino, Rel, Conteudo: string;
  Fontes, Arquivos, Valores, Disponiveis: TStringList;
  I, F: Integer;
begin
  Pasta := ExcludeTrailingPathDelimiter(ExpandFileName(Options.Folder));
  Nome := ExtractFileName(Pasta);
  if Nome = '' then
    raise EBorionNew.Create('informe a pasta do projeto');
  if DirectoryExists(Pasta) and not PastaVazia(Pasta) then
    raise EBorionNew.CreateFmt('a pasta %s já existe e não está vazia', [Pasta]);
  if not DirectoryExists(IncludeTrailingPathDelimiter(Options.TemplatesDir) + Options.Template) then
  begin
    Disponiveis := TStringList.Create;
    try
      BorionListTemplates(Options.TemplatesDir, Disponiveis);
      Disponiveis.Delimiter := ',';
      raise EBorionNew.CreateFmt('template desconhecido "%s" (disponíveis: %s)',
        [Options.Template, StringReplace(Disponiveis.DelimitedText, ',', ', ', [rfReplaceAll])]);
    finally
      Disponiveis.Free;
    end;
  end;

  Programa := BorionProgramName(Nome);
  Titulo := Options.Title;
  if Titulo = '' then
    Titulo := BorionTitleFromName(Nome);

  Fontes := TStringList.Create;    { relativo -> pasta de origem (o template vence o _comum) }
  Arquivos := TStringList.Create;
  Valores := TStringList.Create;
  try
    MontarValores(Options, Programa, Titulo, BorionNpmName(Nome), Valores);
    for F := 0 to 1 do
    begin
      if F = 0 then
        Origem := IncludeTrailingPathDelimiter(Options.TemplatesDir) + COMUM + '\'
      else
        Origem := IncludeTrailingPathDelimiter(Options.TemplatesDir) + Options.Template + '\';
      Arquivos.Clear;
      Listar(Origem, '', Arquivos);
      for I := 0 to Arquivos.Count - 1 do
        Fontes.Values[Arquivos[I]] := Origem;
    end;
    Fontes.Sort;
    for I := 0 to Fontes.Count - 1 do
    begin
      Rel := Fontes.Names[I];
      Conteudo := Substituir(Ler(Fontes.ValueFromIndex[I] + Rel), Valores, not EhAnsi(Rel), Rel);
      Destino := StringReplace(Rel, '__PROGRAM__', Programa, [rfReplaceAll]);
      Gravar(Pasta + '\' + Destino, Conteudo);
      Created.Add(Destino);
    end;
    if Created is TStringList then
      TStringList(Created).Sort;  { pelos nomes finais, para mostrar ao usuário }
  finally
    Valores.Free;
    Arquivos.Free;
    Fontes.Free;
  end;
end;

end.
