# Exemplo: barra de título em HTML

Uma janela sem borda com a barra de título desenhada pela página, como a de um app Tauri com
`"decorations": false`.

O app inteiro é o `TitlebarDemo.dpr` (sem form). Ele só liga o plugin `window`; a janela sem
borda vem do `app.json`:

```pascal
uses
  Borion, BorionWindow;

begin
  TBorionBuilder.Create
    .Plugin(TBorionWindowPlugin.Create)
    .Run;
end.
```

```json
{
  "productName": "Borion: titlebar",
  "build": { "frontendDist": "web" },
  "app": { "windows": [{ "width": 900, "height": 600, "minWidth": 480, "minHeight": 320, "decorations": false }] }
}
```

A barra é HTML comum. O plugin `window` cuida de arrastar e redimensionar; a página só liga os
botões:

```html
<div class="titlebar" data-borion-drag-region>
  <span class="titulo" data-borion-drag-region>Borion: titlebar</span>
  <div class="controles">
    <button id="min">...</button>
    <button id="max">...</button>
    <button id="close">...</button>
  </div>
</div>
```

```js
import * as win from '@borion/api/window';

$('min').onclick = () => win.minimize();
$('max').onclick = () => win.toggleMaximize();
$('close').onclick = () => win.close();
```

## O que ele mostra

| | |
|---|---|
| Arrastar | Pela barra e pelo título (`data-borion-drag-region`); os botões não arrastam |
| Duplo clique | Na barra, maximiza e restaura; o ícone do botão do meio acompanha o `onResized` |
| Redimensionar | Pela beirada da página (5 px), com o cursor de redimensionar. Desmarque "redimensionável" (`setResizable(false)`) e a beirada vira página de novo |
| Maximizar | Fica na área de trabalho, sem cobrir a barra de tarefas |
| Foco | A barra fica cinza com a janela inativa (`onFocusChanged`) |
| `setDecorations(true)` | Volta a borda do Windows e esconde a barra em HTML |
| `startDragging()` | Arrasta a janela a partir de um quadro qualquer, num `mousedown` |

## Rodando

```bat
build.bat
TitlebarDemo.exe
```

O `build.bat` usa o `borion build`: copia o [`@borion/api`](../../js/README.md) para
`web\borion-api\`, empacota a pasta `web\` e o `app.json` em `web.res`, compila o `.rc` e o `.dpr`
(com o *Search path* do `TitlebarDemo.dof`) e copia o `WebView2Loader.dll`.

| | |
|---|---|
| `TitlebarDemo.dpr` | O app inteiro: o `TBorionBuilder` com o plugin `window` |
| `app.json` | A janela sem borda ([referência](../../docs/CONFIG.md)) |
| `web\index.html` / `web\style.css` / `web\app.js` | A barra de título e os botões |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#barra-de-título-em-html).
