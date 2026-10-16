program GlobalShortcutDemo;

{ Exemplo do plugin "global-shortcut" do Borion: atalhos de teclado que
  funcionam com o app em segundo plano. }

uses
  Borion, BorionGlobalShortcut;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (build.bat e GlobalShortcutDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com o frontend (gerado pelo build.bat) }

begin
  TBorionBuilder.Create('Borion: global-shortcut')
    .Size(900, 640)
    .Plugin(TBorionGlobalShortcutPlugin.Create)  { os atalhos saem ao fechar }
    .Run;
end.
