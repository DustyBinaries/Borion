# Borion: plugins

Plugins são conjuntos de comandos nativos prontos (`dialog`, `fs`, `shell`, `menu`, `tray`, `app`,
`clipboard`, `store`), com API tipada no JS
e regras de segurança embutidas. Cada um é uma unit em `Borion/Plugins/`, adicionada com uma
linha:

```pascal
uses BorionScope, BorionFs, BorionDialog, BorionShell;

Scope := TBorionScope.Create('Meu App');
Scope.AllowDir('$APPDATA');                       // %APPDATA%\Meu App

Ipc.AddPlugin(TBorionFsPlugin.Create(Scope));     // dono do escopo
Ipc.AddPlugin(TBorionDialogPlugin.Create(Scope));
Ipc.AddPlugin(TBorionShellPlugin.Create(Scope));
```

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
- [Unicode completo: JSON só com ASCII](#unicode-completo-json-só-com-ascii)
- [Escrevendo um plugin](#escrevendo-um-plugin)
- [Limitações](#limitações)

## Escopo de arquivos

O `TBorionScope` define o que os plugins podem tocar no disco. **Tudo é negado por padrão.**

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

`TBorionFsPlugin.Create(Scope, [OwnsScope = True])`. Por padrão o plugin libera o escopo ao ser
destruído; passe `False` se o escopo pertencer a outro objeto.

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

`TBorionDialogPlugin.Create([Scope])`. O escopo é opcional: sem ele, as escolhas não são
acrescentadas a nenhum escopo.

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

`TBorionShellPlugin.Create([Scope])`.

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
- Ainda faltam outros plugins (`os`, `http`, `notification`...), imagens no `clipboard` e o resto
  do `app`: veja o
  [roadmap](ROADMAP.md).
