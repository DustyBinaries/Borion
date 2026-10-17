program TitlebarDemo;

{ Exemplo de janela sem borda com a barra de título em HTML (como a do Tauri):
  o app.json tira as decorations, a página desenha a barra, arrasta a janela
  pelos elementos com data-borion-drag-region e usa o plugin window para
  minimizar, maximizar e fechar. Sem borda, a beirada da página redimensiona. }

uses
  Borion, BorionWindow;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (TitlebarDemo.dof, usado pelo borion build) }

{$R *.res}
{$R web.res}  { a pasta web\ e o app.json, empacotados pelo borion build }

begin
  TBorionBuilder.Create
    .Plugin(TBorionWindowPlugin.Create)
    .Run;
end.
