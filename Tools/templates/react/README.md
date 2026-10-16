# {{TITLE}}

App Borion (Delphi 7 + WebView2), criado com `borion new` (template `react`: a interface é um
projeto React + Vite). Precisa do Node.js.

## Rodando

```bat
build.bat          :: frontend + exe, com a interface embutida
{{PROGRAM}}.exe
```

Para desenvolver a interface com hot-reload:

```bat
dev.bat            :: Vite em http://localhost:{{DEV_PORT}} + o app ligado a ele
```

Ou abra `{{PROGRAM}}.dpr` na IDE do Delphi 7 (o *Search path* já está no `{{PROGRAM}}.dof`), mas
rode o `build.bat` antes uma vez: ele gera o `app.res` com a interface.

## Estrutura

| | |
|---|---|
| `{{PROGRAM}}.dpr` | O app inteiro: o `TBorionBuilder` monta a janela, os plugins e os comandos Delphi |
| `frontend\` | A interface: `index.html` e `src\` (Vite); `@borion/api` instalado da pasta do Borion |
| `build.bat` | `npm run build`, empacota `frontend\dist` em `app.res` e compila |
| `dev.bat` | Servidor do Vite + o app com `--dev-url` |
| `{{PROGRAM}}.rc` | Versão do exe (FileDescription, FileVersion...) |

## Próximos passos

- Um comando novo: escreva a `procedure` no `.dpr` e registre com `.Command('nome', Proc)`; no
  JS, `await invoke('nome', { ... })` (feche o app e rode o `build.bat` para recompilar o Delphi).
- Um plugin: acrescente a unit no `uses` e `.Plugin(TBorionXxxPlugin.Create)` no builder; no
  JS, `import ... from '@borion/api/xxx'`.
- Documentação: `{{BORION_HOME}}\README.md` e `{{BORION_HOME}}\docs\PLUGINS.md`.
