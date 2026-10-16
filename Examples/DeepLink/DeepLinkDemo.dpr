program DeepLinkDemo;

{ Exemplo do plugin "deep-link" do Borion: links borion-exemplo://... abrem o
  app ou, com ele aberto, chegam à janela que já existe. }

uses
  Borion, BorionSingleInstance, BorionDeepLink;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (build.bat e DeepLinkDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com o frontend (gerado pelo build.bat) }

begin
  TBorionBuilder.Create('Borion: deep-link')
    .Size(900, 640)
    .Plugin(TBorionSingleInstancePlugin.Create('Borion.Exemplo.DeepLink'))  { antes: links com o app aberto }
    .Plugin(TBorionDeepLinkPlugin.Create(['borion-exemplo']))  { registra o esquema ao iniciar }
    .Run;
end.
