program AppDemo;

{ Exemplo do plugin "app" do Borion: dados do executável (app.info) e controle
  da janela pela página: minimizar, esconder, mostrar e sair. O app:exit fecha a
  janela como o botão X, passando pelo OnCloseQuery abaixo. }

uses
  Windows, Forms, Borion, BorionApp;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (build.bat e AppDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com o frontend (gerado pelo build.bat) }

{ vale para o X da janela e para o app.exit() da página (que posta um WM_CLOSE) }
procedure PerguntarAntes(Window: TBorionWindow; var CanClose: Boolean);
begin
  CanClose := Application.MessageBox('Fechar o exemplo?', 'Borion: app',
    MB_YESNO or MB_ICONQUESTION) = IDYES;
end;

begin
  TBorionBuilder.Create('Borion: app')
    .Size(900, 640)
    .Plugin(TBorionAppPlugin.Create)
    .OnCloseQuery(PerguntarAntes)
    .Run;
end.
