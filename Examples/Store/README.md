# Exemplo: plugin `store`

Preferências persistidas em `%APPDATA%\Borion Store Demo\prefs.json`, usadas pela página e pelo
Delphi. No Delphi:

```pascal
FStore := TBorionStorePlugin(Ipc.AddPlugin(TBorionStorePlugin.Create('Borion Store Demo')));
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
| `uPrincipal.pas` | A janela (sem `.dfm`): browser, IPC, assets e o plugin |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#store).
