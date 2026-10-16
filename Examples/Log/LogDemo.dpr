program LogDemo;

{ Exemplo do plugin "log" do Borion: o Delphi e a página gravam no mesmo
  arquivo, %LOCALAPPDATA%\Borion Log Demo\logs\Borion Log Demo.log. }

uses
  Borion, BorionLog;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (build.bat e LogDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com o frontend (gerado pelo build.bat) }

var
  Log: TBorionLogPlugin;

begin
  Log := TBorionLogPlugin.Create('Borion Log Demo');
  Log.MinLevel := llDebug;
  Log.Info('app iniciando (linha gravada pelo Delphi)');
  TBorionBuilder.Create('Borion: log')
    .Size(900, 680)
    .Plugin(Log)
    .Run;
end.
