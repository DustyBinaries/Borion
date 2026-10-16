# {{TITLE}}

App Borion (Delphi 7 + WebView2), criado com `borion new` (template `vanilla`: HTML, CSS e JS
puros, sem Node).

## Rodando

```bat
build.bat
{{PROGRAM}}.exe
```

Ou abra `{{PROGRAM}}.dpr` na IDE do Delphi 7 (o *Search path* já está no `{{PROGRAM}}.dof`), mas
rode o `build.bat` antes uma vez: ele gera o `web.res` com a interface.

## Estrutura

| | |
|---|---|
| `{{PROGRAM}}.dpr` | O app inteiro: o `TBorionBuilder` monta a janela, os plugins e os comandos Delphi |
| `web\` | A interface: `index.html`, `app.js` e `style.css` |
| `build.bat` | Copia o `@borion/api` para `web\borion-api\`, empacota `web\` em `web.res` e compila |
| `{{PROGRAM}}.rc` | Versão do exe (FileDescription, FileVersion...) |

Mudou a interface? Rode o `build.bat` de novo: ela vai dentro do exe.

## Próximos passos

- Um comando novo: escreva a `procedure` no `.dpr` e registre com `.Command('nome', Proc)`; no
  JS, `await invoke('nome', { ... })`.
- Um plugin: acrescente a unit no `uses` e `.Plugin(TBorionXxxPlugin.Create)` no builder; no
  JS, o módulo `@borion/api/xxx` (ponha no import map do `index.html`).
- Documentação: `{{BORION_HOME}}\README.md` e `{{BORION_HOME}}\docs\PLUGINS.md`.
