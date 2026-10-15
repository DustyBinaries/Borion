program SingleInstanceDemo;

{ Exemplo do plugin "single-instance" do Borion: o app abre uma vez só; abrir
  de novo (com ou sem argumentos) traz a janela aberta para frente.
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
  uPrincipal in 'uPrincipal.pas';

{ Jsons (json4delphi) vem do ACBr: veja JSON4DELPHI / ACBR_COMUM no build.bat
  e o Search path do projeto (SingleInstanceDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com a pasta web\ (gerado pelo build.bat) }

begin
  { antes de tudo: a segunda execução entrega os argumentos à primeira e sai,
    sem criar janela }
  if BorionIsSecondInstance('Borion.Exemplo.SingleInstance') then
    Exit;
  Application.Initialize;
  Application.Title := 'Borion: single-instance';
  Application.CreateForm(TfrmPrincipal, frmPrincipal);
  Application.Run;
end.
