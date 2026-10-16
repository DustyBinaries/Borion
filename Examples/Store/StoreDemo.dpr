program StoreDemo;

{ Exemplo do plugin "store" do Borion: a página guarda preferências em
  %APPDATA%\Borion Store Demo\prefs.json. O Delphi usa o mesmo store pela API
  nativa: grava a posição da janela ao fechar e a restaura ao abrir. }

uses
  SysUtils, Forms, Jsons, Borion, BorionStore;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (build.bat e StoreDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com o frontend (gerado pelo build.bat) }

var
  Store: TBorionStorePlugin;

{ a posição da janela fica no mesmo prefs.json da página, na chave "janela" }
procedure RestaurarJanela(Window: TBorionWindow);
var
  Json: string;
  J: TJsonObject;
begin
  if not Store.ReadJson('prefs', 'janela', Json) then
    Exit;
  J := TJsonObject.Create;
  try
    J.Parse(Json);
    Window.Position := poDesigned;
    Window.SetBounds(J['left'].AsInteger, J['top'].AsInteger, J['width'].AsInteger, J['height'].AsInteger);
  except
    { valor estranho (editado à mão?): fica a posição padrão }
  end;
  J.Free;
end;

procedure GuardarJanela(Window: TBorionWindow);
begin
  if Window.WindowState = wsNormal then
    Store.WriteJson('prefs', 'janela', Format('{"left":%d,"top":%d,"width":%d,"height":%d}',
      [Window.Left, Window.Top, Window.Width, Window.Height]));
end;

begin
  Store := TBorionStorePlugin.Create('Borion Store Demo');
  { Store.AutoSave := False;  grava só no store.save() / ao fechar }
  TBorionBuilder.Create('Borion: store')
    .Size(900, 640)
    .Plugin(Store)
    .Setup(RestaurarJanela)
    .OnClose(GuardarJanela)
    .Run;
end.
