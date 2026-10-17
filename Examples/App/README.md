# Exemplo: plugin `app`

Dados do executável e controle da janela pela página.

O app inteiro é o `AppDemo.dpr` (sem form):

```pascal
uses
  Windows, Forms, Borion, BorionApp;

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
```

## O que ele mostra

| Seção | O que demonstra |
|---|---|
| 1. `app.info()` | `name` (o `Application.Title`), `version` (o `FileVersion` do `AppDemo.rc`), `exe` e `pid` |
| 2. A janela | `app.minimize()`, `app.hide()` e `app.show()`: a página continua rodando com a janela minimizada ou escondida, e um `setTimeout` a traz de volta depois de 3 s |
| 3. Sair | `app.exit()` fecha a janela como o X, passando pelo `OnCloseQuery` do form, que aqui pergunta antes. Respondendo "Não", o app continua aberto |

O projeto também inclui as units `BorionTray` e `BorionMenu` sem usar os plugins. O `BorionApp`
depende delas porque o `app.show()` sabe tirar a janela da bandeja quando o plugin `tray` está
presente.

## Rodando

```bat
build.bat
AppDemo.exe
```

O `build.bat` chama o `borion build`, que copia os módulos do [`@borion/api`](../../js/README.md)
(`Borion\js`) para `web\borion-api\`, empacota a pasta `web\`, o `app.json` e o ícone no
`web.res` e compila. Não precisa de Node nem de Vite: o *import map* do `index.html` resolve
`import ... from '@borion/api/app'` para a cópia local, e o código fica igual ao de um projeto
com bundler.

O ícone do exe (Explorer, janela, barra de tarefas) vem do `bundle.icon` do `app.json`, como no
Tauri ([docs/CONFIG.md](../../docs/CONFIG.md#ícone)):

```json
"bundle": {
  "icon": ["icons/icon.ico"]
}
```

| | |
|---|---|
| `AppDemo.dpr` | O app inteiro: o `TBorionBuilder` monta a janela com o plugin (sem form) |
| `app.json` | A pasta da interface (`web`) e o ícone. O título e o tamanho continuam no `.dpr`, que vence o `app.json` |
| `icons\icon.ico` | O ícone do app |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#app).
