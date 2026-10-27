# WebView2 para Delphi 7

O **Microsoft Edge WebView2** num controle VCL do **Delphi 7**: o `TWebView2Browser`.

O Delphi 7 não tem o `TEdgeBrowser` (que só existe a partir do 10.4). Por isso as interfaces COM do
WebView2 foram declaradas à mão em `WebView2.pas`, a partir do `WebView2.h` do pacote NuGet oficial
`Microsoft.Web.WebView2`, e embrulhadas no controle.

## Requisitos

- Delphi 7 (gera executáveis 32 bits).
- **WebView2 Runtime** instalado. Já vem no Windows 11; no Windows 10 use o instalador "Evergreen":
  <https://developer.microsoft.com/microsoft-edge/webview2/>
- **`WebView2Loader.dll` versão x86** na pasta do executável. Está nesta pasta; os `build.bat` dos
  exemplos a copiam para junto do exe (veja [Origem do `WebView2Loader.dll`](#origem-do-webview2loaderdll)).

Nenhuma biblioteca externa é necessária.

### Origem do `WebView2Loader.dll`

A DLL desta pasta é a de `build\native\x86\` do pacote NuGet oficial da Microsoft, sem alterações:

| | |
|---|---|
| Pacote | [`Microsoft.Web.WebView2`](https://www.nuget.org/packages/Microsoft.Web.WebView2) **1.0.4258.31** |
| Caminho no pacote | `build/native/x86/WebView2Loader.dll` |
| Versão do arquivo | 1.0.4258.31 |
| Assinatura | Authenticode, `CN=Microsoft Corporation` |
| SHA-256 | `87C61E2CAE380112C60853E28178B8EA9A0D63739FC03CEAD680D4AD3FDE6B7D` |

Para conferir ou baixar de novo (o `.nupkg` é um zip):

```powershell
Invoke-WebRequest https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/1.0.4258.31 -OutFile webview2.zip
Expand-Archive webview2.zip webview2
Get-FileHash webview2\build\native\x86\WebView2Loader.dll        # deve dar o SHA-256 acima
Get-AuthenticodeSignature webview2\build\native\x86\WebView2Loader.dll
```

Para atualizar, troque a versão na URL, copie a DLL nova para esta pasta e atualize esta tabela.

## Arquivos

| Arquivo | O que é |
|---|---|
| `WebView2.pas` | Interfaces COM do WebView2 e carregamento dinâmico do `WebView2Loader.dll` |
| `WebView2Browser.pas` | `TWebView2Browser`, o controle VCL que hospeda o navegador |
| `WebView2Loader.dll` | Loader x86 do pacote NuGet oficial |
| `docs/` | WebResourceRequested ([English](docs/WebResourceRequested.md), [português](docs/WebResourceRequested_pt-BR.md)): interceptação de requisições em detalhe |
| `Tests/` | Testes DUnit (`run-tests.bat`) |
| `Examples/Demo/` | Exemplo com todos os recursos do controle (veja abaixo) |

Para usar num projeto, adicione `WebView2.pas` e `WebView2Browser.pas` (ou ponha esta pasta no
*Search path*) e coloque o `WebView2Loader.dll` ao lado do executável.

## Exemplo

`Examples/Demo/` é um navegador com barra de endereço e um painel para experimentar cada recurso:
eventos de navegação, bloqueio de URLs, política de novas janelas, `PostWebMessage` /
`ExecuteScript`, página embutida no exe e uma "API local" com `WebResourceRequested`.

Abra `WebView2Demo.dpr` na IDE, ou pela linha de comando:

```bat
Examples\Demo\build.bat
```

O `build.bat` gera o `WebView2Demo.res` a partir do `.rc` (se ainda não existir), **sempre regera o
`web.res`** a partir do `web.rc` (os arquivos da pasta `web\`), chama o `dcc32` e copia o
`WebView2Loader.dll` para a pasta. Se compilar pela IDE depois de mexer em `web\`, rode antes
`brcc32 web.rc` (ou o `build.bat`). Se o Delphi não estiver em `C:\bin\Borland\Delphi7`, defina a
variável `DELPHI` antes.

Os fontes (`.pas`, `.dfm`, `.dpr`) estão em **ANSI (cp1252) com CRLF**, como o Delphi 7 espera.
Não os salve em UTF-8, ou os acentos das strings vão quebrar.

## Usando o `TWebView2Browser`

O controle é criado em tempo de execução (não é instalado na paleta):

```pascal
FBrowser := TWebView2Browser.Create(Self);
FBrowser.Parent := Self;
FBrowser.Align := alClient;
FBrowser.OnInitialized := BrowserInitialized;
FBrowser.CreateWebView;                    // assíncrono: termina em OnInitialized
FBrowser.Navigate('https://example.com');  // pode ser chamado antes; fica pendente
```

### Métodos

| Método | Descrição |
|---|---|
| `CreateWebView` | Cria o ambiente e o navegador (assíncrono). Levanta `EWebView2Error` se faltar o loader ou o runtime |
| `Ready` | `True` depois que o navegador foi criado |
| `Recreate` | Fecha o WebView e cria outro, voltando à última URL (é o que o `OnProcessFailed` faz quando o browser cai) |
| `Navigate(Url)` / `NavigateToString(Html)` | Navega para uma URL / carrega HTML direto |
| `GoBack`, `GoForward`, `Reload`, `Stop` | Navegação |
| `CanGoBack`, `CanGoForward`, `Source` | Estado da navegação |
| `ExecuteScript(Js)` | Executa JavaScript; o resultado (JSON) chega em `OnScriptResult` |
| `AddScriptOnDocumentCreated(Js)` | Script que roda em todo documento novo, antes dos scripts da página. Pode ser chamado antes do `CreateWebView` |
| `PostWebMessage(Texto)` / `PostWebMessageAsJson(Json)` | Envia uma mensagem para a página |
| `OpenDevTools` | Abre o DevTools |
| `NotifyParentWindowPositionChanged` | Chamar no `WM_MOVE` do form, para popups e dropdowns abrirem no lugar certo |
| `ServeEmbeddedResources(Host)` | Serve os recursos `RCDATA` do exe em `https://<Host>/` (veja abaixo) |
| `AddWebResourceRequestedFilter(Padrao, [Contexto])` | Faz as URLs que casam com o padrão (curinga `*`) passarem pelo `OnWebResourceRequested` |
| `RemoveWebResourceRequestedFilter(Padrao, [Contexto])` / `ResourceFilterCount` | Remove um filtro (mesmo padrão e contexto) / quantos há |
| `EmbeddedUrl(Caminho)` | Monta a URL de um recurso embutido, ex.: `https://app.localhost/index.html` |

### Propriedades

| Propriedade | Descrição |
|---|---|
| `UserDataFolder` | Pasta de cache/cookies. Padrão: `%LOCALAPPDATA%\<nome do exe>\WebView2` |
| `Language` | Idioma da interface do WebView2 e do `Accept-Language`, ex.: `'pt-BR'`. Antes do `CreateWebView` |
| `AdditionalBrowserArguments` | Argumentos do Chromium, ex.: `'--disable-gpu'`. Antes do `CreateWebView` |
| `DevToolsEnabled` | `False`: sem DevTools (F12, Ctrl+Shift+I, "Inspecionar"). Padrão `True`. Antes do `CreateWebView` |
| `ContextMenusEnabled` | `False`: sem o menu de contexto padrão do WebView2 (botão direito). Padrão `True`. Antes do `CreateWebView` |
| `ZoomControlEnabled` | `False`: o usuário não dá zoom (Ctrl+roda, Ctrl+`+`/`-`). Padrão `True`. Antes do `CreateWebView` |
| `WebView` / `Controller` | As interfaces COM, para o que o controle não embrulha |

### Eventos

| Evento | Quando |
|---|---|
| `OnInitialized(ErrorCode)` | O navegador foi criado (ou falhou: `ErrorCode` é o HRESULT) |
| `OnNavigationStarting(Uri, IsUserInitiated, IsRedirected, var Cancel)` | Antes de cada navegação. `Cancel := True` impede o carregamento |
| `OnNavigationCompleted(Success, WebErrorStatus)` | A navegação terminou |
| `OnNewWindowRequested(Uri, IsUserInitiated, var Action)` | A página pediu uma nova janela (`target="_blank"`, `window.open`). `Action` decide o que acontece |
| `OnSourceChanged(Url)` | A URL atual mudou |
| `OnTitleChanged(Titulo)` | O `document.title` mudou |
| `OnWebMessageReceived(Msg)` | A página chamou `chrome.webview.postMessage(...)` |
| `OnWebMessageJson(Json, Source, var Handled)` | Antes do anterior: a mensagem como JSON e a URL de origem. `Handled := True` o suprime. Útil para implementar um protocolo |
| `OnAcceleratorKeyPressed(KeyEventKind, VirtualKey, var Handled)` | Uma tecla com o foco na página, antes de ela chegar ao JS (o teclado vai direto para o processo do WebView2, e a VCL não a vê). `KeyEventKind`: `COREWEBVIEW2_KEY_EVENT_KIND_KEY_DOWN`, `_KEY_UP`, `_SYSTEM_KEY_DOWN`, `_SYSTEM_KEY_UP`. `Handled := True` impede a página de receber a tecla. Serve para atalhos de menu |
| `OnScriptResult(ErrorCode, ResultJson)` | Resultado de um `ExecuteScript` |
| `OnWebResourceRequested(Request, Response, var Handled)` | Uma requisição casou com um filtro. `Handled := True` responde com `Response`; senão ela segue para a rede |
| `OnProcessFailed(Kind, var Action)` | Um processo do WebView2 caiu ou travou. `Action` já vem com o padrão (veja [Robustez](#robustez)) |
| `OnCallbackError(E)` | Uma exceção num dos eventos acima. Sem handler, vai para o tratador padrão da aplicação |

#### Filtrando navegações com `OnNavigationStarting`

```pascal
procedure TfrmPrincipal.BrowserNavigationStarting(Sender: TObject; const Uri: WideString;
  IsUserInitiated, IsRedirected: Boolean; var Cancel: Boolean);
begin
  Cancel := Pos('bloqueado', LowerCase(Uri)) > 0;
end;
```

Uma navegação cancelada **ainda dispara `OnNavigationCompleted`**, com `Success = False` e
`WebErrorStatus = COREWEBVIEW2_WEB_ERROR_STATUS_OPERATION_CANCELED` (14). Não trate esse código
como erro.

#### Controlando novas janelas com `OnNewWindowRequested`

Sem tratamento, o WebView2 abre links `target="_blank"` e `window.open()` numa janela popup
própria, fora do controle da aplicação. O evento permite escolher outro comportamento pelo
parâmetro `Action`:

| `Action` | Efeito |
|---|---|
| `nwaPopup` (padrão) | O WebView2 abre a janela popup dele |
| `nwaSameWindow` | Navega para a URL no próprio `TWebView2Browser` |
| `nwaCancel` | Não abre nada. Use quando o próprio handler cuidar da URL |

```pascal
procedure TfrmPrincipal.BrowserNewWindowRequested(Sender: TObject; const Uri: WideString;
  IsUserInitiated: Boolean; var Action: TWV2NewWindowAction);
begin
  // abrir no navegador padrão do Windows
  Action := nwaCancel;
  ShellExecute(Handle, 'open', PChar(string(Uri)), nil, nil, SW_SHOWNORMAL);
end;
```

Com `nwaSameWindow`, a navegação passa normalmente pelo `OnNavigationStarting`, então os filtros
continuam valendo.

## Página embutida no executável

O HTML, CSS, JS e imagens da interface ficam **dentro do `.exe`**, como recursos `RCDATA`. Basta
distribuir o executável e o `WebView2Loader.dll`.

O controle cria um host virtual e intercepta as requisições a ele (`WebResourceRequested`),
respondendo com o conteúdo dos recursos:

```pascal
FBrowser.ServeEmbeddedResources('app.localhost');          // antes ou depois do CreateWebView
FBrowser.CreateWebView;
FBrowser.Navigate(FBrowser.EmbeddedUrl('index.html')); // https://app.localhost/index.html
```

Como tudo é servido por URL, a página usa caminhos relativos normalmente
(`<link href="style.css">`, `<script src="app.js">`, `<img src="img/logo.svg">`) e roda numa
origem `https://`, então APIs que exigem contexto seguro funcionam.

**Nome do recurso:** o caminho da URL em maiúsculas, com tudo que não for letra ou dígito trocado
por `_`. A raiz (`/`) serve `INDEX_HTML`.

| URL | Recurso no `web.rc` |
|---|---|
| `https://app.localhost/index.html` | `INDEX_HTML RCDATA "web\\index.html"` |
| `https://app.localhost/style.css` | `STYLE_CSS RCDATA "web\\style.css"` |
| `https://app.localhost/img/logo.svg` | `IMG_LOGO_SVG RCDATA "web\\img\\logo.svg"` |

Para adicionar um arquivo: coloque-o em `web\`, acrescente a linha no `web.rc` e recompile.
O `Content-Type` sai pela extensão (html, css, js, json, svg, png, jpg, gif, ico, woff2). Um
caminho sem recurso correspondente recebe **404**, o que dispara `OnNavigationCompleted` com
`Success = False` se for a página principal.

Limitações: o nome do recurso só tem letras e dígitos ASCII, então acentos e espaços viram `_` e
nomes diferentes podem colidir. Prefira nomes simples, em ASCII.

## Interceptando requisições: `OnWebResourceRequested`

O evento recebe as requisições que casam com algum filtro: os registrados com
`AddWebResourceRequestedFilter` e o host do `ServeEmbeddedResources`, que já é filtrado
automaticamente. Ele roda **antes** do servidor de recursos embutidos, então dá para criar uma
"API local" no mesmo host, sem servidor HTTP:

```pascal
procedure TfrmPrincipal.BrowserWebResourceRequested(Sender: TObject;
  Request: TWV2WebResourceRequest; Response: TWV2WebResourceResponse; var Handled: Boolean);
begin
  if Request.Path = 'api/clientes' then
  begin
    Response.SetJson('[{"id":1,"nome":"Padaria São João"}]');
    Handled := True;
  end;
  // Handled = False: segue para os recursos embutidos (ou para a rede)
end;
```

```js
fetch('api/clientes').then(r => r.json()).then(console.log);
```

**`TWV2WebResourceRequest`** (válido só durante o evento):

| Membro | Descrição |
|---|---|
| `Uri`, `Method` | URL completa e método HTTP |
| `Path` / `RawPath` | `https://app.localhost/a%20b/x?q=1` → `a b/x` (decodificado, UTF-8) / `a%20b/x` (como veio) |
| `QueryParam(Nome)`, `HasQueryParam(Nome)` | Valor decodificado de um parâmetro (`+` vira espaço) |
| `Query` | A query inteira, **sem** decodificar (decodificar tudo junto quebraria `%26` e `%3D`) |
| `GetHeader(Nome)` | Lê um header da requisição |
| `SetHeader(Nome, Valor)`, `RemoveHeader(Nome)` | Alteram a requisição **que segue para a rede**, ex.: injetar `Authorization` |
| `Content` / `ContentText` | Corpo (POST/PUT): bytes brutos / texto decodificado de UTF-8 |
| `ResourceContext` | Tipo do recurso (`COREWEBVIEW2_WEB_RESOURCE_CONTEXT_*`) |

**`TWV2WebResourceResponse`** (começa como `200 OK`, vazia):

| Membro | Descrição |
|---|---|
| `StatusCode`, `ReasonPhrase` | Status HTTP |
| `SetText(Texto, [ContentType])`, `SetJson(Json)` | Conteúdo em UTF-8, com `charset=utf-8` |
| `SetData`, `LoadFromStream`, `LoadFromFile` | Conteúdo binário. `LoadFromFile` deduz o `Content-Type` pela extensão |
| `SetHeader(Nome, Valor)` / `Headers` | Headers da resposta |
| `Defer` / `Complete` | Responder depois (veja abaixo) |

**Resposta adiada:** para responder depois (ex.: quando uma consulta terminar), chame
`Response.Defer`, marque `Handled := True`, guarde a resposta e chame `Response.Complete` mais
tarde, **na thread da interface**. Depois do `Complete` o objeto é liberado. O `Request` não vive
além do evento, então copie antes o que precisar dele.

```pascal
if Request.Path = 'relatorio' then
begin
  Response.Defer;
  Handled := True;
  FPendentes.Add(Response);   // um timer, ou o fim de uma thread (via Synchronize), chama:
end;                          //   Response.SetJson(...); Response.Complete;
```

Uma exceção dentro do evento não escapa para o WebView2: ela vira uma resposta **500** com a
mensagem. Para interceptar outro domínio, registre o filtro antes, por exemplo
`FBrowser.AddWebResourceRequestedFilter('https://api.exemplo.com/*')`. Referência completa,
receitas e limitações em [docs/WebResourceRequested_pt-BR.md](docs/WebResourceRequested_pt-BR.md) ([English](docs/WebResourceRequested.md)).

## Ponte Delphi ↔ JavaScript

Troca de mensagens simples entre a página e o Delphi. Para comandos com Promise, erros e eventos,
monte o seu próprio protocolo sobre `OnWebMessageJson`.

Da página para o Delphi:

```js
window.chrome.webview.postMessage('hora');              // chega como texto
window.chrome.webview.postMessage({ acao: 'salvar' });  // chega como JSON
```

Do Delphi para a página:

```pascal
FBrowser.PostWebMessage('Olá do Delphi');   // chega em event.data
FBrowser.ExecuteScript('somar(20, 22)');    // OnScriptResult recebe '42'
```

```js
window.chrome.webview.addEventListener('message', function (e) { console.log(e.data); });
```

## Robustez

**Exceções nos eventos:** nenhuma exceção escapa de um callback para o WebView2. Uma exceção num
evento do controle (`OnNavigationStarting`, `OnTitleChanged`...) vai para o `OnCallbackError`;
sem handler, vai para o tratador padrão da aplicação (o diálogo de erro da VCL). Assim o
WebView2 não é desestabilizado e a navegação continua. No `OnWebResourceRequested`, a exceção vira
uma resposta 500.

**Queda de processo (`OnProcessFailed`):** o WebView2 roda em processos separados que podem cair.
O evento recebe o tipo (`COREWEBVIEW2_PROCESS_FAILED_KIND_*`) e uma ação já preenchida com o
padrão:

| Queda | Ação padrão | Efeito |
|---|---|---|
| Browser (`..._BROWSER_PROCESS_EXITED`) | `pfaRecreate` | Recria o WebView (fora do callback) e volta à última URL. Filtros, scripts e opções são reaplicados |
| Renderer (`..._RENDER_PROCESS_EXITED`) | `pfaReload` | Recarrega a página |
| Outros (travamento, GPU, utilitários, frames) | `pfaNone` | Nada: o WebView2 se recupera sozinho, ou o app decide |

```pascal
procedure TForm1.BrowserProcessFailed(Sender: TObject; Kind: Integer; var Action: TWV2ProcessFailedAction);
begin
  Log(Format('processo do WebView2 caiu (tipo %d)', [Kind]));
  if Kind = COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_UNRESPONSIVE then
    Action := pfaReload;  { recarrega também quando a página trava }
end;
```

Não abra janelas modais dentro deste (nem de outro) evento do WebView2: poste uma mensagem e
pergunte ao usuário depois que o callback retornar.

**Recriação do handle:** trocar o `Parent` do controle, mudar o `BorderStyle` do form e outras
operações da VCL destroem e recriam o handle da janela. A janela do WebView2 é filha desse
handle e morreria junto. O controle "estaciona" o WebView numa janela oculta durante a troca e o
devolve ao novo handle, sem recarregar a página.

**Liberação:** ao destruir o controle (ou no `Recreate`), os handlers são removidos com os tokens
(`remove_*`), o controller é fechado, e callbacks tardios do WebView antigo são ignorados.

## Testes

```bat
Tests\run-tests.bat
```

28 testes DUnit das partes que não precisam do runtime: requisição e resposta interceptadas (com
uma `ICoreWebView2WebResourceRequest` falsa), decodificação de URL e de query, MIME, nomes de
recurso, opções do ambiente e o controle antes do `CreateWebView`. Precisa do DUnit (variável
`DUNIT`, padrão `C:\dev\lib\dunit\src`).

O que depende do runtime (queda de processo, recriação do handle, resposta adiada, `Language` e
`AdditionalBrowserArguments`, proteção dos callbacks) foi verificado com um app de integração
usando o protocolo do DevTools, inclusive derrubando de propósito o renderer e o processo
browser.

## Armadilhas do Delphi 7 com o WebView2

1. **BOOL vale `-1`.** Em Delphi, `LongBool(True)` é `-1`, mas o WebView2 compara com `TRUE` (1)
   e trata `-1` como falso. Na primeira versão, `put_IsScriptEnabled(True)` *desligou* o
   JavaScript. Todo parâmetro BOOL **de entrada** usa o tipo `WV2BOOL` (Integer) e deve receber
   `BoolToWV2(...)`. Parâmetros de saída podem continuar como `BOOL`.
2. **Exceções de ponto flutuante.** O Chromium espera essas exceções mascaradas. O
   `WebView2Browser.pas` chama `Set8087CW($133F)` na inicialização; sem isso aparecem erros
   "Invalid floating point operation" aleatórios.
3. **Callbacks sem métodos anônimos.** Cada callback é uma pequena classe `TInterfacedObject` que
   repassa a chamada ao controle. No `Destroy` do controle elas são desligadas, para que um
   callback tardio não acesse um objeto já liberado.
4. **Ordem da vtable.** Em `WebView2.pas` a ordem dos métodos de cada interface é a ordem da
   vtable. Não remova nem reordene métodos, mesmo os não usados; eles estão lá para ocupar o slot.
5. **Apartment STA.** O `ComObj` está no `uses` para que o `Application.Initialize` chame
   `CoInitialize`.
6. **Strings.** Strings devolvidas pelo WebView2 (`LPWSTR*`) precisam ser liberadas com
   `CoTaskMemFree`; use `TakeCoTaskString`. Já o `LPCWSTR` recebido em `ExecuteScript` pertence ao
   WebView2: copie, não libere.

## Limitações

- Só um subconjunto da API está declarado. Para usar outro recurso, declare a interface em
  `WebView2.pas` conferindo a ordem dos métodos no `WebView2.h`.
- Apenas 32 bits (limite do Delphi 7).
- `Response.Complete` (resposta adiada) precisa ser chamado na thread da interface.
- Respostas adiadas ainda pendentes quando o WebView é liberado ou recriado são descartadas; não
  chame `Complete` nelas depois disso.
