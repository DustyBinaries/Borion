# Exemplo: plugin `autostart`

Iniciar o app junto com o Windows.

O app inteiro é o `AutostartDemo.dpr` (sem form):

```pascal
uses
  Borion, BorionAutostart;

begin
  TBorionBuilder.Create('Borion: autostart')
    .Size(900, 640)
    { nome na aba Inicializar do Gerenciador de Tarefas; --autostart marca a
      execução que veio do login }
    .Plugin(TBorionAutostartPlugin.Create('Borion Autostart Demo', '--autostart'))
    .Run;
end.
```

## O que ele mostra

| Seção | O que demonstra |
|---|---|
| 1. Ligar e desligar | `enable`, `disable` e `isEnabled`; o efeito aparece na aba Inicializar do Gerenciador de Tarefas, e desabilitar lá é refletido aqui |
| 2. `launchedAtLogin` | Se esta execução veio do login (o app é registrado com `--autostart`) |

Lembre de desmarcar antes de apagar o exemplo, para não deixar o valor no `Run`.
## Rodando

```bat
build.bat
AutostartDemo.exe
```

O `build.bat` copia os módulos do [`@borion/api`](../../js/README.md) (`Borion\js`) para
`web\borion-api\`, empacota a pasta `web\` com o `borion pack` e compila. Não precisa de Node
nem de Vite: o *import map* do `index.html` resolve `import ... from '@borion/api/autostart'` para a
cópia local, e o código fica igual ao de um projeto com bundler.

| | |
|---|---|
| `AutostartDemo.dpr` | O app inteiro: o `TBorionBuilder` monta a janela com o plugin (sem form) |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#autostart).
