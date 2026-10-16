program {{PROGRAM}};

// {{TITLE_COMMENT}}: app Borion. A interface está em web\ (HTML, CSS e JS); a lógica
// nativa, aqui. O app inteiro é montado pelo TBorionBuilder, sem form, com o
// título, a janela e a CSP do app.json (embutido no exe pelo borion build).
//   borion dev    -> o app servindo web\ direto da pasta (recarrega ao salvar)
//   borion build  -> empacota web\ e compila o exe

uses
  SysUtils, Borion, BorionIpc, BorionDialog;

{$R *.res}
{$R web.res}  // a pasta web\, empacotada pelo build.bat

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
  TBorionBuilder.Create  // título e janela: app.json
    .Plugin(TBorionDialogPlugin.Create)  // diálogos nativos: @borion/api/dialog
    .Command('saudar', Saudar)
    .Run;
end.
