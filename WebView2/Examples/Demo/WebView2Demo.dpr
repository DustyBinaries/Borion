program WebView2Demo;

{ Exemplo do TWebView2Browser puro: navegação, eventos,
  PostWebMessage/ExecuteScript, página embutida e WebResourceRequested. }

uses
  Forms,
  XPMan,
  WebView2 in '..\..\WebView2.pas',
  WebView2Browser in '..\..\WebView2Browser.pas',
  uPrincipal in 'uPrincipal.pas' {frmPrincipal};

{$R *.res}
{$R web.res}  { arquivos da pasta web\ (gerado a partir de web.rc pelo build.bat) }

begin
  Application.Initialize;
  Application.Title := 'WebView2 + Delphi 7';
  Application.CreateForm(TfrmPrincipal, frmPrincipal);
  Application.Run;
end.
