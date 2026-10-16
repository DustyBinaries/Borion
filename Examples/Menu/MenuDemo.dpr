program MenuDemo;

{ Exemplo do plugin "menu" do Borion: barra de menu nativa montada pela página,
  atalhos de teclado com o foco na página, update e menu de contexto (popup).
  O app inteiro está aqui: sem form, a janela é montada pelo TBorionBuilder.
    build.bat -> copia o @borion/api para web\, borion pack web web.res, compila }

uses
  Borion, BorionMenu;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (build.bat e MenuDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com a pasta web\ (gerado pelo build.bat) }

begin
  TBorionBuilder.Create('Borion: menu')
    .Size(900, 640)
    .Plugin(TBorionMenuPlugin.Create)  { a barra vai para a janela do app }
    .Run;
end.
