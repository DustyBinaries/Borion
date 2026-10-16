program TrayDemo;

{ Exemplo do plugin "tray" do Borion: ícone na bandeja com tooltip, menu e
  notificações; minimizar esconde a janela na bandeja. }

uses
  Borion, BorionTray;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (build.bat e TrayDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com o frontend (gerado pelo build.bat) }

var
  Tray: TBorionTrayPlugin;

begin
  Tray := TBorionTrayPlugin.Create;
  Tray.MinimizeToTray := True;  { minimizar esconde a janela; clicar no ícone a traz de volta }
  { Tray.RestoreOnClick := False;  para tratar o clique só na página (tray:click) }
  TBorionBuilder.Create('Borion: tray')
    .Size(900, 640)
    .Plugin(Tray)
    .Run;
end.
