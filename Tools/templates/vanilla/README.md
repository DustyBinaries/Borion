# {{TITLE}}

App Borion (Delphi 7 + WebView2), criado com `borion new` (template `vanilla`: HTML, CSS e JS
puros, sem Node).

## Rodando

```bat
borion dev         :: o app servindo web\ direto da pasta: salvou, a página recarrega
borion build       :: o {{PROGRAM}}.exe com a interface embutida
```

(`dev.bat` e `build.bat` fazem o mesmo, sem precisar do `borion` no PATH.) No `borion dev`,
mudar o `.dpr` (ou outra unit) recompila e reabre o app; feche o app para encerrar.

Ou abra `{{PROGRAM}}.dpr` na IDE do Delphi 7 (o *Search path* já está no `{{PROGRAM}}.dof`), mas
rode o `borion build` antes uma vez: ele gera o `web.res` com a interface.

## Estrutura

| | |
|---|---|
| `{{PROGRAM}}.dpr` | O app inteiro: o `TBorionBuilder` monta a janela, os plugins e os comandos Delphi |
| `web\` | A interface: `index.html`, `app.js` e `style.css` |
| `build.bat` / `dev.bat` | `borion build` / `borion dev` (copiam o `@borion/api` para `web\borion-api\`, empacotam `web\` em `web.res` e compilam) |
| `{{PROGRAM}}.rc` | Versão do exe (FileDescription, FileVersion...) |

Para distribuir, rode o `borion build`: a interface vai dentro do exe.

## Próximos passos

- Um comando novo: escreva a `procedure` no `.dpr` e registre com `.Command('nome', Proc)`; no
  JS, `await invoke('nome', { ... })`.
- Um plugin: acrescente a unit no `uses` e `.Plugin(TBorionXxxPlugin.Create)` no builder; no
  JS, o módulo `@borion/api/xxx` (ponha no import map do `index.html`).
- Documentação: `{{BORION_HOME}}\README.md` e `{{BORION_HOME}}\docs\PLUGINS.md`.
