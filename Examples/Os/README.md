# Exemplo: plugin `os`

Informações do sistema pela página.

O app inteiro é o `OsDemo.dpr` (sem form):

```pascal
uses
  Borion, BorionOs;

begin
  TBorionBuilder.Create('Borion: os')
    .Size(900, 640)
    .Plugin(TBorionOsPlugin.Create)
    .Run;
end.
```

## O que ele mostra

| Seção | O que demonstra |
|---|---|
| 1. `os.info()` | Plataforma, arquitetura do Windows e do processo, versão real e build, `displayVersion`, nome da edição, idioma e nome do computador |
| 2. O navegador | O que o `navigator` diz, para comparar: o `userAgent` diz "Windows NT 10.0" também no Windows 11 e não conhece o nome do computador |
| 3. Idioma | `os.locale()` usado com o `Intl` para formatar data e número |
## Rodando

```bat
build.bat
OsDemo.exe
```

O `build.bat` copia os módulos do [`@borion/api`](../../js/README.md) (`Borion\js`) para
`web\borion-api\`, empacota a pasta `web\` com o `borion pack` e compila. Não precisa de Node
nem de Vite: o *import map* do `index.html` resolve `import ... from '@borion/api/os'` para a
cópia local, e o código fica igual ao de um projeto com bundler.

| | |
|---|---|
| `OsDemo.dpr` | O app inteiro: o `TBorionBuilder` monta a janela com o plugin (sem form) |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#os).
