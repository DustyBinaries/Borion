program WindowDemo;

{ Exemplo do plugin "window" do Borion: a página controla a própria janela
  (título, tamanho, posição, maximizar, tela cheia, borda, sempre no topo),
  acompanha os eventos dela e intercepta o fechamento com um "deseja salvar?"
  em HTML. O título e o tamanho inicial vêm do app.json. }

uses
  Borion, BorionWindow;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (WindowDemo.dof, usado pelo borion build) }

{$R *.res}
{$R web.res}  { a pasta web\ e o app.json, empacotados pelo borion build }

begin
  TBorionBuilder.Create
    .Plugin(TBorionWindowPlugin.Create)
    .Run;
end.
