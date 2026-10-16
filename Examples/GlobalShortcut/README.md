# Exemplo: plugin `global-shortcut`

Atalhos de teclado que funcionam com o app em segundo plano.

O app inteiro é o `GlobalShortcutDemo.dpr` (sem form):

```pascal
uses
  Borion, BorionGlobalShortcut;

begin
  TBorionBuilder.Create('Borion: global-shortcut')
    .Size(900, 640)
    .Plugin(TBorionGlobalShortcutPlugin.Create)  { os atalhos saem ao fechar }
    .Run;
end.
```

## O que ele mostra

| Seção | O que demonstra |
|---|---|
| 1. Registrar | `register` com o atalho digitado (`CmdOrCtrl+Shift+F9` já vem registrado); atalhos inválidos ou letras sozinhas são recusados com a mensagem do erro |
| 2. Registrados | Os atalhos normalizados, com `unregister` e `unregisterAll` |
| Pressionados | Minimize a janela, vá para outro programa e pressione o atalho: o evento chega e o título da janela (na barra de tarefas) mostra a contagem |
## Rodando

```bat
build.bat
GlobalShortcutDemo.exe
```

O `build.bat` copia os módulos do [`@borion/api`](../../js/README.md) (`Borion\js`) para
`web\borion-api\`, empacota a pasta `web\` com o `borion pack` e compila. Não precisa de Node
nem de Vite: o *import map* do `index.html` resolve `import ... from '@borion/api/global-shortcut'` para a
cópia local, e o código fica igual ao de um projeto com bundler.

| | |
|---|---|
| `GlobalShortcutDemo.dpr` | O app inteiro: o `TBorionBuilder` monta a janela com o plugin (sem form) |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#global-shortcut).
