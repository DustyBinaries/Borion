# Exemplo: plugin `deep-link`

Links `borion-exemplo://...` abrem este app. No `.dpr`, como no exemplo do `single-instance`:

```pascal
if BorionIsSecondInstance('Borion.Exemplo.DeepLink') then
  Exit;
```

e no form:

```pascal
FIpc.AddPlugin(TBorionSingleInstancePlugin.Create);  // antes: links com o app aberto
FIpc.AddPlugin(TBorionDeepLinkPlugin.Create(['borion-exemplo']));
```

## O que ele mostra

| Seção | O que demonstra |
|---|---|
| 1. Experimente | Links para colar no Executar (Win+R) ou no navegador, com o app aberto ou fechado |
| 2. `getCurrent` | O link que abriu o app, já validado e quebrado em ação e parâmetros |
| 3. `onOpenUrl` | Links abertos com o app rodando: chegam a esta janela pela outra execução |
| 4. Registro | `isRegistered`, `register` e `unregister` |

Ao abrir, o exemplo registra `borion-exemplo` em `HKCU\Software\Classes`. O botão "Tirar o
registro" apaga.
## Rodando

```bat
build.bat
DeepLinkDemo.exe
```

O `build.bat` copia os módulos do [`@borion/api`](../../js/README.md) (`Borion\js`) para
`web\borion-api\`, empacota a pasta `web\` com o `borion pack` e compila. Não precisa de Node
nem de Vite: o *import map* do `index.html` resolve `import ... from '@borion/api/deep-link'` para a
cópia local, e o código fica igual ao de um projeto com bundler.

| | |
|---|---|
| `uPrincipal.pas` | A janela (sem `.dfm`): browser, IPC, assets e o plugin |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#deep-link).
