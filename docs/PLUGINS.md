# Borion: plugins

Plugins são conjuntos de comandos nativos prontos (`dialog`, `fs`, `shell`, `menu`, `tray`, `app`),
com API tipada no JS
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
- Os atalhos do `menu` só funcionam com o foco na janela do app (não são atalhos globais do
  sistema). O `popup` e o menu da bandeja são menus Win32 sem ícones.
- Ainda faltam outros plugins (`clipboard`, `store`, `os`, `http`...) e o resto do `app`: veja o
  [roadmap](ROADMAP.md).
