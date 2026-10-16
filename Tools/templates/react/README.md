# {{TITLE}}

App Borion (Delphi 7 + WebView2), criado com `borion new` (template `react`: a interface é um
projeto React + Vite). Precisa do Node.js.

## Rodando

```bat
borion dev         :: Vite em http://localhost:{{DEV_PORT}} (hot-reload) + o app ligado a ele
borion build       :: frontend + {{PROGRAM}}.exe, com a interface embutida
```

(`dev.bat` e `build.bat` fazem o mesmo, sem precisar do `borion` no PATH.) No `borion dev`,
mudar o `.dpr` (ou outra unit) recompila e reabre o app; feche o app para encerrar (o Vite fecha
junto).

Ou abra `{{PROGRAM}}.dpr` na IDE do Delphi 7 (o *Search path* já está no `{{PROGRAM}}.dof`), mas
rode o `borion build` antes uma vez: ele gera o `app.res` com a interface.

## Estrutura

| | |
|---|---|
| `{{PROGRAM}}.dpr` | O app inteiro: o `TBorionBuilder` monta a janela, os plugins e os comandos Delphi |
| `app.json` | Nome, versão, identificador, a janela (tamanho, limites, borda) e onde fica a interface; vai embutido no exe ([referência]({{BORION_HOME}}\docs\CONFIG.md)) |
| `frontend\` | A interface: `index.html` e `src\` (Vite); `@borion/api` instalado da pasta do Borion |
| `build.bat` / `dev.bat` | `borion build` (`npm run build`, empacota `frontend\dist` em `app.res` e compila) / `borion dev` |
| `{{PROGRAM}}.rc` | Versão do exe (FileDescription, FileVersion...) |

## Próximos passos

- Um comando novo: escreva a `procedure` no `.dpr` e registre com `.Command('nome', Proc)`; no
  JS, `await invoke('nome', { ... })` (no `borion dev`, salvar o `.dpr` recompila e reabre o app).
- Um plugin: acrescente a unit no `uses` e `.Plugin(TBorionXxxPlugin.Create)` no builder; no
  JS, `import ... from '@borion/api/xxx'`.
- Documentação: `{{BORION_HOME}}\README.md` e `{{BORION_HOME}}\docs\PLUGINS.md`.
