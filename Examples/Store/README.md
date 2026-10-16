# Exemplo: plugin `store`

Preferências persistidas em `%APPDATA%\Borion Store Demo\prefs.json`, usadas pela página e pelo
Delphi.

O app inteiro é o `StoreDemo.dpr` (sem form):

```pascal
uses
  SysUtils, Forms, Jsons, Borion, BorionStore;

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
```

## O que ele mostra

| Seção | O que demonstra |
|---|---|
| Aberturas | Um contador gravado a cada execução: feche e abra o exemplo para ver os valores voltarem |
| 1. Preferências | `get`/`set` de texto (salvo a cada tecla) e do tema, aplicado com `onKeyChange` |
| 2. Lista | Um array como valor, com emoji |
| 3. O arquivo | `entries` atualizado pelo `onChange`, `reload` (pega edições feitas por fora no arquivo) e `clear` |
| Janela | O Delphi grava a posição da janela no mesmo store ao fechar (`WriteJson`) e a restaura ao abrir (`ReadJson`); a chave `janela` aparece na seção 3 |
## Rodando

```bat
build.bat
StoreDemo.exe
```

O `build.bat` copia os módulos do [`@borion/api`](../../js/README.md) (`Borion\js`) para
`web\borion-api\`, empacota a pasta `web\` com o `borion pack` e compila. Não precisa de Node
nem de Vite: o *import map* do `index.html` resolve `import ... from '@borion/api/store'` para a
cópia local, e o código fica igual ao de um projeto com bundler.

| | |
|---|---|
| `StoreDemo.dpr` | O app inteiro: o `TBorionBuilder` monta a janela com o plugin (sem form) |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#store).
