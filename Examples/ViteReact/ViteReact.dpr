program ViteReact;

{ Exemplo do Borion com frontend React + Vite (pasta frontend\).
  O app inteiro: a janela é montada pelo TBorionBuilder e os comandos nativos
  estão em uComandos.pas.
    build.bat  -> npm run build, borion pack frontend\dist app.res, compila
    dev.bat    -> servidor do Vite com hot-reload + o app com --dev-url }

uses
  Borion,
  uComandos in 'uComandos.pas';

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (build.bat e ViteReact.dof) }

{$R *.res}
{$R app.res}  { pacote BORION_ASSETS com o frontend (gerado pelo build.bat) }

begin
  TBorionBuilder.Create('Borion + React')
    .Size(1000, 680)
    .Commands(RegistrarComandos)  { procedure RegistrarComandos(Ipc: TBorionIpc) }
    .Run;
end.
