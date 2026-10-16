# Exemplo: plugin `http`

O `fetch` feito pelo Delphi (WinInet), sem CORS e com escopo de URLs. Precisa de internet.

O app inteiro é o `HttpDemo.dpr` (sem form):

```pascal
uses
  Borion, BorionHttp;

var
  Http: TBorionHttpPlugin;

begin
  Http := TBorionHttpPlugin.Create;
  { escopo: tudo negado por padrão; só estas URLs }
  Http.Allow('https://example.com/*');
  Http.Allow('https://api.github.com/*');
  Http.Allow('https://httpbin.org/*');
  TBorionBuilder.Create('Borion: http')
    .Size(900, 680)
    .Plugin(Http)
    .Run;
end.
```

## O que ele mostra

| Seção | O que demonstra |
|---|---|
| 1. Sem CORS | A mesma URL (`example.com`, que não manda cabeçalhos CORS) pelo `fetch` do navegador, que é barrado, e pelo `@borion/api/http`, que traz a página |
| 2. JSON | A API do GitHub com `headers` e `r.json()`; o cabeçalho `x-ratelimit-remaining` da resposta |
| 3. POST, timeout, cancelamento | POST com JSON e emoji (o `httpbin.org` devolve o que recebeu); `timeout: 2000` numa resposta de 5 s (`TIMEOUT`); uma requisição de 10 s cancelada por `AbortController` (`AbortError`) |
| 4. Escopo | Uma URL que não está no `Allow` rejeita com `FORBIDDEN_URL` |
## Rodando

```bat
build.bat
HttpDemo.exe
```

O `build.bat` copia os módulos do [`@borion/api`](../../js/README.md) (`Borion\js`) para
`web\borion-api\`, empacota a pasta `web\` com o `borion pack` e compila. Não precisa de Node
nem de Vite: o *import map* do `index.html` resolve `import ... from '@borion/api/http'` para a
cópia local, e o código fica igual ao de um projeto com bundler.

| | |
|---|---|
| `HttpDemo.dpr` | O app inteiro: o `TBorionBuilder` monta a janela com o plugin (sem form) |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#http).
