# Exemplo: Borion Editor

Um editor de texto feito **só com os plugins oficiais** (`dialog`, `fs`, `shell`, `menu`, `tray`,
`app`, `store`): não há nenhum
comando Delphi próprio. O frontend é Vite + JS puro, sem framework.

| | |
|---|---|
| `frontend/src/main.js` | Toda a lógica: abrir, salvar, recentes, menus, bandeja |
| `Editor.dpr` | O app inteiro, sem form: o `TBorionBuilder` com o escopo e os 7 plugins (~25 linhas úteis) |
| `build.bat` / `dev.bat` | Build de produção / modo dev com hot-reload (porta 5174) |

## O que ele faz

- **Novo, Abrir, Salvar, Salvar como**, com atalhos `Ctrl+N`, `Ctrl+O`, `Ctrl+S` e
  `Ctrl+Shift+S` (`dialog.open`, `dialog.save`, `fs.readTextFile`, `fs.writeTextFile`).
- Pergunta antes de descartar alterações (`dialog.ask`).
- **Arquivos recentes** em `%APPDATA%\Borion Editor\recentes.json` (`fs` com `baseDir: appData`).
- **Mostrar na pasta** (`shell.showInFolder`) e link externo (`shell.open`).
- **Barra de menu nativa** (`menu.setMenu`): Arquivo, Exibir (quebra de linha, item com
  marcação) e Ajuda (`F1` mostra a versão com `app.info`). Os atalhos funcionam mesmo com o foco
  no texto, e "Mostrar na pasta" é habilitado com `menu.update` quando há um arquivo.
- **Menu de contexto nativo** na lista de recentes (`menu.popup`): abrir, remover, limpar a lista.
  No texto fica o menu do próprio WebView2, com recortar, copiar e colar.
- **Bandeja** (`tray`): ícone com o nome do arquivo no tooltip, menu Mostrar/Novo/Sair e
  notificação ao salvar. Minimizar esconde a janela na bandeja (`MinimizeToTray`).
- **Sair** (menu ou bandeja) pergunta antes de descartar alterações e fecha com `app.exit`.
- **Preferências** (`store`): a quebra de linha fica em
  `%APPDATA%\Borion Editor\preferencias.json` e volta como estava na próxima execução.
- Texto gravado em UTF-8.

## Segurança na prática

O escopo libera só `%APPDATA%\Borion Editor` e `Documentos\Borion Editor`. Fora isso, o app
alcança apenas o que o usuário escolhe nos diálogos, e só o arquivo escolhido, não a pasta
dele. Por isso um item da lista de **recentes** fora dessas pastas é recusado na sessão
seguinte (`FORBIDDEN_PATH`). O editor explica isso e reabre o diálogo apontando para o arquivo,
para o usuário confirmar.

## Rodando

```bat
build.bat
Editor.exe
```

ou, para desenvolver a interface com hot-reload:

```bat
dev.bat
```

Requisitos e detalhes: [README do Borion](../../README.md) e [docs/PLUGINS.md](../../docs/PLUGINS.md).
