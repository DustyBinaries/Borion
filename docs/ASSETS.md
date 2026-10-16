# Borion: assets do frontend e modo dev

Como a interface (HTML/CSS/JS, inclusive o `dist/` de um build do Vite) entra no executável, como
é servida para o WebView2 e como desenvolver com hot-reload.

- [Visão geral](#visão-geral)
- [CLI: `borion pack`](#cli-borion-pack)
- [`TBorionAssets`](#tborionassets)
- [Fallback de SPA](#fallback-de-spa)
- [Headers](#headers)
- [Modo dev (hot-reload)](#modo-dev-hot-reload)
- [Fluxo com Vite](#fluxo-com-vite)
- [Formato do pacote](#formato-do-pacote)
- [Limitações](#limitações)

## Visão geral

```
frontend/dist/  --borion pack-->  app.res  --{$R app.res}-->  .exe  --TBorionAssets-->  https://app.local/
 (qualquer                         (recurso                     (um arquivo              (WebView2, com
  estrutura)                        BORION_ASSETS)               só)                      fallback de SPA)
```

1. A CLI `borion pack` junta todos os arquivos de uma pasta num pacote (com compressão zlib) e grava
   um `.res` com o recurso `BORION_ASSETS`. Não precisa de `.rc` nem do `brcc32`, e nomes de
   arquivo com hash (`index-SVctTc9F.css`), subpastas e acentos funcionam.
2. O projeto inclui o `.res` com `{$R app.res}`.
3. Em tempo de execução, o `TBorionAssets` lê o pacote do próprio exe e responde às requisições
   para `https://app.local/`.

Comparando com o `ServeEmbeddedResources` do [`TWebView2Browser`](../../WebView2/README.md), que
continua existindo para casos simples: lá, cada arquivo é uma linha manual num `.rc`, e o nome
do recurso deriva do caminho.

## CLI: `borion pack`

A CLI é um console app Delphi 7 em `Borion/Tools/` (compile com `Borion\Tools\build.bat`; os
`build.bat` dos exemplos fazem isso sozinhos se o `borion.exe` não existir).

```bat
borion new <pasta> [--template vanilla|vite|react] [--title "Título"] [--port 5173]
borion pack <pasta> <saida.res> [--no-compress] [--name NOME] [--verbose]
borion list <arquivo.res> [--name NOME]
borion version
```

O `borion new` cria um app a partir de um template (veja [Criando um app](../README.md#criando-um-app));
os `build.bat` gerados chamam o `borion pack`.

```
> borion pack frontend\dist app.res --verbose
  assets/index-KmBqLWLh.js                           230298 ->     71834 zlib
  assets/index-SVctTc9F.css                            1418 ->       629 zlib
  index.html                                            394 ->       265 zlib
3 arquivo(s): 221,4 KB -> 68,7 KB em app.res
```

- **Compressão:** zlib (unit `ZLib` do Delphi 7), só quando reduz pelo menos 10%. Formatos já
  comprimidos (`png`, `jpg`, `webp`, `woff2`, `mp4`, `zip`...) são guardados como estão.
  `--no-compress` desliga.
- **Determinístico:** o mesmo conteúdo gera o mesmo pacote (arquivos ordenados).
- O pacote é relido e validado antes de o `.res` ser gravado.
- Saída com código ≠ 0 em caso de erro, para uso em scripts.

## `TBorionAssets`

```pascal
uses BorionAssets;

FAssets := TBorionAssets.Create(Self, FBrowser);          // lê BORION_ASSETS do exe
FIpc.AllowOrigin(BorionOriginOf(FAssets.StartUrl));       // app.local, ou o servidor dev
FBrowser.CreateWebView;
FBrowser.Navigate(FAssets.StartUrl);                      // https://app.local/
```

| Membro | Descrição |
|---|---|
| `Create(Owner, Browser, [Host])` | Carrega o pacote do exe, registra o filtro de `https://<Host>/*` e assume o `Browser.OnWebResourceRequested`. `Host` padrão: `app.local` |
| `StartUrl` | Onde navegar: o `DevUrl` em modo dev, senão a raiz `https://<Host>/` |
| `Url(Caminho)` / `Origin` | `https://<Host>/<Caminho>` / `https://<Host>` |
| `IsDev` / `DevUrl` | Modo dev (veja abaixo) |
| `Pack` / `PackError` | O pacote carregado, ou `nil` e o motivo (ex.: o exe foi compilado sem o `.res`) |
| `SetPack(Pack)` | Troca o pacote (ex.: `TBorionPack.FromFile`, para testes) |
| `IndexFile` | Padrão `index.html` |
| `SpaFallback` | Padrão `True` (veja abaixo) |
| `CacheControl` | Padrão `no-cache` |
| `ContentSecurityPolicy` | Padrão vazio (sem o header) |
| `OnRequest` | Requisições do host antes dos assets: o lugar para uma API local (`/api/...`) |
| `ServePath(Caminho, Response)` | O servidor em si, sem browser (é o que os testes usam) |

> O `TBorionAssets` assume o `Browser.OnWebResourceRequested`. Um handler que já estava lá
> continua sendo chamado primeiro; depois disso, use o **`OnRequest`** em vez de atribuir o evento
> do browser de novo.

Sem pacote (exe compilado sem o `.res`), toda requisição recebe 404 com a explicação. No modo
dev o pacote não é necessário.

## Fallback de SPA

Apps com roteamento no cliente (React Router, Vue Router...) usam URLs como `/clientes/2` que não
são arquivos. Na primeira navegação o roteador cuida delas, mas um **F5** pede `/clientes/2` ao
servidor. Com `SpaFallback`, o `TBorionAssets` responde o `index.html` quando:

- o caminho não existe no pacote, **e**
- o último segmento não tem extensão (`clientes/2` sim; `assets/x.js` não, continua 404).

Por isso o `StartUrl` é a raiz `/` e não `/index.html`: para o roteador, `/index.html` seria uma
rota desconhecida.

## Headers

Toda resposta do `TBorionAssets` leva:

| Header | Valor |
|---|---|
| `Content-Type` | Pela extensão (`BorionMimeType`): html, css, js/mjs, json, map, svg, png, jpg, webp, avif, ico, woff/woff2, ttf, wasm, mp3, mp4, webm, pdf... |
| `X-Content-Type-Options` | `nosniff` |
| `Cache-Control` | `no-cache` (configurável). O WebView2 guarda cache no `UserDataFolder` entre versões do exe; sem isto, uma atualização poderia mostrar arquivos antigos |
| `Content-Security-Policy` | Só se `ContentSecurityPolicy` estiver preenchido. A Fase 5 do roadmap vai definir um padrão restritivo |

## Modo dev (hot-reload)

Para desenvolver a interface sem recompilar, o app abre o **servidor de desenvolvimento** (ex.:
Vite) em vez do pacote embutido. O `TBorionAssets` lê a URL na criação:

| Fonte | Exemplo |
|---|---|
| Parâmetro | `app.exe --dev-url=http://localhost:5173` ou `app.exe --dev-url http://localhost:5173` |
| Variável de ambiente | `set BORION_DEV_URL=http://localhost:5173` |

O parâmetro vence a variável. Com ela definida, `IsDev = True` e `StartUrl` = a URL do servidor.

A ponte do Borion é injetada em qualquer origem, então o IPC funciona no modo dev, desde que a
origem esteja liberada. Por isso o padrão é:

```pascal
FIpc.AllowOrigin(BorionOriginOf(FAssets.StartUrl));
```

Em produção libera `https://app.local`; em dev, `http://localhost:5173`. O app nunca libera as duas
ao mesmo tempo.

## Fluxo com Vite

O exemplo [`Examples/ViteReact`](../Examples/ViteReact/README.md) tem o fluxo completo:

| Script | O que faz |
|---|---|
| `build.bat` | `npm run build` → `borion pack frontend\dist app.res` → compila o exe |
| `dev.bat` | Sobe o Vite (`npm run dev`, porta fixa 5173), espera ele responder e abre o exe com `--dev-url` |

No `vite.config.js`:

- `server.strictPort: true`, para a porta ser previsível;
- `server.fs.allow` incluindo `Borion/js`, porque o `@borion/api` é instalado como link para
  fora da pasta do frontend.

No modo dev, mudanças em `frontend\src` aparecem na hora, com o estado do React preservado.
Mudanças no Delphi (comandos) exigem fechar o app e rodar o `build.bat`.

## Formato do pacote

Um blob único (`BorionPack.pas`), little-endian:

```
'BORP'  Word versão(1)  Cardinal N
N x [ Word tamanho | caminho UTF-8 com '/' | Byte flags (1=zlib) |
      Cardinal tamanho original | Cardinal tamanho guardado | Cardinal posição ]
área de dados
```

Os caminhos ficam em UTF-8, e a URL é decodificada (`%C3%A7` → bytes UTF-8) antes da busca, que
tenta o caminho exato e depois sem diferenciar maiúsculas. Assim, nomes com acento funcionam sem
passar pela página de código ANSI do Delphi 7. O `.res` é escrito direto no formato de recursos
Win32 (`BorionWriteRes`), e `BorionReadRes` lê de volta (usado por `borion list` e nos testes).

## Limitações

- O conteúdo é descomprimido a cada requisição (sem cache em memória). Para os tamanhos típicos
  de um frontend isso é imperceptível, mas arquivos de vários MB pagam o custo toda vez.
- Respostas inteiras em memória: vídeos grandes não devem ir no pacote.
- Nomes de arquivo fora da página de código do Windows (ex.: CJK num Windows em português) não são
  lidos pelo `borion pack`, porque o Delphi 7 lista arquivos em ANSI.
- `Content-Security-Policy` ainda sem padrão (Fase 5).
