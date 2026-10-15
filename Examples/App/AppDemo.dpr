program AppDemo;

{ Exemplo do plugin "app" do Borion: dados do executável (app.info) e controle
  da janela pela página: minimizar, esconder, mostrar e sair.
    build.bat -> copia o @borion/api para web\, borion pack web web.res, compila }

uses
  Forms,
  XPMan,
  WebView2 in '..\..\WebView2\WebView2.pas',
  WebView2Browser in '..\..\WebView2\WebView2Browser.pas',
  BorionJson in '..\..\BorionJson.pas',
  BorionIpc in '..\..\BorionIpc.pas',
  BorionPack in '..\..\BorionPack.pas',
  BorionAssets in '..\..\BorionAssets.pas',
  BorionMenu in '..\..\Plugins\BorionMenu.pas',  { o BorionTray monta o menu do ícone com ela }
  BorionTray in '..\..\Plugins\BorionTray.pas',  { usada pelo BorionApp (app:show tira a janela da bandeja) }
  BorionApp in '..\..\Plugins\BorionApp.pas',
  uPrincipal in 'uPrincipal.pas';

{ Jsons (json4delphi) vem do ACBr: veja JSON4DELPHI / ACBR_COMUM no build.bat
  e o Search path do projeto (AppDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com a pasta web\ (gerado pelo build.bat) }

begin
  Application.Initialize;
  Application.Title := 'Borion: app';
  Application.CreateForm(TfrmPrincipal, frmPrincipal);
  Application.Run;
end.
