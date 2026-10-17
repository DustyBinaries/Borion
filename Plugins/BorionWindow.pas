unit BorionWindow;

(*
  Borion — Native Application Engine
  Plugin "window": a janela do app controlada pelo JS (como o window do Tauri).

    .Plugin(TBorionWindowPlugin.Create)               // no TBorionBuilder
    Ipc.AddPlugin(TBorionWindowPlugin.Create(Form));  // num form já existente

  Comandos (tamanho e posição em pixels, da janela inteira, como no app.json):
    window:setTitle {title}
    window:minimize, unminimize, maximize, unmaximize, toggleMaximize
    window:show, hide, setFocus, center
    window:setSize {width, height}       window:setPosition {x, y}
    window:setMinSize / setMaxSize {width, height}   (0 = sem limite)
    window:setFullscreen {fullscreen}    window:setAlwaysOnTop {alwaysOnTop}
    window:setResizable {resizable}      window:setDecorations {decorations}
    window:state -> {title, x, y, width, height, minimized, maximized, fullscreen,
                     visible, focused, alwaysOnTop, resizable, decorations}
    window:close     pede para fechar: passa pelo close-requested e pelo OnCloseQuery
    window:destroy   fecha sem o close-requested (o OnCloseQuery do Delphi ainda vale)

  Eventos:
    window:resized {width, height, minimized, maximized}
    window:moved {x, y}
    window:focus-changed {focused}
    window:close-requested {id}

  Fechamento interceptado ("deseja salvar?"): o onCloseRequested do
  @borion/api/window liga a interceptação (window:interceptClose). Com ela, o
  WM_CLOSE (o X, Alt+F4, app:exit, window:close) não fecha: vira o evento
  window:close-requested, e a página responde com window:closeResolve {id,
  close}. Se ela não confirmar o recebimento (window:closeAck) em AckTimeout
  ms (página travada ou recarregada sem o listener), a janela fecha assim
  mesmo: uma página quebrada não prende o app aberto.
*)

interface

uses
  Windows, Messages, SysUtils, Classes, Controls, Forms, Jsons, BorionIpc;

type
  TBorionWindowPlugin = class(TBorionPlugin)
  private
    FForm: TCustomForm;
    FVigia: TComponent;
    FOldWndProc: TWndMethod;
    FHooked: Boolean;
    FTimer: HWND;
    FAckTimeout: Cardinal;
    FIntercept: Boolean;
    FPendingId: Integer;      { close-requested sem resposta (0 = nenhum) }
    FNextId: Integer;
    FClosing: Boolean;        { o próximo WM_CLOSE fecha de verdade }
    FResizable: Boolean;
    FFullscreen: Boolean;
    FSavedBounds: TRect;
    FSavedBorder: TFormBorderStyle;
    FSavedState: TWindowState;
    function Formulario: TCustomForm;
    function EhPrincipal: Boolean;
    function Minimizada: Boolean;
    procedure Hook;
    procedure Unhook;
    procedure FormWndProc(var Message: TMessage);
    procedure TimerWndProc(var Message: TMessage);
    procedure PedirFechamento;
    procedure FecharDeVerdade;
    procedure AplicarBorda(Decorations: Boolean);
    procedure EntrarTelaCheia;
    procedure SairTelaCheia;
    procedure EmitirTamanho;
    procedure CmdSetTitle(Call: TBorionCall);
    procedure CmdMinimize(Call: TBorionCall);
    procedure CmdUnminimize(Call: TBorionCall);
    procedure CmdMaximize(Call: TBorionCall);
    procedure CmdUnmaximize(Call: TBorionCall);
    procedure CmdToggleMaximize(Call: TBorionCall);
    procedure CmdShow(Call: TBorionCall);
    procedure CmdHide(Call: TBorionCall);
    procedure CmdSetFocus(Call: TBorionCall);
    procedure CmdCenter(Call: TBorionCall);
    procedure CmdSetSize(Call: TBorionCall);
    procedure CmdSetPosition(Call: TBorionCall);
    procedure CmdSetMinSize(Call: TBorionCall);
    procedure CmdSetMaxSize(Call: TBorionCall);
    procedure CmdSetFullscreen(Call: TBorionCall);
    procedure CmdSetAlwaysOnTop(Call: TBorionCall);
    procedure CmdSetResizable(Call: TBorionCall);
    procedure CmdSetDecorations(Call: TBorionCall);
    procedure CmdState(Call: TBorionCall);
    procedure CmdClose(Call: TBorionCall);
    procedure CmdDestroy(Call: TBorionCall);
    procedure CmdInterceptClose(Call: TBorionCall);
    procedure CmdCloseAck(Call: TBorionCall);
    procedure CmdCloseResolve(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    { AForm nil: o form do browser do Ipc (ou o MainForm) }
    constructor Create(AForm: TCustomForm = nil);
    destructor Destroy; override;
    function Name: string; override;
    { O form foi liberado antes do plugin (chamado pelo vigia) }
    procedure FormFreed;
    property Form: TCustomForm read FForm;
    { Espera pela confirmação da página no close-requested (ms, padrão 2000) }
    property AckTimeout: Cardinal read FAckTimeout write FAckTimeout;
    { A página pediu para interceptar o fechamento }
    property InterceptClose: Boolean read FIntercept;
    property Fullscreen: Boolean read FFullscreen;
  end;

implementation

uses
  Borion;

const
  TIMER_ACK = 1;

type
  { acesso às propriedades protegidas do TCustomForm (BorderStyle, FormStyle...) }
  TFormAcesso = class(TCustomForm);

  { avisa o plugin quando o form é liberado }
  TVigia = class(TComponent)
  private
    FPlugin: TBorionWindowPlugin;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

procedure TVigia.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (FPlugin <> nil) and (AComponent = FPlugin.FForm) then
    FPlugin.FormFreed;
end;

function Logico(B: Boolean): string;
begin
  if B then
    Result := 'true'
  else
    Result := 'false';
end;

{ TBorionWindowPlugin }

constructor TBorionWindowPlugin.Create(AForm: TCustomForm);
begin
  inherited Create;
  FForm := AForm;
  FAckTimeout := 2000;
  FTimer := Classes.AllocateHWnd(TimerWndProc);
end;

destructor TBorionWindowPlugin.Destroy;
begin
  Unhook;
  if FTimer <> 0 then
  begin
    KillTimer(FTimer, TIMER_ACK);
    Classes.DeallocateHWnd(FTimer);
  end;
  FVigia.Free;
  inherited;
end;

function TBorionWindowPlugin.Name: string;
begin
  Result := 'window';
end;

procedure TBorionWindowPlugin.Install;
begin
  if (FForm = nil) and (Ipc <> nil) and (Ipc.Browser <> nil) then
    FForm := GetParentForm(Ipc.Browser);
  if FForm = nil then
    FForm := Application.MainForm;
  Hook;

  Command('setTitle', CmdSetTitle);
  Command('minimize', CmdMinimize);
  Command('unminimize', CmdUnminimize);
  Command('maximize', CmdMaximize);
  Command('unmaximize', CmdUnmaximize);
  Command('toggleMaximize', CmdToggleMaximize);
  Command('show', CmdShow);
  Command('hide', CmdHide);
  Command('setFocus', CmdSetFocus);
  Command('center', CmdCenter);
  Command('setSize', CmdSetSize);
  Command('setPosition', CmdSetPosition);
  Command('setMinSize', CmdSetMinSize);
  Command('setMaxSize', CmdSetMaxSize);
  Command('setFullscreen', CmdSetFullscreen);
  Command('setAlwaysOnTop', CmdSetAlwaysOnTop);
  Command('setResizable', CmdSetResizable);
  Command('setDecorations', CmdSetDecorations);
  Command('state', CmdState);
  Command('close', CmdClose);
  Command('destroy', CmdDestroy);
  Command('interceptClose', CmdInterceptClose);
  Command('closeAck', CmdCloseAck);
  Command('closeResolve', CmdCloseResolve);
end;

procedure TBorionWindowPlugin.Hook;
begin
  if (FForm = nil) or FHooked then
    Exit;
  FResizable := TFormAcesso(FForm).BorderStyle in [bsSizeable, bsSizeToolWin, bsNone];
  FOldWndProc := FForm.WindowProc;
  FForm.WindowProc := FormWndProc;
  FHooked := True;
  FVigia := TVigia.Create(nil);
  TVigia(FVigia).FPlugin := Self;
  FForm.FreeNotification(FVigia);
end;

procedure TBorionWindowPlugin.Unhook;
begin
  if not FHooked then
    Exit;
  FHooked := False;
  { só desfaz se ninguém encadeou outro WindowProc depois do nosso }
  if TMethod(FForm.WindowProc).Data = Self then
    FForm.WindowProc := FOldWndProc;
end;

procedure TBorionWindowPlugin.FormFreed;
begin
  FHooked := False;
  FForm := nil;
end;

function TBorionWindowPlugin.Formulario: TCustomForm;
begin
  Result := FForm;
  if Result = nil then
    raise EBorionError.Create('NO_WINDOW', 'nenhuma janela para controlar');
end;

function TBorionWindowPlugin.EhPrincipal: Boolean;
begin
  Result := (FForm <> nil) and (FForm = Application.MainForm);
end;

function TBorionWindowPlugin.Minimizada: Boolean;
begin
  { no Delphi 7, minimizar o form principal minimiza a janela da TApplication }
  Result := (EhPrincipal and IsIconic(Application.Handle)) or (FForm.WindowState = wsMinimized);
end;

{ --- mensagens do form ----------------------------------------------------- }

procedure TBorionWindowPlugin.FormWndProc(var Message: TMessage);
begin
  if Message.Msg = WM_CLOSE then
  begin
    if FClosing then
      FClosing := False
    else if FIntercept then
    begin
      if FPendingId = 0 then
        PedirFechamento;  { um pedido de cada vez: o segundo clique no X espera o primeiro }
      Exit;
    end;
  end;
  FOldWndProc(Message);
  case Message.Msg of
    WM_SIZE:
      EmitirTamanho;
    WM_MOVE:
      if (Ipc <> nil) and (FForm <> nil) then
        Ipc.EmitJson('window:moved', Format('{"x":%d,"y":%d}', [FForm.Left, FForm.Top]));
    WM_ACTIVATE:
      if Ipc <> nil then
        Ipc.EmitJson('window:focus-changed', '{"focused":' +
          Logico(LoWord(Message.WParam) <> WA_INACTIVE) + '}');
  end;
end;

procedure TBorionWindowPlugin.EmitirTamanho;
begin
  if (Ipc = nil) or (FForm = nil) then
    Exit;
  Ipc.EmitJson('window:resized', Format('{"width":%d,"height":%d,"minimized":%s,"maximized":%s}',
    [FForm.Width, FForm.Height, Logico(Minimizada), Logico(FForm.WindowState = wsMaximized)]));
end;

procedure TBorionWindowPlugin.TimerWndProc(var Message: TMessage);
begin
  if (Message.Msg = WM_TIMER) and (Message.WParam = TIMER_ACK) then
  begin
    KillTimer(FTimer, TIMER_ACK);
    { a página não respondeu: fecha mesmo assim }
    if FPendingId <> 0 then
    begin
      FPendingId := 0;
      FecharDeVerdade;
    end;
  end
  else
    Message.Result := DefWindowProc(FTimer, Message.Msg, Message.WParam, Message.LParam);
end;

procedure TBorionWindowPlugin.PedirFechamento;
begin
  Inc(FNextId);
  FPendingId := FNextId;
  Ipc.EmitJson('window:close-requested', Format('{"id":%d}', [FPendingId]));
  SetTimer(FTimer, TIMER_ACK, FAckTimeout, nil);
end;

procedure TBorionWindowPlugin.FecharDeVerdade;
begin
  if FForm = nil then
    Exit;
  FClosing := True;
  { postado: fechar dentro do callback do WebView2 destruiria o browser no meio dele }
  PostMessage(FForm.Handle, WM_CLOSE, 0, 0);
end;

{ --- borda e tela cheia ---------------------------------------------------- }

procedure TBorionWindowPlugin.AplicarBorda(Decorations: Boolean);
var
  F: TFormAcesso;
begin
  F := TFormAcesso(FForm);
  if not Decorations then
    F.BorderStyle := bsNone
  else if FResizable then
  begin
    F.BorderStyle := bsSizeable;
    F.BorderIcons := F.BorderIcons + [biMaximize];
  end
  else
  begin
    F.BorderStyle := bsSingle;
    F.BorderIcons := F.BorderIcons - [biMaximize];
  end;
end;

procedure TBorionWindowPlugin.EntrarTelaCheia;
var
  F: TFormAcesso;
begin
  if FFullscreen then
    Exit;
  F := TFormAcesso(FForm);
  FSavedState := F.WindowState;
  if F.WindowState <> wsNormal then
    F.WindowState := wsNormal;
  FSavedBounds := F.BoundsRect;
  FSavedBorder := F.BorderStyle;
  F.BorderStyle := bsNone;
  F.BoundsRect := Screen.MonitorFromWindow(F.Handle).BoundsRect;
  FFullscreen := True;
end;

procedure TBorionWindowPlugin.SairTelaCheia;
var
  F: TFormAcesso;
begin
  if not FFullscreen then
    Exit;
  F := TFormAcesso(FForm);
  FFullscreen := False;
  AplicarBorda(FSavedBorder <> bsNone);
  F.BoundsRect := FSavedBounds;
  if FSavedState = wsMaximized then
    F.WindowState := wsMaximized;
end;

{ --- comandos -------------------------------------------------------------- }

procedure TBorionWindowPlugin.CmdSetTitle(Call: TBorionCall);
var
  F: TCustomForm;
begin
  F := Formulario;
  F.Caption := Call.ArgStr('title');
  { o título agora é do JS: não acompanha mais o document.title }
  if F is TBorionWindow then
    TBorionWindow(F).TitleFromPage := False;
end;

procedure TBorionWindowPlugin.CmdMinimize(Call: TBorionCall);
begin
  if EhPrincipal then
    Application.Minimize
  else
    Formulario.WindowState := wsMinimized;
end;

procedure TBorionWindowPlugin.CmdUnminimize(Call: TBorionCall);
begin
  Formulario;
  if EhPrincipal and IsIconic(Application.Handle) then
    Application.Restore;
  if FForm.WindowState = wsMinimized then
    FForm.WindowState := wsNormal;
end;

procedure TBorionWindowPlugin.CmdMaximize(Call: TBorionCall);
begin
  SairTelaCheia;
  Formulario.WindowState := wsMaximized;
end;

procedure TBorionWindowPlugin.CmdUnmaximize(Call: TBorionCall);
begin
  if Formulario.WindowState = wsMaximized then
    FForm.WindowState := wsNormal;
end;

procedure TBorionWindowPlugin.CmdToggleMaximize(Call: TBorionCall);
begin
  if Formulario.WindowState = wsMaximized then
    FForm.WindowState := wsNormal
  else
  begin
    SairTelaCheia;
    FForm.WindowState := wsMaximized;
  end;
end;

procedure TBorionWindowPlugin.CmdShow(Call: TBorionCall);
begin
  Formulario.Show;
end;

procedure TBorionWindowPlugin.CmdHide(Call: TBorionCall);
begin
  Formulario.Hide;
end;

procedure TBorionWindowPlugin.CmdSetFocus(Call: TBorionCall);
begin
  Formulario;
  if EhPrincipal and IsIconic(Application.Handle) then
    Application.Restore;
  FForm.Show;
  SetForegroundWindow(FForm.Handle);
end;

procedure TBorionWindowPlugin.CmdCenter(Call: TBorionCall);
var
  R: TRect;
begin
  R := Screen.MonitorFromWindow(Formulario.Handle).WorkareaRect;
  FForm.SetBounds(R.Left + (R.Right - R.Left - FForm.Width) div 2,
    R.Top + (R.Bottom - R.Top - FForm.Height) div 2, FForm.Width, FForm.Height);
end;

function Inteiro(Call: TBorionCall; const Nome: string; Minimo: Integer): Integer;
var
  V: TJsonValue;
begin
  V := Call.Arg(Nome);
  if (V = nil) or (V.ValueType <> jvNumber) or (Frac(V.AsNumber) <> 0) or (V.AsNumber < Minimo) or
    (V.AsNumber > 32767) then
    raise EBorionError.Create('INVALID_ARGS', Format('"%s" deve ser um inteiro de %d a 32767', [Nome, Minimo]));
  Result := Trunc(V.AsNumber);
end;

function Posicao(Call: TBorionCall; const Nome: string): Integer;
var
  V: TJsonValue;
begin
  V := Call.Arg(Nome);
  if (V = nil) or (V.ValueType <> jvNumber) or (Frac(V.AsNumber) <> 0) or (Abs(V.AsNumber) > 32767) then
    raise EBorionError.Create('INVALID_ARGS', Format('"%s" deve ser um inteiro', [Nome]));
  Result := Trunc(V.AsNumber);
end;

function Logica(Call: TBorionCall; const Nome: string): Boolean;
var
  V: TJsonValue;
begin
  V := Call.Arg(Nome);
  if (V = nil) or (V.ValueType <> jvBoolean) then
    raise EBorionError.Create('INVALID_ARGS', Format('"%s" deve ser true ou false', [Nome]));
  Result := V.AsBoolean;
end;

procedure TBorionWindowPlugin.CmdSetSize(Call: TBorionCall);
var
  W, H: Integer;
begin
  W := Inteiro(Call, 'width', 1);
  H := Inteiro(Call, 'height', 1);
  Formulario;
  SairTelaCheia;
  if FForm.WindowState <> wsNormal then
    FForm.WindowState := wsNormal;
  FForm.SetBounds(FForm.Left, FForm.Top, W, H);
end;

procedure TBorionWindowPlugin.CmdSetPosition(Call: TBorionCall);
var
  X, Y: Integer;
begin
  X := Posicao(Call, 'x');
  Y := Posicao(Call, 'y');
  Formulario;
  SairTelaCheia;
  if FForm.WindowState <> wsNormal then
    FForm.WindowState := wsNormal;
  FForm.SetBounds(X, Y, FForm.Width, FForm.Height);
end;

procedure TBorionWindowPlugin.CmdSetMinSize(Call: TBorionCall);
var
  W, H: Integer;
begin
  W := Inteiro(Call, 'width', 0);
  H := Inteiro(Call, 'height', 0);
  TFormAcesso(Formulario).Constraints.MinWidth := W;
  TFormAcesso(FForm).Constraints.MinHeight := H;
end;

procedure TBorionWindowPlugin.CmdSetMaxSize(Call: TBorionCall);
var
  W, H: Integer;
begin
  W := Inteiro(Call, 'width', 0);
  H := Inteiro(Call, 'height', 0);
  TFormAcesso(Formulario).Constraints.MaxWidth := W;
  TFormAcesso(FForm).Constraints.MaxHeight := H;
end;

procedure TBorionWindowPlugin.CmdSetFullscreen(Call: TBorionCall);
begin
  Formulario;
  if Logica(Call, 'fullscreen') then
    EntrarTelaCheia
  else
    SairTelaCheia;
end;

procedure TBorionWindowPlugin.CmdSetAlwaysOnTop(Call: TBorionCall);
begin
  if Logica(Call, 'alwaysOnTop') then
    TFormAcesso(Formulario).FormStyle := fsStayOnTop
  else
    TFormAcesso(Formulario).FormStyle := fsNormal;
end;

procedure TBorionWindowPlugin.CmdSetResizable(Call: TBorionCall);
begin
  FResizable := Logica(Call, 'resizable');
  Formulario;
  if FFullscreen then
  begin
    { em tela cheia, vale ao sair dela }
    if FSavedBorder = bsNone then
      Exit
    else if FResizable then
      FSavedBorder := bsSizeable
    else
      FSavedBorder := bsSingle;
  end
  else if TFormAcesso(FForm).BorderStyle <> bsNone then
    AplicarBorda(True);
end;

procedure TBorionWindowPlugin.CmdSetDecorations(Call: TBorionCall);
var
  D: Boolean;
begin
  D := Logica(Call, 'decorations');
  Formulario;
  if not FFullscreen then
    AplicarBorda(D)
  { em tela cheia, vale ao sair dela }
  else if not D then
    FSavedBorder := bsNone
  else if FResizable then
    FSavedBorder := bsSizeable
  else
    FSavedBorder := bsSingle;
end;

procedure TBorionWindowPlugin.CmdState(Call: TBorionCall);
var
  O: TJsonObject;
  F: TFormAcesso;
begin
  F := TFormAcesso(Formulario);
  O := Call.Result.AsObject;
  O.Put('title', F.Caption);
  O.Put('x', F.Left);
  O.Put('y', F.Top);
  O.Put('width', F.Width);
  O.Put('height', F.Height);
  O.Put('minimized', Minimizada);
  O.Put('maximized', F.WindowState = wsMaximized);
  O.Put('fullscreen', FFullscreen);
  O.Put('visible', F.Visible);
  O.Put('focused', F.HandleAllocated and (GetForegroundWindow = F.Handle));
  O.Put('alwaysOnTop', F.FormStyle = fsStayOnTop);
  O.Put('resizable', FResizable);
  if FFullscreen then
    O.Put('decorations', FSavedBorder <> bsNone)
  else
    O.Put('decorations', F.BorderStyle <> bsNone);
end;

procedure TBorionWindowPlugin.CmdClose(Call: TBorionCall);
begin
  PostMessage(Formulario.Handle, WM_CLOSE, 0, 0);
end;

procedure TBorionWindowPlugin.CmdDestroy(Call: TBorionCall);
begin
  Formulario;
  FPendingId := 0;
  KillTimer(FTimer, TIMER_ACK);
  FecharDeVerdade;
end;

procedure TBorionWindowPlugin.CmdInterceptClose(Call: TBorionCall);
begin
  FIntercept := Logica(Call, 'enabled');
  if not FIntercept then
  begin
    FPendingId := 0;
    KillTimer(FTimer, TIMER_ACK);
  end;
end;

procedure TBorionWindowPlugin.CmdCloseAck(Call: TBorionCall);
begin
  { a página recebeu o pedido: a decisão pode levar o tempo que precisar }
  if (FPendingId <> 0) and (Call.ArgInt('id') = FPendingId) then
    KillTimer(FTimer, TIMER_ACK);
end;

procedure TBorionWindowPlugin.CmdCloseResolve(Call: TBorionCall);
begin
  if (FPendingId = 0) or (Call.ArgInt('id') <> FPendingId) then
    Exit;  { resposta a um pedido antigo }
  FPendingId := 0;
  KillTimer(FTimer, TIMER_ACK);
  if Call.ArgBool('close') then
    FecharDeVerdade;
end;

end.
