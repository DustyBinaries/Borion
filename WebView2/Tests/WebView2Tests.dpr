program WebView2Tests;

{ Testes DUnit do TWebView2Browser (console), sem o runtime do WebView2.
  Sai com código = número de falhas + erros. Rode com run-tests.bat. }

{$APPTYPE CONSOLE}

uses
  TestFramework,
  TextTestRunner,
  WebView2 in '..\WebView2.pas',
  WebView2Browser in '..\WebView2Browser.pas',
  TestWebView2 in 'TestWebView2.pas';

begin
  RunRegisteredTests(rxbHaltOnFailures);
end.
