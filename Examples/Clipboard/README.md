# Exemplo: plugin `clipboard`

A área de transferência do Windows pela página.

O app inteiro é o `ClipboardDemo.dpr` (sem form):

```pascal
uses
  Borion, BorionClipboard;

begin
  TBorionBuilder.Create('Borion: clipboard')
    .Size(900, 640)
    .Plugin(TBorionClipboardPlugin.Create)
    { TBorionClipboardPlugin.Create(False): a página só copia, não lê o que o
      usuário copiou de outros programas }
    .Run;
end.
```

## O que ele mostra

| Seção | O que demonstra |
|---|---|
| 1. Copiar | `writeText` com acentos, aspas curvas, euro, emoji e japonês: tudo chega intacto ao Windows (confira colando no Bloco de Notas). O botão "em 3 s" copia sem clique, onde a Clipboard API do navegador pediria permissão |
| 2. Ler | `readText` do que foi copiado em outro programa, com os code points; `null` quando não há texto; `clear` |
| 3. HTML | `writeHtml` com negrito, itálico, cor e lista, mais o texto puro em `altText`: colando no Word ou no WordPad a formatação vai junto |
## Rodando

```bat
build.bat
ClipboardDemo.exe
```

O `build.bat` copia os módulos do [`@borion/api`](../../js/README.md) (`Borion\js`) para
`web\borion-api\`, empacota a pasta `web\` com o `borion pack` e compila. Não precisa de Node
nem de Vite: o *import map* do `index.html` resolve `import ... from '@borion/api/clipboard'` para a
cópia local, e o código fica igual ao de um projeto com bundler.

| | |
|---|---|
| `ClipboardDemo.dpr` | O app inteiro: o `TBorionBuilder` monta a janela com o plugin (sem form) |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#clipboard).
