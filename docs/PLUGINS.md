# Borion: plugins

Plugins são conjuntos de comandos nativos prontos (`dialog`, `fs`, `shell`, `menu`, `tray`, `app`,
`clipboard`, `store`, `os`, `http`, `notification`, `single-instance`, `deep-link`, `autostart`, `global-shortcut`, `log`), com API tipada no JS
e regras de segurança embutidas. Cada um é uma unit em `Borion/Plugins/`, adicionada com uma
linha no [`TBorionBuilder`](../README.md#criando-um-app):

```pascal
uses Borion, BorionFs, BorionDialog, BorionShell;

begin
  TBorionBuilder.Create('Meu App')
    .AllowDir('$APPDATA')                 // %APPDATA%\Meu App: o escopo de arquivos do app
    .Plugin(TBorionFsPlugin.Create)       // sem escopo próprio: usam o do app
    .Plugin(TBorionDialogPlugin.Create)
    .Plugin(TBorionShellPlugin.Create)
    .Run;
end.
```

Num form existente, o mesmo com o IPC criado à mão: `Ipc.AddPlugin(TBorionFsPlugin.Create)`.

```js
import { open } from '@borion/api/dialog';
import { readTextFile } from '@borion/api/fs';

const caminho = await open({ filters: [{ name: 'Texto', extensions: ['txt'] }] });
if (caminho) console.log(await readTextFile(caminho));
```

- [Escopo de arquivos](#escopo-de-arquivos)
- [`fs`](#fs)
- [`dialog`](#dialog)
- [`shell`](#shell)
- [`menu`](#menu)
- [`tray`](#tray)
- [`app`](#app)
- [`clipboard`](#clipboard)
- [`store`](#store)
- [`os`](#os)
- [`http`](#http)
- [`notification`](#notification)
- [`single-instance`](#single-instance)
- [`deep-link`](#deep-link)
- [`autostart`](#autostart)
- [`global-shortcut`](#global-shortcut)
- [`log`](#log)
- [Unicode completo: JSON só com ASCII](#unicode-completo-json-só-com-ascii)
- [Escrevendo um plugin](#escrevendo-um-plugin)
- [Limitações](#limitações)

## Escopo de arquivos

O `TBorionScope` define o que os plugins podem tocar no disco. **Tudo é negado por padrão.**

O app tem um escopo só, compartilhado pelos plugins `fs`, `dialog` e `shell`: o que o
`TBorionBuilder` libera com `.AllowDir`/`.AllowFile` (fica em `Ipc.Scope`, liberado pelo IPC).
Plugins criados com um `TBorionScope` próprio continuam usando o deles.

```pascal
Scope.AllowDir('$APPDATA');                 // a pasta e tudo abaixo dela
Scope.AllowDir('C:\Dados\Importar', False); // só os arquivos diretos, sem subpastas
Scope.AllowFile('$DOCUMENT\config.ini');    // um arquivo
```

| Variável | Pasta |
|---|---|
| `$APPDATA` / `$APPLOCALDATA` | `%APPDATA%\<app>` / `%LOCALAPPDATA%\<app>` (o nome vem do `Create`) |
| `$DOCUMENT`, `$DESKTOP`, `$DOWNLOAD`, `$PICTURE`, `$HOME` | Pastas do usuário |
| `$TEMP` | Pasta temporária |
| `$EXE` | Pasta do executável |

Antes da comparação, todo caminho é validado e normalizado:

| Regra | Exemplo recusado |
|---|---|
| Só caminhos absolutos (ou relativos a um `baseDir`) | `dados\x.txt`, `\x.txt`, `C:x` |
| `..` e `.` são resolvidos antes de comparar | `C:\app\dados\..\segredo.txt` → `C:\app\segredo.txt` (fora) |
| A comparação é feita com a barra final | liberar `C:\app` **não** libera `C:\app2` |
| Sem caminhos de dispositivo | `\\?\C:\x`, `\\.\PhysicalDrive0` |
| Sem *alternate data streams* | `nota.txt:oculto`, `x::$DATA` |
| Sem nomes reservados do Windows | `NUL`, `con.txt`, `COM1` |
| Sem caracteres inválidos | `* ? " < > \|` e caracteres de controle |

A comparação não diferencia maiúsculas. Erros: `INVALID_PATH` (caminho inválido) e
`FORBIDDEN_PATH` (válido, mas fora do escopo).

**Escolhas do usuário:** o plugin `dialog` acrescenta ao escopo o que o usuário escolhe:
o arquivo aberto ou salvo (só ele, não a pasta) e a pasta escolhida em `directory: true`. É o
modelo do Tauri. O app pode ler e gravar o que o usuário apontou, mas um script na página não
alcança o resto do disco. Essas permissões valem só para a sessão.

### Diretórios-base

No JS, caminhos relativos usam `baseDir`:

```js
import { readTextFile, BaseDirectory } from '@borion/api/fs';
await readTextFile('config.json', { baseDir: BaseDirectory.AppData });  // %APPDATA%\<app>\config.json
```

Valores: `appData`, `appLocalData`, `document`, `desktop`, `download`, `picture`, `home`, `temp`,
`exe`. O resultado continua sujeito ao escopo, e `..` não escapa dele.

## `fs`

`TBorionFsPlugin.Create([Scope, OwnsScope = True])`. Sem `Scope`, usa o escopo do app (o do
`TBorionBuilder`, ou `Ipc.Scope`). Com um escopo próprio, o plugin o libera ao ser destruído;
passe `OwnsScope = False` se ele pertencer a outro objeto.

| JS (`@borion/api/fs`) | Comando | Resultado |
|---|---|---|
| `readTextFile(path, {encoding?, baseDir?})` | `fs:readTextFile` | `string` |
| `writeTextFile(path, contents, {append?, encoding?, baseDir?})` | `fs:writeTextFile` | — |
| `readFile(path)` / `writeFile(path, bytes)` | `fs:readFile` / `fs:writeFile` | `Uint8Array` (base64 no fio) |
| `exists(path)` | `fs:exists` | `boolean` |
| `stat(path)` | `fs:stat` | `{isFile, isDirectory, size, modified, readonly}` |
| `readDir(path)` | `fs:readDir` | `[{name, ...stat}]` |
| `mkdir(path, {recursive?})` | `fs:mkdir` | — |
| `remove(path, {recursive?})` | `fs:remove` | — |
| `rename(from, to)` / `copyFile(from, to)` | `fs:rename` / `fs:copyFile` | — |

- **Texto:** UTF-8 por padrão (lê com ou sem BOM, grava sem BOM); `encoding: 'ansi'` para
  arquivos legados.
- **`remove` recursivo não segue junções nem links simbólicos:** remove só o link. Uma junção
  dentro do escopo apontando para fora não leva o `remove` a apagar o que está do outro lado
  (coberto por teste).
- **`exists` também respeita o escopo:** fora dele, a resposta é `FORBIDDEN_PATH`, não `false`,
  para não revelar o que existe no disco.
- **Erros:** `FORBIDDEN_PATH`, `INVALID_PATH`, `INVALID_BASE_DIR`, `INVALID_ARGS`, `NOT_FOUND`,
  `ALREADY_EXISTS`, `IO_ERROR`, `INVALID_BASE64`.

## `dialog`

`TBorionDialogPlugin.Create([Scope])`. Sem `Scope`, as escolhas do usuário entram no escopo do
app (o mesmo do `fs`).

| JS (`@borion/api/dialog`) | Resultado |
|---|---|
| `open({title?, multiple?, directory?, filters?, defaultPath?})` | caminho, lista (`multiple`) ou `null` (cancelado) |
| `save({title?, filters?, defaultPath?})` | caminho ou `null` |
| `message(texto, {title?, kind?})` | — |
| `confirm(texto, {title?, kind?, buttons?})` | `boolean` (OK/Cancelar) |
| `ask(texto, {title?, kind?})` | `boolean` (Sim/Não) |

```js
const arquivos = await open({
  multiple: true,
  filters: [
    { name: 'Imagens', extensions: ['png', 'jpg'] },
    { name: 'Todos os arquivos', extensions: ['*'] },
  ],
});
```

- `kind`: `'info'`, `'warning'` ou `'error'`. Sem `title`, o diálogo usa o título da janela.
- `save` pede confirmação para sobrescrever e acrescenta a extensão do primeiro filtro.
- Os diálogos são modais na janela do app e rodam com **`Ipc.Later`**: abrem depois que o callback
  do WebView2 retorna. Abrir uma janela modal dentro do callback COM causaria reentrância.

## `shell`

`TBorionShellPlugin.Create([Scope])`. Sem `Scope`, usa o escopo do app.

| JS (`@borion/api/shell`) | O que faz |
|---|---|
| `open(alvo)` | Abre uma URL no navegador padrão, ou um arquivo/pasta no programa associado |
| `showInFolder(path, {baseDir?})` | Abre o Explorer com o item selecionado |

A política existe para que nenhum script da página consiga **executar programas**:

- **URLs:** só os esquemas de `AllowedSchemes`, que por padrão são `https`, `http` e `mailto`.
  `file:`, `javascript:`, `ms-settings:`, `search-ms:` e qualquer outro são recusados
  (`FORBIDDEN_URL`). Para liberar um esquema próprio, use `Shell.AllowedSchemes.Add('meuapp')`.
- **Arquivos:** só dentro do escopo (sem escopo, nenhum) e **nunca executáveis ou scripts**:
  `.exe`, `.bat`, `.cmd`, `.ps1`, `.vbs`, `.js`, `.msi`, `.lnk`, `.url`, `.hta`, `.reg`, `.scr`,
  `.dll` e outros (`FORBIDDEN_FILE_TYPE`). Pontos e espaços no fim do nome (`a.exe.`) não
  enganam a verificação.

## `menu`

Exemplo: [`Examples/Menu`](../Examples/Menu/README.md).

`TBorionMenuPlugin.Create([AForm])`. Sem `AForm`, usa o form onde está o browser do `Ipc`. A barra
de menu é um `TMainMenu` comum da VCL, montado a partir do JSON.

| JS (`@borion/api/menu`) | O que faz |
|---|---|
| `setMenu(items)` | Monta a barra de menu (lista vazia remove a barra) |
| `update(id, {enabled?, checked?, label?, accelerator?})` | Muda um item da barra |
| `clear()` | Remove a barra |
| `popup(items, {x?, y?})` | Menu de contexto nativo; devolve o `id` escolhido ou `null` |
| `onClick((id, checked) => ...)` | Clique num item da barra (ou atalho de teclado) |
| `onItems({id: handler, ...})` | O mesmo, despachando por `id` |

```js
import * as menu from '@borion/api/menu';

await menu.setMenu([
  { label: '&Arquivo', items: [
    { id: 'salvar', label: '&Salvar', accelerator: 'Ctrl+S' },
    { type: 'separator' },
    { id: 'sair', label: 'Sai&r' },
  ] },
  { label: '&Exibir', items: [
    { id: 'quebra', label: '&Quebra de linha', type: 'checkbox', checked: true },
  ] },
]);
menu.onItems({ salvar, sair, quebra: (ligada) => ... });

li.oncontextmenu = async (e) => {
  e.preventDefault();
  const id = await menu.popup([{ id: 'abrir', label: '&Abrir' }, { id: 'remover', label: '&Remover' }]);
};
```

- **Item:** `{id, label, type?: 'normal' | 'checkbox' | 'separator', enabled?, checked?,
  accelerator?, items?}`. `items` cria um submenu; `&` marca a letra de acesso. Itens
  `checkbox` alternam sozinhos e mandam o novo estado em `checked`.
- **Atalhos** (`'Ctrl+S'`, `'Ctrl+Shift+S'`, `'F5'`, `'Alt+F4'`): com o foco na página, o teclado
  vai direto para o processo do WebView2 e a VCL nunca vê o `Ctrl+S`. O plugin escuta o evento
  `OnAcceleratorKeyPressed` do `TWebView2Browser` (o `AcceleratorKeyPressed` do controller),
  procura um item habilitado com aquele atalho, dispara o clique e marca a tecla como tratada:
  a página não recebe o `keydown`, então um atalho tratado em JS não dispara duas vezes. Teclas
  sem item no menu seguem normalmente para a página.
- **`popup`** roda com `CommandLater` (o `TrackPopupMenu` é modal) e abre no cursor, ou em `x, y`
  (coordenadas da página). Ao fechar, o foco volta para a página.
- Use o `popup` para menus próprios do app. Em campos de texto, prefira o menu de contexto do
  próprio WebView2: um item "Colar" feito em JS precisaria da Clipboard API, e ela pede
  permissão ao usuário quando chamada fora de um gesto dele na página.
- **Erros:** `INVALID_MENU` (item ou atalho inválido), `NOT_FOUND` (`update` com id
  desconhecido), `NO_WINDOW` (sem form).

## `tray`

Exemplo: [`Examples/Tray`](../Examples/Tray/README.md).

`TBorionTrayPlugin.Create`. O ícone é o do executável (recurso `MAINICON`) ou o padrão do Windows;
troque pela propriedade `Icon`. A página não escolhe o ícone.

| JS (`@borion/api/tray`) | O que faz |
|---|---|
| `show({tooltip?})` / `hide()` | Mostra ou tira o ícone |
| `setTooltip(texto)` | Texto ao passar o mouse (até 127 caracteres) |
| `setMenu(items)` | Menu do clique direito, no mesmo formato do `menu` (`null` remove) |
| `notify(titulo, mensagem, {kind?})` | Notificação (balão; toast no Windows 10/11). `kind`: `'info'`, `'warning'`, `'error'`, `'none'` |
| `onClick`, `onDoubleClick` | Cliques no ícone |
| `onMenu((id) => ...)` | Item escolhido no menu do ícone |
| `onNotificationClick` | Clique na notificação |

```pascal
Tray := TBorionTrayPlugin(Ipc.AddPlugin(TBorionTrayPlugin.Create));
Tray.MinimizeToTray := True;   // minimizar esconde a janela (e o botão da barra de tarefas)
```

```js
import * as tray from '@borion/api/tray';
import * as app from '@borion/api/app';

await tray.setMenu([{ id: 'mostrar', label: '&Mostrar' }, { type: 'separator' }, { id: 'sair', label: 'Sai&r' }]);
await tray.show({ tooltip: 'Meu App' });
tray.onMenu((id) => (id === 'sair' ? app.exit() : app.show()));
await tray.notify('Arquivo salvo', 'C:\\notas.txt');
```

- `RestoreOnClick` (padrão `True`): o clique simples no ícone também restaura a janela.
- `MinimizeToTray` (padrão `False`): minimizar esconde a janela na bandeja e mostra o ícone.
  `RestoreWindow` (Delphi) ou `app.show()` (JS) a trazem de volta.
- `notify` mostra o ícone se ele estiver escondido (o Windows exige um ícone para notificar).
- Se o Explorer reiniciar, o ícone é recolocado sozinho (mensagem `TaskbarCreated`).
- O menu do ícone roda fora do callback do WebView2 e só existe enquanto está aberto.

## `app`

Exemplo: [`Examples/App`](../Examples/App/README.md).

`TBorionAppPlugin.Create([AForm])`. Por enquanto só a parte de que menus e bandeja precisam: um
item "Sair" não tem como fechar o app sem ela.

| JS (`@borion/api/app`) | O que faz |
|---|---|
| `exit()` | Fecha a janela principal (passa pelo `OnCloseQuery`/`OnClose` do form) |
| `show()` | Mostra e traz a janela para frente, inclusive se estiver na bandeja |
| `hide()` / `minimize()` | Esconde / minimiza a janela |
| `info()` | `{name, version, exe, pid}`; `version` é o `FileVersion` do exe (`''` se não houver) |

## `clipboard`

Exemplo: [`Examples/Clipboard`](../Examples/Clipboard/README.md).

`TBorionClipboardPlugin.Create([AllowRead = True])`.

| JS (`@borion/api/clipboard`) | O que faz |
|---|---|
| `writeText(texto)` | Copia texto |
| `readText()` | Texto da área de transferência, ou `null` se não houver texto |
| `writeHtml(html, altText?)` | Copia HTML (o formato "HTML Format" do Windows: colar no Word mantém a formatação); `altText` é o texto puro para quem não entende HTML |
| `clear()` | Esvazia a área de transferência |

```js
import { writeText, readText } from '@borion/api/clipboard';

await writeText('Olá 😀');
const texto = await readText();
```

- Funciona a partir de qualquer código da página. A Clipboard API do navegador
  (`navigator.clipboard`) pede permissão ao usuário quando não é chamada dentro de um clique
  na página (depois de um menu nativo, por exemplo).
- **Ler expõe o que o usuário copiou de outros programas**, senhas inclusive. Se a página só
  precisa copiar, crie com `TBorionClipboardPlugin.Create(False)`: o `readText` passa a
  rejeitar com `FORBIDDEN`.
- Se outro programa estiver com a área de transferência aberta, o plugin tenta de novo por
  ~150 ms e então rejeita com `CLIPBOARD_BUSY`.
- No Delphi: `BorionClipboardReadText`, `BorionClipboardWriteText`, `BorionClipboardWriteHtml`
  e `BorionClipboardClear`, com `WideString`.
- Imagens ainda não são suportadas.

## `store`

Exemplo: [`Examples/Store`](../Examples/Store/README.md).

`TBorionStorePlugin.Create(AppName)`: os arquivos ficam em `%APPDATA%\<AppName>` (troque pela
propriedade `Dir`). Um store é um arquivo JSON com um objeto chave → valor, no estilo do store do
Tauri.

```js
import { load } from '@borion/api/store';

const prefs = await load('settings.json');      // '.json' é opcional
await prefs.set('tema', 'escuro');
await prefs.set('janela', { w: 800, h: 600 }); // qualquer valor JSON
const tema = await prefs.get('tema');          // undefined se não existir
prefs.onKeyChange('tema', (valor) => aplicarTema(valor));
```

| `Store` | O que faz |
|---|---|
| `get(chave)` | Valor, ou `undefined` se a chave não existir (`null` guardado volta `null`) |
| `set(chave, valor)` | Grava; recusa valores que o `JSON.stringify` não serializa |
| `has(chave)` / `delete(chave)` | `boolean` (`delete`: se existia) |
| `clear()` | Apaga todas as chaves |
| `entries()` / `keys()` / `values()` / `length()` | Na ordem em que as chaves foram criadas |
| `save()` | Grava agora (só é preciso com `AutoSave = False`) |
| `reload()` | Descarta o que não foi gravado e relê o arquivo |
| `onChange((chave, valor) => ...)` / `onKeyChange(chave, valor => ...)` | Alterações vindas desta página, de outra ou do Delphi; `undefined` = apagada |

- **Nome do store:** letras, números, `.`, `_` e `-`, até 64 caracteres. Não aceita caminhos,
  então a página não escolhe onde gravar (`INVALID_STORE`). Maiúsculas não importam
  (`Settings` = `settings.json`).
- **`AutoSave`** (padrão `True`): cada alteração grava o arquivo na hora, num temporário que
  depois substitui o original (uma queda no meio não deixa o arquivo pela metade). Com `False`,
  grava no `save()`, no `Save` do Delphi e ao destruir o plugin.
- **Arquivo corrompido** (editado à mão, por exemplo): é renomeado para `<nome>.json.corrupt` e o
  store recomeça vazio, para o app não travar nem perder os dados antigos. Arquivos em UTF-8,
  com ou sem BOM, editados à mão são lidos normalmente.
- **No Delphi**, o mesmo store: `ReadJson`/`WriteJson` (valor como texto JSON),
  `ReadString`/`WriteString` (`WideString`), `Delete` e `Save`. As alterações feitas pelo Delphi
  também emitem `store:change` para a página.

```pascal
Store := TBorionStorePlugin(Ipc.AddPlugin(TBorionStorePlugin.Create('Meu App')));
if Store.ReadJson('settings', 'janela', Json) then ...
Store.WriteString('settings', 'ultimoUsuario', Nome);
```

- **Erros:** `INVALID_STORE`, `INVALID_ARGS` (chave ou valor inválido), `IO_ERROR`.

## `os`

Exemplo: [`Examples/Os`](../Examples/Os/README.md).

`TBorionOsPlugin.Create`. Como o plugin `os` do Tauri, mas todas as funções são assíncronas.

| JS (`@borion/api/os`) | Exemplo |
|---|---|
| `platform()`, `family()`, `type()` | `'windows'` |
| `arch()` | Arquitetura do Windows: `'x86_64'`, `'aarch64'`, `'x86'`, `'arm'` |
| `version()` | `'10.0.22631'`: a versão real, sem o "modo de compatibilidade" do `GetVersionEx` |
| `locale()` | `'pt-BR'` (BCP 47), ou `null` |
| `hostname()` | Nome DNS do computador |
| `eol()` / `exeExtension()` | CRLF (`"\r\n"`) / `'exe'` |
| `info()` | Tudo de uma vez, mais `build` (22631), `displayVersion` (`'23H2'`), `name` (`'Windows 11 Pro'`) e `processArch` (`'x86'`: o Delphi 7 só gera 32 bits) |

O `name` vem da visão de 64 bits do registro. Um processo de 32 bits leria o `WOW6432Node`, que
pode guardar o nome de antes de uma troca de edição. O "Windows 10" que o Windows 11 ainda
grava ali é corrigido pelo número do build.

## `http`

Exemplo: [`Examples/Http`](../Examples/Http/README.md).

`TBorionHttpPlugin.Create`. Requisições feitas pelo Delphi (WinInet), sem as regras de CORS do
navegador. A interface é a do `fetch`:

```pascal
Http := TBorionHttpPlugin(Ipc.AddPlugin(TBorionHttpPlugin.Create));
Http.Allow('https://api.exemplo.com/v1/*');   // tudo negado por padrão
Http.Allow('https://*.cdn.exemplo.com');      // sem caminho = o host inteiro
```

```js
import { fetch } from '@borion/api/http';

const r = await fetch('https://api.exemplo.com/v1/itens', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
  body: JSON.stringify({ nome: 'José' }),
  timeout: 10000,                // extra do Borion: ms, a requisição inteira
});
if (r.ok) console.log(await r.json());
```

- **Devolve um `Response` de verdade** (`json()`, `text()`, `blob()`, `headers`, `url`,
  `redirected`). Como no `fetch`, status de erro (404, 500) resolvem normalmente.
- **Corpo:** `string` (UTF-8, `text/plain;charset=UTF-8` se não houver `Content-Type`),
  `URLSearchParams`, `Blob`, `ArrayBuffer` ou `TypedArray`. `FormData` e streams não são
  suportados.
- **Escopo** (`Allow`): `'*'` no host vale só dentro do host (`https://*.cdn.com` não casa
  `https://mal.com/.cdn.com`). Sem porta no padrão, só a porta padrão do esquema; `:*` libera
  qualquer porta. URLs com usuário/senha (`https://api.ok.com@outro.com/`) são recusadas.
- **Redirecionamentos** são seguidos pelo plugin, não pelo WinInet: cada destino passa pelo
  escopo (`FORBIDDEN_URL` se sair dele) e o `Authorization`/`Cookie` não vão para outro host.
  `redirect: 'manual'` devolve o 3xx, `'error'` rejeita com `REDIRECT`; `maxRedirections` (padrão
  10). 303 (e 301/302 de um POST) viram GET sem corpo; 307/308 mantêm método e corpo.
- **Cancelar:** `signal` (`AbortController`) cancela no Delphi e rejeita com `AbortError`.
- **`timeout`** é medido pelo próprio plugin (o do WinInet não vale enquanto espera a resposta).
- **Sem cookies e sem cache** do sistema: cada requisição é independente. `gzip`/`deflate` são
  pedidos e descompactados sozinhos. O proxy é o configurado no Windows.
- **Limites:** `MaxResponseSize` (padrão 50 MB, `TOO_LARGE` acima); `UserAgent` para trocar o
  `User-Agent`. Cada requisição roda numa thread: a interface não trava.
- O `Response` montado no JS não expõe `Set-Cookie` (o navegador esconde esse cabeçalho).
- **Erros** (`code`): `INVALID_URL`, `FORBIDDEN_URL`, `TIMEOUT`, `CANCELED`, `REDIRECT`,
  `TOO_MANY_REDIRECTS`, `TOO_LARGE`, `NETWORK_ERROR` (DNS, conexão recusada, certificado
  inválido...), `INVALID_ARGS` (cabeçalho com quebra de linha, método inválido).

## `notification`

Exemplo: [`Examples/Notification`](../Examples/Notification/README.md).

`TBorionNotificationPlugin.Create([AppId])`. Notificações nativas do Windows 10/11 (toast, via
WinRT), com botões. `AppId` identifica o app nas notificações e em Configurações > Sistema >
Notificações; sem ele, vale `'Borion.' + Application.Title`.

```js
import { sendNotification, onAction } from '@borion/api/notification';

await sendNotification({
  id: 'pedido-42',                    // opcional; o mesmo id substitui a anterior
  title: 'Pedido #42 aguardando aprovação',
  body: 'Cliente: José da Silva',
  actions: [{ id: 'aprovar', title: 'Aprovar' }, { id: 'recusar', title: 'Recusar' }],
});
onAction(({ id, action }) => { /* action: null no clique na notificação, ou o id do botão */ });
```

| JS (`@borion/api/notification`) | O que faz |
|---|---|
| `sendNotification(titulo \| {title, body?, id?, silent?, actions?})` | Mostra a notificação; devolve o id. Até 5 botões |
| `hide(id)` | Tira da tela uma notificação mostrada |
| `isPermissionGranted()` / `requestPermission()` | Se o usuário não desligou as notificações do app. O Windows não pergunta: `requestPermission` só informa (`'granted'`/`'denied'`) |
| `onAction(({id, action}) => ...)` | Clique na notificação ou num botão |
| `onDismissed(({id, reason}) => ...)` | Fechada: `'user'`, `'hidden'` (pelo `hide`) ou `'timeout'` (foi para a Central de Ações) |

- **Sem atalho no Menu Iniciar:** um app desktop sem pacote precisa de um AppUserModelID
  registrado para mostrar toasts. O plugin grava `DisplayName` (e `IconUri`, se houver
  `IconPath`) em `HKCU\Software\Classes\AppUserModelId\<AppId>` e define o AppId do
  processo, como o Windows Community Toolkit faz. No desinstalador, chame
  `BorionNotificationUnregister(AppId)`.
- **Clicar traz a janela para frente** (`FocusOnClick`, padrão `True`), saindo da bandeja se for o
  caso. No Delphi também há o evento `OnClick(Sender, Id, Action)`.
- **Os eventos só chegam com o app aberto.** Uma notificação clicada na Central de Ações depois de
  fechar o app não o abre de novo (isso exigiria registrar um ativador COM).
- `IconPath`: imagem `.png`/`.jpg` mostrada na notificação (`appLogoOverride`).
- Sem WinRT (Windows 7), a notificação vira um balão do plugin `tray`, se houver; senão rejeita
  com `UNSUPPORTED`.
- **Erros:** `INVALID_ARGS` (id inválido, mais de 5 botões), `NOTIFICATION_FAILED`, `UNSUPPORTED`.

## `single-instance`

Exemplo: [`Examples/SingleInstance`](../Examples/SingleInstance/README.md).

O app roda uma vez só. Abrir de novo (pelo atalho, ou com um arquivo arrastado para o exe) traz a
janela aberta para frente e entrega a ela os argumentos da nova execução.

```pascal
// no .dpr, antes de criar o form: a segunda execução nem chega a criar janela
begin
  if BorionIsSecondInstance('Empresa.MeuApp') then
    Exit;
  Application.Initialize;
  ...

// no form
Ipc.AddPlugin(TBorionSingleInstancePlugin.Create);
```

```js
import { args, onSecondInstance } from '@borion/api/single-instance';

const inicio = await args();                       // { args, cwd } desta execução
onSecondInstance(({ args, cwd }) => abrir(args));  // as próximas
```

- `args` não inclui o exe. Unicode completo (os argumentos são lidos com `CommandLineToArgvW`).
- Se o `.dpr` não chamar `BorionIsSecondInstance`, o plugin faz a verificação ao ser criado; numa
  segunda execução, o app termina sem mostrar a janela (mas o form chega a ser criado).
- A janela volta para frente (`FocusOnSecondInstance`, padrão `True`), saindo da bandeja se for
  o caso. No Delphi, o evento `OnSecondInstance(Sender, Args, Cwd)`.
- Vale por sessão do Windows: dois usuários logados têm uma instância cada.
- Por baixo: um mutex nomeado e uma janela só de mensagens que recebe um `WM_COPYDATA`.

## `deep-link`

Exemplo: [`Examples/DeepLink`](../Examples/DeepLink/README.md).

Links `meuapp://...` abrem o app, como o deep-link do Tauri.

```pascal
Ipc.AddPlugin(TBorionSingleInstancePlugin.Create);        // antes: links com o app aberto
Ipc.AddPlugin(TBorionDeepLinkPlugin.Create(['meuapp']));
```

```js
import { getCurrent, onOpenUrl } from '@borion/api/deep-link';

const inicial = await getCurrent();          // URLs que abriram o app, ou null
onOpenUrl((urls) => urls.forEach(abrir));    // links abertos com o app rodando
```

| JS (`@borion/api/deep-link`) | O que faz |
|---|---|
| `getCurrent()` | URLs que abriram esta execução, ou `null` |
| `onOpenUrl((urls) => ...)` | Links abertos com o app já rodando |
| `register(esquema)` / `unregister(esquema)` / `isRegistered(esquema)` | Só esquemas declarados no Delphi (`FORBIDDEN_SCHEME`) |

- **Registro:** `HKCU\Software\Classes\<esquema>` (`URL Protocol` e `shell\open\command` apontando
  para o exe). Com `AutoRegister` (padrão), o plugin registra a cada início, o que mantém o caminho
  certo se o app mudar de pasta. Não precisa de administrador.
- **Com o app aberto**, o Windows abre outra execução com a URL; o `single-instance` a entrega à
  janela aberta e o `deep-link` emite `onOpenUrl`. Sem o `single-instance`, cada link abre uma
  janela nova.
- O `unregister` só apaga o registro se ele apontar para este exe: outro app pode usar o mesmo
  esquema.
- Esquemas válidos começam com letra (letras, números, `+`, `-`, `.`). Os do sistema (`http`,
  `https`, `file`, `mailto`, `ms-*`...) são recusados (`INVALID_SCHEME`).
- **Segurança: qualquer site pode abrir um link do seu esquema.** Trate a URL como entrada não
  confiável: valide antes de agir e nunca execute algo só porque um link pediu.
- No Delphi: `OnOpenUrl(Sender, Urls)`, `RegisterScheme`, `UnregisterScheme`, `IsRegistered`.

## `autostart`

Exemplo: [`Examples/Autostart`](../Examples/Autostart/README.md).

`TBorionAutostartPlugin.Create([AppName, Args])`. Iniciar o app com o Windows, como o autostart
do Tauri. `AppName` (padrão: `Application.Title`) é o nome na aba Inicializar do Gerenciador de
Tarefas; `Args` (padrão `--autostart`) vai junto do exe, para o app saber que veio do login.

| JS (`@borion/api/autostart`) | O que faz |
|---|---|
| `enable()` / `disable()` | Liga / desliga (`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`) |
| `isEnabled()` | Se vai iniciar com o Windows |
| `launchedAtLogin()` | Se esta execução veio do login (para abrir minimizado na bandeja, por exemplo) |

- O usuário pode desabilitar o app no Gerenciador de Tarefas sem apagar o valor do `Run` (o
  Windows marca em `StartupApproved`). O `isEnabled()` leva isso em conta, e o `enable()` volta a
  ligar.
- O `isEnabled()` só é `true` se o valor apontar para este exe (não para uma cópia em outra
  pasta).
- Sem administrador: vale para o usuário atual.

## `global-shortcut`

Exemplo: [`Examples/GlobalShortcut`](../Examples/GlobalShortcut/README.md).

`TBorionGlobalShortcutPlugin.Create`. Atalhos de teclado que funcionam com o app em segundo
plano (`RegisterHotKey`), como o global-shortcut do Tauri.

```js
import { register } from '@borion/api/global-shortcut';

await register('CmdOrCtrl+Shift+Space', ({ shortcut }) => app.show());
```

| JS (`@borion/api/global-shortcut`) | O que faz |
|---|---|
| `register(atalho \| [atalhos], handler)` | Registra; devolve o atalho normalizado (`'Ctrl+Shift+Space'`) |
| `unregister(atalho \| [atalhos])` / `unregisterAll()` | Libera |
| `isRegistered(atalho)` | Se este app registrou |

- **Sintaxe:** modificadores e tecla separados por `+`, sem diferenciar maiúsculas. Modificadores:
  `Ctrl` (`Control`, `CmdOrCtrl`, `CommandOrControl`), `Alt` (`Option`), `Shift`, `Win` (`Super`,
  `Meta`, `Cmd`). Teclas: `A`-`Z`, `0`-`9`, `F1`-`F24`, `Space`, `Enter`, `Tab`, `Escape`,
  `Backspace`, `Delete`, `Insert`, `Home`, `End`, `PageUp`, `PageDown`, `Up`, `Down`, `Left`,
  `Right`, `PrintScreen`, `Pause`, `Plus`, `Minus`, `Comma`, `Period`, `Num0`-`Num9` e as de mídia
  (`MediaPlayPause`, `MediaNext`, `MediaPrevious`, `MediaStop`, `VolumeUp`, `VolumeDown`,
  `VolumeMute`).
- **Letras, números e teclas de digitação exigem um modificador:** um atalho global `A`
  capturaria a letra A no Windows inteiro. Teclas F, de mídia, `PrintScreen` e `Pause` podem ser
  sozinhas.
- Registrar de novo um atalho que já é deste app só troca o handler (a página pode ter sido
  recarregada). Um atalho em uso por outro programa rejeita com `ALREADY_REGISTERED`.
- Segurar a tecla não repete o evento. Os atalhos são liberados quando o app fecha.
- No Delphi: `Register`, `Unregister`, `UnregisterAll` e o evento `OnShortcut(Sender, Shortcut)`.
- **Erros:** `INVALID_SHORTCUT`, `ALREADY_REGISTERED`, `REGISTER_FAILED`.

## `log`

Exemplo: [`Examples/Log`](../Examples/Log/README.md).

`TBorionLogPlugin.Create(AppName)`. Log em arquivo (UTF-8) com níveis e rotação, o mesmo para o
Delphi e para a página.

```pascal
Log := TBorionLogPlugin(Ipc.AddPlugin(TBorionLogPlugin.Create('Meu App')));
Log.MinLevel := llDebug;
Log.Info('iniciando');   // de qualquer thread
```

```js
import { info, error, forwardConsole, attachConsole } from '@borion/api/log';

info('pedido salvo');
forwardConsole();   // console.* e erros não tratados da página também vão para o arquivo
attachConsole();    // o que for gravado (inclusive pelo Delphi) aparece no console do DevTools
```

```
2026-10-15 10:40:00.564 [INFO ] [delphi] janela criada
2026-10-15 10:40:07.676 [WARN ] [js] pedido 42 salvo por José 😀
2026-10-15 10:40:07.680 [ERROR] [console] Error: algo deu errado
    at onclick (https://app.local/app.js:22:50)
```

| JS (`@borion/api/log`) | O que faz |
|---|---|
| `trace`, `debug`, `info`, `warn`, `error` (`mensagem, {target?}`) | Grava uma linha; `target` é o rótulo (padrão `js`) |
| `forwardConsole()` | `console.log/info/warn/error/debug`, erros e Promises rejeitadas não tratados também vão para o arquivo (rótulo `console`); devolve quem desfaz |
| `attachConsole()` | Cada linha gravada aparece no console do DevTools; devolve quem desfaz |
| `logPath()` | Caminho do arquivo |

- **Arquivo:** `%LOCALAPPDATA%\<app>\logs\<app>.log` (troque pela propriedade `Dir`). Ao passar de
  `MaxFileSize` (1 MB), vira `.log.1`, o `.1` vira `.2`... até `KeepFiles` (5).
- **`MinLevel`** (padrão `llInfo`): `debug` e `trace` são ignorados até baixar o nível.
- O arquivo fica aberto permitindo leitura e escrita por outros: dá para acompanhar com
  `Get-Content -Wait` ou abrir no editor com o app rodando.
- `EchoToDebugger` também manda cada linha para o `OutputDebugString` (DebugView, IDE).
- Unicode completo (emoji inclusive), nas linhas da página e do Delphi (`WideString`).

## Unicode completo: JSON só com ASCII

As strings do Delphi 7 são ANSI: emoji e caracteres fora da página de código do Windows viram `?`
ao entrar no Delphi. Para o `clipboard` e o `store`, em que o texto precisa sair exatamente como
entrou, o `@borion/api` manda e recebe **JSON só com ASCII**: o resto vai como `\uXXXX`
(`"olá"` → `"ol\u00e1"`).

- O `store` guarda esse texto como está, sem interpretar. O arquivo continua sendo JSON comum.
- O `clipboard` converte direto de e para UTF-16 (`CF_UNICODETEXT`).

Os módulos JS fazem isso sozinhos. Quem chama `invoke` direto precisa seguir o formato: no
`clipboard`, `text`/`html`/`altText` são literais JSON de string (com as aspas); no `store`, `key`
é um literal de string e `value` o texto JSON do valor. No Delphi, as funções estão no
`BorionJson`: `WideToJsonLiteral`, `JsonLiteralToWide` e `IsAsciiJson`.

## Escrevendo um plugin

Um plugin é uma classe com `Name` e `Install`; no app, entra com `.Plugin(TMeuPlugin.Create)`.

```pascal
type
  TMeuPlugin = class(TBorionPlugin)
  private
    procedure CmdOla(Call: TBorionCall);
    procedure CmdEscolher(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    function Name: string; override;
  end;

function TMeuPlugin.Name: string;
begin
  Result := 'meu';
end;

procedure TMeuPlugin.Install;
begin
  Command('ola', CmdOla);                // registra 'meu:ola'
  CommandLater('escolher', CmdEscolher); // roda fora do callback (pode abrir janelas modais)
end;
```

- `Ipc.AddPlugin(P)` define `P.Ipc`, chama `Install` e passa a ser o dono do plugin. Não pode haver
  dois plugins com o mesmo `Name` (`EBorionError` com code `PLUGIN`).
- `Command` registra `<Name>:<comando>`; o handler é um `TBorionCall` como qualquer comando.
- `CommandLater` usa `Ipc.Later`: a chamada é adiada e o handler roda depois, na thread da
  interface. A resposta sai quando o handler retorna: `Result`, `Reject` ou exceção. Dentro de um
  handler `Later` não chame `Defer` de novo.
- `Ipc.FindPlugin('fs')` devolve o plugin, por exemplo para ajustar `AllowedSchemes`.

## Limitações

- O escopo compara caminhos depois de `GetFullPathName`. Links simbólicos ou junções que já
  existam **dentro** de uma pasta liberada e apontem para fora dela podem ser seguidos por
  leitura e escrita; só o `remove` recursivo se protege. Não libere pastas onde terceiros
  possam criar links.
- As permissões dadas pelo `dialog` duram só a sessão (não há escopo persistido).
- Nomes 8.3 (`PROGRA~1`) não são expandidos: são comparados como estão, o que só pode negar,
  nunca liberar a mais.
- Caminhos com caracteres fora da página de código do Windows não são suportados (Delphi 7 ANSI).
  O mesmo vale para o texto do `fs` e dos outros plugins, exceto `clipboard` e `store` (veja
  [Unicode completo](#unicode-completo-json-só-com-ascii)).
- Os atalhos do `menu` só funcionam com o foco na janela do app (não são atalhos globais do
  sistema). O `popup` e o menu da bandeja são menus Win32 sem ícones.
- Ainda faltam os caminhos do `os`/`app`,
  imagens no `clipboard` e o upload com `FormData` no `http`: veja o
  [roadmap](ROADMAP.md).
