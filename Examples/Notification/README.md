# Exemplo: plugin `notification`

Notificações nativas do Windows (toast) mandadas pela página.

O app inteiro é o `NotificationDemo.dpr` (sem form):

```pascal
uses
  Borion, BorionNotification;

begin
  TBorionBuilder.Create('Borion: notification')
    .Size(900, 640)
    { AppId: identifica o app nas notificações e nas Configurações do Windows }
    .Plugin(TBorionNotificationPlugin.Create('Borion.Exemplo.Notification'))
    .Run;
end.
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
| `NotificationDemo.dpr` | O app inteiro: o `TBorionBuilder` monta a janela com o plugin (sem form) |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#notification).
