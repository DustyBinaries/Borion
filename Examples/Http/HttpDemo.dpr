program HttpDemo;

{ Exemplo do plugin "http" do Borion: fetch pelo Delphi, sem CORS, com escopo
  de URLs, timeout e cancelamento. }

uses
  Borion, BorionHttp;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (build.bat e HttpDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com o frontend (gerado pelo build.bat) }

var
  Http: TBorionHttpPlugin;

begin
  Http := TBorionHttpPlugin.Create;
  { escopo: tudo negado por padrão; só estas URLs }
  Http.Allow('https://example.com/*');
  Http.Allow('https://api.github.com/*');
  Http.Allow('https://httpbin.org/*');
  TBorionBuilder.Create('Borion: http')
    .Size(900, 680)
    .Plugin(Http)
    .Run;
end.
