# Exemplo: plugin `window`

A página controla a própria janela e decide se ela pode fechar.

O app inteiro é o `WindowDemo.dpr` (sem form). O título e o tamanho inicial vêm do `app.json`:

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
  "productName": "Borion: window",
  "build": { "frontendDist": "web" },
  "app": { "windows": [{ "width": 960, "height": 760, "minWidth": 640, "minHeight": 480 }] }
}
```

## O que ele mostra

| Seção | O que demonstra |
|---|---|
| 1. Estado | `state()`, atualizado pelo `onResized`, `onMoved` e `onFocusChanged` (agrupados num `requestAnimationFrame`, porque chegam em rajada ao arrastar) |
| 2. Título | `setTitle()`: até ali o título acompanha o `<title>` da página; depois, fica o do JS |
| 3. Tamanho e posição | `setSize()` (respeitando o mínimo do `app.json`), `center()` e `setPosition()` |
| 4. Estado da janela | `minimize()` com `setFocus()` 3 s depois, `toggleMaximize()`, `setFullscreen()` (Esc sai), `setAlwaysOnTop()`, `setResizable()` e `setDecorations()` |
| 5. Fechar | `onCloseRequested`: com o texto alterado, fechar pelo X, por Alt+F4 ou por `close()` abre um `<dialog>` em HTML ("Salvar", "Não salvar", "Cancelar"); `destroy()` fecha sem perguntar |

## Rodando

```bat
build.bat
WindowDemo.exe
```

Diferente dos outros exemplos de plugin, este usa o `borion build`, por causa do `app.json`. Ele
copia o [`@borion/api`](../../js/README.md) para `web\borion-api\`, empacota a pasta `web\` e o
`app.json` em `web.res`, compila o `.rc` e o `.dpr` (com o *Search path* do `WindowDemo.dof`) e
copia o `WebView2Loader.dll`.

| | |
|---|---|
| `WindowDemo.dpr` | O app inteiro: o `TBorionBuilder` com o plugin |
| `app.json` | Título, versão e a janela inicial ([referência](../../docs/CONFIG.md)) |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#window).
