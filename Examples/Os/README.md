# Exemplo: plugin `os`

Informações do sistema pela página. No Delphi:

```pascal
Ipc.AddPlugin(TBorionOsPlugin.Create);
```

## O que ele mostra

| Seção | O que demonstra |
|---|---|
| 1. `os.info()` | Plataforma, arquitetura do Windows e do processo, versão real e build, `displayVersion`, nome da edição, idioma e nome do computador |
| 2. O navegador | O que o `navigator` diz, para comparar: o `userAgent` diz "Windows NT 10.0" também no Windows 11 e não conhece o nome do computador |
| 3. Idioma | `os.locale()` usado com o `Intl` para formatar data e número |
## Rodando

```bat
build.bat
OsDemo.exe
```

O `build.bat` copia os módulos do [`@borion/api`](../../js/README.md) (`Borion\js`) para
`web\borion-api\`, empacota a pasta `web\` com o `borion pack` e compila. Não precisa de Node
nem de Vite: o *import map* do `index.html` resolve `import ... from '@borion/api/os'` para a
cópia local, e o código fica igual ao de um projeto com bundler.

| | |
|---|---|
| `uPrincipal.pas` | A janela (sem `.dfm`): browser, IPC, assets e o plugin |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#os).
