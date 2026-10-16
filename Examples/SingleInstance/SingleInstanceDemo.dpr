program SingleInstanceDemo;

{ Exemplo do plugin "single-instance" do Borion: o app abre uma vez só; abrir
  de novo (com ou sem argumentos) traz a janela aberta para frente. }

uses
  Borion, BorionSingleInstance;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (build.bat e SingleInstanceDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com o frontend (gerado pelo build.bat) }

begin
  TBorionBuilder.Create('Borion: single-instance')
    .Size(900, 640)
    { numa segunda execução, o plugin entrega os argumentos à primeira e o Run
      termina sem criar janela }
    .Plugin(TBorionSingleInstancePlugin.Create('Borion.Exemplo.SingleInstance'))
    .Run;
end.
