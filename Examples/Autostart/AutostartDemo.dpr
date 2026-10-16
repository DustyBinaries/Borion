program AutostartDemo;

{ Exemplo do plugin "autostart" do Borion: iniciar o app junto com o Windows. }

uses
  Borion, BorionAutostart;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (build.bat e AutostartDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com o frontend (gerado pelo build.bat) }

begin
  TBorionBuilder.Create('Borion: autostart')
    .Size(900, 640)
    { nome na aba Inicializar do Gerenciador de Tarefas; --autostart marca a
      execução que veio do login }
    .Plugin(TBorionAutostartPlugin.Create('Borion Autostart Demo', '--autostart'))
    .Run;
end.
