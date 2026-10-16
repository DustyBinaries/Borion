# Borion — Native Application Engine

Framework "estilo Tauri" para **Delphi 7**: a interface em HTML/CSS/JS rodando no WebView2, e a
lógica nativa em Delphi, com uma ponte `invoke` / `emit` / `listen` entre os dois. Ainda em
construção: veja o [roadmap](docs/ROADMAP.md).

```js
const soma = await borion.invoke('somar', { a: 20, b: 22 });   // comando Delphi -> 42
```

```pascal
program MeuApp;   // o app inteiro: sem form, a janela é montada pelo builder

uses
  Borion, BorionIpc, BorionFs, BorionDialog;

{$R *.res}
{$R web.res}   // o frontend, empacotado pelo "borion pack"

procedure Somar(Call: TBorionCall);
begin
  Call.Result.AsNumber := Call.ArgNum('a') + Call.ArgNum('b');
end;

begin
  TBorionBuilder.Create('Meu App')
    .Size(1000, 700)
    .AllowDir('$APPDATA')                 // escopo de arquivos: negado por padrão
    .Plugin(TBorionFsPlugin.Create)
    .Plugin(TBorionDialogPlugin.Create)
    .Command('somar', Somar)
    .Run;
end.
```

O Borion roda sobre o [`TWebView2Browser`](WebView2/README.md) e acrescenta:

- **App sem form** (`TBorionBuilder`): o app inteiro escrito no `.dpr`, como o `tauri::Builder`.
  A janela, o IPC e o frontend embutido são montados pelo `Run`. Veja [Criando um app](#criando-um-app).
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
- **Integração com o Windows**: `notification` (notificações nativas com botões),
  `single-instance` (o app abre uma vez só e recebe os argumentos das próximas execuções),
  `deep-link` (links `meuapp://` abrem o app), `autostart` (iniciar com o Windows) e
  `global-shortcut` (atalhos que funcionam com o app em segundo plano).
- **Log**: `log` em arquivo com níveis e rotação, o mesmo para o Delphi e para a página, com o
  `console` da página repassado.

## Criando um app

O jeito mais rápido é a CLI, que gera um projeto pronto para compilar:

```bat
Tools\borion.exe new meu-app                    :: HTML/JS puro, sem Node
Tools\borion.exe new meu-app --template vite     :: Vite (ou --template react)
cd meu-app
build.bat                                         :: compila o MeuApp.exe com a interface embutida
dev.bat                                           :: (vite e react) Vite com hot-reload + o app
```

`borion new <pasta> [--template vanilla|vite|react] [--title "Título"] [--port 5173]` cria:

- o `.dpr` com o `TBorionBuilder` e um comando Delphi de exemplo;
- a interface (`web\` ou `frontend\`);
- o `build.bat` (e o `dev.bat`);
- o `.rc` com a versão do exe;
- o `.dof` com o *Search path*, para abrir na IDE;
- o `.gitignore` e um README.

O projeto aponta para esta pasta do Borion (`BORION_HOME` no `build.bat`). Os templates ficam em
[`Tools/templates`](Tools/templates/README.md).

O `TBorionBuilder` (unit `Borion`) monta o app a partir do `.dpr`, encadeando a configuração e
terminando no `Run`:

| Método | O que faz |
|---|---|
| `TBorionBuilder.Create(Titulo)` | Título do app e da janela (já vale para os plugins criados na mesma expressão) |
| `.Size(L, A)`, `.MinSize(L, A)`, `.Maximized` | Tamanho da janela (padrão 1000×700, centralizada) |
| `.FixedTitle` | O caption não acompanha o `document.title` da página |
| `.Plugin(P)` | Adiciona um plugin |
| `.Command(nome, Proc)` / `.Commands(Registrar)` | Um comando (`procedure Proc(Call: TBorionCall)`) ou uma procedure que registra vários (`procedure Registrar(Ipc: TBorionIpc)`) |
| `.AllowDir(pasta)` / `.AllowFile(arquivo)` | Escopo de arquivos do app, usado pelos plugins `fs`, `dialog` e `shell` criados sem escopo |
| `.Url(url)` / `.AllowOrigin(origem)` | Abrir uma URL em vez do frontend embutido; liberar mais uma origem no IPC |
| `.UserDataFolder(pasta)` | Pasta de dados do WebView2 |
| `.Setup(Proc)` | `procedure Proc(Window: TBorionWindow)`, depois de montar e antes de abrir a página: acesso ao form, ao browser, ao IPC e aos plugins |
| `.OnCloseQuery(Proc)` / `.OnClose(Proc)` | Confirmar ou guardar algo ao fechar |
| `.Run` | Roda o app e libera o builder |

- **Plugins com configuração** são criados antes, numa variável:
  `Tray := TBorionTrayPlugin.Create; Tray.MinimizeToTray := True;` e depois `.Plugin(Tray)`.
- **Uma instância só:** `.Plugin(TBorionSingleInstancePlugin.Create('Empresa.MeuApp'))`. Numa
  segunda execução, o plugin entrega os argumentos à primeira e o `Run` termina sem criar janela.
- A janela (`TBorionWindow`) tem o browser ocupando tudo, o ícone do exe, e no modo dev mostra a
  URL do servidor no título.
- O `.dpr` só lista as units que o app usa (`Borion` e os plugins); as pastas do Borion, de
  `Borion/Plugins` e do WebView2 vão no *Search path* (os exemplos fazem isso no `build.bat` e no
  `.dof`).

**Num form existente:** para pôr o Borion dentro de um app Delphi que já tem forms, crie o
`TWebView2Browser`, o `TBorionIpc` e o `TBorionAssets` no próprio form, como no
[`Examples/Demo`](#exemplos) e no [guia do IPC](docs/IPC.md#configuração).

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
| `Borion.pas` | `TBorionBuilder` e `TBorionWindow`: o app montado a partir do `.dpr`, sem form |
| `BorionIpc.pas` | `TBorionIpc` (comandos, eventos, origens), `TBorionCall`, `EBorionError` e a ponte JS injetada |
| `BorionJson.pas` | Correções de Unicode na fronteira JSON entre o JS e o Delphi 7 |
| `BorionAssets.pas` | `TBorionAssets`: serve o frontend embutido (SPA, headers, MIME) e o modo dev |
| `BorionPack.pas` | Formato do pacote de assets, compressão e leitura/escrita de `.res` |
| `Plugins/` | `TBorionScope` (escopo de arquivos) e os plugins `fs`, `dialog`, `shell`, `menu`, `tray`, `app`, `clipboard`, `store`, `os`, `http`, `notification`, `single-instance`, `deep-link`, `autostart`, `global-shortcut` e `log` ([docs](docs/PLUGINS.md)) |
| `Tools/` | CLI `borion` (console Delphi): `borion new` (com os templates em `Tools/templates`), `borion pack`, `borion list` |
| `js/` | Pacote ESM [`@borion/api`](js/README.md) para apps com bundler, e `borion.d.ts` (tipos do `window.borion`) |
| `docs/IPC.md` | Guia completo do IPC |
| `docs/ASSETS.md` | Assets do frontend, `borion pack`, fallback de SPA e modo dev |
| `docs/ROADMAP.md` | Roadmap do framework |
| `Examples/Demo/` | Exemplo com todas as funcionalidades do IPC, num form Delphi tradicional, página em HTML/JS puro (veja abaixo) |
| `Examples/ViteReact/` | App React + Vite: build embutido no exe e modo dev com hot-reload ([README](Examples/ViteReact/README.md)) |
| `Examples/Editor/` | Editor de texto com Vite + JS puro, feito só com os plugins oficiais ([README](Examples/Editor/README.md)) |
| `Examples/Menu/`, `Tray/`, `App/`, `Clipboard/`, `Store/`, `Os/`, `Http/`, `Notification/`, `SingleInstance/`, `DeepLink/`, `Autostart/`, `GlobalShortcut/`, `Log/` | Um exemplo pequeno para cada plugin, sem bundler ([Menu](Examples/Menu/README.md), [Tray](Examples/Tray/README.md), [App](Examples/App/README.md), [Clipboard](Examples/Clipboard/README.md), [Store](Examples/Store/README.md), [Os](Examples/Os/README.md), [Http](Examples/Http/README.md), [Notification](Examples/Notification/README.md), [SingleInstance](Examples/SingleInstance/README.md), [DeepLink](Examples/DeepLink/README.md), [Autostart](Examples/Autostart/README.md), [GlobalShortcut](Examples/GlobalShortcut/README.md), [Log](Examples/Log/README.md)) |
| `Tests/` | Testes DUnit e o `run-tests.bat`, que roda também os testes JS (veja abaixo) |

Para usar num projeto: ponha no *Search path* as pastas `WebView2/`, `Borion/` e
`Borion/Plugins/`, a da `Jsons.pas` e a do `ACBr.inc`. Os exemplos (exceto o `Demo`) são um
`.dpr` só, com o `TBorionBuilder`.

## Exemplos

**[`Examples/Editor/`](Examples/Editor/README.md):** um editor de texto (abrir, salvar, recentes)
sem nenhum comando Delphi próprio, só com os plugins oficiais. Mostra o escopo de arquivos na
prática, a barra de menu nativa com atalhos, o ícone na bandeja e preferências no `store`.

**[`Examples/Menu/`](Examples/Menu/README.md), [`Tray/`](Examples/Tray/README.md),
[`App/`](Examples/App/README.md), [`Clipboard/`](Examples/Clipboard/README.md),
[`Store/`](Examples/Store/README.md), [`Os/`](Examples/Os/README.md),
[`Http/`](Examples/Http/README.md), [`Notification/`](Examples/Notification/README.md),
[`SingleInstance/`](Examples/SingleInstance/README.md), [`DeepLink/`](Examples/DeepLink/README.md),
[`Autostart/`](Examples/Autostart/README.md), [`GlobalShortcut/`](Examples/GlobalShortcut/README.md) e
[`Log/`](Examples/Log/README.md):** um exemplo isolado para cada plugin, com página em HTML/JS
puro e o app inteiro num `.dpr` de poucas linhas (`TBorionBuilder`). Mostram tudo o que o plugin faz: barra de menu,
atalhos, `update` e `popup`; ícone, menu, notificações e minimizar para a bandeja; `app.info`,
minimizar, esconder e sair passando pelo `OnCloseQuery`; copiar e colar texto com emoji e
copiar HTML; preferências que sobrevivem entre execuções, inclusive a posição da janela,
gravada pelo Delphi no mesmo store; a versão real do Windows; o `fetch` do Borion buscando,
lado a lado, uma página que o `fetch` do navegador não alcança por CORS; notificações nativas com
botões; o app que abre uma vez só e recebe os argumentos das próximas execuções; links
`borion-exemplo://` abrindo o app; a inicialização com o Windows; atalhos globais com o app
em segundo plano; e o log do Delphi e da página no mesmo arquivo.

**[`Examples/ViteReact/`](Examples/ViteReact/README.md):** um app React com Vite. O `build.bat`
gera um único exe com o frontend embutido; o `dev.bat` abre o app ligado ao servidor do Vite,
com hot-reload.

**`Examples/Demo/`:** mostra o Borion dentro de um form Delphi tradicional, sem bundler. A janela Delphi tem só o
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

Roda **245 testes DUnit** e **67 testes JS** (`node:test`):

- DUnit: o Unicode do `BorionJson`, o roteamento do `TBorionIpc` sem WebView2, e o pacote de
  assets e o `TBorionAssets` (compressão, caminhos UTF-8, `.res`, fallback de SPA, headers,
  modo dev);
  e os plugins (escopo contra `..`, prefixo vizinho, dispositivos e streams; todo o `fs` pelo IPC,
  inclusive uma junção apontando para fora do escopo; política do `shell`; `Ipc.Later`; menu
  montado a partir do JSON, atalhos e popup; bandeja com o `Shell_NotifyIcon` capturado; `app`;
  `clipboard` com a área de transferência real e emoji; `store` com arquivo corrompido,
  editado à mão e sem `AutoSave`; o JSON só com ASCII; `os`; `http` contra um servidor HTTP
  local: escopo, redirecionamentos, timeout, cancelamento, binário e limites; XML e eventos do
  `notification`; entrega dos argumentos do `single-instance` com Unicode; registro do
  `deep-link` e do `autostart` no HKCU, com caminho Unicode e o "Desabilitado" do Gerenciador de
  Tarefas; atalhos globais (sintaxe, conflito com outro programa, WM_HOTKEY); log com níveis,
  rotação, várias threads e Unicode; o `TBorionBuilder` e o escopo de arquivos do app; o `borion new` com os templates de verdade);
- JS: a ponte real, o pacote `@borion/api` e os módulos `dialog`, `fs`, `shell`, `menu`, `tray`, `app`, `clipboard`, `store`, `os`, `http`, `notification`,
  `single-instance`, `deep-link`, `autostart`, `global-shortcut` e `log`.
Precisa do [DUnit](https://dunit.sourceforge.net/) (variável `DUNIT`, padrão
`C:\dev\lib\dunit\src`) e do Node.js 18+. Detalhes no [guia do IPC](docs/IPC.md#testes).
