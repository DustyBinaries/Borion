# @borion/api

API JavaScript do **Borion — Native Application Engine** para apps com bundler (Vite, Rollup,
esbuild, webpack...).

```js
import { invoke, listen, emit } from '@borion/api';

const soma = await invoke('somar', { a: 20, b: 22 });   // comando Delphi -> 42
const parar = listen('progresso', (p) => console.log(p.pct));
emit('salvou', { id: 7 });
```

É uma camada fina sobre a ponte que o `TBorionIpc` injeta em toda página (`window.borion`).
Sem bundler, use a ponte direto, sem instalar nada: `window.borion.invoke(...)`.

## Instalação

O pacote ainda não está publicado no npm. Instale a partir desta pasta:

```bash
npm install ../caminho/para/Borion/js
```

ou no `package.json` do frontend:

```json
{
  "dependencies": {
    "@borion/api": "file:../caminho/para/Borion/js"
  }
}
```

Os tipos TypeScript vêm junto (`index.d.ts`). Para tipar também o `window.borion` global,
importe os tipos globais uma vez:

```ts
import type {} from '@borion/api/global';
```

## API

| Função | Descrição |
|---|---|
| `invoke(cmd, args?, { timeout? })` | Chama um comando Delphi. `Promise` com o resultado; rejeita com `Error` que tem `code` e `command` |
| `listen(evento, handler)` | Escuta um evento do Delphi (`Ipc.Emit`). `handler(payload, evento)`. Devolve a função para parar |
| `once(evento, handler)` | Como `listen`, só a primeira vez |
| `emit(evento, payload?)` | Envia um evento ao Delphi (`Ipc.Listen`) |
| `isBorion()` | `true` quando a página roda dentro de um app Borion |
| `version()` | Versão da ponte, ou `null` fora do Borion |
| `NOT_AVAILABLE` | Código de erro usado fora do Borion |

Também há um export default com as mesmas funções (`import borion from '@borion/api'`).

Códigos de erro do `invoke`: o `Code` de um `EBorionError` no Delphi, o nome da classe da
exceção, `UNKNOWN_COMMAND`, `FORBIDDEN_ORIGIN`, `TIMEOUT` e `NOT_AVAILABLE`. Veja o
[guia do IPC](../docs/IPC.md).

## Fora de um app Borion

Abrir a página num navegador comum (por exemplo, `vite dev` no Chrome) é útil para trabalhar no
layout. Nesse caso não há ponte, e:

- `invoke` **rejeita** com `code = 'NOT_AVAILABLE'` (não lança);
- `listen`, `once` e `emit` **lançam** o mesmo erro.

Para a página funcionar nos dois ambientes, verifique antes:

```js
import { isBorion, listen } from '@borion/api';

if (isBorion()) {
  listen('progresso', atualizarBarra);
}
```

A ponte é procurada a cada chamada, não na importação. A ordem dos imports não importa.

## Testes

```bash
npm test          # nesta pasta
```

Os testes da ponte usam o script real gerado pelo Delphi, que o DUnit exporta para
`Tests/out/`. Por isso, rode a bateria completa com `Borion\Tests\run-tests.bat`.
