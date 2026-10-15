program BorionTests;

{ Testes DUnit do Borion (console). Sai com código = número de falhas + erros.
  Rode com run-tests.bat, que também roda os testes JS (Borion/js/test). }

{$APPTYPE CONSOLE}

uses
  TestFramework,
  TextTestRunner,
  WebView2 in '..\..\WebView2\WebView2.pas',
  WebView2Browser in '..\..\WebView2\WebView2Browser.pas',
  BorionJson in '..\BorionJson.pas',
  BorionIpc in '..\BorionIpc.pas',
  TestBorionJson in 'TestBorionJson.pas',
  BorionPack in '..\BorionPack.pas',
  BorionAssets in '..\BorionAssets.pas',
  TestBorionIpc in 'TestBorionIpc.pas',
  BorionScope in '..\Plugins\BorionScope.pas',
  BorionFs in '..\Plugins\BorionFs.pas',
  BorionDialog in '..\Plugins\BorionDialog.pas',
  BorionShell in '..\Plugins\BorionShell.pas',
  TestBorionPack in 'TestBorionPack.pas',
  BorionMenu in '..\Plugins\BorionMenu.pas',
  BorionTray in '..\Plugins\BorionTray.pas',
  BorionApp in '..\Plugins\BorionApp.pas',
  BorionClipboard in '..\Plugins\BorionClipboard.pas',
  BorionStore in '..\Plugins\BorionStore.pas',
  BorionOs in '..\Plugins\BorionOs.pas',
  BorionHttp in '..\Plugins\BorionHttp.pas',
  TestBorionPlugins in 'TestBorionPlugins.pas',
  TestBorionUi in 'TestBorionUi.pas',
  TestBorionData in 'TestBorionData.pas',
  TestBorionNet in 'TestBorionNet.pas';

begin
  RunRegisteredTests(rxbHaltOnFailures);
end.
