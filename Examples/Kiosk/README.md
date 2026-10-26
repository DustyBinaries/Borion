# Exemplo: modo kiosk

Um app em tela cheia para um totem ou um caixa: a janela cobre o monitor, fica por cima de tudo, não
tem borda nem DevTools e não fecha por Alt+F4. A saída é escondida atrás de um PIN.

O Borion não tem um "modo kiosk" único (o Tauri também não): ele é a soma de opções da janela
com o que a página faz. O app inteiro é o `KioskDemo.dpr` (sem form), que só liga o plugin
`window`:

```pascal
uses
  Borion, BorionWindow;

begin
  TBorionBuilder.Create
    .Plugin(TBorionWindowPlugin.Create)
    .Run;
end.
```

## O `app.json`

```json
{
  "app": {
    "windows": [{
      "fullscreen": true,
      "decorations": false,
      "alwaysOnTop": true,
      "resizable": false,
      "devTools": false
    }]
  }
}
```

| Chave | Efeito |
|---|---|
| `fullscreen` | Abre cobrindo o monitor inteiro, inclusive a barra de tarefas (precisa do plugin `window`) |
| `decorations: false` | Sem borda nem barra de título |
| `alwaysOnTop` | Nenhuma outra janela fica por cima |
| `resizable: false` | O usuário não muda o tamanho |
| `devTools: false` | Sem F12, Ctrl+Shift+I e "Inspecionar" |

## O que a página faz (`web\app.js`)

| | |
|---|---|
| Fechamento | `win.onCloseRequested` com `event.preventDefault()` barra o X, o Alt+F4 e o `app.exit()` |
| Menu de contexto e atalhos | `contextmenu` e `keydown` com `preventDefault`: F5, Ctrl+R, Ctrl+P, Ctrl+/-, F11, F12, e o zoom com Ctrl+roda |
| Cursor | Some depois de 3 s sem mover o mouse |
| Saída | Cinco cliques no canto superior esquerdo abrem um `<dialog>` com o PIN (`1234`); certo, `win.destroy()` fecha sem passar pelo `onCloseRequested` |

## O que não dá para fazer pela página

O Borion, como o Tauri, só controla a própria janela. Ficam de fora o **Ctrl+Alt+Del**, o
**Win+teclas** e o **Alt+Tab**, que são do Windows. Num quiosque de verdade, combine o app com
o *Acesso atribuído* (Assigned Access) do Windows, ou troque o shell, para que ele seja a única coisa
que o usuário alcança.

O PIN do exemplo fica na página só para mostrar o fluxo. Um app real deve conferi-lo num comando
Delphi, com a senha fora do JavaScript.

## Rodando

```bat
build.bat
KioskDemo.exe
```

Para sair: cinco cliques no canto superior esquerdo (a página marca o canto com uma linha tracejada
e conta os cliques) e o PIN `1234`. Se algo der errado durante o
desenvolvimento, `taskkill /im KioskDemo.exe /f`.

O `build.bat` usa o `borion build`: copia o [`@borion/api`](../../js/README.md) para
`web\borion-api\`, empacota a pasta `web\` e o `app.json` em `web.res`, compila o `.rc` e o `.dpr`
(com o *Search path* do `KioskDemo.dof`) e copia o `WebView2Loader.dll`.

| | |
|---|---|
| `KioskDemo.dpr` | O app inteiro: o `TBorionBuilder` com o plugin `window` |
| `app.json` | A janela em tela cheia ([referência](../../docs/CONFIG.md)) |
| `web\index.html` / `web\style.css` / `web\app.js` | A página, o relógio, o bloqueio e o PIN |

Referência: [docs/PLUGINS.md](../../docs/PLUGINS.md) (plugin `window`, `onCloseRequested`).
