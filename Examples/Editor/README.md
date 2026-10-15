# Exemplo: Borion Editor

Um editor de texto feito **só com os plugins oficiais** (`dialog`, `fs`, `shell`): não há nenhum
comando Delphi próprio. O frontend é Vite + JS puro, sem framework.

| | |
|---|---|
| `frontend/src/main.js` | Toda a lógica: abrir, salvar, recentes, atalhos |
| `uPrincipal.pas` | A janela: browser, IPC, assets, escopo e os 3 plugins (~20 linhas úteis) |
| `build.bat` / `dev.bat` | Build de produção / modo dev com hot-reload (porta 5174) |

## O que ele faz

- **Novo, Abrir, Salvar, Salvar como**, com atalhos `Ctrl+N`, `Ctrl+O`, `Ctrl+S` e
  `Ctrl+Shift+S` (`dialog.open`, `dialog.save`, `fs.readTextFile`, `fs.writeTextFile`).
- Pergunta antes de descartar alterações (`dialog.ask`).
- **Arquivos recentes** em `%APPDATA%\Borion Editor\recentes.json` (`fs` com `baseDir: appData`).
- **Mostrar na pasta** (`shell.showInFolder`) e link externo (`shell.open`).
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
