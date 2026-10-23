program MultiWindowDemo;

{ Exemplo de várias janelas do Borion: as janelas vêm do app.json (a
  principal, e a de configurações, aberta sob demanda) ou são criadas pela
  página (as notas). Todas usam o mesmo IPC: o comando "contar" abaixo e o
  plugin window servem todas, e cada chamada sabe de que janela veio. }

uses
  SysUtils, Borion, BorionIpc, BorionWindow, BorionWindowState;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (MultiWindowDemo.dof, usado pelo borion build) }

{$R *.res}
{$R web.res}  { a pasta web\ e o app.json, empacotados pelo borion build }

var
  Chamadas: Integer;

{ Um comando só, para todas as janelas: Call.Window diz quem chamou }
procedure Contar(Call: TBorionCall);
begin
  Inc(Chamadas);
  Call.Result.AsString := Format('chamada %d, vinda da janela "%s" (%d abertas)',
    [Chamadas, Call.Window, BorionWindows.Count]);
end;

begin
  TBorionBuilder.Create
    .Plugin(TBorionWindowPlugin.Create)
    .Plugin(TBorionWindowStatePlugin.Create)  { tamanho e posição de cada janela, de uma execução para outra }
    .Command('contar', Contar)
    .Run;
end.
