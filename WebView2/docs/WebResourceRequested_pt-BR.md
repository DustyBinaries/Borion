# Interceptando requisições com `OnWebResourceRequested`

*Read in English: [WebResourceRequested.md](WebResourceRequested.md).*

Este documento descreve como o `TWebView2Browser` intercepta requisições da página para que o
Delphi responda no lugar da rede. É assim que funcionam a página embutida no executável e a
"API local" da demonstração.

- [Visão geral](#visão-geral)
- [Fluxo de uma requisição](#fluxo-de-uma-requisição)
- [Filtros](#filtros)
- [O evento](#o-evento)
- [Referência: `TWV2WebResourceRequest`](#referência-twv2webresourcerequest)
- [Referência: `TWV2WebResourceResponse`](#referência-twv2webresourceresponse)
  ([resposta adiada](#resposta-adiada))
- [Receitas](#receitas)
- [Erros e exceções](#erros-e-exceções)
- [Cuidados e limitações](#cuidados-e-limitações)
- [Por dentro](#por-dentro)

## Visão geral

O WebView2 só avisa a aplicação das requisições cujo endereço casa com um **filtro** registrado.
Para cada uma delas, o `TWebView2Browser` dispara o `OnWebResourceRequested`, e o seu código
escolhe entre duas saídas:

- **responder em Delphi**: monta a resposta (status, headers, conteúdo) e marca
  `Handled := True`. Nada sai para a rede;
- **deixar passar**: não marca `Handled`. A requisição segue normalmente, e você pode
  alterar os headers dela antes.

Usos típicos:

| Uso | Como |
|---|---|
| API local para a interface (sem servidor HTTP) | Responder `https://app.localhost/api/...` com JSON |
| Página embutida no executável | `ServeEmbeddedResources`, que usa este mesmo mecanismo |
| Injetar autenticação em chamadas a um servidor | `Request.SetHeader('Authorization', ...)` sem marcar `Handled` |
| Bloquear recursos (anúncios, rastreadores, imagens) | Responder 403/204 para os padrões indesejados |
| Servir arquivos do disco durante o desenvolvimento | `Response.LoadFromFile(...)` |

## Fluxo de uma requisição

```
página faz uma requisição (navegação, <script>, <img>, fetch, XHR...)
        │
        ▼
a URL casa com algum filtro? ── não ──► rede (o Delphi nem fica sabendo)
        │ sim
        ▼
OnWebResourceRequested(Request, Response, Handled)
        │
        ├─ Handled = True ─────────────────────────► envia Response
        │
        ▼ Handled = False
é do host do ServeEmbeddedResources? ── sim ──► recurso RCDATA (ou 404) ──► envia
        │ não
        ▼
rede (com os headers que o evento tiver alterado)
```

O evento roda **antes** do servidor de recursos embutidos. Por isso ele pode tratar caminhos do
mesmo host (`api/...`) e até sobrepor um arquivo embutido. O que ele não tratar continua vindo
de dentro do executável.

## Filtros

```pascal
procedure AddWebResourceRequestedFilter(const UriPattern: WideString;
  ResourceContext: Integer = COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
```

- `UriPattern` aceita o curinga `*`, por exemplo `https://api.exemplo.com/*` ou `*.png`.
- Pode ser chamado **antes** do `CreateWebView`: o filtro fica pendente e é aplicado assim que o
  navegador fica pronto.
- O `ServeEmbeddedResources('app.localhost')` já registra `https://app.localhost/*`.
- `RemoveWebResourceRequestedFilter(Padrao, [Contexto])` remove um filtro (o padrão e o contexto
  precisam ser os mesmos do registro); `ResourceFilterCount` diz quantos há.

`ResourceContext` restringe o filtro a um tipo de recurso. A unit só declara a constante
`COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL`; os demais valores podem ser passados como número:

| Valor | Contexto | Valor | Contexto |
|---|---|---|---|
| 0 | `ALL` (todos) | 9 | `TEXT_TRACK` |
| 1 | `DOCUMENT` | 10 | `EVENT_SOURCE` |
| 2 | `STYLESHEET` | 11 | `WEBSOCKET` |
| 3 | `IMAGE` | 12 | `MANIFEST` |
| 4 | `MEDIA` | 13 | `SIGNED_EXCHANGE` |
| 5 | `FONT` | 14 | `PING` |
| 6 | `SCRIPT` | 15 | `CSP_VIOLATION_REPORT` |
| 7 | `XML_HTTP_REQUEST` | 16 | `OTHER` |
| 8 | `FETCH` | | |

Prefira filtros estreitos: cada requisição filtrada passa pela thread da interface (veja
[Cuidados e limitações](#cuidados-e-limitações)).

## O evento

```pascal
TWV2WebResourceRequestedEvent = procedure(Sender: TObject;
  Request: TWV2WebResourceRequest; Response: TWV2WebResourceResponse;
  var Handled: Boolean) of object;
```

| Parâmetro | Descrição |
|---|---|
| `Request` | A requisição interceptada. Só é válida durante o evento: não guarde a referência |
| `Response` | A resposta a enviar. Já vem como `200 OK`, sem headers e sem conteúdo |
| `Handled` | Começa `False`. `True` envia `Response`; `False` deixa a requisição seguir |

Exemplo mínimo:

```pascal
FBrowser.ServeEmbeddedResources('app.localhost');
FBrowser.OnWebResourceRequested := BrowserWebResourceRequested;
FBrowser.CreateWebView;

procedure TfrmPrincipal.BrowserWebResourceRequested(Sender: TObject;
  Request: TWV2WebResourceRequest; Response: TWV2WebResourceResponse; var Handled: Boolean);
begin
  if Request.Path = 'api/hora' then
  begin
    Response.SetJson('{"hora":"' + FormatDateTime('hh:nn:ss', Now) + '"}');
    Handled := True;
  end;
end;
```

```js
fetch('api/hora').then(r => r.json()).then(d => console.log(d.hora));
```

## Referência: `TWV2WebResourceRequest`

| Membro | Tipo | Descrição |
|---|---|---|
| `Uri` | `WideString` | URL completa, ex.: `https://app.localhost/api/eco?origem=demo` |
| `Method` | `WideString` | `GET`, `POST`, `PUT`, `DELETE`... |
| `Path` | função | Caminho sem esquema, host, query e fragmento, decodificado (`%XX` em UTF-8): `https://app.localhost/a%20b/x` → `a b/x` |
| `RawPath` | função | O mesmo, como veio na URL: `a%20b/x` |
| `QueryParam(Nome)` | função | Valor decodificado de um parâmetro (`+` vira espaço); `''` se não houver |
| `HasQueryParam(Nome)` | função | O parâmetro existe (mesmo vazio ou sem `=`)? |
| `Query` | função | O que vem depois do `?`, sem ele e **sem decodificar**: `origem=demo`. Decodificar a query inteira quebraria valores com `%26` (`&`) ou `%3D` (`=`); use `QueryParam` |
| `GetHeader(Nome)` | função | Valor de um header da requisição, ou `''` se não existir |
| `SetHeader(Nome, Valor)` | procedimento | Cria ou substitui um header da requisição que **segue para a rede** |
| `RemoveHeader(Nome)` | procedimento | Remove um header da requisição que segue para a rede |
| `Content` | `string` | Corpo (POST/PUT) em bytes brutos. Vazio se não houver |
| `ContentText` | `WideString` | O corpo decodificado de UTF-8 |
| `ResourceContext` | `Integer` | Tipo do recurso (tabela em [Filtros](#filtros)) |
| `Native` | `ICoreWebView2WebResourceRequest` | A interface COM original, para o que não foi embrulhado |

Observações:

- O corpo é lido uma única vez, na primeira vez que `Content` ou `ContentText` é acessado.
- `SetHeader` e `RemoveHeader` só fazem sentido quando o evento **não** trata a requisição.
  Se você responde com `Handled := True`, a requisição nunca sai e os headers alterados são
  descartados.

## Referência: `TWV2WebResourceResponse`

| Membro | Descrição |
|---|---|
| `StatusCode` | Status HTTP. Padrão `200` |
| `ReasonPhrase` | Texto do status. Padrão `OK`. Ajuste junto com o `StatusCode` (`404` / `Not Found`) |
| `SetText(Texto, [ContentType])` | Grava o texto em UTF-8 e define `Content-Type: <tipo>; charset=utf-8`. Padrão `text/plain` |
| `SetJson(Json)` | Atalho para `SetText(Json, 'application/json')` |
| `SetData(Ptr, Tamanho, ContentType)` | Copia um bloco de memória (binário) |
| `LoadFromStream(Stream, ContentType)` | Copia o stream inteiro, desde a posição 0 |
| `LoadFromFile(Arquivo, [ContentType])` | Carrega um arquivo. Sem `ContentType`, deduz pela extensão |
| `SetHeader(Nome, Valor)` | Define um header da resposta |
| `Headers` | `TStringList` no formato `Nome=Valor`, para manipulação direta |
| `Content` | `TMemoryStream` com o corpo, para escrita direta |
| `HeadersText` | Os headers no formato enviado ao WebView2 (`Nome: Valor` separados por CRLF) |
| `Defer` / `Complete` / `Deferred` | Resposta adiada (veja abaixo) |

Tipos deduzidos pela extensão (`LoadFromFile` e recursos embutidos): `html`/`htm`, `css`,
`js`/`mjs`, `json`, `txt`, `svg`, `png`, `jpg`/`jpeg`, `gif`, `webp`, `ico`, `woff`/`woff2`,
`wasm`. Os demais viram `application/octet-stream`.

### Resposta adiada

O evento roda na thread da interface. Para uma resposta que depende de trabalho demorado (uma
consulta, um cálculo numa thread), adie:

```pascal
procedure TForm1.BrowserWebResourceRequested(Sender: TObject; Request: TWV2WebResourceRequest;
  Response: TWV2WebResourceResponse; var Handled: Boolean);
begin
  if Request.Path = 'api/relatorio' then
  begin
    Response.Defer;                              // pede o adiamento ao WebView2
    Handled := True;
    TRelatorio.Create(Response, Request.QueryParam('mes'));   // copie o que precisar do Request
  end;
end;

{ quando terminar, NA THREAD DA INTERFACE (ex.: no Synchronize da thread): }
Response.SetJson(Json);
Response.Complete;                               // envia e libera o objeto
```

- `Defer` só vale dentro do `OnWebResourceRequested`, e `Complete` só depois de `Defer`; fora
  disso levantam `EWebView2Error`.
- O `Request` é liberado no fim do evento. Copie antes os valores de que precisar.
- Várias respostas podem ficar adiadas ao mesmo tempo, e a página continua respondendo.
- Uma exceção no evento depois do `Defer` responde 500 na hora e encerra o adiamento.
- Respostas adiadas pendentes quando o WebView é liberado ou recriado são descartadas: não chame
  `Complete` nelas depois disso.

> **Strings no Delphi 7:** `SetText` e `SetJson` recebem `WideString`. Literais e variáveis
> `string` (ANSI) são convertidos pela página de código do sistema (cp1252 no Windows em
> português), então acentos em literais do código-fonte chegam certos na página.

## Receitas

### API local com rotas

```pascal
procedure TfrmPrincipal.BrowserWebResourceRequested(Sender: TObject;
  Request: TWV2WebResourceRequest; Response: TWV2WebResourceResponse; var Handled: Boolean);
var
  Path: WideString;
begin
  Path := Request.Path;
  if Copy(Path, 1, 4) <> 'api/' then
    Exit;  { não é da API: segue para os recursos embutidos }
  Handled := True;

  if (Path = 'api/clientes') and (Request.Method = 'GET') then
    Response.SetJson(ClientesComoJson)
  else if (Path = 'api/clientes') and (Request.Method = 'POST') then
  begin
    SalvarCliente(Request.ContentText);  { corpo JSON enviado pela página }
    Response.StatusCode := 201;
    Response.ReasonPhrase := 'Created';
  end
  else
  begin
    Response.StatusCode := 404;
    Response.ReasonPhrase := 'Not Found';
    Response.SetJson('{"erro":"rota desconhecida"}');
  end;
end;
```

Lado da página:

```js
fetch('api/clientes', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ nome: 'Padaria São João' })
}).then(r => console.log(r.status));   // 201
```

O exemplo (`Examples/Demo/uPrincipal.pas`) tem as rotas `api/clientes`, `api/hora`, `api/eco` (que
devolve corpo, `Content-Type` e query do POST) e `api/erro` (que gera um 500 de propósito).

### Montar JSON com segurança

O Delphi 7 não tem biblioteca de JSON. Para inserir texto variável, escape aspas, barras e
caracteres de controle. A demonstração usa esta função:

```pascal
function JsonStr(const S: WideString): WideString;  { devolve o texto entre aspas, escapado }
...
Response.SetJson('{"nome":' + JsonStr(Edit1.Text) + '}');
```

### Injetar um header de autenticação

```pascal
FBrowser.AddWebResourceRequestedFilter('https://api.exemplo.com/*');

{ no evento: }
if Pos('https://api.exemplo.com/', Request.Uri) = 1 then
  Request.SetHeader('Authorization', 'Bearer ' + FToken);
{ Handled continua False: a requisição segue, já com o header }
```

O token fica no Delphi e nunca aparece no JavaScript da página.

> Esta receita não foi testada: o protótipo não chama nenhum servidor externo.

### Bloquear um tipo de recurso

```pascal
FBrowser.AddWebResourceRequestedFilter('*', 3);  { 3 = IMAGE }

{ no evento: }
if Request.ResourceContext = 3 then
begin
  Response.StatusCode := 403;
  Response.ReasonPhrase := 'Forbidden';
  Handled := True;
end;
```

### Servir do disco durante o desenvolvimento

Para editar HTML/CSS/JS sem recompilar o `web.res`, sirva a pasta `web\` direto do disco e
deixe os recursos embutidos para a versão final:

```pascal
function ServirDoDisco(Request: TWV2WebResourceRequest;
  Response: TWV2WebResourceResponse): Boolean;
var
  Caminho, Arquivo: string;
begin
  Result := False;
  Caminho := Request.Path;
  if (Caminho = '') or (Pos('..', Caminho) > 0) then
    Exit;  { não deixa a página sair da pasta web\ }
  Arquivo := ExtractFilePath(ParamStr(0)) + 'web\' +
    StringReplace(Caminho, '/', '\', [rfReplaceAll]);
  if FileExists(Arquivo) then
  begin
    Response.LoadFromFile(Arquivo);
    Result := True;
  end;
end;

{ no evento: }
{$IFDEF WEB_DO_DISCO}
if not Handled then
  Handled := ServirDoDisco(Request, Response);
{$ENDIF}
```

Defina `WEB_DO_DISCO` em *Project › Options › Directories/Conditionals* (ou `-DWEB_DO_DISCO`
no `dcc32`) só nas compilações de desenvolvimento. O Delphi 7 não define um símbolo `DEBUG`
sozinho.

Como o evento roda antes dos recursos embutidos, o arquivo do disco tem prioridade, e o que
não existir no disco ainda vem do executável. A raiz (`Path` vazio) cai no `index.html`
embutido. A verificação de `..` impede que a página leia arquivos fora da pasta `web\`.

## Erros e exceções

O evento é chamado de dentro de um callback COM do WebView2, e uma exceção Delphi que escapasse
dali seria um problema. Por isso o `TWebView2Browser` captura qualquer exceção do evento e
responde **500 Internal Server Error**, com o texto `500 - <Classe>: <Mensagem>`:

```js
fetch('api/erro').then(r => r.text()).then(console.log);
// "500 - Exception: erro proposital no handler Delphi"
```

O 500 é enviado mesmo que a requisição não fosse do host embutido: depois de uma exceção,
não dá para saber se o evento pretendia tratá-la.

Respostas de erro da **página principal** (404, 500) fazem o `OnNavigationCompleted` chegar com
`Success = False`. Para `fetch` e XHR, o erro aparece só no `status` da resposta.

## Cuidados e limitações

- **Roda na thread da interface.** O evento é síncrono, e enquanto ele roda a VCL e a página
  ficam paradas. Para trabalho demorado, use a [resposta adiada](#resposta-adiada).
- **Corpo inteiro em memória.** O conteúdo da resposta é copiado para um stream em memória
  antes de ser entregue. Para arquivos grandes (vídeos, downloads), prefira servir pela rede
  ou pelo disco com uma URL `file://`.
- **CORS.** Uma resposta interceptada de outro domínio continua sujeita a CORS. Se a página em
  `https://app.localhost` fizer `fetch` em `https://api.exemplo.com` e o Delphi responder no lugar,
  inclua `Response.SetHeader('Access-Control-Allow-Origin', 'https://app.localhost')`. Rotas no
  mesmo host (`api/...`) não têm esse problema.
- **Um único header por nome.** `Response.SetHeader` substitui; não há como enviar o mesmo
  header duas vezes (ex.: vários `Set-Cookie`).
- **Filtros** podem ser removidos (`RemoveWebResourceRequestedFilter`, com o mesmo padrão e
  contexto) e contados (`ResourceFilterCount`), mas não listados.

## Por dentro

Para quem for estender o código:

| Peça | Onde | O que faz |
|---|---|---|
| `AddWebResourceRequestedFilter` | `WebView2Browser.pas` | Guarda o filtro e chama `ApplyResourceFilters` |
| `ApplyResourceFilters` | `WebView2Browser.pas` | Registra o handler no WebView2 (uma vez) e aplica os filtros pendentes. Chamado também no `ControllerCreated` |
| `WebResourceRequested` | `WebView2Browser.pas` | Cria `Request`/`Response`, dispara o evento, cai no `ServeEmbedded` e trata exceções |
| `SendResponse` | `WebView2Browser.pas` | Copia o conteúdo para um `IStream` (`SHCreateMemStream`) e chama `CreateWebResourceResponse` e `put_Response` |
| `ICoreWebView2WebResourceRequest`, `...Response`, `...RequestedEventArgs`, `ICoreWebView2HttpRequestHeaders` | `WebView2.pas` | Interfaces COM, na ordem da vtable do `WebView2.h` |

Dois detalhes do Delphi 7 que aparecem aqui:

- `SHCreateMemStream` é declarada devolvendo `Pointer`, não `IStream`. O Delphi trata
  interfaces devolvidas por função como um parâmetro oculto, o que não bate com a convenção do
  C. O ponteiro é atribuído "cru" (`Pointer(Result) := ...`) para assumir a referência sem um
  `AddRef` a mais.
- O `IStream` criado copia os bytes. A resposta não depende do `TMemoryStream` nem do recurso
  `RCDATA` depois de enviada, então os dois podem ser liberados no fim do evento.
