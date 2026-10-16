program DeepLinkDemo;

{ Exemplo do plugin "deep-link" do Borion: links borion-exemplo://... abrem o
  app ou, com ele aberto, chegam à janela que já existe.
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
  BorionSingleInstance in '..\..\Plugins\BorionSingleInstance.pas',
  BorionRegistry in '..\..\Plugins\BorionRegistry.pas',
  BorionDeepLink in '..\..\Plugins\BorionDeepLink.pas',
  uPrincipal in 'uPrincipal.pas';

{ Jsons (json4delphi) vem do ACBr: veja JSON4DELPHI / ACBR_COMUM no build.bat
  e o Search path do projeto (DeepLinkDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com a pasta web\ (gerado pelo build.bat) }

begin
  { antes de tudo: a segunda execução entrega os argumentos à primeira e sai,
    sem criar janela }
  if BorionIsSecondInstance('Borion.Exemplo.DeepLink') then
    Exit;
  Application.Initialize;
  Application.Title := 'Borion: deep-link';
  Application.CreateForm(TfrmPrincipal, frmPrincipal);
  Application.Run;
end.
