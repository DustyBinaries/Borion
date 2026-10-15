# Exemplo: plugin `menu`

A barra de menu da janela é **nativa** (um `TMainMenu` da VCL) e é montada pela página com
`menu.setMenu`. No Delphi, só uma linha:

```pascal
Ipc.AddPlugin(TBorionMenuPlugin.Create);
```

## O que ele mostra

| Seção | O que demonstra |
|---|---|
| Barra de menu | Submenu (Arquivo › Exportar), separador, item desabilitado, itens com marcação (Exibir › Painel lateral / Tema escuro) e atalhos (`Ctrl+N`, `Ctrl+S`, `Ctrl+B`, `Ctrl+D`, `F1`) |
| 1. Atalhos | Com o foco num campo da página, o `Ctrl+S` vai para o menu e a página **não** recebe a tecla. Com o item desabilitado, a tecla chega à página |
| 2. `menu.update` | Habilitar/desabilitar, renomear e trocar o atalho de um item; remover e recriar a barra |
| 3. `menu.popup` | Menu de contexto no clique direito (com checkbox e submenu) e um menu aberto embaixo de um botão, em `x, y` da página. Devolve o `id` escolhido ou `null` |
| Eventos | Cada `menu:click` (`id` e, nos checkbox, `checked`) |

## Rodando

```bat
build.bat
MenuDemo.exe
```

O `build.bat` copia os módulos do [`@borion/api`](../../js/README.md) (`Borion\js`) para
`web\borion-api\`, empacota a pasta `web\` com o `borion pack` e compila. Não precisa de Node
nem de Vite: o *import map* do `index.html` resolve `import ... from '@borion/api/menu'` para a
cópia local, e o código fica igual ao de um projeto com bundler.

| | |
|---|---|
| `uPrincipal.pas` | A janela (sem `.dfm`): browser, IPC, assets e o plugin |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#menu).
