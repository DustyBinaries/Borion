# Exemplo: plugin `log`

O Delphi e a página gravando no mesmo arquivo,
`%LOCALAPPDATA%\Borion Log Demo\logs\Borion Log Demo.log`.

O app inteiro é o `LogDemo.dpr` (sem form):

```pascal
uses
  Borion, BorionLog;

var
  Log: TBorionLogPlugin;

begin
  Log := TBorionLogPlugin.Create('Borion Log Demo');
  Log.MinLevel := llDebug;
  Log.Info('app iniciando (linha gravada pelo Delphi)');
  TBorionBuilder.Create('Borion: log')
    .Size(900, 680)
    .Plugin(Log)
    .Run;
end.
```

## O que ele mostra

| Seção | O que demonstra |
|---|---|
| 1. Gravar | `debug`, `info`, `warn` e `error` com a mensagem digitada (emoji inclusive) |
| 2. O console | `forwardConsole`: `console.log`, `console.error(new Error())` e uma exceção não tratada vão para o arquivo, com a pilha |
| 3. O que foi gravado | `attachConsole`: cada linha, inclusive a do Delphi, aparece no DevTools e na página |

Acompanhe o arquivo com o app aberto: `Get-Content -Wait "$env:LOCALAPPDATA\Borion Log Demo\logs\Borion Log Demo.log"`.
## Rodando

```bat
build.bat
LogDemo.exe
```

O `build.bat` copia os módulos do [`@borion/api`](../../js/README.md) (`Borion\js`) para
`web\borion-api\`, empacota a pasta `web\` com o `borion pack` e compila. Não precisa de Node
nem de Vite: o *import map* do `index.html` resolve `import ... from '@borion/api/log'` para a
cópia local, e o código fica igual ao de um projeto com bundler.

| | |
|---|---|
| `LogDemo.dpr` | O app inteiro: o `TBorionBuilder` monta a janela com o plugin (sem form) |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#log).
