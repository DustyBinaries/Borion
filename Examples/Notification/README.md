# Exemplo: plugin `notification`

Notificações nativas do Windows (toast) mandadas pela página. No Delphi:

```pascal
FIpc.AddPlugin(TBorionNotificationPlugin.Create('Borion.Exemplo.Notification'));
```

## O que ele mostra

| Seção | O que demonstra |
|---|---|
| Permissão | `isPermissionGranted()`: se as notificações do app estão ligadas nas Configurações do Windows |
| 1. Simples | Título e corpo com emoji, com ou sem som; uma com atraso de 5 s, para ver com a janela minimizada |
| 2. Com botões | "Aprovar ✓" e "Recusar": o clique chega em `onAction` com o id do botão e a janela volta para frente; `hide` tira a última da tela |
| Eventos | `onAction` e `onDismissed` (`user`, `hidden`, `timeout`) |

O exemplo registra o AppId `Borion.Exemplo.Notification` em
`HKCU\Software\Classes\AppUserModelId`. Para tirar: `BorionNotificationUnregister`.
## Rodando

```bat
build.bat
NotificationDemo.exe
```

O `build.bat` copia os módulos do [`@borion/api`](../../js/README.md) (`Borion\js`) para
`web\borion-api\`, empacota a pasta `web\` com o `borion pack` e compila. Não precisa de Node
nem de Vite: o *import map* do `index.html` resolve `import ... from '@borion/api/notification'` para a
cópia local, e o código fica igual ao de um projeto com bundler.

| | |
|---|---|
| `uPrincipal.pas` | A janela (sem `.dfm`): browser, IPC, assets e o plugin |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#notification).
