program OsDemo;

{ Exemplo do plugin "os" do Borion: versão real do Windows, arquitetura,
  idioma e nome do computador. }

uses
  Borion, BorionOs;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (build.bat e OsDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com o frontend (gerado pelo build.bat) }

begin
  TBorionBuilder.Create('Borion: os')
    .Size(900, 640)
    .Plugin(TBorionOsPlugin.Create)
    .Run;
end.
