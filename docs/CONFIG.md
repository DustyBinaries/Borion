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
| `identifier` | texto | Identificador reverso (`com.empresa.app`): letras, dígitos, `-` e `_`, em duas partes ou mais. O `app:info` devolve; os próximos recursos (instalador, AppUserModelID) vão usá-lo |
| `build.frontendDist` | texto | Pasta da interface pronta, relativa ao `app.json` (veja abaixo) |
| `build.devUrl` | texto | URL do servidor de desenvolvimento (`http://` ou `https://`). O `borion dev` abre o app nela, e a porta vai para o Vite (`--port`) |
| `app.windows` | lista | As janelas. **Por enquanto só a primeira** (a principal) é usada; as outras geram um aviso |
| `app.windows[0].title` | texto | Título da janela. Com ele, o título fica fixo; sem ele, o título é o `productName` e acompanha o `document.title` da página |
| `app.windows[0].width`, `height` | inteiro | Tamanho inicial (padrão 1000×700) |
| `app.windows[0].minWidth`, `minHeight`, `maxWidth`, `maxHeight` | inteiro | Limites de tamanho (0 = sem limite) |
| `app.windows[0].resizable` | lógico | `false`: borda fixa, sem maximizar (padrão `true`) |
| `app.windows[0].center` | lógico | `false`: posição escolhida pelo Windows (padrão `true`, centralizada) |
| `app.windows[0].maximized` | lógico | Abre maximizada |
| `app.windows[0].decorations` | lógico | `false`: sem borda nem barra de título. Feche a janela pelo plugin `app` (`exit`). A barra de título em HTML está no roadmap |
| `app.windows[0].alwaysOnTop` | lógico | Sempre por cima das outras janelas |
| `app.security.csp` | texto | O header `Content-Security-Policy` dos assets embutidos e da pasta no `--dev-dir`. Não vale para o servidor do Vite |
| `$schema` | texto | Aceito e ignorado |

### Onde fica a interface

Sem `build.frontendDist`, a convenção: `frontend\package.json` → projeto npm com a saída em
`frontend\dist`; senão, a pasta `web\`, estática.

Com `build.frontendDist`:

- se a pasta acima dela tem um `package.json` (`"ui/dist"` com `ui\package.json`), é um projeto
  npm: o `borion build` roda `npm run build` em `ui\` e empacota `ui\dist`;
- senão, é uma interface estática, empacotada como está (`"web"`, `"public"`).

## API Delphi

```pascal
uses BorionConfig;

BorionAppConfig.ProductName;     // o app.json embutido (os padrões, se não houver)
BorionAppConfig.Window.Width;
BorionAppConfigError;            // '' ou o erro de leitura do recurso

C := TBorionConfig.Create;       // ler de outro lugar
C.LoadFromFile('outro.json');    // EBorionConfig se inválido; avisos em C.Warnings
TBorionBuilder.Create.Config(C)...
```

`TBorionWindow.ApplyConfig(Config, TituloPadrao)` aplica uma `TBorionWindowConfig` a uma janela. O
builder usa esse método, e as próximas janelas (várias janelas, na Fase 3) também vão usá-lo.

## Ainda não

- Várias janelas (`app.windows[1..]`), `x`/`y`, `fullscreen` e `url` por janela.
- `beforeDevCommand` / `beforeBuildCommand`: hoje o comando é sempre o `npm run dev` / `npm run build`.
- Versão, ícone e manifesto do exe a partir do `app.json` (hoje o `.rc` é escrito à mão; Fase 7).
- Capabilities e permissões (Fase 5).
