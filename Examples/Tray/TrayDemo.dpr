program TrayDemo;

{ Exemplo do plugin "tray" do Borion: ícone na bandeja com tooltip, menu e
  notificações; minimizar esconde a janela na bandeja.
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
  BorionTray in '..\..\Plugins\BorionTray.pas',
  uPrincipal in 'uPrincipal.pas';

{ Jsons (json4delphi) vem do ACBr: veja JSON4DELPHI / ACBR_COMUM no build.bat
  e o Search path do projeto (TrayDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com a pasta web\ (gerado pelo build.bat) }

begin
  Application.Initialize;
  Application.Title := 'Borion: tray';
  Application.CreateForm(TfrmPrincipal, frmPrincipal);
  Application.Run;
end.
