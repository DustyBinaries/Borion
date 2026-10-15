# Exemplo: plugin `http`

O `fetch` feito pelo Delphi (WinInet), sem CORS e com escopo de URLs. No Delphi:

```pascal
Http := TBorionHttpPlugin(Ipc.AddPlugin(TBorionHttpPlugin.Create));
Http.Allow('https://example.com/*');
Http.Allow('https://api.github.com/*');
Http.Allow('https://httpbin.org/*');
```

Precisa de internet.

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
| `uPrincipal.pas` | A janela (sem `.dfm`): browser, IPC, assets e o plugin |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#http).
