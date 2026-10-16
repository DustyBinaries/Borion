program ClipboardDemo;

{ Exemplo do plugin "clipboard" do Borion: copiar e colar texto (com emoji) e
  copiar HTML com formatação. }

uses
  Borion, BorionClipboard;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (build.bat e ClipboardDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com o frontend (gerado pelo build.bat) }

begin
  TBorionBuilder.Create('Borion: clipboard')
    .Size(900, 640)
    .Plugin(TBorionClipboardPlugin.Create)
    { TBorionClipboardPlugin.Create(False): a página só copia, não lê o que o
      usuário copiou de outros programas }
    .Run;
end.
