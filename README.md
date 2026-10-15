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
| `Tools/` | CLI `borion` (console Delphi): `borion pack`, `borion list` |
| `js/` | Pacote ESM [`@borion/api`](js/README.md) para apps com bundler, e `borion.d.ts` (tipos do `window.borion`) |
| `docs/IPC.md` | Guia completo do IPC |
| `docs/ASSETS.md` | Assets do frontend, `borion pack`, fallback de SPA e modo dev |
| `docs/ROADMAP.md` | Roadmap do framework |
| `Examples/Demo/` | Exemplo com todas as funcionalidades do IPC, página em HTML/JS puro (veja abaixo) |
| `Examples/ViteReact/` | App React + Vite: build embutido no exe e modo dev com hot-reload ([README](Examples/ViteReact/README.md)) |
| `Tests/` | Testes DUnit e o `run-tests.bat`, que roda também os testes JS (veja abaixo) |

Para usar num projeto: adicione as units do `WebView2/` e do `Borion/` e ponha a pasta da
`Jsons.pas` e a do `ACBr.inc` no *Search path*.

## Exemplos

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

Roda **81 testes DUnit** e **24 testes JS** (`node:test`):

- DUnit: o Unicode do `BorionJson`, o roteamento do `TBorionIpc` sem WebView2, e o pacote de
  assets e o `TBorionAssets` (compressão, caminhos UTF-8, `.res`, fallback de SPA, headers,
  modo dev);
- JS: a ponte real e o pacote `@borion/api`.
Precisa do [DUnit](https://dunit.sourceforge.net/) (variável `DUNIT`, padrão
`C:\dev\lib\dunit\src`) e do Node.js 18+. Detalhes no [guia do IPC](docs/IPC.md#testes).
