program AutostartDemo;

{ Exemplo do plugin "autostart" do Borion: iniciar o app junto com o Windows.
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
  BorionSingleInstance in '..\..\Plugins\BorionSingleInstance.pas',  { argumentos com Unicode }
  BorionMenu in '..\..\Plugins\BorionMenu.pas',  { usadas pelo BorionSingleInstance }
  BorionTray in '..\..\Plugins\BorionTray.pas',
  BorionApp in '..\..\Plugins\BorionApp.pas',
  BorionRegistry in '..\..\Plugins\BorionRegistry.pas',
  BorionAutostart in '..\..\Plugins\BorionAutostart.pas',
  uPrincipal in 'uPrincipal.pas';

{ Jsons (json4delphi) vem do ACBr: veja JSON4DELPHI / ACBR_COMUM no build.bat
  e o Search path do projeto (AutostartDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com a pasta web\ (gerado pelo build.bat) }

begin
  Application.Initialize;
  Application.Title := 'Borion: autostart';
  Application.CreateForm(TfrmPrincipal, frmPrincipal);
  Application.Run;
end.
