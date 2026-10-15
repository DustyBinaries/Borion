program Editor;

{ Borion Editor: editor de texto com frontend Vite + JS puro (pasta frontend\)
  feito só com os plugins oficiais dialog, fs e shell.
    build.bat  -> npm run build, borion pack frontend\dist app.res, compila
    dev.bat    -> servidor do Vite com hot-reload + o app com --dev-url }

uses
  Forms,
  XPMan,
  WebView2 in '..\..\WebView2\WebView2.pas',
  WebView2Browser in '..\..\WebView2\WebView2Browser.pas',
  BorionJson in '..\..\BorionJson.pas',
  BorionIpc in '..\..\BorionIpc.pas',
  BorionPack in '..\..\BorionPack.pas',
  BorionAssets in '..\..\BorionAssets.pas',
  BorionScope in '..\..\Plugins\BorionScope.pas',
  BorionFs in '..\..\Plugins\BorionFs.pas',
  BorionDialog in '..\..\Plugins\BorionDialog.pas',
  BorionShell in '..\..\Plugins\BorionShell.pas',
  uPrincipal in 'uPrincipal.pas' {frmPrincipal};

{ Jsons (json4delphi) vem do ACBr: veja JSON4DELPHI / ACBR_COMUM no build.bat
  e o Search path do projeto (Editor.dof) }

{$R *.res}
{$R app.res}  { pacote BORION_ASSETS com frontend\dist (gerado pelo build.bat) }

begin
  Application.Initialize;
  Application.Title := 'Borion Editor';
  Application.CreateForm(TfrmPrincipal, frmPrincipal);
  Application.Run;
end.
