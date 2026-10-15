# Exemplo: plugin `single-instance`

O app abre uma vez só. No `.dpr`, antes de criar o form:

```pascal
if BorionIsSecondInstance('Borion.Exemplo.SingleInstance') then
  Exit;
```

e no form:

```pascal
FIpc.AddPlugin(TBorionSingleInstancePlugin.Create);
```

## O que ele mostra

| Seção | O que demonstra |
|---|---|
| 1. Esta execução | `args()`: os argumentos e a pasta atual da primeira abertura |
| 2. Outras execuções | Abra o exe de novo, com ou sem argumentos (`SingleInstanceDemo.exe "um arquivo.txt" --opcao`), ou arraste um arquivo para cima dele: a segunda execução sai na hora, esta janela volta para frente e `onSecondInstance` recebe os argumentos (com acentos e emoji) |
## Rodando

```bat
build.bat
SingleInstanceDemo.exe
```

O `build.bat` copia os módulos do [`@borion/api`](../../js/README.md) (`Borion\js`) para
`web\borion-api\`, empacota a pasta `web\` com o `borion pack` e compila. Não precisa de Node
nem de Vite: o *import map* do `index.html` resolve `import ... from '@borion/api/single-instance'` para a
cópia local, e o código fica igual ao de um projeto com bundler.

| | |
|---|---|
| `uPrincipal.pas` | A janela (sem `.dfm`): browser, IPC, assets e o plugin |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#single-instance).
