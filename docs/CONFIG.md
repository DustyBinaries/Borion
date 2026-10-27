# Configuração: `app.json`

O `app.json`, na pasta do projeto, é a configuração do app, como o `tauri.conf.json` do Tauri: o
nome, a versão, a janela principal, a CSP e onde o `borion build` e o `borion dev` acham a
interface. O `borion new` já gera um.

```json
{
  "productName": "Meu App",
  "version": "0.1.0",
  "identifier": "com.exemplo.meu-app",
  "build": {
    "frontendDist": "frontend/dist",
    "devUrl": "http://localhost:5173"
  },
  "app": {
    "windows": [
      {
        "title": "Meu App",
        "width": 1000,
        "height": 700,
        "minWidth": 600,
        "minHeight": 400,
        "resizable": true,
        "center": true
      }
    ],
    "security": {
      "csp": "default-src 'self'; style-src 'self' 'unsafe-inline'"
    }
  },
  "bundle": {
    "icon": ["icons/icon.ico"]
  }
}
```

Com o app.json, o `.dpr` fica só com o que é código:

```pascal
begin
  TBorionBuilder.Create   // título, janela e CSP vêm do app.json embutido
    .Plugin(TBorionDialogPlugin.Create)
    .Command('saudar', Saudar)
    .Run;
end.
```

## Como ele chega ao app

O `borion build` lê e valida o `app.json` e o grava no mesmo `.res` da interface (o `{$R web.res}` ou
`{$R app.res}` do `.dpr`), como o recurso `BORION_CONFIG`, ao lado do `BORION_ASSETS`. No
`Run`, o `TBorionBuilder` lê esse recurso (`BorionAppConfig`, unit `BorionConfig`).

- **Não vai no `*.res` do projeto:** a IDE do Delphi regrava esse arquivo (ícone e versão) e
  apagaria o recurso.
- **No `borion dev`,** mudar o `app.json` reabre o app com a configuração nova, como acontece
  com os `.pas`. Só o recurso do app.json é trocado no `.res`; a interface empacotada continua
  a mesma.
- **Sem `app.json`** (os exemplos antigos, um `.res` gerado à mão), o app usa os padrões e o que
  o `.dpr` definir.
- **Um app.json inválido** para o `borion build` com a mensagem. Se mesmo assim chegar um
  inválido ao exe, o app avisa e abre com os padrões.

## Precedência

1. Os métodos do builder no `.dpr` (`.Size(800, 600)`, `.Csp(...)`) vencem o `app.json`, campo
   por campo: `.Size` muda só o tamanho, e o resto continua vindo do arquivo.
2. Depois vem o `app.json` embutido.
3. Por último, os padrões: janela de 1000×700, redimensionável, centralizada, com borda, e o
   nome do exe como título.

`TBorionBuilder.Create('Título')` vence o `productName`. Para usar outra configuração no lugar
da embutida (lida de um arquivo, por exemplo), chame `.Config(MinhaConfig)` logo depois do
`Create`.

## Referência

Tudo é opcional. Um tipo errado (`"width": "800"`) ou um valor inválido para o build com a
mensagem e o caminho da chave (`"app.windows[0].width" deve ser um número inteiro...`). Uma chave
desconhecida (um `"widht"`) vira um aviso, mas o build continua. `null` vale o mesmo que a
chave ausente.

| Chave | Tipo | O que faz |
|---|---|---|
| `productName` | texto | Nome do app: `Application.Title`, o título da janela e o nome usado pelos plugins (`autostart`, `deep-link`, escopo do `$APPDATA`...) |
| `version` | texto | Versão no formato `1.2.3` (até 4 números de 0 a 65535, sufixo opcional `-beta.1` ou `+build`). É o que o `app:info` devolve |
| `identifier` | texto | Identificador reverso (`com.empresa.app`): letras, dígitos, `-` e `_`, em duas partes ou mais. O `app:info` devolve, e o `window-state` grava na pasta `%APPDATA%\<identifier>`; os próximos recursos (instalador, AppUserModelID) vão usá-lo |
| `build.frontendDist` | texto | Pasta da interface pronta, relativa ao `app.json` (veja abaixo) |
| `build.devUrl` | texto | URL do servidor de desenvolvimento (`http://` ou `https://`). O `borion dev` abre o app nela, e a porta vai para o Vite (`--port`) |
| `app.windows` | lista | As janelas; a primeira é a principal ([várias janelas](#várias-janelas)) |
| `app.windows[].label` | texto | Rótulo da janela: letras, dígitos, `-` e `_`, único. Obrigatório a partir da segunda; a primeira é `main` se não tiver |
| `app.windows[].url` | texto | A página da janela, um caminho do app começando com `/` (padrão `/`): `"/config.html"` |
| `app.windows[].create` | lógico | `false`: a janela só fica definida, e abre depois (pelo JS ou pelo Delphi). Não vale para a principal |
| `app.windows[].visible` | lógico | `false`: criada escondida (padrão `true`) |
| `app.windows[].title` | texto | Título da janela. Com ele, o título fica fixo; sem ele, o título é o `productName` e acompanha o `document.title` da página |
| `app.windows[].width`, `height` | inteiro | Tamanho inicial (padrão 1000×700) |
| `app.windows[].minWidth`, `minHeight`, `maxWidth`, `maxHeight` | inteiro | Limites de tamanho (0 = sem limite) |
| `app.windows[].resizable` | lógico | `false`: borda fixa, sem maximizar (padrão `true`) |
| `app.windows[].center` | lógico | `false`: posição escolhida pelo Windows (padrão `true`, centralizada) |
| `app.windows[].maximized` | lógico | Abre maximizada |
| `app.windows[].decorations` | lógico | `false`: sem borda nem barra de título, para desenhar a barra em HTML ([plugin `window`](PLUGINS.md#barra-de-título-em-html): arrastar, maximizar, redimensionar pela beirada e os botões) |
| `app.windows[].alwaysOnTop` | lógico | Sempre por cima das outras janelas |
| `app.windows[].fullscreen` | lógico | Abre em tela cheia, sem borda, cobrindo o monitor (precisa do [plugin `window`](PLUGINS.md)); com `decorations: false` e `alwaysOnTop: true`, é a base de um app em modo quiosque. `setFullscreen(false)` sai dela |
| `app.windows[].devTools` | lógico | `false`: sem DevTools (F12, Ctrl+Shift+I, "Inspecionar"); padrão `true` |
| `app.windows[].contextMenu` | lógico | `false`: sem o menu de contexto padrão (botão direito: Voltar, Salvar como, Inspecionar...); padrão `true`. O `menu` do Borion (`popup`) continua funcionando |
| `app.windows[].browserKeys` | lógico | `false`: sem as teclas de navegador: recarregar (F5, Ctrl+R), ver fonte (Ctrl+U) e zoom (Ctrl+roda, Ctrl+`+`/`-`/`0`). A página não recebe essas teclas; padrão `true` |
| `app.security.allowNavigation` | lista | Origens (`"https://docs.exemplo.com"`, `"http://localhost:8080"`, ou `"*"`) para onde as janelas podem navegar, além do app ([navegação](#navegação-e-janelas-novas)) |
| `app.security.csp` | texto | O header `Content-Security-Policy` dos assets embutidos e da pasta no `--dev-dir`. Não vale para o servidor do Vite |
| `bundle.icon` | lista | Os ícones do app, relativos ao `app.json`, como no `tauri.conf.json`. O primeiro `.ico` da lista vira o ícone do exe ([ícone](#ícone)); os `.png` e `.icns` são aceitos e ignorados |
| `bundle.active` | lógico | Aceito, como no Tauri; ainda não faz nada (o instalador é da Fase 7) |
| `$schema` | texto | Aceito e ignorado |

### Onde fica a interface

Sem `build.frontendDist`, a convenção: `frontend\package.json` → projeto npm com a saída em
`frontend\dist`; senão, a pasta `web\`, estática.

Com `build.frontendDist`:

- se a pasta acima dela tem um `package.json` (`"ui/dist"` com `ui\package.json`), é um projeto
  npm: o `borion build` roda `npm run build` em `ui\` e empacota `ui\dist`;
- senão, é uma interface estática, empacotada como está (`"web"`, `"public"`).

### Várias janelas

```json
"windows": [
  { "label": "main", "width": 900, "height": 680 },
  { "label": "config", "url": "/config.html", "title": "Configurações", "width": 420,
    "height": 360, "resizable": false, "create": false }
]
```

- As janelas sem `"create": false` abrem junto com a principal; as outras ficam só definidas.
- **Abrir depois:** `createWindow('config')` no JS (do plugin [`window`](PLUGINS.md#window)) ou
  `BorionWindows.Open('config')` no Delphi. O JS também cria janelas que não estão no
  `app.json`, passando `url`, `title`, tamanho etc.
- **O mesmo IPC:** todas as janelas usam o mesmo IPC (veja o [guia do IPC](IPC.md#várias-janelas)):
  os comandos e plugins do `.dpr` servem todas, e cada chamada sabe de que janela veio.
- **Fechar:** a principal fecha o app, e as outras junto. Uma secundária só se fecha (e é
  liberada); o `onCloseRequested` de cada uma vale só para ela.
- **Os métodos do builder** (`.Size`, `.Maximized`...) mudam só a principal.

Para cada janela vale o mesmo frontend: no build, as páginas da pasta `frontendDist`; no
`borion dev`, o servidor do Vite (um projeto com várias páginas) ou a pasta `web\`.

### Navegação e janelas novas

Uma janela do Borion só navega para o app (o frontend embutido, o `devUrl`), para as origens
liberadas no IPC (`AllowOrigin`, `Url()`) e para as de `app.security.allowNavigation`:

```json
"security": { "allowNavigation": ["https://docs.exemplo.com"] }
```

- **Qualquer outra navegação é cancelada.** Se partiu de um gesto do usuário (um clique num link
  ou num botão que faz `location.href = ...`) para `http`, `https` ou `mailto`, abre no
  **navegador do sistema**; um redirecionamento do servidor ou uma navegação de script sem gesto
  só é cancelado. Nada além desses esquemas é executado (`file:`, `javascript:`...).
- **Janela nova nunca abre** (`target="_blank"`, `window.open`): o link de fora vai para o
  navegador do sistema, e um link para o próprio app é ignorado. Para abrir outra janela do app,
  use `createWindow` / `BorionWindows.Open`.
- **`allowNavigation` não dá acesso ao IPC:** só a navegação. O IPC continua só para as origens
  do `AllowOrigin`.
- No Delphi: `.AllowNavigation('https://docs.exemplo.com')` no builder (soma-se ao arquivo) ou
  `Window.AllowNavigation(...)` numa janela. `"*"` libera qualquer navegação.

### Ícone

```json
"bundle": {
  "icon": ["icons/32x32.png", "icons/128x128.png", "icons/icon.icns", "icons/icon.ico"]
}
```

O `borion build` grava o `.ico` no mesmo `.res` da interface, como o recurso `MAINICON` (o
mesmo nome que a IDE usa). Esse é o ícone do exe no Explorer, da janela, da barra de tarefas,
do plugin `tray` e dos links do `deep-link`, sem código no `.dpr`.

- **Só o `.ico` conta:** o Windows não usa `.png` nem `.icns`. A lista do Tauri pode ser colada
  como está, mas precisa ter um `.ico`. Sem ele, o build para com a mensagem. Ponha no `.ico`
  as imagens de 16, 24, 32, 48 e 256 px; o Windows escolhe a de cada lugar.
- **Arquivo inexistente ou `.ico` inválido** param o build com a mensagem.
- **No `borion dev`,** trocar o `.ico` recompila e reabre o app, como acontece com o `app.json`.
- **Um ícone só:** se o `.res` do projeto (o `{$R *.res}`) também tiver um `MAINICON` (um
  `MAINICON ICON "x.ico"` no `.rc`, ou o ícone que a IDE grava), o linker do Delphi 7 não aceita
  os dois ("Duplicate resource"). O `borion build` para antes e diz qual tirar. Sem
  `bundle.icon`, vale o do `.rc`, como antes.

## API Delphi

```pascal
uses BorionConfig;

BorionAppConfig.ProductName;     // o app.json embutido (os padrões, se não houver)
BorionAppConfig.Window.Width;
BorionAppConfigError;            // '' ou o erro de leitura do recurso

C := TBorionConfig.Create;       // ler de outro lugar
C.LoadFromFile('outro.json');    // EBorionConfig se inválido; avisos em C.Warnings
TBorionBuilder.Create.Config(C)...

C.Window.ContextMenu;            // contextMenu e browserKeys de cada janela
C.AllowNavigation;               // TStringList: app.security.allowNavigation
```

```pascal
uses Borion;

BorionWindows.Main;                  // a janela principal (TBorionWindow)
BorionWindows.Find('config');        // nil se não estiver aberta
BorionWindows.Open('config');        // a do app.json; aberta, só ganha o foco
BorionWindows.CreateWindow(Config);  // uma TBorionWindowConfig qualquer
BorionWindows.Count; BorionWindows[I].WindowLabel;
```

O `BorionWindows` existe durante o `TBorionBuilder.Run`. `TBorionWindow.ApplyConfig(Config,
TituloPadrao)` aplica uma `TBorionWindowConfig` a uma janela (o builder usa esse método para
todas).

A navegação de cada janela também tem API: `TBorionBuilder.AllowNavigation('https://docs.exemplo.com')`
(soma-se ao `app.security.allowNavigation`) e `TBorionWindow.AllowNavigation(...)`, que vale só para
aquela janela. Veja [navegação e janelas novas](#navegação-e-janelas-novas).

## Ainda não

- `x`/`y` e `fullscreen` por janela; uma janela com outro site (`url` externa).
- `beforeDevCommand` / `beforeBuildCommand`: hoje o comando é sempre o `npm run dev` / `npm run build`.
- Versão e manifesto do exe a partir do `app.json` (hoje o `.rc` é escrito à mão; Fase 7).
- Capabilities e permissões, CSP padrão restritiva (Fase 5).
