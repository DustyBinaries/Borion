# Templates do `borion new`

Cada pasta é um template; `_comum` tem os arquivos que valem para todos (o template vence se
tiver um arquivo com o mesmo caminho).

| Template | Interface | Precisa de Node |
|---|---|---|
| `vanilla` | HTML, CSS e JS puros em `web\` (o `@borion/api` vai copiado, via import map) | Não |
| `vite` | Projeto Vite com JS puro em `frontend\`, com `dev.bat` (hot-reload) | Sim |
| `react` | Projeto React + Vite em `frontend\`, com `dev.bat` (hot-reload) | Sim |

Todos geram o app inteiro num `.dpr` com o `TBorionBuilder`, um comando Delphi de exemplo
(`saudar`) e o plugin `dialog`.

## Escrevendo um template

- **Nomes de arquivo:** `__PROGRAM__` vira o nome do programa (`MeuApp.dpr`).
- **Conteúdo:** `{{CHAVE}}` vira o valor. Uma chave desconhecida é erro, para não gerar um
  projeto quebrado.
- **Codificação:** `.dpr`, `.pas`, `.rc`, `.dof` e `.bat` ficam em cp1252 com CRLF (como o
  Delphi 7 e o `cmd` esperam); o resto, em UTF-8. Os valores são convertidos para a codificação de
  cada arquivo.

| Chave | Valor |
|---|---|
| `PROGRAM` | Nome do programa, um identificador Pascal (`meu-app` → `MeuApp`) |
| `TITLE` | Título do app, como digitado (`--title`, ou derivado da pasta: `meu-app` → `Meu App`) |
| `TITLE_PAS` | O título para uma string Pascal (aspas simples dobradas) |
| `TITLE_HTML` | O título escapado para HTML |
| `TITLE_JS` | O título para uma string JS entre aspas simples |
| `TITLE_RC` | O título para uma string do `.rc` (aspas duplas dobradas) |
| `TITLE_COMMENT` | O título numa linha só, para comentários |
| `NPM_NAME` | Nome de pacote npm (`Meu App` → `meu-app`) |
| `BORION_HOME`, `WEBVIEW2_HOME` | Pastas do Borion e do WebView2 |
| `JSON4DELPHI`, `ACBR_COMUM` | Pastas da `Jsons.pas` e do `ACBr.inc` |
| `SEARCH_PATH` | *Search path* completo para o `.dof` |
| `BORION_JS` | Pasta `Borion/js` com barras normais (para o npm e o Vite) |
| `DEV_PORT` | Porta do Vite no `dev.bat` (`--port`, padrão 5173) |
