program {{PROGRAM}};

// {{TITLE_COMMENT}}: app Borion. A interface é um projeto React + Vite em frontend\; a
// lógica nativa, aqui. O app inteiro é montado pelo TBorionBuilder, sem form.
//   borion dev    -> servidor do Vite com hot-reload + o app ligado a ele
//   borion build  -> npm run build, empacota frontend\dist e compila o exe

uses
  SysUtils, Borion, BorionIpc, BorionDialog;

{$R *.res}
{$R app.res}  // frontend\dist, empacotado pelo build.bat

// Um comando nativo. No JS: await invoke('saudar', { nome: 'Ana' })
procedure Saudar(Call: TBorionCall);
var
  Nome: string;
begin
  Nome := Trim(Call.ArgStr('nome'));
  if Nome = '' then
    raise EBorionError.Create('NOME_VAZIO', 'Digite um nome.');  // vira error.code no JS
  Call.Result.AsString := Format('Olá, %s! Esta resposta veio do Delphi às %s.',
    [Nome, FormatDateTime('hh:nn:ss', Now)]);
end;

begin
  TBorionBuilder.Create('{{TITLE_PAS}}')
    .Size(900, 640)
    .Plugin(TBorionDialogPlugin.Create)  // diálogos nativos: @borion/api/dialog
    .Command('saudar', Saudar)
    .Run;
end.
