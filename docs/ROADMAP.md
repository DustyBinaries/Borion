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
| Assets embutidos (protocolo customizado) | `ServeEmbeddedResources` + `web.rc` | ✅ básico pronto |
| `invoke('comando', args)` → `#[tauri::command]` | `borion.invoke()` → `TBorionIpc.RegisterCommand` | ✅ Fase 1 |
| Eventos `emit`/`listen` | `borion.emit/listen` ↔ `Ipc.Emit/Listen` | ✅ Fase 1 |
| `@tauri-apps/api` | Ponte injetada (`window.borion`) + pacote ESM `@borion/api` | ✅ Fase 1 |
| `tauri.conf.json` | `app.json` embutido | ⬜ Fase 3 |
| Plugins (fs, dialog, shell, store...) | Units Delphi que registram comandos | ⬜ Fase 4 |
| Capabilities / permissões | Lista de comandos permitidos por janela e origem | ⬜ Fase 5 |
| `tauri dev` / `tauri build` | CLI própria | ⬜ Fase 6 |
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

**Robustez do `TWebView2Browser`**
- [ ] Proteger **todos** os callbacks COM com `try/except`. Hoje só o `WebResourceRequested` e o
      `WebMessageReceived` fazem isso.
- [ ] Evento `ProcessFailed`: o renderer ou o browser caiu, então recriar ou avisar.
- [ ] Tratar `RecreateWnd` (`put_ParentWindow` no novo handle).
- [ ] Expor `GetDeferral` para respostas assíncronas no `WebResourceRequested`.
- [ ] `RemoveWebResourceRequestedFilter` e remoção dos handlers (`remove_*` com os tokens).
- [ ] Decodificar `%XX` (UTF-8) em `Path` e `Query`.
- [ ] Opções do ambiente (`ICoreWebView2EnvironmentOptions`): idioma, argumentos do browser.
- [ ] Testes DUnit do `TWebView2Browser` nas partes puras: mapeamento de recursos, MIME, `Path` e
      `Query` do `TWV2WebResourceRequest`. (Os do Borion já existem: `Tests`.)

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
- [x] Testes DUnit do `BorionJson` e do roteamento de comandos (`Tests`, 56 testes),
      com `TBorionIpc.ProcessMessage` / `OnPost` para testar sem WebView2.

**Lado JS**
- [x] Declarar `AddScriptToExecuteOnDocumentCreated` e injetar a ponte antes de qualquer script
      da página (`TWebView2Browser.AddScriptOnDocumentCreated`).
- [x] `borion.invoke(cmd, args, {timeout})`: Promise, com tabela de pendentes por id.
- [x] `listen` / `once` / `emit`; `listen` devolve a função para cancelar.
- [x] Mensagens do Borion isoladas dos listeners da página (`stopImmediatePropagation`).
- [x] Tipos TypeScript: `js/borion.d.ts`.
- [x] Pacote ESM `@borion/api` (`import { invoke } from '@borion/api'`) sobre a ponte injetada,
      com `isBorion()` e erro `NOT_AVAILABLE` fora do app.
- [x] Testes JS (`node:test`, 24 testes) da ponte real e do pacote, rodados pelo
      `Tests/run-tests.bat`.
- [ ] Publicar o `@borion/api` no npm (hoje: `npm install <caminho>/Borion/js`).

**Marco 1:** ✅ `await borion.invoke('somar', {a: 20, b: 22})` devolve `42` vindo de um comando
Delphi registrado em uma linha.

---

## Fase 2: Assets e servidor de frontend

- [ ] Ferramenta que **gera o `.rc` a partir de uma pasta** (ex.: o `dist/` do Vite), sem lista
      manual.
- [ ] Nomes de recurso que suportem qualquer caminho: um índice com caminho → id, em vez de
      depender do nome do recurso.
- [ ] Compressão opcional dos assets (unit `ZLib` do Delphi 7), com descompressão ao servir.
- [ ] **SPA fallback**: rota desconhecida sem extensão → `index.html`, para o roteamento do React
      e afins funcionar.
- [ ] Headers padrão: `Cache-Control`, `Content-Security-Policy` configurável, MIME completo
      (`webp`, `mp4`, `wasm`, `map`...).
- [ ] **Modo dev**: carregar de `devUrl` (ex.: `http://localhost:5173`) para usar o hot-reload do
      Vite, mantendo a ponte IPC.
- [ ] Exemplo com Vite + vanilla JS e outro com React.

**Marco 2:** um app React feito com Vite roda em modo dev com hot-reload e, no build, sai
embutido no `.exe`.

---

## Fase 3: Configuração e janelas

**Configuração (`app.json`, embutido no exe)**
- [ ] `identifier`, `productName`, `version`.
- [ ] Janela principal: `title`, `width`/`height`, `minWidth`, `resizable`, `center`,
      `maximized`, `decorations`.
- [ ] `build.devUrl`, `build.frontendDist`.
- [ ] `security.csp`, permissões (Fase 5).
- [ ] O app sobe **sem código de form**: `TApp.Run` lê a configuração e cria a janela.

**Janelas**
- [ ] `TAppWindow`: um form com browser, criado pela configuração ou em tempo de execução.
- [ ] API JS de janela: `setTitle`, `minimize`, `maximize`, `close`, `setSize`, `center`,
      `setFullscreen`, `setAlwaysOnTop`, `show`/`hide`.
- [ ] Múltiplas janelas, com rótulo e mensagens entre elas.
- [ ] Evento `close-requested` interceptável pelo JS ("deseja salvar?").
- [ ] Persistir tamanho, posição e estado (plugin *window-state*).
- [ ] **Janela sem borda** com barra de título em HTML: arrastar pela região
      (`app-region: drag` no runtime recente, ou `WM_NCHITTEST` no form).
- [ ] **DPI**: manifesto per-monitor e escalonamento. A VCL do Delphi 7 não é DPI-aware, então
      precisa de atenção.

**Marco 3:** um app de várias janelas, configurado só por `app.json` + HTML, sem escrever form.

---

## Fase 4: Plugins e APIs nativas

- [ ] **Arquitetura de plugin**: `IAppPlugin` (nome, comandos, script JS opcional, init/finalize),
      registrado no `.dpr` com uma linha.

Plugins, em ordem de utilidade:
- [ ] `dialog`: abrir e salvar arquivo, escolher pasta, mensagem e confirmação.
- [ ] `fs`: ler e gravar texto e binário, listar, criar, apagar. **Com escopo** (Fase 5).
- [ ] `shell`: abrir URL ou arquivo no programa padrão.
- [ ] `clipboard`: texto (e imagem, depois).
- [ ] `store`: chave-valor persistido em JSON no `%APPDATA%`.
- [ ] `os` / `app`: versão, caminhos (`appData`, `documents`...), sair, reiniciar.
- [ ] `http`: requisições pelo Delphi (WinInet), sem CORS.
- [ ] `notification`: balão do tray ou toast do Windows.
- [ ] `tray`: ícone, menu e cliques.
- [ ] `menu`: menu da janela e menu de contexto nativos.
- [ ] `global-shortcut`: atalhos globais (`RegisterHotKey`).
- [ ] `single-instance`: segunda execução foca a primeira e repassa os argumentos.
- [ ] `deep-link`: registrar `meuapp://` e receber os links.
- [ ] `autostart`: iniciar com o Windows.
- [ ] `log`: log em arquivo, com o lado JS repassando `console.*`.
- [ ] `sql` (opcional): SQLite ou o banco que o Delphi já acessa, um diferencial para o público
      Delphi.

**Marco 4:** um editor de texto de exemplo (abrir, salvar, menu, tray) feito só com plugins
oficiais.

---

## Fase 5: Segurança

- [ ] **Capabilities**: arquivo que diz quais comandos e plugins cada janela ou origem pode
      chamar. Negar por padrão.
- [ ] Recusar IPC vindo de origens fora do app (sites externos abertos na janela).
- [ ] **Escopos do `fs`**: só pastas permitidas (`$APPDATA/**`, `$DOCUMENT/meuapp/**`), sem `..`.
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

- [ ] `app new <nome> [--template vanilla|react|vue]`: cria o projeto (`.dpr`, `app.json`,
      `src-web/`).
- [ ] `app dev`: sobe o servidor do frontend, compila o Delphi e abre com `devUrl`.
- [ ] `app build`: build do frontend → gera `.rc` → `brcc32` → `dcc32` → exe em `dist/`.
- [ ] `app info`: versões de Delphi, runtime WebView2 e Node, para diagnóstico.
- [ ] Detectar o Delphi pelo registro, sem caminho fixo.
- [ ] Gerar os tipos TypeScript dos comandos a partir do registro Delphi (opcional e ambicioso).

**Marco 6:** do zero a um app rodando com `app new meuapp && cd meuapp && app dev`.

---

## Fase 7: Distribuição e atualização

- [ ] Instalador com **Inno Setup**, a partir de um template preenchido pelo `app.json`.
- [ ] Estratégia de runtime WebView2: *Evergreen bootstrapper* no instalador (padrão), offline
      ou *Fixed Version* (pasta junto do app).
- [ ] Ícone, versão e manifesto gerados pelo `app.json` (hoje o `.rc` é manual).
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
- [x] Repositório separado em `WebView2/` e `Borion/`, cada um com exemplo próprio
- [x] Documentação: READMEs de cada parte, `WebView2/docs/WebResourceRequested.md`,
      `Borion/docs/IPC.md`

## Ordem sugerida para começar

1. ~~Tomar as decisões de nome, biblioteca JSON e transporte do IPC.~~ ✅
2. Fase 0, só os itens de robustez dos callbacks e a reorganização de pastas.
3. ~~**Fase 1 inteira**: é o que transforma o protótipo num framework.~~ ✅
4. Fase 2: gerar o `.rc` da pasta, SPA fallback e modo dev.
5. Fase 4: só `dialog`, `fs` e `shell`, junto com o mínimo da Fase 5 (escopo do `fs` e validação
   de origem).

Esses cinco passos formam uma **v0.1** utilizável. Configuração, CLI e distribuição vêm depois.
