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
  TestBorionPack in 'TestBorionPack.pas';

begin
  RunRegisteredTests(rxbHaltOnFailures);
end.
