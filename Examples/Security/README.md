# Exemplo: segurança da janela

Uma janela que não deixa a página sair do app: ela só navega para onde o `app.json` permite, nenhuma
janela nova abre, e o release fica sem menu de contexto, DevTools e teclas de navegador. Tudo vem
do `app.json`; o `SecurityDemo.dpr` só chama o `TBorionBuilder`.

```json
{
  "app": {
    "windows": [{ "devTools": false, "contextMenu": false, "browserKeys": false }],
    "security": {
      "csp": "default-src 'self'; style-src 'self' 'unsafe-inline'; frame-src 'none'",
      "allowNavigation": ["https://example.org"]
    }
  }
}
```

| Chave | Efeito |
|---|---|
| `allowNavigation` | A janela navega para o app e para o `example.org`. Qualquer outro destino é cancelado |
| `contextMenu: false` | Sem o menu de contexto padrão (Voltar, Atualizar, Salvar como...) |
| `browserKeys: false` | F5, Ctrl+R, Ctrl+U e o zoom (Ctrl+roda, Ctrl+`+`/`-`/`0`) não chegam à página nem fazem nada |
| `devTools: false` | Sem F12, Ctrl+Shift+I e "Inspecionar" |
| `csp` | O header `Content-Security-Policy` das páginas do app |

## O que a página mostra

Cada item da lista tenta sair do app de um jeito, e a página conta o que ela mesma enxergou:

| Tentativa | O que acontece |
|---|---|
| Link para `example.com`, `target="_blank"`, `window.open`, `location.href` num clique | Cancelado na janela e aberto no **navegador do sistema** |
| Link para `example.org` | Navega na própria janela (está no `allowNavigation`); volte com Alt+← |
| `mailto:` | Abre o programa de e-mail |
| `file:///C:/Windows/notepad.exe` | Cancelado: só `http`, `https` e `mailto` vão para fora, e nada é executado |
| Link do app com `target="_blank"` | Ignorado: janela nova nunca abre |
| F5, Ctrl+R, Ctrl+U, Ctrl+`+`/`-` | Os **sensores** não mudam: a página nem recebe a tecla (uma comum, como `x`, chega) |
| Botão direito | A página recebe o `contextmenu`, mas o menu nativo não aparece |

Mude as chaves no `app.json` (`contextMenu: true`, `browserKeys: true`, tire o `allowNavigation`),
rode o `build.bat` de novo e compare.

## Rodando

```bat
build.bat
SecurityDemo.exe
```

O `build.bat` usa o `borion build`: empacota a pasta `web\` e o `app.json` em `web.res`, compila o
`.rc` e o `.dpr` (com o *Search path* do `SecurityDemo.dof`) e copia o `WebView2Loader.dll`.

Veja a [navegação e as janelas novas](../../docs/CONFIG.md#navegação-e-janelas-novas) no guia do
`app.json`.
