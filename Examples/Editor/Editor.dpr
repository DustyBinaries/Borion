program Editor;

{ Borion Editor: editor de texto com frontend Vite + JS puro (pasta frontend\)
  feito só com os plugins oficiais (dialog, fs, shell, menu, tray, app, store).
  Toda a lógica está no frontend (frontend\src\main.js); aqui só a montagem.
    build.bat  -> npm run build, borion pack frontend\dist app.res, compila
    dev.bat    -> servidor do Vite com hot-reload + o app com --dev-url }

uses
  SysUtils, Borion, BorionScope, BorionFs, BorionDialog, BorionShell, BorionMenu, BorionTray,
  BorionApp, BorionStore;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (build.bat e Editor.dof) }

{$R *.res}
{$R app.res}  { pacote BORION_ASSETS com o frontend (gerado pelo build.bat) }

const
  APP_NOME = 'Borion Editor';

var
  Tray: TBorionTrayPlugin;

begin
  { pastas do app (os recentes e uma pasta em Documentos) }
  ForceDirectories(BorionBaseDirPath(bdAppData, APP_NOME));
  ForceDirectories(BorionBaseDirPath(bdDocument, APP_NOME) + '\' + APP_NOME);
  Tray := TBorionTrayPlugin.Create;
  Tray.MinimizeToTray := True;

  TBorionBuilder.Create(APP_NOME)
    .Size(1000, 700)
    .MinSize(600, 400)
    { escopo de arquivos: negado por padrão. Liberadas só a pasta de dados do app
      e uma pasta em Documentos; o resto, só o que o usuário escolher nos
      diálogos (o plugin dialog acrescenta ao escopo) }
    .AllowDir('$APPDATA')
    .AllowDir('$DOCUMENT\' + APP_NOME)
    .Plugin(TBorionFsPlugin.Create)
    .Plugin(TBorionDialogPlugin.Create)
    .Plugin(TBorionShellPlugin.Create)
    { barra de menu (os atalhos funcionam com o foco no texto), bandeja e janela }
    .Plugin(TBorionMenuPlugin.Create)
    .Plugin(Tray)
    .Plugin(TBorionAppPlugin.Create)
    .Plugin(TBorionStorePlugin.Create(APP_NOME))  { preferências em %APPDATA%\Borion Editor }
    .Run;
end.
