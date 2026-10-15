unit uComandos;

{ Comandos Delphi chamados pelo frontend React com invoke() do @borion/api. }

interface

uses
  BorionIpc;

procedure RegistrarComandos(Ipc: TBorionIpc);

implementation

uses
  Windows, SysUtils, Classes, Jsons, WebView2;

type
  TClienteFicticio = record
    Id: Integer;
    Nome, Cidade: string;
    Desde: Integer;
  end;

const
  CLIENTES: array[0..4] of TClienteFicticio = (
    (Id: 1; Nome: 'Padaria São João'; Cidade: 'Curitiba'; Desde: 2009),
    (Id: 2; Nome: 'Mercado Bom Preço'; Cidade: 'Londrina'; Desde: 2014),
    (Id: 3; Nome: 'Farmácia Saúde'; Cidade: 'Maringá'; Desde: 2017),
    (Id: 4; Nome: 'Oficina do Zé'; Cidade: 'Cascavel'; Desde: 2020),
    (Id: 5; Nome: 'Açougue Três Irmãos'; Cidade: 'Ponta Grossa'; Desde: 2022));

// invoke('info') -> objeto
procedure CmdInfo(Call: TBorionCall);
var
  O: TJsonObject;
begin
  O := Call.Result.AsObject;
  O.Put('borion', BORION_VERSION);
  O.Put('delphi', '7');
  O.Put('webview2', string(GetWebView2RuntimeVersion));
  O.Put('executavel', ExtractFileName(ParamStr(0)));
  O.Put('origem', string(Call.Source));
  O.Put('hora', FormatDateTime('dd/mm/yyyy hh:nn:ss', Now));
end;

// invoke('saudacao', {nome}) -> texto
procedure CmdSaudacao(Call: TBorionCall);
var
  Nome: string;
begin
  Nome := Trim(Call.ArgStr('nome'));
  if Nome = '' then
    raise EBorionError.Create('VALIDACAO', 'Informe o nome.');
  Call.Result.AsString := 'Olá, ' + Nome + '! Esta resposta veio do Delphi 7.';
end;

procedure PutCliente(O: TJsonObject; const C: TClienteFicticio);
begin
  O.Put('id', C.Id);
  O.Put('nome', C.Nome);
  O.Put('cidade', C.Cidade);
  O.Put('desde', C.Desde);
end;

// invoke('listarClientes') -> array
procedure CmdListarClientes(Call: TBorionCall);
var
  I: Integer;
begin
  for I := Low(CLIENTES) to High(CLIENTES) do
    PutCliente(Call.Result.AsArray.Add.AsObject, CLIENTES[I]);
end;

// invoke('cliente', {id}) -> objeto, ou erro NAO_ENCONTRADO
procedure CmdCliente(Call: TBorionCall);
var
  I, Id: Integer;
begin
  Id := Call.ArgInt('id');
  for I := Low(CLIENTES) to High(CLIENTES) do
    if CLIENTES[I].Id = Id then
    begin
      PutCliente(Call.Result.AsObject, CLIENTES[I]);
      Exit;
    end;
  raise EBorionError.Create('NAO_ENCONTRADO', Format('Cliente %d não existe.', [Id]));
end;

{ --- comando assíncrono --------------------------------------------------- }

type
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
  FCall.Result.AsObject.Put('mensagem', 'Tarefa concluída numa thread Delphi');
  FCall.Result.AsObject.Put('passos', FPassos);
  FCall.Resolve;
end;

// invoke('tarefaLonga', {passos}) -> resolve depois; emite 'tarefa:progresso'
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
  Ipc.RegisterCommandProc('info', CmdInfo);
  Ipc.RegisterCommandProc('saudacao', CmdSaudacao);
  Ipc.RegisterCommandProc('listarClientes', CmdListarClientes);
  Ipc.RegisterCommandProc('cliente', CmdCliente);
  Ipc.RegisterCommandProc('tarefaLonga', CmdTarefaLonga);
end;

end.
