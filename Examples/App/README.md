# Exemplo: plugin `app`

Dados do executável e controle da janela pela página. No Delphi:

```pascal
Ipc.AddPlugin(TBorionAppPlugin.Create);
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

O `build.bat` copia os módulos do [`@borion/api`](../../js/README.md) (`Borion\js`) para
`web\borion-api\`, empacota a pasta `web\` com o `borion pack` e compila. Não precisa de Node
nem de Vite: o *import map* do `index.html` resolve `import ... from '@borion/api/app'` para a
cópia local, e o código fica igual ao de um projeto com bundler.

| | |
|---|---|
| `uPrincipal.pas` | A janela (sem `.dfm`): browser, IPC, assets e o plugin |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#app).
