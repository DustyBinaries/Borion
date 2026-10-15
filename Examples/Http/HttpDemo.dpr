program HttpDemo;

{ Exemplo do plugin "http" do Borion: fetch pelo Delphi, sem CORS, com escopo
  de URLs, timeout e cancelamento.
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
  BorionScope in '..\..\Plugins\BorionScope.pas',
  BorionFs in '..\..\Plugins\BorionFs.pas',  { base64 }
  BorionHttp in '..\..\Plugins\BorionHttp.pas',
  uPrincipal in 'uPrincipal.pas';

{ Jsons (json4delphi) vem do ACBr: veja JSON4DELPHI / ACBR_COMUM no build.bat
  e o Search path do projeto (HttpDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com a pasta web\ (gerado pelo build.bat) }

begin
  Application.Initialize;
  Application.Title := 'Borion: http';
  Application.CreateForm(TfrmPrincipal, frmPrincipal);
  Application.Run;
end.
