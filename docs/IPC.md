# Borion IPC: `invoke`, `emit` e `listen`

O IPC do **Borion — Native Application Engine** liga a página (JavaScript) ao Delphi 7 no
estilo do Tauri. A página chama **comandos** Delphi e recebe o resultado numa Promise. Os dois
lados trocam **eventos**.

```js
const soma = await borion.invoke('somar', { a: 20, b: 22 });   // 42
```

```pascal
Ipc.RegisterCommand('somar', CmdSomar);

procedure TForm1.CmdSomar(Call: TBorionCall);
begin
  Call.Result.AsNumber := Call.ArgNum('a') + Call.ArgNum('b');
end;
```

- [Configuração](#configuração)
- [Comandos](#comandos)
- [Comandos assíncronos e threads](#comandos-assíncronos-e-threads)
- [Erros](#erros)
- [Eventos](#eventos)
- [API JavaScript](#api-javascript)
- [Segurança: origens](#segurança-origens)
- [Texto e Unicode](#texto-e-unicode)
- [Protocolo](#protocolo)
- [Testes](#testes)
- [Limitações conhecidas](#limitações-conhecidas)

## Configuração

O Borion usa a biblioteca **Jsons** (json4delphi, distribuída com o ACBr). O projeto precisa
enxergar `Jsons.pas` e o `ACBr.inc`, que ela inclui:

| Onde | O que configurar |
|---|---|
| `build.bat` | Variáveis `JSON4DELPHI` (pasta da `Jsons.pas`) e `ACBR_COMUM` (pasta do `ACBr.inc`). Os padrões apontam para `C:\dev\lib\ACBr\...` |
| IDE | *Project › Options › Directories/Conditionals › Search path* (no exemplo, já preenchido em `Examples/Demo/BorionDemo.dof`) |

Units do Borion:

| Unit | Conteúdo |
|---|---|
| `BorionIpc.pas` | `TBorionIpc`, `TBorionCall`, `EBorionError` e a ponte JS |
| `BorionJson.pas` | Conversões de JSON entre ANSI e Unicode (veja [Texto e Unicode](#texto-e-unicode)) |
| `js/borion.d.ts` | Tipos TypeScript da API JS |

Num app feito com o [`TBorionBuilder`](../README.md#criando-um-app), o IPC já vem montado: os
comandos entram com `.Command('somar', Somar)` e, no `.Setup`, `Window.Ipc` dá acesso a ele.

Num form existente, criando o IPC à mão:

```pascal
FBrowser := TWebView2Browser.Create(Self);
...
FIpc := TBorionIpc.Create(Self, FBrowser);   // antes do CreateWebView
FIpc.AllowOrigin('https://app.localhost');        // quem pode usar o IPC
FIpc.RegisterCommand('somar', CmdSomar);

FBrowser.ServeEmbeddedResources('app.localhost');
FBrowser.CreateWebView;
FBrowser.Navigate(FBrowser.EmbeddedUrl('index.html'));
```

O `TBorionIpc`:

- injeta a ponte JS (`window.borion`) em todo documento, **antes** dos scripts da página.
  Crie o IPC antes do `CreateWebView`; se criar depois, a ponte só aparece a partir do próximo
  documento.
- assume o `OnWebMessageJson` do browser. Mensagens que não são do Borion continuam chegando no
  `OnWebMessageReceived`, então `chrome.webview.postMessage` "cru" segue funcionando.
- é um `TComponent`: com `Owner` = form, é liberado junto com ele.

## Comandos

Um comando recebe um `TBorionCall`. Há duas formas de registro:

```pascal
{ método de um objeto (form, data module...) }
Ipc.RegisterCommand('somar', CmdSomar);          // procedure(Call: TBorionCall) of object

{ procedure solta: o "backend" não precisa de form (veja Examples/Demo/uComandos.pas) }
Ipc.RegisterCommandProc('info', CmdInfo);        // procedure(Call: TBorionCall)
```

Registrar o mesmo nome de novo substitui o anterior. `UnregisterCommand(Nome)` remove. Os nomes
diferenciam maiúsculas.

### Argumentos

O segundo parâmetro do `invoke` é um objeto, acessível por `Call.Args` (`TJsonObject`) ou pelos
atalhos, que devolvem o padrão quando o argumento não existe ou é `null`:

| Método | Exemplo |
|---|---|
| `ArgStr(Nome, [Padrão])` | `Call.ArgStr('nome')` |
| `ArgInt(Nome, [Padrão])` | `Call.ArgInt('passos', 10)` |
| `ArgNum(Nome, [Padrão])` | `Call.ArgNum('valor')` (Extended) |
| `ArgBool(Nome, [Padrão])` | `Call.ArgBool('ativo', True)` |
| `HasArg(Nome)` | argumento presente? |
| `Arg(Nome)` | o `TJsonValue`, ou `nil`; para objetos e arrays aninhados |

> **Cuidado:** acessar `Call.Args['x']` direto **cria** a chave se ela não existir (é o
> `AutoAdd` da Jsons). Prefira os atalhos acima ou `Arg`.

### Resultado

`Call.Result` é um `TJsonValue` que começa como `null`:

```pascal
Call.Result.AsString := 'texto';
Call.Result.AsNumber := 42;
Call.Result.AsBoolean := True;

with Call.Result.AsObject do      // vira objeto na primeira chamada
begin
  Put('nome', 'Padaria');
  Put('ativo', True);
end;

Item := Call.Result.AsArray.Add.AsObject;   // array de objetos
Item.Put('id', 1);
```

Outros dados: `Call.Command` (nome), `Call.Source` (URL do documento que chamou) e `Call.Ipc`.

## Comandos assíncronos e threads

Por padrão, a resposta é enviada quando o handler retorna. Para responder depois, chame
**`Call.Defer`** e, mais tarde, **`Call.Resolve`** ou **`Call.Reject`**:

```pascal
procedure CmdTarefaLonga(Call: TBorionCall);
begin
  Call.Defer;
  TTarefaLonga.Create(Call).Resume;   // a thread chama Call.Resolve no fim
end;

procedure TTarefaLonga.Execute;
begin
  ...
  FCall.Ipc.EmitJson('tarefa:progresso', '{"passo":3,"total":10}');  // de qualquer thread
  FCall.Result.AsObject.Put('ok', True);
  FCall.Resolve;                                                     // de qualquer thread
end;
```

Regras:

- `Resolve`, `Reject`, `Emit` e `EmitJson` podem ser chamados **de qualquer thread**. O Borion
  leva a resposta para a thread da interface (o WebView2 só aceita chamadas dela).
- Depois do `Defer`, a chamada pertence a quem vai resolvê-la. Ela é liberada pelo Borion depois
  do `Resolve`/`Reject`, então não use o objeto depois disso.
- Enquanto uma thread mexe em `Call.Result`, ninguém mais deve mexer.
- Dentro do handler, `Resolve`/`Reject` repetidos são ignorados: vale o primeiro. Numa chamada
  adiada, o primeiro `Resolve`/`Reject` **envia a resposta e libera o objeto**; não chame de
  novo nem acesse `Call` depois disso.
- Uma chamada adiada que nunca é resolvida deixa a Promise pendente para sempre. No JS, use
  `{ timeout }` (veja [API JavaScript](#api-javascript)).

> **Ao fechar o app** com threads em andamento: as chamadas pendentes ficam órfãs
> (`Call.Ipc = nil`) e se liberam no `Resolve`/`Reject`. A thread não deve usar `Call.Ipc` sem
> checar `nil`, e o ideal é terminá-la antes de destruir o form.

### Janelas modais: `Ipc.Later`

Os handlers rodam dentro do callback do WebView2. Abrir ali uma janela modal (`ShowModal`,
`MessageDlg`, um diálogo de arquivo) causa reentrância no callback COM. Para isso existe o
`Later`: a chamada é adiada e o handler roda logo depois, na thread da interface. A resposta sai
quando ele retorna.

```pascal
procedure TForm1.CmdEscolherCliente(Call: TBorionCall);
begin
  FIpc.Later(Call, MostrarEscolha);   // adia; não use Call depois desta linha
end;

procedure TForm1.MostrarEscolha(Call: TBorionCall);
begin
  if TfrmEscolha.Executar(Id) then    // form modal, fora do callback
    Call.Result.AsInteger := Id;      // senão: null
end;
```

Plugins fazem o mesmo com `CommandLater` (veja [PLUGINS.md](PLUGINS.md#escrevendo-um-plugin)).

## Erros

Qualquer exceção no handler rejeita a Promise. O `error.message` é a mensagem, e o `error.code`
é o `Code` de um `EBorionError` ou o nome da classe da exceção:

```pascal
raise EBorionError.Create('VALIDACAO', 'Informe o nome.');   // error.code = 'VALIDACAO'
raise Exception.Create('falhou');                             // error.code = 'Exception'
Call.Reject('sem permissão', 'NEGADO');                       // sem exceção
```

```js
try {
  await borion.invoke('saudacao', { nome: '' });
} catch (e) {
  console.log(e.code, e.message, e.command);   // VALIDACAO  Informe o nome.  saudacao
}
```

Códigos do próprio Borion:

| Código | Quando |
|---|---|
| `UNKNOWN_COMMAND` | Nenhum comando registrado com esse nome |
| `FORBIDDEN_ORIGIN` | O documento não é de uma origem liberada |
| `TIMEOUT` | Gerado no JS, quando a opção `timeout` estoura |

## Eventos

**Delphi → JS**

```pascal
Ipc.EmitJson('progresso', '{"pct":50}');      // payload já em JSON

Payload := TJsonObject.Create;
try
  Payload.Put('texto', 'olá');
  Ipc.Emit('mensagem', Payload);              // TJsonObject, TJsonArray ou TJsonValue
finally
  Payload.Free;                               // o Emit não assume o objeto
end;
```

```js
const parar = borion.listen('progresso', (p) => console.log(p.pct));
parar();   // deixa de escutar
```

**JS → Delphi**

```js
borion.emit('salvou', { id: 7 });
```

```pascal
Ipc.Listen('salvou', EventoSalvou);   // ou '*' para todos os eventos

procedure TForm1.EventoSalvou(const Event: string; Payload: TJsonValue);
begin
  ShowMessage(IntToStr(Payload.AsObject['id'].AsInteger));
end;
```

O `Payload` pertence ao Borion e só vale durante a chamada. Uma exceção num listener é
registrada no `OnLog` e não impede os demais.

## Várias janelas

Um `TBorionIpc` serve todas as janelas do app: comandos, listeners e plugins são registrados uma
vez. Cada janela é um browser com um rótulo (`'main'` na principal, a do `Create`). O
`TBorionBuilder` faz isso sozinho para as janelas do [`app.json`](CONFIG.md#várias-janelas); à
mão:

```pascal
Ipc := TBorionIpc.Create(Self, BrowserPrincipal);   // a janela 'main'
Ipc.AddWindow('config', OutroBrowser);              // antes do CreateWebView dele
```

- **Respostas:** o `invoke` responde só à janela que chamou. `Call.Window` traz o rótulo dela,
  e `Call.Browser`, o browser.
- **Contexto:** durante um comando ou listener, `Ipc.CurrentWindow` diz de qual janela veio a
  mensagem.
- **Eventos:** `Ipc.Emit` vai para todas as janelas. `Ipc.EmitTo('config', ...)` e
  `Ipc.EmitJsonTo` vão só para uma (`'*'` = todas).
- **Entre janelas:** a página manda com `borion.emitTo('main', 'evento', payload)` (ou `'*'`).
  O Delphi só repassa como um evento comum, e o `listen` da outra janela recebe. A origem
  precisa estar liberada; um destino que não existe é ignorado e registrado no `OnLog`.
- **Rótulo na página:** cada página recebe o seu em `borion.label` (`windowLabel()` no
  `@borion/api`).
- **Fechar:** liberar o browser tira a janela do IPC. Uma resposta adiada para uma janela que já
  fechou é descartada.
- **Plugins:** um plugin que acompanha cada janela (como o `window`) sobrescreve `WindowAdded` e
  `WindowRemoved`.

## API JavaScript

A ponte é injetada como `window.borion` (e `window.__BORION__`), congelada e não
sobrescrevível. Os tipos estão em [`js/borion.d.ts`](../js/borion.d.ts).

| Função | Descrição |
|---|---|
| `invoke(cmd, args?, { timeout? })` | Chama um comando. `Promise` com o resultado, ou rejeitada com `Error` + `code` |
| `listen(evento, cb)` | Escuta um evento do Delphi. `cb(payload, evento)`. Devolve a função `unlisten` |
| `once(evento, cb)` | Como `listen`, só a primeira vez |
| `emit(evento, payload?)` | Envia um evento ao Delphi |
| `emitTo(janela, evento, payload?)` | Envia um evento a outra janela do app (`'*'` = todas) |
| `label` | Rótulo da janela desta página (`'main'` na principal) |
| `version` | Versão do Borion |

Sem `chrome.webview` (página aberta num navegador comum), a ponte não é criada. Teste com
`if (window.borion)`.

### Com bundler: pacote `@borion/api`

Para apps com Vite, Rollup e afins, o pacote ESM em [`Borion/js`](../js/README.md) expõe a mesma
API como imports tipados:

```js
import { invoke, listen, emit, isBorion } from '@borion/api';
const soma = await invoke('somar', { a: 20, b: 22 });
```

Fora de um app Borion, `invoke` rejeita e `listen`/`once`/`emit` lançam um erro com
`code = 'NOT_AVAILABLE'`; `isBorion()` permite tratar esse caso. Instalação e detalhes no
[README do pacote](../js/README.md).

## Segurança: origens

O IPC é **negado por padrão**. Só documentos de origens liberadas com `AllowOrigin` podem chamar
comandos ou emitir eventos:

```pascal
Ipc.AllowOrigin('https://app.localhost');        // a página embutida
Ipc.AllowOrigin('http://localhost:5173');    // servidor de desenvolvimento (Vite)
Ipc.AllowOrigin('*');                        // qualquer origem: só para testes
```

A ponte é injetada em **todo** documento, inclusive sites externos abertos na janela, porque o
WebView2 não filtra a injeção por origem. É a checagem no Delphi que protege os comandos. Uma
página de outra origem recebe `FORBIDDEN_ORIGIN`, e a tentativa aparece no `OnLog`:

```
Borion: invoke negado para a origem https://example.com: listarArquivos
```

A origem vem do WebView2 (`Source` da mensagem), não da página, então não pode ser forjada pelo
JavaScript. Permissões por comando e escopos (ex.: quais pastas um comando de arquivos pode ler)
estão na Fase 5 do [roadmap](ROADMAP.md).

## Texto e Unicode

O Delphi 7 trabalha com `string` ANSI (cp1252 no Windows em português). A biblioteca Jsons tem
dois problemas nessa fronteira, corrigidos pelo `BorionJson.pas`:

| Sentido | Problema da Jsons | Correção |
|---|---|---|
| Delphi → JS | Escreve `\u00XX` com o byte ANSI: `€ “ ” – — …` (cp1252 $80–$9F) chegariam como caracteres de controle | `AnsiJsonToWide` converte para o code point Unicode certo |
| JS → Delphi | `\uXXXX` acima de $FF é truncado (`€` virava `¬`) | `WideJsonToAnsi` troca esses escapes pelo caractere antes do parse |

O que **não** tem solução no Delphi 7: caracteres fora da página de código do sistema (emoji,
CJK...) chegam ao Delphi como `?`.

## Protocolo

Para quem quiser implementar a ponte em outro lugar ou depurar com o DevTools. Toda mensagem do
Borion é um objeto com `"__borion": 1`:

```jsonc
// JS -> Delphi (chrome.webview.postMessage)
{"__borion":1,"kind":"invoke","id":7,"cmd":"somar","args":{"a":20,"b":22}}
{"__borion":1,"kind":"emit","event":"salvou","payload":{"id":7}}
{"__borion":1,"kind":"emitTo","target":"main","event":"nota","payload":{"texto":"..."}}

// Delphi -> JS (PostWebMessageAsJson)
{"__borion":1,"kind":"response","id":7,"ok":true,"result":42}
{"__borion":1,"kind":"response","id":7,"ok":false,"error":{"code":"VALIDACAO","message":"..."}}
{"__borion":1,"kind":"event","event":"progresso","payload":{"pct":50}}
```

A ponte JS escuta `chrome.webview` `message` e chama `stopImmediatePropagation` nas mensagens do
Borion, então listeners da própria página não as veem.

## Testes

```bat
Borion\Tests\run-tests.bat
```

Compila e roda as duas baterias e sai com erro se alguma falhar:

| Bateria | Onde | O que cobre |
|---|---|---|
| DUnit (Delphi) | `Tests/` | `BorionJson` (Unicode nos dois sentidos) e `TBorionIpc`: roteamento, argumentos, erros, chamadas adiadas (inclusive de outra thread), origens, eventos e mensagens malformadas |
| `node:test` (JS) | `Borion/js/test/` | A ponte JS real (exportada pelo DUnit) num `chrome.webview` simulado, e o pacote `@borion/api` |

Requisitos: DUnit (`DUNIT`, padrão `C:\dev\lib\dunit\src`), as variáveis da Jsons já citadas e
Node.js 18+ (sem Node, os testes JS são pulados com aviso).

Os testes Delphi não precisam de WebView2: criam o IPC sem browser (`TBorionIpc.Create(nil, nil)`),
entregam mensagens com **`ProcessMessage`** e capturam as respostas com **`OnPost`**. Essas duas
peças também servem para diagnóstico num app real:

```pascal
Ipc.OnPost := RegistrarSaida;   // cada resposta/evento enviado à página
Ipc.ProcessMessage('{"__borion":1,"kind":"invoke","id":1,"cmd":"info"}', 'https://app.localhost/');
```

## Limitações conhecidas

- **Ordem das chaves:** objetos que vão do Delphi para o JS chegam com as chaves em **ordem
  alfabética**, porque o `PostWebMessageAsJson` do WebView2 reordena. Não dependa da ordem.
- **Chaves sem diferenciar maiúsculas no Delphi:** a Jsons busca chaves com `SameText`, então
  `{"Nome":1,"nome":2}` é ambíguo.
- **Números** passam por `Extended`. Inteiros acima de 2^53 perdem precisão no JS, como em
  qualquer JSON.
- **Handlers síncronos rodam na thread da interface:** um comando demorado sem `Defer` trava a
  janela. Use `Defer` + thread.
- **Latência:** cerca de 0,5 ms por `invoke` na máquina de teste (comando trivial).
