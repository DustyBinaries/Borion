program NotificationDemo;

{ Exemplo do plugin "notification" do Borion: notificações nativas do Windows
  (toast) com botões, e os eventos de clique e de fechamento. }

uses
  Borion, BorionNotification;

{ Jsons (json4delphi) vem do ACBr; as pastas do Borion e do WebView2 estão no
  search path (build.bat e NotificationDemo.dof) }

{$R *.res}
{$R web.res}  { pacote BORION_ASSETS com o frontend (gerado pelo build.bat) }

begin
  TBorionBuilder.Create('Borion: notification')
    .Size(900, 640)
    { AppId: identifica o app nas notificações e nas Configurações do Windows }
    .Plugin(TBorionNotificationPlugin.Create('Borion.Exemplo.Notification'))
    .Run;
end.
