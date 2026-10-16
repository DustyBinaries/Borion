# Exemplo: Borion + React + Vite

Um app React (Vite) com lógica em Delphi 7: o frontend chama comandos Delphi com o
[`@borion/api`](../../js/README.md) e, no build, vai inteiro para dentro do `.exe`.

| | |
|---|---|
| `frontend/` | App React + Vite. Roteamento no cliente (`/clientes/2`), chamadas a comandos Delphi, eventos de uma thread |
| `uComandos.pas` | Comandos: `info`, `saudacao`, `listarClientes`, `cliente`, `tarefaLonga` |
| `ViteReact.dpr` | O app inteiro, sem form: o `TBorionBuilder` com os comandos de `uComandos.pas` |
| `build.bat` | Build de produção |
| `dev.bat` | Modo dev com hot-reload |

## Requisitos

Os do [Borion](../../README.md#requisitos) e **Node.js 20.19+** (para o Vite).

## Build de produção

```bat
build.bat
ViteReact.exe
```

Na ordem: `npm install` (só na primeira vez), `npm run build`, `borion pack frontend\dist app.res`,
`dcc32`. O resultado é um único `ViteReact.exe` (mais o `WebView2Loader.dll`), com a interface
embutida e servida em `https://app.local/`.

## Desenvolvimento

```bat
dev.bat
```

Abre o Vite numa janela separada (`http://localhost:5173`) e o app com
`--dev-url=http://localhost:5173`. Edite `frontend\src\App.jsx`: a mudança aparece na hora, sem
recarregar a página e sem recompilar o Delphi. Para mudar comandos Delphi, feche o app e rode o
`build.bat`. Para parar o Vite, feche a janela dele.

Abrir `http://localhost:5173` num navegador comum também funciona para trabalhar no layout. A
página avisa que está fora do Borion, e os comandos falham com `NOT_AVAILABLE`.

## Pontos para observar

- **Fallback de SPA:** navegue até um cliente e aperte **F5**. A URL `/clientes/2` não é um
  arquivo, e o `TBorionAssets` devolve o `index.html` para o roteador resolver.
- **Erros:** `/clientes/99` mostra o `EBorionError('NAO_ENCONTRADO', ...)` do Delphi.
- **Thread:** em *Tarefa*, o progresso chega por `listen('tarefa:progresso')`, registrado num
  `useEffect` cujo cleanup é a própria função devolvida pelo `listen`.
- **Origem:** o IPC só libera a origem de onde a interface veio: `https://app.local` no build,
  `http://localhost:5173` no dev.

Detalhes em [docs/ASSETS.md](../../docs/ASSETS.md).
