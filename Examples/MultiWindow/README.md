# Exemplo: várias janelas

Um app com várias janelas, todas no mesmo IPC: os plugins e comandos do `.dpr` servem todas, e
cada chamada sabe de que janela veio.

O app inteiro é o `MultiWindowDemo.dpr` (sem form):

```pascal
procedure Contar(Call: TBorionCall);
begin
  Inc(Chamadas);
  Call.Result.AsString := Format('chamada %d, vinda da janela "%s" (%d abertas)',
    [Chamadas, Call.Window, BorionWindows.Count]);
end;

begin
  TBorionBuilder.Create
    .Plugin(TBorionWindowPlugin.Create)
    .Command('contar', Contar)
    .Run;
end.
```

As janelas estão no `app.json`:

```json
"windows": [
  { "label": "main", "width": 900, "height": 680, "minWidth": 600, "minHeight": 420 },
  { "label": "config", "url": "/config.html", "title": "Configurações", "width": 420,
    "height": 360, "resizable": false, "create": false }
]
```

## O que ele mostra

| Janela | O que demonstra |
|---|---|
| Principal (`index.html`) | `getAllWindows()` (atualizado por `onCreated` e `onDestroyed`), com `setFocus()` e `close()` em cada uma; `createWindow('config')` abre a definição do `app.json` (já aberta, só ganha o foco); `createWindow('nota-N', { url, title, width, height })` cria janelas que não estão no `app.json`; `listen('nota')` recebe o que as notas mandam |
| Configurações (`config.html`) | O tema de todas as janelas: grava no `localStorage` (a mesma origem, para as que abrirem depois) e manda `emitTo('*', 'tema', ...)` para as abertas |
| Nota (`nota.html`) | `emitTo('main', 'nota', { de, texto })` e `close()` |
| Todas | `invoke('contar')`: um comando Delphi registrado uma vez responde a qualquer janela, e `Call.Window` diz de qual veio |

Fechar a principal fecha o app e as outras. No Delphi 7, as janelas secundárias não têm botão
próprio na barra de tarefas.

## Rodando

```bat
build.bat
MultiWindowDemo.exe
```

O `build.bat` chama o `borion build`, que copia o [`@borion/api`](../../js/README.md) para
`web\borion-api\`, empacota a pasta `web\` (as três páginas) e o `app.json` em `web.res` e
compila.

Referência: [várias janelas no app.json](../../docs/CONFIG.md#várias-janelas), [no
IPC](../../docs/IPC.md#várias-janelas) e [no plugin window](../../docs/PLUGINS.md#window).
