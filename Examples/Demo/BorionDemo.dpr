program BorionDemo;

{ Exemplo do Borion — Native Application Engine: comandos (invoke), erros,
  comando assíncrono numa thread, eventos nos dois sentidos e origens. }

uses
  Forms,
  XPMan,
  WebView2 in '..\..\WebView2\WebView2.pas',
  WebView2Browser in '..\..\WebView2\WebView2Browser.pas',
  BorionJson in '..\..\BorionJson.pas',
  BorionIpc in '..\..\BorionIpc.pas',
  BorionPack in '..\..\BorionPack.pas',
  BorionAssets in '..\..\BorionAssets.pas',
  uComandos in 'uComandos.pas',
  uPrincipal in 'uPrincipal.pas' {frmPrincipal};

{ Jsons (json4delphi) vem do ACBr: veja JSON4DELPHI / ACBR_COMUM no build.bat
  e o Search path do projeto (BorionDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com a pasta web\ (gerado por "borion pack" no build.bat) }

begin
  Application.Initialize;
  Application.Title := 'Borion Demo';
  Application.CreateForm(TfrmPrincipal, frmPrincipal);
  Application.Run;
end.
