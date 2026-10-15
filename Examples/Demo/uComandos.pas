unit uComandos;

{ Comandos da demonstração, chamados pela página com borion.invoke(...).
  São procedures simples (RegisterCommandProc): o "backend" não precisa de form. }

interface

uses
  BorionIpc;

procedure RegistrarComandos(Ipc: TBorionIpc);

implementation

uses
  Windows, SysUtils, Classes, Jsons, WebView2;

// invoke('somar', {a, b}) -> número
procedure CmdSomar(Call: TBorionCall);
begin
  Call.Result.AsNumber := Call.ArgNum('a') + Call.ArgNum('b');
end;

// invoke('saudacao', {nome}) -> texto com acentos e aspas tipográficas (teste de Unicode)
procedure CmdSaudacao(Call: TBorionCall);
var
  Nome: string;
begin
  Nome := Trim(Call.ArgStr('nome'));
  if Nome = '' then
    raise EBorionError.Create('VALIDACAO', 'Informe o nome.');
  Call.Result.AsString := 'Olá, ' + Nome + '! “Saudações” do Delphi 7 — Borion ' +
    BORION_VERSION + ' (€ 1,00)';
end;

// invoke('info') -> objeto
procedure CmdInfo(Call: TBorionCall);
var
  O: TJsonObject;
begin
  O := Call.Result.AsObject;
  O.Put('borion', BORION_VERSION);
  O.Put('delphi', '7');
  O.Put('executavel', ParamStr(0));
  O.Put('webview2', string(GetWebView2RuntimeVersion));
  O.Put('pid', Integer(GetCurrentProcessId));
  O.Put('hora', FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
  O.Put('origem', string(Call.Source));
end;

// invoke('listarArquivos', {pasta?}) -> array de {nome, pasta, tamanho}
procedure CmdListarArquivos(Call: TBorionCall);
var
  Pasta: string;
  SR: TSearchRec;
  Lista: TJsonArray;
  Item: TJsonObject;
begin
  Pasta := Call.ArgStr('pasta', ExtractFilePath(ParamStr(0)));
  if not DirectoryExists(Pasta) then
    raise EBorionError.Create('NAO_ENCONTRADO', 'Pasta não existe: ' + Pasta);
  Lista := Call.Result.AsArray;
  if FindFirst(IncludeTrailingPathDelimiter(Pasta) + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') then
      begin
        Item := Lista.Add.AsObject;
        Item.Put('nome', SR.Name);
        Item.Put('pasta', (SR.Attr and faDirectory) <> 0);
        Item.Put('tamanho', SR.Size);
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

// invoke('falhar') -> Promise rejeitada com error.code = 'DEMO'
procedure CmdFalhar(Call: TBorionCall);
begin
  raise EBorionError.Create('DEMO', 'Falha proposital no Delphi');
end;

{ --- comando assíncrono --------------------------------------------------- }

type
  { Trabalho numa thread: emite progresso e resolve a chamada no fim.
    Resolve, Reject e Emit podem ser chamados de qualquer thread. }
  TTarefaLonga = class(TThread)
  private
    FCall: TBorionCall;
    FPassos: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(ACall: TBorionCall; APassos: Integer);
  end;

constructor TTarefaLonga.Create(ACall: TBorionCall; APassos: Integer);
begin
  inherited Create(True);
  FCall := ACall;
  FPassos := APassos;
  FreeOnTerminate := True;
end;

procedure TTarefaLonga.Execute;
var
  I: Integer;
begin
  for I := 1 to FPassos do
  begin
    Sleep(250);
    if FCall.Ipc <> nil then
      FCall.Ipc.EmitJson('tarefa:progresso', Format('{"passo":%d,"total":%d}', [I, FPassos]));
  end;
  FCall.Result.AsObject.Put('mensagem', 'Tarefa concluída numa thread');
  FCall.Result.AsObject.Put('passos', FPassos);
  FCall.Resolve;
end;

// invoke('tarefaLonga', {passos?}) -> resolve depois; emite 'tarefa:progresso'
procedure CmdTarefaLonga(Call: TBorionCall);
var
  Passos: Integer;
begin
  Passos := Call.ArgInt('passos', 10);
  if (Passos < 1) or (Passos > 100) then
    raise EBorionError.Create('VALIDACAO', 'passos deve estar entre 1 e 100');
  Call.Defer;
  TTarefaLonga.Create(Call, Passos).Resume;
end;

procedure RegistrarComandos(Ipc: TBorionIpc);
begin
  Ipc.RegisterCommandProc('somar', CmdSomar);
  Ipc.RegisterCommandProc('saudacao', CmdSaudacao);
  Ipc.RegisterCommandProc('info', CmdInfo);
  Ipc.RegisterCommandProc('listarArquivos', CmdListarArquivos);
  Ipc.RegisterCommandProc('falhar', CmdFalhar);
  Ipc.RegisterCommandProc('tarefaLonga', CmdTarefaLonga);
end;

end.
