program KioskDemo;

{ Exemplo de modo kiosk: o app.json abre a janela em tela cheia, sem borda, por cima
  de tudo e sem DevTools; a pagina impede o fechamento (onCloseRequested), o menu de
  contexto e os atalhos do navegador, e so sai com um PIN. }

uses
  Borion, BorionWindow;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estao no
  search path (KioskDemo.dof, usado pelo borion build) }

{$R *.res}
{$R web.res}  { a pasta web\ e o app.json, empacotados pelo borion build }

begin
  TBorionBuilder.Create
    .Plugin(TBorionWindowPlugin.Create)
    .Run;
end.
