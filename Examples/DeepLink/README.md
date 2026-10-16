# Exemplo: plugin `deep-link`

Links `borion-exemplo://...` abrem este app. O plugin `single-instance` vem antes, para os
links abertos com o app já rodando.

O app inteiro é o `DeepLinkDemo.dpr` (sem form):

```pascal
uses
  Borion, BorionSingleInstance, BorionDeepLink;

begin
  TBorionBuilder.Create('Borion: deep-link')
    .Size(900, 640)
    .Plugin(TBorionSingleInstancePlugin.Create('Borion.Exemplo.DeepLink'))  { antes: links com o app aberto }
    .Plugin(TBorionDeepLinkPlugin.Create(['borion-exemplo']))  { registra o esquema ao iniciar }
    .Run;
end.
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
| `DeepLinkDemo.dpr` | O app inteiro: o `TBorionBuilder` monta a janela com o plugin (sem form) |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#deep-link).
