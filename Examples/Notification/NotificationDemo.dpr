program NotificationDemo;

{ Exemplo do plugin "notification" do Borion: notificações nativas do Windows
  (toast) com botões, e os eventos de clique e de fechamento.
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
  BorionMenu in '..\..\Plugins\BorionMenu.pas',  { usadas pelo BorionApp e pelo BorionTray }
  BorionTray in '..\..\Plugins\BorionTray.pas',
  BorionApp in '..\..\Plugins\BorionApp.pas',
  BorionNotification in '..\..\Plugins\BorionNotification.pas',
  uPrincipal in 'uPrincipal.pas';

{ Jsons (json4delphi) vem do ACBr: veja JSON4DELPHI / ACBR_COMUM no build.bat
  e o Search path do projeto (NotificationDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com a pasta web\ (gerado pelo build.bat) }

begin
  Application.Initialize;
  Application.Title := 'Borion: notification';
  Application.CreateForm(TfrmPrincipal, frmPrincipal);
  Application.Run;
end.
