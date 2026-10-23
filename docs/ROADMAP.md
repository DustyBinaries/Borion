# Roadmap do Borion — Native Application Engine

De protótipo a framework "estilo Tauri" para Delphi 7. O objetivo é que alguém crie um app desktop escrevendo a **interface em HTML/CSS/JS** (inclusive
com React, Vue ou Svelte via Vite) e a **lógica nativa em Delphi 7**. A ponte entre os dois deve
ser simples, segura e tipada, e o resultado deve ser **um único `.exe` pequeno** usando o
WebView2 do sistema.

Marque os itens conforme forem concluídos. Cada fase termina num marco utilizável.

## Como o Tauri se traduz aqui

| Tauri | Equivalente aqui | Situação |
|---|---|---|
| WRY (WebView do sistema) | `TWebView2Browser` + `WebView2.pas` | ✅ básico pronto |
| Assets embutidos (protocolo customizado) | `borion pack` + `TBorionAssets` (SPA, zlib, headers) | ✅ Fase 2 |
| `invoke('comando', args)` → `#[tauri::command]` | `__BORION__.invoke()` → `TBorionIpc.RegisterCommand` | ✅ Fase 1 |
| Eventos `emit`/`listen` | `__BORION__.emit/listen` ↔ `Ipc.Emit/Listen` | ✅ Fase 1 |
| `@tauri-apps/api` | Ponte injetada (`window.__BORION__`) + pacote ESM `@borion/api` | ✅ Fase 1 |
| `tauri.conf.json` | `app.json` embutido | ✅ Fase 3 |
| Janelas (`WebviewWindow`, `emitTo`) | `BorionWindows` + plugin `window`, um IPC para todas | ✅ Fase 3 |
| Plugins (fs, dialog, shell, store...) | Units Delphi que registram comandos | ✅ Fase 4 |
| Capabilities / permissões | Lista de comandos permitidos por janela e origem | ⬜ Fase 5 |
| `create-tauri-app` / `tauri dev` / `tauri build` | CLI própria: `borion new`, `borion dev` e `borion build` | ✅ Fase 6 |
| Bundler + updater | Inno Setup + atualizador | ⬜ Fase 7 |
| Multiplataforma | **Fora de escopo**: WebView2 é só Windows, e o Delphi 7 só gera 32 bits | — |

## Decisões

- [x] **Nome:** Borion — Native Application Engine. Prefixo `Borion` nas units e `TBorion` nas
      classes (o Delphi 7 não aceita units com ponto no nome). As units antigas (`WebView2*`,
      `TWV2*`) serão renomeadas na Fase 0.
- [x] **Biblioteca JSON:** `Jsons.pas` (json4delphi, distribuída com o ACBr), com as correções de
      Unicode do `BorionJson.pas`.
- [x] **Transporte do IPC:** `postMessage` / `PostWebMessageAsJson` com id de correlação.
- [x] **Linguagem da CLI:** console app em Delphi 7.
- [x] **Delphi suportado:** só o Delphi 7.
- [ ] **Versão mínima** do Windows e do runtime WebView2.
- [ ] **Licença** do projeto.

---

## Fase 0: Fundação

O núcleo atual precisa ser robusto antes de crescer em cima dele.

**Organização**
- [x] Separar o WebView2 do Borion: `WebView2/` (controle, sem dependências) e `Borion/`
      (framework), cada um com `docs/` e `Examples/`.
- [x] Transformar a demo atual em exemplos: `WebView2/Examples/Demo` (só o controle) e
      `Borion/Examples/Demo` (só o framework).
- [ ] Renomear as units do controle para o padrão do projeto, se fizer sentido
      (`WebView2Browser` → ?), e criar `Borion/plugins/`, `templates/` e `tools/` quando surgirem.
- [ ] Pacote `.dpk` opcional para instalar o componente na paleta da IDE.

**Robustez do `TWebView2Browser`** (detalhes no [README do WebView2](../WebView2/README.md#robustez))
- [x] Proteger **todos** os callbacks COM com `try/except`: exceções vão para o
      `OnCallbackError` (ou para o tratador padrão da aplicação), nunca para o WebView2.
- [x] Evento `OnProcessFailed` com ação padrão: browser caiu → recria o WebView e volta à
      última URL (reaplicando filtros, scripts e opções); renderer caiu → recarrega.
- [x] Tratar `RecreateWnd`: o WebView é "estacionado" numa janela oculta e volta para o novo
      handle, sem recarregar a página (troca de `Parent`, `BorderStyle`...).
- [x] Resposta adiada no `WebResourceRequested`: `Response.Defer` / `Response.Complete`
      (`GetDeferral`).
- [x] `RemoveWebResourceRequestedFilter` e remoção dos handlers com os tokens (`remove_*`) ao
      liberar ou recriar.
- [x] `Path` decodificado (`%XX` em UTF-8), `RawPath` e `QueryParam` / `HasQueryParam`. O
      `Query` continua cru de propósito.
- [x] Opções do ambiente (`ICoreWebView2EnvironmentOptions`): `Language` e
      `AdditionalBrowserArguments`.
- [x] Testes DUnit do `TWebView2Browser` nas partes puras (`WebView2/Tests`, 28 testes) e
      verificação com o runtime num app de integração (quedas de processo, recriação de handle,
      resposta adiada, opções, callbacks).
**Marco 0:** o mesmo protótipo, organizado, sem crashes conhecidos e com testes.

---

## Fase 1: IPC no estilo Tauri (o coração)

Documentação: [IPC.md](IPC.md).

**Lado Delphi**
- [x] Integrar a biblioteca JSON (`Jsons.pas`) e corrigir o Unicode na fronteira
      (`BorionJson.pas`: cp1252 $80–$9F na saída, `\uXXXX` > $FF na entrada).
- [x] `TBorionIpc`: registro de comandos por nome, `RegisterCommand` (método) e
      `RegisterCommandProc` (procedure solta), com `procedure(Call: TBorionCall)`.
- [x] Protocolo das mensagens: `{__borion, kind, id, cmd, args}` → `{id, ok, result | error}`.
- [x] Erros: exceção Delphi → Promise rejeitada com `message` e `code` (`EBorionError`).
- [x] Comandos **assíncronos**: `Call.Defer` + `Resolve`/`Reject` de qualquer thread
      (encaminhados para a thread da UI).
- [x] Eventos Delphi → JS: `Ipc.Emit` / `EmitJson`, de qualquer thread.
- [x] Eventos JS → Delphi: `Ipc.Listen` / `Unlisten`, com curinga `*`.
- [x] Validar a **origem** de cada mensagem (`Source` do WebView2), negando por padrão
      (`AllowOrigin`).
- [x] Testes DUnit do `BorionJson` e do roteamento de comandos (`Borion/Tests`, 56 testes),
      com `TBorionIpc.ProcessMessage` / `OnPost` para testar sem WebView2.

**Lado JS**
- [x] Declarar `AddScriptToExecuteOnDocumentCreated` e injetar a ponte antes de qualquer script
      da página (`TWebView2Browser.AddScriptOnDocumentCreated`).
- [x] `__BORION__.invoke(cmd, args, {timeout})`: Promise, com tabela de pendentes por id.
- [x] `listen` / `once` / `emit`; `listen` devolve a função para cancelar.
- [x] Mensagens do Borion isoladas dos listeners da página (`stopImmediatePropagation`).
- [x] Tipos TypeScript: `js/borion.d.ts`.
- [x] Pacote ESM `@borion/api` (`import { invoke } from '@borion/api'`) sobre a ponte injetada,
      com `isBorion()` e erro `NOT_AVAILABLE` fora do app.
- [x] Testes JS (`node:test`, 24 testes) da ponte real e do pacote, rodados pelo
      `Borion/Tests/run-tests.bat`.
- [ ] Publicar o `@borion/api` no npm (hoje: `npm install <caminho>/Borion/js`).

**Marco 1:** ✅ `await __BORION__.invoke('somar', {a: 20, b: 22})` devolve `42` vindo de um comando
Delphi registrado em uma linha.

---

## Fase 2: Assets e servidor de frontend

Documentação: [ASSETS.md](ASSETS.md).

- [x] Ferramenta que **empacota uma pasta** (ex.: o `dist/` do Vite) sem lista manual: CLI
      `borion pack <pasta> <saida.res>`, que grava o `.res` direto (sem `.rc` nem `brcc32`).
- [x] Qualquer caminho de arquivo: um pacote único (`BORION_ASSETS`) com índice caminho → dados,
      caminhos em UTF-8 (acentos ok) e busca sem diferenciar maiúsculas.
- [x] Compressão zlib (unit `ZLib` do Delphi 7) quando reduz pelo menos 10%, pulando formatos já
      comprimidos; descompressão ao servir.
- [x] **Fallback de SPA**: rota sem extensão que não existe → `index.html`. `StartUrl` é a raiz
      `/`, não `/index.html`.
- [x] Headers padrão: `Cache-Control: no-cache`, `X-Content-Type-Options: nosniff`, CSP
      configurável, tabela de MIME completa (`webp`, `avif`, `wasm`, `map`, `mp4`, fontes...).
- [x] **Modo dev**: `--dev-url=<url>` ou `BORION_DEV_URL` → `StartUrl` aponta para o servidor do
      Vite; IPC liberado para a origem dele com `AllowOrigin(BorionOriginOf(StartUrl))`.
- [x] Exemplo React + Vite (`Examples/ViteReact`): `build.bat` e `dev.bat`.
- [x] `Examples/Demo` migrado para `borion pack` + `TBorionAssets` (é o exemplo sem bundler).
- [x] Testes DUnit do pacote e do servidor (25 testes).
- [ ] Exemplo com Vite + JS puro (sem React). Hoje, o mais próximo é o `Examples/Demo`, que é
      JS puro mas sem Vite.
- [ ] Cache em memória dos arquivos descomprimidos.
- [x] `borion dev` / `borion build` na CLI, no lugar dos `.bat` dos exemplos (feito na Fase 6).

**Marco 2:** ✅ o app React feito com Vite roda em modo dev com hot-reload (testado: edição no
`App.jsx` aparece sem recarregar a página e sem perder o estado) e, no build, sai embutido no
`.exe`.

---

## Fase 3: Configuração e janelas

Documentação: [CONFIG.md](CONFIG.md).

**Configuração (`app.json`, embutido no exe)**
- [x] `identifier`, `productName`, `version` (validados; o `app:info` devolve a versão e o
      identificador).
- [x] Janelas (`app.windows`): `label`, `url`, `create`, `visible`, `title`, `width`/`height`,
      `minWidth`/`minHeight`, `maxWidth`/`maxHeight`, `resizable`, `center`, `maximized`,
      `decorations`, `alwaysOnTop`.
- [x] `build.devUrl`, `build.frontendDist` (lidos pelo `borion build` e pelo `borion dev`).
- [x] `app.security.csp`. As permissões ficam para a Fase 5.
- [x] Embutido pelo `borion build` no `.res` da interface (recurso `BORION_CONFIG`, fora do `*.res`
      que a IDE regrava). O `borion dev` reabre o app quando ele muda. Tipo errado é erro, chave
      desconhecida é aviso, e os métodos do builder no `.dpr` vencem o arquivo.
- [x] O app sobe **sem código de form**: o `TBorionBuilder` (unit `Borion`) monta a janela, o IPC,
      os assets, o escopo e os plugins a partir do `.dpr`, como o `tauri::Builder`, partindo do
      `app.json`.
- [ ] `beforeDevCommand` / `beforeBuildCommand` (hoje, sempre `npm run dev` / `npm run build`).

**Janelas**
- [x] Janela criada pela configuração ou em tempo de execução: `TBorionWindow` (um form com
      browser) e o `BorionWindows` (`Open`, `CreateWindow`, `Find`), ou `createWindow` no JS.
- [x] API JS de janela: plugin `window` (`@borion/api/window`) com `setTitle`, `minimize`,
      `maximize`, `close`, `setSize`, `setPosition`, `center`, `setFullscreen`, `setAlwaysOnTop`,
      `setResizable`, `setDecorations`, `show`/`hide`, `state()` e os eventos `onResized`,
      `onMoved` e `onFocusChanged`.
- [x] Múltiplas janelas, com rótulo e mensagens entre elas: um `TBorionIpc` para todas (plugins
      e comandos registrados uma vez, `Call.Window`, `Ipc.EmitTo`), `emitTo` entre páginas,
      `getWindow`/`getAllWindows` e os eventos `window:created`/`window:destroyed`. Fechar a
      principal fecha o app.
- [ ] Barra de menu (`menu`) por janela: hoje, só a principal.
- [ ] `onCloseRequested` das secundárias quando a principal fecha (hoje elas fecham sem
      perguntar).
- [x] Evento `close-requested` interceptável pelo JS ("deseja salvar?"): `onCloseRequested` com
      handler `async` e `preventDefault()`. Uma página que não responde não prende a janela.
- [x] Persistir tamanho, posição e maximizado (plugin `window-state`): restaurados antes de a
      janela aparecer e gravados ao fechar, em `%APPDATA%\<identifier>\.window-state.json`.
- [x] **Janela sem borda** com barra de título em HTML: `data-borion-drag-region` (arrastar e
      duplo clique para maximizar), `startDragging`/`startResizeDragging`, a beirada da página
      redimensionando e o maximizado na área de trabalho (`Examples/Titlebar`).
- [ ] **DPI**: manifesto per-monitor e escalonamento. A VCL do Delphi 7 não é DPI-aware, então
      precisa de atenção.

**Marco 3:** ✅ um app de várias janelas, configurado só por `app.json` + HTML, sem escrever form:
o `Examples/MultiWindow` (testado: a janela de configurações do `app.json` abre sob demanda, as
notas são criadas pela página, o tema muda todas com `emitTo('*')`, as notas falam com a
principal, e fechar a principal encerra o app).

---

## Fase 4: Plugins e APIs nativas

Documentação: [PLUGINS.md](PLUGINS.md).

- [x] **Arquitetura de plugin**: `TBorionPlugin` (nome, `Install`, comandos com prefixo
      `plugin:comando`), adicionado com `Ipc.AddPlugin(...)` numa linha. `CommandLater` /
      `Ipc.Later` para comandos que abrem janelas modais fora do callback do WebView2.
- [ ] Script JS opcional por plugin (injetado junto com a ponte).
- [x] Módulos JS tipados por plugin: `@borion/api/dialog`, `/fs`, `/shell`, `/menu`, `/tray`, `/app`, `/window`,
      `/clipboard`, `/store`, `/os`, `/http`,
      `/notification`, `/single-instance`, `/deep-link`, `/autostart`,
      `/global-shortcut`, `/log`, `/window-state`.

Plugins, em ordem de utilidade:
- [x] `dialog`: abrir (arquivo, vários, pasta) e salvar, mensagem, confirmação e Sim/Não. O que
      o usuário escolhe entra no escopo do `fs`.
- [x] `fs`: ler e gravar texto (UTF-8/ANSI) e binário, `exists`, `stat`, `readDir`, `mkdir`,
      `remove` (sem seguir junções), `rename`, `copyFile`; `baseDir`. **Com escopo.**
- [x] `shell`: abrir URL (esquemas liberados) ou arquivo do escopo (nunca executáveis) e
      `showInFolder`.
- [x] `clipboard`: texto e HTML, com Unicode completo (JSON só com ASCII na ponte) e leitura
      opcional (`AllowRead`). Imagem fica para depois.
- [x] `store`: chave-valor persistido em JSON no `%APPDATA%`, com gravação atômica,
      `AutoSave`, evento `store:change`, recuperação de arquivo corrompido e API no Delphi.
- [ ] `os` / `app`: versão, caminhos (`appData`, `documents`...), sair, reiniciar. **Parcial:** o
      `app` mínimo já tem sair, mostrar, esconder, minimizar e `info` (nome, versão, exe, pid), e o
      `os` tem plataforma, arquitetura, versão real, idioma e nome do computador. Faltam os
      caminhos e reiniciar.
- [x] `http`: requisições pelo Delphi (WinInet), sem CORS, com a interface do `fetch`, escopo de
      URLs, redirecionamentos verificados, timeout e cancelamento. Falta `FormData`/streaming.
- [x] `notification`: toast nativo (WinRT) com botões e eventos de clique/fechamento, sem atalho
      no Menu Iniciar (AppUserModelID no registro); balão do `tray` no Windows 7.
- [x] `tray`: ícone, tooltip, menu, cliques, notificações, minimizar para a bandeja e
      recolocar o ícone quando o Explorer reinicia.
- [x] `menu`: barra de menu (submenus, separadores, itens com marcação, `update`) e menu de
      contexto (`popup`) nativos. Atalhos funcionam com o foco na página, pelo
      `AcceleratorKeyPressed` do WebView2 (novo evento `OnAcceleratorKeyPressed` do controle).
- [x] `global-shortcut`: atalhos globais (`RegisterHotKey`), com a sintaxe do Tauri e proteção
      contra atalhos de uma tecla de digitação só.
- [x] `single-instance`: segunda execução foca a primeira e repassa os argumentos (Unicode).
- [x] `deep-link`: registrar `meuapp://` (HKCU) e receber os links, com o app fechado ou aberto
      (via `single-instance`).
- [x] `autostart`: iniciar com o Windows (HKCU `Run`), respeitando o Gerenciador de Tarefas.
- [x] `log`: log em arquivo (UTF-8, níveis, rotação), o mesmo para o Delphi e para a página;
      `forwardConsole` repassa o `console.*`, `attachConsole` mostra o log no DevTools.
- [ ] `sql` (opcional): SQLite ou o banco que o Delphi já acessa, um diferencial para o público
      Delphi.

**Marco 4:** ✅ um editor de texto de exemplo (abrir, salvar, menu, tray) feito só com plugins
oficiais: o `Examples/Editor` abre, salva, guarda recentes e mostra na pasta (`dialog`, `fs`,
`shell`), tem barra de menu com atalhos e menu de contexto (`menu`), ícone, menu e notificação na
bandeja (`tray`) e sai pelo menu (`app`).

---

## Fase 5: Segurança

- [ ] **Capabilities**: arquivo que diz quais comandos e plugins cada janela ou origem pode
      chamar. Negar por padrão.
- [x] Recusar IPC vindo de origens fora do app (sites externos abertos na janela): `AllowOrigin`,
      negado por padrão (Fase 1).
- [x] **Escopos do `fs`**: `TBorionScope` com pastas e arquivos liberados (`$APPDATA`,
      `$DOCUMENT\meuapp`...), `..` resolvido antes da comparação, recusa de dispositivos, streams
      e nomes reservados; o `dialog` acrescenta as escolhas do usuário.
- [ ] Escopo persistido entre sessões (opcional, para recentes fora das pastas fixas).
- [ ] Junções/links simbólicos dentro de pastas liberadas: hoje só o `remove` recursivo se
      protege.
- [ ] CSP padrão restritiva, injetada nos headers dos assets.
- [ ] Bloquear navegação para fora do app por padrão (`NavigationStarting`), com lista de
      permitidos.
- [ ] Política padrão para novas janelas (abrir no navegador do sistema).
- [ ] Em release: desligar DevTools, menu de contexto padrão, atalhos de recarregar e zoom.
- [ ] Documento de modelo de ameaças: o que o JS pode e não pode fazer.

**Marco 5:** um XSS na página não consegue ler arquivos fora do escopo nem chamar comandos não
liberados.

---

## Fase 6: CLI e templates

- [x] `borion new <pasta> [--template vanilla|vite|react]`: cria o projeto (o `.dpr` com o
      `TBorionBuilder`, a interface, `build.bat`/`dev.bat`, `.rc`, `.dof`, `.gitignore`, README e o
      `app.json`) a partir dos templates em `Tools/templates`.
- [x] `borion dev`: sobe o Vite e abre o app com `--dev-url`, ou, numa interface estática, abre
      com `--dev-dir` (servida do disco, com live reload); compila só se preciso e, quando o
      Delphi muda, recompila e reabre. Fechar o app encerra tudo. Pendente: a página servida
      pelo `WebResourceRequested` leva ~2 s para trocar a cada recarga (veja
      [ASSETS](ASSETS.md#limitações)).
- [x] `borion build`: build do frontend → `borion pack` → `brcc32` (se o `.rc` mudou) → `dcc32`
      → exe na pasta do projeto, com o `WebView2Loader.dll`. O projeto vem do `app.json`
      (`build.frontendDist`, `build.devUrl`) e, sem ele, da convenção (`.dpr`,
      `web\`/`frontend\`, `.dof`). Falta a saída em `dist/`.
- [ ] `app info`: versões de Delphi, runtime WebView2 e Node, para diagnóstico.
- [x] Detectar o Delphi pelo registro, sem caminho fixo (a variável `DELPHI` vence).
- [ ] Gerar os tipos TypeScript dos comandos a partir do registro Delphi (opcional e ambicioso).

**Marco 6:** ✅ do zero a um app rodando com `borion new meuapp && cd meuapp && borion dev`
(testado com os templates `vanilla` e `vite`: o app abre, a interface recarrega, mudar o `.dpr`
recompila e reabre, e fechar o app encerra o Vite).

---

## Fase 7: Distribuição e atualização

- [ ] Instalador com **Inno Setup**, a partir de um template preenchido pelo `app.json`.
- [ ] Estratégia de runtime WebView2: *Evergreen bootstrapper* no instalador (padrão), offline
      ou *Fixed Version* (pasta junto do app).
- [x] Ícone do exe pelo `bundle.icon` do `app.json` (o `.ico` vira o `MAINICON`).
- [ ] Versão e manifesto gerados pelo `app.json` (hoje o `.rc` é manual).
- [ ] Assinatura de código (`signtool`) opcional no `app build`.
- [ ] **Updater**: JSON de versão num servidor, download, verificação de assinatura, troca do
      exe e reinício. API JS `checkUpdate()` / `installUpdate()`.

**Marco 7:** o app é publicado e se atualiza sozinho.

---

## Fase 8: Projeto e comunidade

- [ ] Documentação: guia de início, conceitos (IPC, segurança), referência de plugins, receitas.
- [ ] Exemplos: todo list, editor de texto, app com banco de dados, app de tray.
- [ ] Comparativo honesto com Tauri e Electron (tamanho, memória, limitações).
- [ ] CI: build e testes (exige Delphi num runner self-hosted).
- [ ] Changelog e versionamento semântico.

---

## Situação atual (o que o protótipo já tem)

- [x] WebView2 hospedado num controle VCL do Delphi 7, com as interfaces COM declaradas à mão
- [x] Navegação, histórico, DevTools
- [x] Eventos: `NavigationStarting`, `NavigationCompleted`, `NewWindowRequested`,
      `SourceChanged`, `DocumentTitleChanged`
- [x] Mensagens nos dois sentidos (`postMessage`, `PostWebMessage`, `ExecuteScript`)
- [x] Página embutida no executável (`RCDATA` + host virtual)
- [x] `WebResourceRequested` genérico, base para "API local"
- [x] **Borion IPC**: `invoke` / `emit` / `listen`, comandos assíncronos, validação de origem
- [x] **Assets**: `borion pack` + `TBorionAssets` (fallback de SPA, zlib, headers) e modo dev com hot-reload
- [x] **Configuração**: `app.json` embutido no exe (nome, versão, janelas, CSP, build)
- [x] **Várias janelas** no mesmo IPC, com eventos entre elas
- [x] **Plugins** `dialog`, `fs` e `shell`, com escopo de arquivos negado por padrão
- [x] **Robustez** do `TWebView2Browser`: callbacks protegidos, queda de processo, recriação de handle
- [x] Repositório separado em `WebView2/` e `Borion/`, cada um com exemplo próprio
- [x] Documentação: READMEs de cada parte, `WebView2/docs/WebResourceRequested.md`,
      `Borion/docs/IPC.md`, `Borion/docs/ASSETS.md`, `Borion/docs/CONFIG.md`

## Ordem sugerida para começar

1. ~~Tomar as decisões de nome, biblioteca JSON e transporte do IPC.~~ ✅
2. ~~Fase 0, só os itens de robustez dos callbacks e a reorganização de pastas.~~ ✅
3. ~~**Fase 1 inteira**: é o que transforma o protótipo num framework.~~ ✅
4. ~~Fase 2: gerar o `.rc` da pasta, SPA fallback e modo dev.~~ ✅
5. ~~Fase 4: só `dialog`, `fs` e `shell`, junto com o mínimo da Fase 5 (escopo do `fs` e validação
   de origem).~~ ✅

Esses cinco passos formam uma **v0.1** utilizável. Configuração, CLI e distribuição vêm depois.

**Situação:** os cinco passos estão feitos: **v0.1 completa.** Depois dela, os plugins `menu`, `tray` e o
`app` mínimo fecharam o Marco 4, a CLI `borion new`/`dev`/`build` fechou o Marco 6, e o `app.json`
com várias janelas, controladas pelo plugin `window`, fechou o Marco 3. Depois, vieram a janela sem
borda com barra de título em HTML e o *window-state*. Próximos candidatos: o resto da Fase 3
(DPI, menu nas secundárias), a segurança da Fase 5, o `sql` (opcional) e os caminhos do
`os`/`app`.
