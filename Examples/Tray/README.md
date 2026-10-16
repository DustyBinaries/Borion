# Exemplo: plugin `tray`

Ícone na área de notificação (bandeja) do Windows, controlado pela página.

O app inteiro é o `TrayDemo.dpr` (sem form):

```pascal
uses
  Borion, BorionTray;

var
  Tray: TBorionTrayPlugin;

begin
  Tray := TBorionTrayPlugin.Create;
  Tray.MinimizeToTray := True;  { minimizar esconde a janela; clicar no ícone a traz de volta }
  { Tray.RestoreOnClick := False;  para tratar o clique só na página (tray:click) }
  TBorionBuilder.Create('Borion: tray')
    .Size(900, 640)
    .Plugin(Tray)
    .Run;
end.
```

## O que ele mostra

| Seção | O que demonstra |
|---|---|
| Minimizar | A janela some da tela e da barra de tarefas e fica só o ícone; um clique nele a traz de volta (`RestoreOnClick`) |
| 1. Ícone e tooltip | `tray.show`, `tray.hide`, `tray.setTooltip` |
| 2. Menu do ícone | `tray.setMenu` + `tray.onMenu`: um contador, itens habilitados conforme o estado e um checkbox "Não perturbe" que a página guarda e reenvia |
| 3. Notificações | `tray.notify` com título, mensagem e `kind` (`info`, `warning`, `error`, `none`); uma com atraso de 5 s, para dar tempo de minimizar. Se o ícone estiver escondido, ele reaparece (o Windows exige um ícone para notificar) |
| Eventos | `tray:click`, `tray:doubleClick`, `tray:menu` e `tray:balloonClick` (clique na notificação) |

O ícone é o do executável (recurso `MAINICON`). Este exemplo não tem um, então aparece o ícone
padrão do Windows; troque pela propriedade `Tray.Icon`.

## Rodando

```bat
build.bat
TrayDemo.exe
```

O `build.bat` copia os módulos do [`@borion/api`](../../js/README.md) (`Borion\js`) para
`web\borion-api\`, empacota a pasta `web\` com o `borion pack` e compila. Não precisa de Node
nem de Vite: o *import map* do `index.html` resolve `import ... from '@borion/api/tray'` para a
cópia local, e o código fica igual ao de um projeto com bundler.

| | |
|---|---|
| `TrayDemo.dpr` | O app inteiro: o `TBorionBuilder` monta a janela com o plugin (sem form) |
| `web\index.html` / `web\app.js` | A página e o uso do plugin |

Referência completa: [docs/PLUGINS.md](../../docs/PLUGINS.md#tray).
