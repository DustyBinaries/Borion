program SecurityDemo;

{ Exemplo de seguranca da janela: tudo vem do app.json. A janela so navega para o app e
  para o example.org (allowNavigation); qualquer outro link, window.open ou target="_blank"
  vai para o navegador do sistema; e o release fica sem menu de contexto, DevTools e teclas
  de navegador (F5, Ctrl+R, Ctrl+U, zoom). Nao ha codigo Delphi alem do builder. }

uses
  Borion;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estao no
  search path (SecurityDemo.dof, usado pelo borion build) }

{$R *.res}
{$R web.res}  { a pasta web\ e o app.json, empacotados pelo borion build }

begin
  TBorionBuilder.Create.Run;
end.
