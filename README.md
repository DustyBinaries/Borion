# Borion — Native Application Engine

Framework "estilo Tauri" para **Delphi 7**: a interface em HTML/CSS/JS rodando no WebView2, e a
lógica nativa em Delphi, com uma ponte `invoke` / `emit` / `listen` entre os dois. Ainda em
construção: veja o [roadmap](docs/ROADMAP.md).

```js
const soma = await borion.invoke('somar', { a: 20, b: 22 });   // comando Delphi -> 42
```

```pascal
FIpc := TBorionIpc.Create(Self, FBrowser);   // antes do CreateWebView
FIpc.AllowOrigin('https://app.local');        // IPC negado por padrão
FIpc.RegisterCommand('somar', CmdSomar);

procedure TForm1.CmdSomar(Call: TBorionCall);
begin
  Call.Result.AsNumber := Call.ArgNum('a') + Call.ArgNum('b');
end;
```

O Borion roda sobre o [`TWebView2Browser`](WebView2/README.md) e acrescenta:

- **Comandos**: `borion.invoke(cmd, args)` → procedure Delphi, com resultado numa Promise.
- **Erros** com código: exceção Delphi → Promise rejeitada com `error.code`.
- **Comandos assíncronos**: `Call.Defer` + `Resolve`/`Reject`, inclusive de outras threads.
- **Eventos** nos dois sentidos: `Ipc.Emit` → `borion.listen`; `borion.emit` → `Ipc.Listen`.
- **Segurança por origem**: só documentos de origens liberadas usam o IPC.
- **Unicode correto** entre o JS e o ANSI do Delphi 7.
- **Frontend embutido no exe**: `borion pack` empacota o `dist/` (Vite ou qualquer pasta) e o
  `TBorionAssets` serve com fallback de SPA e headers padrão.
- **Modo dev**: `--dev-url=http://localhost:5173` abre o servidor do Vite, com hot-reload.
- **Plugins** `dialog`, `fs` e `shell`, com escopo de arquivos negado por padrão: o app só toca
  as pastas liberadas e o que o usuário escolher nos diálogos.
- **Menus e bandeja**: plugins `menu` (barra de menu com atalhos de teclado e menu de contexto
  nativos), `tray` (ícone, menu e notificações na bandeja) e `app` (sair, mostrar, minimizar).
- **Dados**: `clipboard` (texto e HTML) e `store` (chave-valor persistido em JSON), com Unicode
  completo, inclusive emoji, apesar de o Delphi 7 ser ANSI.
- **Sistema e rede**: `os` (versão real do Windows, arquitetura, idioma) e `http` (o `fetch` feito
  pelo Delphi, sem CORS, com escopo de URLs, timeout e cancelamento).

## Requisitos

- Os requisitos do [WebView2](WebView2/README.md#requisitos) (Delphi 7, WebView2 Runtime,
  `WebView2Loader.dll`).
- **Jsons.pas** (json4delphi, distribuída com o ACBr). Os `build.bat` procuram em
  `C:\dev\lib\ACBr\Fontes\Terceiros\json4delphi\src`, e o `ACBr.inc`, que ela inclui, em
  `C:\dev\lib\ACBr\Fontes\ACBrComum`. Para outros caminhos, defina as variáveis `JSON4DELPHI` e
  `ACBR_COMUM` e ajuste o *Search path* do projeto na IDE (no exemplo, `BorionDemo.dof`).

## Arquivos

| Arquivo | O que é |
|---|---|
| `BorionIpc.pas` | `TBorionIpc` (comandos, eventos, origens), `TBorionCall`, `EBorionError` e a ponte JS injetada |
| `BorionJson.pas` | Correções de Unicode na fronteira JSON entre o JS e o Delphi 7 |
| `BorionAssets.pas` | `TBorionAssets`: serve o frontend embutido (SPA, headers, MIME) e o modo dev |
| `BorionPack.pas` | Formato do pacote de assets, compressão e leitura/escrita de `.res` |
| `Plugins/` | `TBorionScope` (escopo de arquivos) e os plugins `fs`, `dialog`, `shell`, `menu`, `tray`, `app`, `clipboard`, `store`, `os` e `http` ([docs](docs/PLUGINS.md)) |
| `Tools/` | CLI `borion` (console Delphi): `borion pack`, `borion list` |
| `js/` | Pacote ESM [`@borion/api`](js/README.md) para apps com bundler, e `borion.d.ts` (tipos do `window.borion`) |
| `docs/IPC.md` | Guia completo do IPC |
| `docs/ASSETS.md` | Assets do frontend, `borion pack`, fallback de SPA e modo dev |
| `docs/ROADMAP.md` | Roadmap do framework |
| `Examples/Demo/` | Exemplo com todas as funcionalidades do IPC, página em HTML/JS puro (veja abaixo) |
| `Examples/ViteReact/` | App React + Vite: build embutido no exe e modo dev com hot-reload ([README](Examples/ViteReact/README.md)) |
| `Examples/Editor/` | Editor de texto com Vite + JS puro, feito só com os plugins oficiais ([README](Examples/Editor/README.md)) |
| `Examples/Menu/`, `Tray/`, `App/`, `Clipboard/`, `Store/`, `Os/`, `Http/` | Um exemplo pequeno para cada plugin, sem bundler ([Menu](Examples/Menu/README.md), [Tray](Examples/Tray/README.md), [App](Examples/App/README.md), [Clipboard](Examples/Clipboard/README.md), [Store](Examples/Store/README.md), [Os](Examples/Os/README.md), [Http](Examples/Http/README.md)) |
| `Tests/` | Testes DUnit e o `run-tests.bat`, que roda também os testes JS (veja abaixo) |

Para usar num projeto: adicione as units do `WebView2/` e do `Borion/` e ponha a pasta da
`Jsons.pas` e a do `ACBr.inc` no *Search path*.

## Exemplos

**[`Examples/Editor/`](Examples/Editor/README.md):** um editor de texto (abrir, salvar, recentes)
sem nenhum comando Delphi próprio, só com os plugins oficiais. Mostra o escopo de arquivos na
prática, a barra de menu nativa com atalhos, o ícone na bandeja e preferências no `store`.

**[`Examples/Menu/`](Examples/Menu/README.md), [`Tray/`](Examples/Tray/README.md),
[`App/`](Examples/App/README.md), [`Clipboard/`](Examples/Clipboard/README.md),
[`Store/`](Examples/Store/README.md), [`Os/`](Examples/Os/README.md) e
[`Http/`](Examples/Http/README.md):** um exemplo isolado para cada plugin, com página em HTML/JS
puro e uma janela Delphi de poucas linhas. Mostram tudo o que o plugin faz: barra de menu,
atalhos, `update` e `popup`; ícone, menu, notificações e minimizar para a bandeja; `app.info`,
minimizar, esconder e sair passando pelo `OnCloseQuery`; copiar e colar texto com emoji e
copiar HTML; preferências que sobrevivem entre execuções, inclusive a posição da janela,
gravada pelo Delphi no mesmo store; a versão real do Windows; e o `fetch` do Borion buscando,
lado a lado, uma página que o `fetch` do navegador não alcança por CORS.

**[`Examples/ViteReact/`](Examples/ViteReact/README.md):** um app React com Vite. O `build.bat`
gera um único exe com o frontend embutido; o `dev.bat` abre o app ligado ao servidor do Vite,
com hot-reload.

**`Examples/Demo/`:** mostra o modelo de app do Borion sem bundler. A janela Delphi tem só o
browser e um painel de log; a interface inteira é a página `web\` (HTML/JS puro, empacotada pelo
`borion pack`), e a lógica nativa são os comandos de `uComandos.pas`, escritos como procedures
soltas.

| Seção da página | O que demonstra |
|---|---|
| 1. Comandos | `somar`, `saudacao` (Unicode nos dois sentidos), `info` (objeto), `listarArquivos` (array) |
| 2. Erros | `EBorionError`, validação, comando inexistente e `timeout` no JS |
| 3. Comando assíncrono | `tarefaLonga`: `Call.Defer`, thread, eventos de progresso, `Resolve` |
| 4. Eventos | `borion.emit` → log da janela; botão "Emitir" da janela → `borion.listen` |
| 5. Segurança | Origem liberada com `AllowOrigin`; outras recebem `FORBIDDEN_ORIGIN` |

Abra `BorionDemo.dpr` na IDE, ou pela linha de comando:

```bat
Examples\Demo\build.bat
```

## Testes

```bat
Tests\run-tests.bat
```

Roda **194 testes DUnit** e **56 testes JS** (`node:test`):

- DUnit: o Unicode do `BorionJson`, o roteamento do `TBorionIpc` sem WebView2, e o pacote de
  assets e o `TBorionAssets` (compressão, caminhos UTF-8, `.res`, fallback de SPA, headers,
  modo dev);
  e os plugins (escopo contra `..`, prefixo vizinho, dispositivos e streams; todo o `fs` pelo IPC,
  inclusive uma junção apontando para fora do escopo; política do `shell`; `Ipc.Later`; menu
  montado a partir do JSON, atalhos e popup; bandeja com o `Shell_NotifyIcon` capturado; `app`;
  `clipboard` com a área de transferência real e emoji; `store` com arquivo corrompido,
  editado à mão e sem `AutoSave`; o JSON só com ASCII; `os`; `http` contra um servidor HTTP
  local: escopo, redirecionamentos, timeout, cancelamento, binário e limites);
- JS: a ponte real, o pacote `@borion/api` e os módulos `dialog`, `fs`, `shell`, `menu`, `tray`, `app`, `clipboard`, `store`, `os` e `http`.
Precisa do [DUnit](https://dunit.sourceforge.net/) (variável `DUNIT`, padrão
`C:\dev\lib\dunit\src`) e do Node.js 18+. Detalhes no [guia do IPC](docs/IPC.md#testes).
