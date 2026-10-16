program borion;

(*
  Borion — Native Application Engine: ferramenta de linha de comando.

    borion pack <pasta> <saida.res> [--no-compress] [--name NOME] [--verbose]
        Empacota a pasta (ex.: o dist/ do Vite) num .res com o recurso
        BORION_ASSETS, pronto para {$R saida.res} no projeto.

    borion list <arquivo.res> [--name NOME]
        Lista o conteúdo de um pacote.

    borion new <pasta> [--template vanilla|vite|react] [--title "Título"] [--port 5173]
        Cria um app Borion: o .dpr com o TBorionBuilder, a interface e os
        scripts de build, a partir de Tools\templates.

    borion build [pasta]
        Compila o projeto: frontend, pacote de assets, recursos e o exe.

    borion dev [pasta] [--port 5173] [--no-watch]
        Modo dev: o app ligado ao servidor do Vite (ou à pasta web\, com
        recarga automática); recompila e reabre quando o Delphi muda.

    borion version
*)

{$APPTYPE CONSOLE}

uses
  Windows,
  SysUtils,
  Classes,
  BorionPack in '..\BorionPack.pas',
  BorionNew in 'BorionNew.pas',
  BorionProject in 'BorionProject.pas',
  BorionBuild in 'BorionBuild.pas';

const
  VERSAO = '0.3.0';

var
  Args: TStringList;

{ o console usa a página OEM (ex.: 850); o Delphi 7 trabalha em ANSI (cp1252) }
function Oem(const S: string): string;
begin
  SetLength(Result, Length(S));
  if S <> '' then
    CharToOemBuff(PChar(S), PChar(Result), Length(S));
end;

procedure Ajuda;
begin
  Writeln('Borion ' + VERSAO + ' - Native Application Engine');
  Writeln;
  Writeln('Uso:');
  Writeln('  borion pack <pasta> <saida.res> [--no-compress] [--name NOME] [--verbose]');
  Writeln('      Empacota os arquivos da pasta num .res com o recurso ' + BORION_PACK_RESOURCE + '.');
  Writeln('  borion list <arquivo.res> [--name NOME]');
  Writeln('      Lista o conteudo de um pacote.');
  Writeln('  borion new <pasta> [--template vanilla|vite|react] [--title "Titulo"] [--port 5173]');
  Writeln('      Cria um app Borion (padrao: template vanilla, HTML/JS puro, sem Node).');
  Writeln('  borion build [pasta]');
  Writeln('      Compila o projeto (frontend, assets, recursos e o exe).');
  Writeln('  borion dev [pasta] [--port 5173] [--no-watch]');
  Writeln('      Abre o app em modo dev; recompila e reabre quando o Delphi muda.');
  Writeln('  borion version');
end;

function TemOpcao(const Nome: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to Args.Count - 1 do
    if SameText(Args[I], Nome) then
    begin
      Result := True;
      Exit;
    end;
end;

function ValorOpcao(const Nome, Padrao: string): string;
var
  I: Integer;
begin
  Result := Padrao;
  for I := 0 to Args.Count - 2 do
    if SameText(Args[I], Nome) then
    begin
      Result := Args[I + 1];
      Exit;
    end;
end;

{ argumentos posicionais (sem as opções e seus valores) }
function Posicional(Indice: Integer): string;
var
  I, N: Integer;
begin
  Result := '';
  N := 0;
  I := 0;
  while I < Args.Count do
  begin
    if Copy(Args[I], 1, 2) = '--' then
    begin
      if SameText(Args[I], '--name') or SameText(Args[I], '--template') or
        SameText(Args[I], '--title') or SameText(Args[I], '--port') then
        Inc(I);  { pula o valor }
    end
    else
    begin
      if N = Indice then
      begin
        Result := Args[I];
        Exit;
      end;
      Inc(N);
    end;
    Inc(I);
  end;
end;

function Kb(Bytes: Int64): string;
begin
  Result := FormatFloat('#,##0.0', Bytes / 1024) + ' KB';
end;

function CmdPack: Integer;
var
  Pasta, Saida: string;
  Opcoes: TBorionPackOptions;
  Pacote: TMemoryStream;
  Log: TStringList;
  N, I: Integer;
  Pack: TBorionPack;
  Original: Int64;
begin
  Pasta := Posicional(1);
  Saida := Posicional(2);
  if (Pasta = '') or (Saida = '') then
  begin
    Ajuda;
    Result := 2;
    Exit;
  end;
  Opcoes.Compress := not TemOpcao('--no-compress');
  Pacote := TMemoryStream.Create;
  Log := TStringList.Create;
  try
    N := BorionPackFolder(Pasta, Pacote, Opcoes, Log);
    if TemOpcao('--verbose') then
      for I := 0 to Log.Count - 1 do
        Writeln('  ', Oem(Log[I]));
    { relê o pacote gerado: garante que ele é válido antes de gravar }
    Pack := TBorionPack.FromStream(Pacote);
    try
      Original := 0;
      for I := 0 to Pack.Count - 1 do
        Inc(Original, Pack[I].OriginalSize);
    finally
      Pack.Free;
    end;
    ForceDirectories(ExtractFilePath(ExpandFileName(Saida)));
    BorionWriteRes(Saida, ValorOpcao('--name', BORION_PACK_RESOURCE), Pacote);
    Writeln(Oem(Format('%d arquivo(s): %s -> %s em %s', [N, Kb(Original), Kb(Pacote.Size), Saida])));
    Result := 0;
  finally
    Log.Free;
    Pacote.Free;
  end;
end;

function CmdList: Integer;
var
  Arquivo, Nome: string;
  Dados: TMemoryStream;
  Pack: TBorionPack;
  I: Integer;
  E: TBorionPackEntry;
  Total: Int64;
begin
  Result := 1;
  Arquivo := Posicional(1);
  if Arquivo = '' then
  begin
    Ajuda;
    Result := 2;
    Exit;
  end;
  Nome := ValorOpcao('--name', BORION_PACK_RESOURCE);
  Dados := TMemoryStream.Create;
  try
    if not BorionReadRes(Arquivo, Nome, Dados) then
      raise EBorionPack.CreateFmt('recurso %s não encontrado em %s', [Nome, Arquivo]);
    Pack := TBorionPack.FromStream(Dados);
    try
      Total := 0;
      for I := 0 to Pack.Count - 1 do
      begin
        E := Pack[I];
        Inc(Total, E.OriginalSize);
        Writeln(Oem(Format('  %-50s %10d %10d %s', [Utf8ToAnsi(E.Path), E.OriginalSize, E.StoredSize,
          Copy('zlib', 1, 4 * Ord(E.Flags and BORION_PACK_FLAG_ZLIB <> 0))])));
      end;
      Writeln(Oem(Format('%d arquivo(s), %s (%s no pacote)', [Pack.Count, Kb(Total), Kb(Dados.Size)])));
    finally
      Pack.Free;
    end;
    Result := 0;
  finally
    Dados.Free;
  end;
end;


{ pasta da variável de ambiente, ou o padrão }
function Ambiente(const Nome, Padrao: string): string;
begin
  Result := GetEnvironmentVariable(Nome);
  if Result = '' then
    Result := Padrao;
end;

procedure Saida(const Line: string);
begin
  Writeln(Oem(Line));
  Flush(Output);  { antes da saída dos processos filhos (npm, dcc32), que escrevem direto no console }
end;

{ pasta do Borion (com Borion.pas e js\): BORION_HOME ou a pasta acima do borion.exe }
function BorionHome: string;
begin
  Result := Ambiente('BORION_HOME', ExpandFileName(ExtractFilePath(ParamStr(0)) + '..'));
  Result := ExcludeTrailingPathDelimiter(Result);
end;

function PastaDoProjeto: string;
begin
  Result := Posicional(1);
  if Result = '' then
    Result := GetCurrentDir;
end;

function CmdBuild: Integer;
var
  P: TBorionProject;
begin
  P := TBorionProject.Create(PastaDoProjeto);
  try
    BorionBuildProject(P, BorionHome);
    Result := 0;
  finally
    P.Free;
  end;
end;

function CmdDev: Integer;
var
  P: TBorionProject;
  O: TBorionDevOptions;
begin
  O.Port := StrToIntDef(ValorOpcao('--port', '0'), -1);
  if (O.Port < 0) or (O.Port > 65535) then
    raise EBorionProject.Create('--port deve ser um número de 1 a 65535');
  O.Watch := not TemOpcao('--no-watch');
  P := TBorionProject.Create(PastaDoProjeto);
  try
    BorionDevProject(P, BorionHome, O);
    Result := 0;
  finally
    P.Free;
  end;
end;

function CmdNew: Integer;
var
  O: TBorionNewOptions;
  Criados: TStringList;
  Aqui: string;
  I: Integer;
  Vite: Boolean;
begin
  if Posicional(1) = '' then
  begin
    Ajuda;
    Result := 2;
    Exit;
  end;
  { o borion.exe fica em Borion\Tools: o resto se acha a partir dele }
  Aqui := ExtractFilePath(ParamStr(0));
  O.Folder := Posicional(1);
  O.Title := ValorOpcao('--title', '');
  O.Template := LowerCase(ValorOpcao('--template', 'vanilla'));
  O.TemplatesDir := Aqui + 'templates';
  O.BorionHome := Ambiente('BORION_HOME', ExpandFileName(Aqui + '..'));
  O.WebView2Home := Ambiente('WEBVIEW2_HOME', ExpandFileName(O.BorionHome + '\..\WebView2'));
  O.Json4Delphi := Ambiente('JSON4DELPHI', 'C:\dev\lib\ACBr\Fontes\Terceiros\json4delphi\src');
  O.AcbrComum := Ambiente('ACBR_COMUM', 'C:\dev\lib\ACBr\Fontes\ACBrComum');
  O.DevPort := StrToIntDef(ValorOpcao('--port', '5173'), 0);
  if (O.DevPort < 1) or (O.DevPort > 65535) then
    raise EBorionNew.Create('--port deve ser um número de 1 a 65535');
  if not FileExists(O.BorionHome + '\Borion.pas') then
    raise EBorionNew.CreateFmt('Borion.pas não encontrado em %s (defina BORION_HOME)', [O.BorionHome]);
  if not FileExists(O.WebView2Home + '\WebView2Loader.dll') then
    Writeln(Oem('aviso: WebView2Loader.dll não encontrado em ' + O.WebView2Home + ' (defina WEBVIEW2_HOME)'));
  if not FileExists(O.Json4Delphi + '\Jsons.pas') then
    Writeln(Oem('aviso: Jsons.pas não encontrada em ' + O.Json4Delphi + ' (defina JSON4DELPHI antes do build.bat)'));

  Criados := TStringList.Create;
  try
    BorionNewProject(O, Criados);
    Writeln(Oem(Format('Projeto criado em %s (template %s):', [ExpandFileName(O.Folder), O.Template])));
    for I := 0 to Criados.Count - 1 do
      Writeln('  ', Oem(Criados[I]));
    Vite := FileExists(IncludeTrailingPathDelimiter(ExpandFileName(O.Folder)) + 'dev.bat');
    Writeln;
    Writeln('Proximos passos:');
    Writeln(Oem('  cd "' + O.Folder + '"'));
    Writeln('  borion build             compila (a interface vai dentro do exe); ou build.bat');
    if Vite then
      Writeln('  borion dev               o app em modo dev, recarregando sozinho; ou dev.bat');
    Result := 0;
  finally
    Criados.Free;
  end;
end;

var
  I: Integer;
  Comando: string;
begin
  BorionOut := Saida;
  Args := TStringList.Create;
  try
    for I := 1 to ParamCount do
      Args.Add(ParamStr(I));
    Comando := LowerCase(Posicional(0));
    try
      if Comando = 'pack' then
        ExitCode := CmdPack
      else if Comando = 'list' then
        ExitCode := CmdList
      else if Comando = 'new' then
        ExitCode := CmdNew
      else if Comando = 'build' then
        ExitCode := CmdBuild
      else if Comando = 'dev' then
        ExitCode := CmdDev
      else if (Comando = 'version') or TemOpcao('--version') then
        Writeln('borion ' + VERSAO)
      else
      begin
        Ajuda;
        if Comando <> '' then
          ExitCode := 2;
      end;
    except
      on E: Exception do
      begin
        Writeln(ErrOutput, Oem('erro: ' + E.Message));
        ExitCode := 1;
      end;
    end;
  finally
    Args.Free;
  end;
end.
