unit BorionWindow;

(*
  Borion — Native Application Engine
  Plugin "window": as janelas do app controladas pelo JS (como o window do Tauri).

    .Plugin(TBorionWindowPlugin.Create)               // no TBorionBuilder: todas as janelas
    Ipc.AddPlugin(TBorionWindowPlugin.Create(Form));  // num form já existente: só ele

  Cada comando age sobre a janela que chamou, ou sobre a do argumento "label".
  Tamanho e posição em pixels, da janela inteira, como no app.json:
    window:setTitle {title}
    window:minimize, unminimize, maximize, unmaximize, toggleMaximize
    window:show, hide, setFocus, center
    window:setSize {width, height}       window:setPosition {x, y}
    window:setMinSize / setMaxSize {width, height}   (0 = sem limite)
    window:setFullscreen {fullscreen}    window:setAlwaysOnTop {alwaysOnTop}
    window:setResizable {resizable}      window:setDecorations {decorations}
    window:startDragging                 arrasta a janela (com o botão do mouse apertado)
    window:startResizeDragging {direction}   redimensiona por uma borda: North, South,
                     East, West, NorthEast, NorthWest, SouthEast ou SouthWest
    window:state -> {label, title, x, y, width, height, minimized, maximized,
                     fullscreen, visible, focused, alwaysOnTop, resizable, decorations}
    window:close     pede para fechar: passa pelo close-requested e pelo OnCloseQuery
    window:destroy   fecha sem o close-requested (o OnCloseQuery do Delphi ainda vale)

  Várias janelas (com o TBorionBuilder):
    window:list -> [{label, title, visible, main}]
    window:create {label, url?, title?, width?, ...}   abre uma janela: a do app.json
                     com esse rótulo (os argumentos vencem) ou uma nova

  Eventos, para a própria janela:
    window:resized {width, height, minimized, maximized}
    window:moved {x, y}
    window:focus-changed {focused}
    window:close-requested {id}
  (window:created e window:destroyed {label}, para todas, saem do TBorionBuilder)

  Barra de título em HTML (janela sem decorations): o plugin injeta em cada
  janela um script (BorionWindowDragScript) que arrasta a janela pelos
  elementos com o atributo data-borion-drag-region e maximiza/restaura com um
  duplo clique neles. Vale o próprio elemento, não os filhos: marque também os
  textos da barra, e os botões dentro dela continuam botões. Sem decorations e
  redimensionável, a borda da página (5 px) redimensiona a janela. Só para o
  script: window:internalToggleMaximize (só se redimensionável),
  window:internalResizeBorder -> {enabled} e o evento window:resize-border
  {enabled}. Uma janela sem decorations maximizada fica na área de trabalho,
  sem cobrir a barra de tarefas.

  Fechamento interceptado ("deseja salvar?"): o onCloseRequested do
  @borion/api/window liga a interceptação da janela (window:interceptClose).
  Com ela, o WM_CLOSE (o X, Alt+F4, app:exit, window:close) não fecha: vira o
  evento window:close-requested, e a página responde com window:closeResolve
  {id, close}. Se ela não confirmar o recebimento (window:closeAck) em
  AckTimeout ms (página travada ou recarregada sem o listener), a janela fecha
  assim mesmo: uma página quebrada não prende o app aberto.
*)

interface

uses
  Windows, Messages, SysUtils, Classes, Controls, Forms, Jsons, BorionIpc, WebView2Browser;

type
  TBorionWindowPlugin = class(TBorionPlugin)
  private
    FFixedForm: TCustomForm;
    FJanelas: TList;
    FTimer: HWND;
    FAckTimeout: Cardinal;
    FNextId: Integer;
    procedure TimerWndProc(var Message: TMessage);
    function Adicionar(const WindowLabel: string; AForm: TCustomForm): TObject;
    function Achar(const WindowLabel: string): TObject;
    function Alvo(Call: TBorionCall): TObject;
    function GetForm: TCustomForm;
    function GetFullscreen: Boolean;
    function GetInterceptClose: Boolean;
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
    procedure CmdStartDragging(Call: TBorionCall);
    procedure CmdStartResizeDragging(Call: TBorionCall);
    procedure CmdInternalToggleMaximize(Call: TBorionCall);
    procedure CmdInternalResizeBorder(Call: TBorionCall);
    procedure CmdState(Call: TBorionCall);
    procedure CmdClose(Call: TBorionCall);
    procedure CmdDestroy(Call: TBorionCall);
    procedure CmdInterceptClose(Call: TBorionCall);
    procedure CmdCloseAck(Call: TBorionCall);
    procedure CmdCloseResolve(Call: TBorionCall);
    procedure CmdList(Call: TBorionCall);
    procedure CmdCreate(Call: TBorionCall);
  protected
    procedure Install; override;
    procedure WindowAdded(const WindowLabel: string; ABrowser: TWebView2Browser); override;
    procedure WindowRemoved(const WindowLabel: string; ABrowser: TWebView2Browser); override;
  public
    { AForm nil: todas as janelas do Ipc (ou o MainForm, sem nenhuma).
      AForm informado: só esse form, com o rótulo 'main'. }
    constructor Create(AForm: TCustomForm = nil);
    destructor Destroy; override;
    function Name: string; override;
    { O form da janela; nil se ela não existir }
    function FormOf(const WindowLabel: string): TCustomForm;
    { Espera pela confirmação da página no close-requested (ms, padrão 2000) }
    property AckTimeout: Cardinal read FAckTimeout write FAckTimeout;
    { --- a janela 'main' (ou a única), para o uso com um form só --- }
    property Form: TCustomForm read GetForm;
    property InterceptClose: Boolean read GetInterceptClose;
    property Fullscreen: Boolean read GetFullscreen;
  end;

{ O script que o plugin injeta em cada janela: a região de arrastar
  (data-borion-drag-region) e a borda de redimensionar sem decorations }
function BorionWindowDragScript: WideString;

implementation

uses
  BorionConfig, Borion;

type
  { acesso às propriedades protegidas do TCustomForm (BorderStyle, FormStyle...) }
  TFormAcesso = class(TCustomForm);

  { Uma janela acompanhada: o WindowProc do form, a interceptação do
    fechamento e o que a tela cheia guardou. Recebe o aviso de form liberado. }
  TJanela = class(TComponent)
  private
    FPlugin: TBorionWindowPlugin;
    FLabel: string;
    FForm: TCustomForm;
    FOldWndProc: TWndMethod;
    FHooked: Boolean;
    FIntercept: Boolean;
    FPendingId: Integer;      { close-requested sem resposta (0 = nenhum) }
    FClosing: Boolean;        { o próximo WM_CLOSE fecha de verdade }
    FResizable: Boolean;
    FResizeBorder: Boolean;   { o último window:resize-border emitido }
    FFullscreen: Boolean;
    FSavedBounds: TRect;
    FSavedBorder: TFormBorderStyle;
    FSavedState: TWindowState;
    procedure Hook;
    procedure Unhook;
    procedure FormWndProc(var Message: TMessage);
    procedure Emitir(const Event, PayloadJson: string);
    procedure EmitirTamanho;
    procedure PedirFechamento;
    procedure FecharDeVerdade;
    procedure CancelarPedido;
    procedure AplicarBorda(Decorations: Boolean);
    function Redimensionavel: Boolean;
    procedure SetRedimensionavel(Value: Boolean);
    function BordaDaPagina: Boolean;
    procedure AvisarBordaDaPagina;
    procedure LimitarMaximizada(Info: PMinMaxInfo);
    procedure Arrastar(HitTest: Integer);
    procedure EntrarTelaCheia;
    procedure SairTelaCheia;
    function EhPrincipal: Boolean;
    function Minimizada: Boolean;
    function F: TFormAcesso;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    destructor Destroy; override;
  end;

function Logico(B: Boolean): string;
begin
  if B then
    Result := 'true'
  else
    Result := 'false';
end;

{ TJanela }

destructor TJanela.Destroy;
begin
  CancelarPedido;
  Unhook;
  inherited;
end;

procedure TJanela.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FForm) then
  begin
    FHooked := False;
    FForm := nil;
    CancelarPedido;
  end;
end;

function TJanela.F: TFormAcesso;
begin
  if FForm = nil then
    raise EBorionError.Create('NO_WINDOW', 'a janela "' + FLabel + '" não existe mais');
  Result := TFormAcesso(FForm);
end;

procedure TJanela.Hook;
begin
  if (FForm = nil) or FHooked then
    Exit;
  FResizable := TFormAcesso(FForm).BorderStyle in [bsSizeable, bsSizeToolWin, bsNone];
  FResizeBorder := BordaDaPagina;
  FOldWndProc := FForm.WindowProc;
  FForm.WindowProc := FormWndProc;
  FHooked := True;
  FForm.FreeNotification(Self);
end;

procedure TJanela.Unhook;
begin
  if not FHooked then
    Exit;
  FHooked := False;
  FForm.RemoveFreeNotification(Self);
  { só desfaz se ninguém encadeou outro WindowProc depois do nosso }
  if TMethod(FForm.WindowProc).Data = Self then
    FForm.WindowProc := FOldWndProc;
end;

function TJanela.EhPrincipal: Boolean;
begin
  Result := (FForm <> nil) and (FForm = Application.MainForm);
end;

function TJanela.Minimizada: Boolean;
begin
  { no Delphi 7, minimizar o form principal minimiza a janela da TApplication }
  Result := (EhPrincipal and IsIconic(Application.Handle)) or (FForm.WindowState = wsMinimized);
end;

procedure TJanela.Emitir(const Event, PayloadJson: string);
begin
  if FPlugin.Ipc <> nil then
    FPlugin.Ipc.EmitJsonTo(FLabel, Event, PayloadJson);
end;

procedure TJanela.FormWndProc(var Message: TMessage);
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
    WM_GETMINMAXINFO:
      LimitarMaximizada(PMinMaxInfo(Message.LParam));
    WM_SIZE:
      begin
        EmitirTamanho;
        AvisarBordaDaPagina;
      end;
    WM_MOVE:
      if FForm <> nil then
        Emitir('window:moved', Format('{"x":%d,"y":%d}', [FForm.Left, FForm.Top]));
    WM_ACTIVATE:
      Emitir('window:focus-changed', '{"focused":' + Logico(LoWord(Message.WParam) <> WA_INACTIVE) + '}');
  end;
end;

procedure TJanela.EmitirTamanho;
begin
  if FForm = nil then
    Exit;
  Emitir('window:resized', Format('{"width":%d,"height":%d,"minimized":%s,"maximized":%s}',
    [FForm.Width, FForm.Height, Logico(Minimizada), Logico(FForm.WindowState = wsMaximized)]));
end;

procedure TJanela.PedirFechamento;
begin
  Inc(FPlugin.FNextId);
  FPendingId := FPlugin.FNextId;
  Emitir('window:close-requested', Format('{"id":%d}', [FPendingId]));
  { o id do pedido é o id do timer: cada janela tem o seu }
  SetTimer(FPlugin.FTimer, FPendingId, FPlugin.FAckTimeout, nil);
end;

procedure TJanela.CancelarPedido;
begin
  if FPendingId <> 0 then
  begin
    KillTimer(FPlugin.FTimer, FPendingId);
    FPendingId := 0;
  end;
end;

procedure TJanela.FecharDeVerdade;
begin
  if FForm = nil then
    Exit;
  FClosing := True;
  { postado: fechar dentro do callback do WebView2 destruiria o browser no meio dele }
  PostMessage(FForm.Handle, WM_CLOSE, 0, 0);
end;

procedure TJanela.AplicarBorda(Decorations: Boolean);
begin
  if not Decorations then
    F.BorderStyle := bsNone
  else if Redimensionavel then
  begin
    F.BorderStyle := bsSizeable;
    F.BorderIcons := F.BorderIcons + [biMaximize];
  end
  else
  begin
    F.BorderStyle := bsSingle;
    F.BorderIcons := F.BorderIcons - [biMaximize];
  end;
  AvisarBordaDaPagina;
end;

{ a TBorionWindow guarda o "resizable" do app.json (sem borda, o BorderStyle
  não diz); um form comum, só o plugin }
function TJanela.Redimensionavel: Boolean;
begin
  if FForm is TBorionWindow then
    Result := TBorionWindow(FForm).Resizable
  else
    Result := FResizable;
end;

procedure TJanela.SetRedimensionavel(Value: Boolean);
begin
  FResizable := Value;
  if FForm is TBorionWindow then
    TBorionWindow(FForm).Resizable := Value;
end;

{ a página redimensiona a janela pela borda: sem decorations, redimensionável
  e no tamanho normal }
function TJanela.BordaDaPagina: Boolean;
begin
  Result := (FForm <> nil) and not FFullscreen and (TFormAcesso(FForm).BorderStyle = bsNone) and
    Redimensionavel and (FForm.WindowState = wsNormal) and not Minimizada;
end;

procedure TJanela.AvisarBordaDaPagina;
var
  B: Boolean;
begin
  B := BordaDaPagina;
  if B = FResizeBorder then
    Exit;
  FResizeBorder := B;
  Emitir('window:resize-border', '{"enabled":' + Logico(B) + '}');
end;

{ sem borda, o Windows maximiza sobre o monitor inteiro, cobrindo a barra de
  tarefas: maximizada, a janela fica na área de trabalho }
procedure TJanela.LimitarMaximizada(Info: PMinMaxInfo);
var
  M: TMonitor;
begin
  if (FForm = nil) or FFullscreen or (TFormAcesso(FForm).BorderStyle <> bsNone) or
    not FForm.HandleAllocated then
    Exit;
  M := Screen.MonitorFromWindow(FForm.Handle);
  if M = nil then
    Exit;
  { relativa ao monitor da janela }
  Info.ptMaxPosition := Point(M.WorkareaRect.Left - M.BoundsRect.Left,
    M.WorkareaRect.Top - M.BoundsRect.Top);
  Info.ptMaxSize := Point(M.WorkareaRect.Right - M.WorkareaRect.Left,
    M.WorkareaRect.Bottom - M.WorkareaRect.Top);
end;

function BotaoPrincipalApertado: Boolean;
var
  VK: Integer;
begin
  { o GetAsyncKeyState vê o botão físico }
  if GetSystemMetrics(SM_SWAPBUTTON) <> 0 then
    VK := VK_RBUTTON
  else
    VK := VK_LBUTTON;
  Result := GetAsyncKeyState(VK) < 0;
end;

{ Arrasta (HTCAPTION) ou redimensiona (HTLEFT...) como se o clique fosse na
  borda da janela: o Windows faz o resto, com o botão ainda apertado. A
  mensagem chega pelo WebView2 depois do mousedown; se o botão já foi solto, o
  loop do Windows ficaria preso ao mouse até o próximo clique. Postada: o loop
  roda fora do callback do WebView2. }
procedure TJanela.Arrastar(HitTest: Integer);
var
  P: TPoint;
begin
  if not BotaoPrincipalApertado then
    Exit;
  GetCursorPos(P);
  ReleaseCapture;
  PostMessage(F.Handle, WM_NCLBUTTONDOWN, HitTest, MakeLParam(Word(P.X), Word(P.Y)));
end;

procedure TJanela.EntrarTelaCheia;
begin
  if FFullscreen then
    Exit;
  FSavedState := F.WindowState;
  if F.WindowState <> wsNormal then
    F.WindowState := wsNormal;
  FSavedBounds := F.BoundsRect;
  FSavedBorder := F.BorderStyle;
  { antes de mudar a borda e o tamanho: o NormalBounds fica o de antes }
  if FForm is TBorionWindow then
    TBorionWindow(FForm).Fullscreen := True;
  F.BorderStyle := bsNone;
  F.BoundsRect := Screen.MonitorFromWindow(F.Handle).BoundsRect;
  FFullscreen := True;
end;

procedure TJanela.SairTelaCheia;
begin
  if not FFullscreen then
    Exit;
  FFullscreen := False;
  AplicarBorda(FSavedBorder <> bsNone);
  F.BoundsRect := FSavedBounds;
  if FForm is TBorionWindow then
    TBorionWindow(FForm).Fullscreen := False;
  if FSavedState = wsMaximized then
    F.WindowState := wsMaximized;
end;

{ TBorionWindowPlugin }

constructor TBorionWindowPlugin.Create(AForm: TCustomForm);
begin
  inherited Create;
  FFixedForm := AForm;
  FJanelas := TList.Create;
  FAckTimeout := 2000;
  FTimer := Classes.AllocateHWnd(TimerWndProc);
end;

destructor TBorionWindowPlugin.Destroy;
var
  I: Integer;
begin
  for I := FJanelas.Count - 1 downto 0 do
    TJanela(FJanelas[I]).Free;
  FJanelas.Free;
  if FTimer <> 0 then
    Classes.DeallocateHWnd(FTimer);
  inherited;
end;

function TBorionWindowPlugin.Name: string;
begin
  Result := 'window';
end;

function TBorionWindowPlugin.Adicionar(const WindowLabel: string; AForm: TCustomForm): TObject;
var
  J: TJanela;
begin
  Result := Achar(WindowLabel);
  if (Result <> nil) or (AForm = nil) then
    Exit;
  J := TJanela.Create(nil);
  J.FPlugin := Self;
  J.FLabel := WindowLabel;
  J.FForm := AForm;
  J.Hook;
  FJanelas.Add(J);
  Result := J;
  { "fullscreen": true no app.json }
  if (AForm is TBorionWindow) and TBorionWindow(AForm).StartFullscreen then
    J.EntrarTelaCheia;
end;

function TBorionWindowPlugin.Achar(const WindowLabel: string): TObject;
var
  I: Integer;
begin
  for I := 0 to FJanelas.Count - 1 do
  begin
    Result := FJanelas[I];
    if TJanela(Result).FLabel = WindowLabel then
      Exit;
  end;
  Result := nil;
end;

function TBorionWindowPlugin.Alvo(Call: TBorionCall): TObject;
var
  L: string;
begin
  L := Call.ArgStr('label', Call.Window);
  Result := Achar(L);
  if (Result = nil) and (FJanelas.Count = 1) and (FFixedForm <> nil) and not Call.HasArg('label') then
    Result := FJanelas[0];  { um form só: é ele }
  if (Result = nil) or (TJanela(Result).FForm = nil) then
    raise EBorionError.Create('WINDOW_NOT_FOUND', 'nenhuma janela "' + L + '"');
end;

function TBorionWindowPlugin.FormOf(const WindowLabel: string): TCustomForm;
var
  J: TObject;
begin
  J := Achar(WindowLabel);
  if J = nil then
    Result := nil
  else
    Result := TJanela(J).FForm;
end;

function TBorionWindowPlugin.GetForm: TCustomForm;
begin
  if FJanelas.Count > 0 then
    Result := TJanela(FJanelas[0]).FForm
  else
    Result := nil;
end;

function TBorionWindowPlugin.GetFullscreen: Boolean;
begin
  Result := (FJanelas.Count > 0) and TJanela(FJanelas[0]).FFullscreen;
end;

function TBorionWindowPlugin.GetInterceptClose: Boolean;
begin
  Result := (FJanelas.Count > 0) and TJanela(FJanelas[0]).FIntercept;
end;

procedure TBorionWindowPlugin.Install;
var
  I: Integer;
  B: TWebView2Browser;
  L: string;
begin
  if FFixedForm <> nil then
  begin
    L := 'main';
    for I := 0 to Ipc.WindowCount - 1 do
    begin
      B := Ipc.WindowBrowser(Ipc.WindowLabel(I));
      if GetParentForm(B) = FFixedForm then
        L := Ipc.WindowLabel(I);
    end;
    Adicionar(L, FFixedForm);
    B := Ipc.WindowBrowser(L);
    if B <> nil then
      B.AddScriptOnDocumentCreated(BorionWindowDragScript);
  end
  else if Ipc.WindowCount > 0 then
  begin
    for I := 0 to Ipc.WindowCount - 1 do
      WindowAdded(Ipc.WindowLabel(I), Ipc.WindowBrowser(Ipc.WindowLabel(I)));
  end
  else if Application.MainForm <> nil then
    Adicionar('main', Application.MainForm);

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
  Command('startDragging', CmdStartDragging);
  Command('startResizeDragging', CmdStartResizeDragging);
  Command('internalToggleMaximize', CmdInternalToggleMaximize);
  Command('internalResizeBorder', CmdInternalResizeBorder);
  Command('state', CmdState);
  Command('close', CmdClose);
  Command('destroy', CmdDestroy);
  Command('interceptClose', CmdInterceptClose);
  Command('closeAck', CmdCloseAck);
  Command('closeResolve', CmdCloseResolve);
  Command('list', CmdList);
  { criar uma janela (e um WebView) não pode ser dentro do callback do WebView2 }
  CommandLater('create', CmdCreate);
end;

procedure TBorionWindowPlugin.WindowAdded(const WindowLabel: string; ABrowser: TWebView2Browser);
begin
  if FFixedForm = nil then
  begin
    Adicionar(WindowLabel, GetParentForm(ABrowser));
    ABrowser.AddScriptOnDocumentCreated(BorionWindowDragScript);
  end;
end;

procedure TBorionWindowPlugin.WindowRemoved(const WindowLabel: string; ABrowser: TWebView2Browser);
var
  J: TObject;
begin
  if FFixedForm <> nil then
    Exit;
  J := Achar(WindowLabel);
  if J <> nil then
  begin
    FJanelas.Remove(J);
    J.Free;
  end;
end;

procedure TBorionWindowPlugin.TimerWndProc(var Message: TMessage);
var
  I: Integer;
  J: TJanela;
begin
  if Message.Msg = WM_TIMER then
  begin
    KillTimer(FTimer, Message.WParam);
    { a página não confirmou o pedido: fecha mesmo assim }
    for I := 0 to FJanelas.Count - 1 do
    begin
      J := TJanela(FJanelas[I]);
      if (J.FPendingId <> 0) and (J.FPendingId = Integer(Message.WParam)) then
      begin
        J.FPendingId := 0;
        J.FecharDeVerdade;
        Break;
      end;
    end;
  end
  else
    Message.Result := DefWindowProc(FTimer, Message.Msg, Message.WParam, Message.LParam);
end;

{ --- argumentos ------------------------------------------------------------ }

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

{ --- comandos -------------------------------------------------------------- }

procedure TBorionWindowPlugin.CmdSetTitle(Call: TBorionCall);
var
  J: TJanela;
begin
  J := TJanela(Alvo(Call));
  J.F.Caption := Call.ArgStr('title');
  { o título agora é do JS: não acompanha mais o document.title }
  if J.FForm is TBorionWindow then
    TBorionWindow(J.FForm).TitleFromPage := False;
end;

procedure TBorionWindowPlugin.CmdMinimize(Call: TBorionCall);
var
  J: TJanela;
begin
  J := TJanela(Alvo(Call));
  if J.EhPrincipal then
    Application.Minimize
  else
    J.F.WindowState := wsMinimized;
end;

procedure TBorionWindowPlugin.CmdUnminimize(Call: TBorionCall);
var
  J: TJanela;
begin
  J := TJanela(Alvo(Call));
  if J.EhPrincipal and IsIconic(Application.Handle) then
    Application.Restore;
  if J.F.WindowState = wsMinimized then
    J.F.WindowState := wsNormal;
end;

procedure TBorionWindowPlugin.CmdMaximize(Call: TBorionCall);
var
  J: TJanela;
begin
  J := TJanela(Alvo(Call));
  J.SairTelaCheia;
  J.F.WindowState := wsMaximized;
end;

procedure TBorionWindowPlugin.CmdUnmaximize(Call: TBorionCall);
var
  J: TJanela;
begin
  J := TJanela(Alvo(Call));
  if J.F.WindowState = wsMaximized then
    J.F.WindowState := wsNormal;
end;

procedure TBorionWindowPlugin.CmdToggleMaximize(Call: TBorionCall);
var
  J: TJanela;
begin
  J := TJanela(Alvo(Call));
  if J.F.WindowState = wsMaximized then
    J.F.WindowState := wsNormal
  else
  begin
    J.SairTelaCheia;
    J.F.WindowState := wsMaximized;
  end;
end;

procedure TBorionWindowPlugin.CmdShow(Call: TBorionCall);
begin
  TJanela(Alvo(Call)).F.Show;
end;

procedure TBorionWindowPlugin.CmdHide(Call: TBorionCall);
begin
  TJanela(Alvo(Call)).F.Hide;
end;

procedure TBorionWindowPlugin.CmdSetFocus(Call: TBorionCall);
var
  J: TJanela;
begin
  J := TJanela(Alvo(Call));
  if J.EhPrincipal and IsIconic(Application.Handle) then
    Application.Restore;
  if J.F.WindowState = wsMinimized then
    J.F.WindowState := wsNormal;
  J.F.Show;
  SetForegroundWindow(J.F.Handle);
end;

procedure TBorionWindowPlugin.CmdCenter(Call: TBorionCall);
var
  J: TJanela;
  R: TRect;
begin
  J := TJanela(Alvo(Call));
  R := Screen.MonitorFromWindow(J.F.Handle).WorkareaRect;
  J.F.SetBounds(R.Left + (R.Right - R.Left - J.F.Width) div 2,
    R.Top + (R.Bottom - R.Top - J.F.Height) div 2, J.F.Width, J.F.Height);
end;

procedure TBorionWindowPlugin.CmdSetSize(Call: TBorionCall);
var
  J: TJanela;
  W, H: Integer;
begin
  W := Inteiro(Call, 'width', 1);
  H := Inteiro(Call, 'height', 1);
  J := TJanela(Alvo(Call));
  J.SairTelaCheia;
  if J.F.WindowState <> wsNormal then
    J.F.WindowState := wsNormal;
  J.F.SetBounds(J.F.Left, J.F.Top, W, H);
end;

procedure TBorionWindowPlugin.CmdSetPosition(Call: TBorionCall);
var
  J: TJanela;
  X, Y: Integer;
begin
  X := Posicao(Call, 'x');
  Y := Posicao(Call, 'y');
  J := TJanela(Alvo(Call));
  J.SairTelaCheia;
  if J.F.WindowState <> wsNormal then
    J.F.WindowState := wsNormal;
  J.F.SetBounds(X, Y, J.F.Width, J.F.Height);
end;

procedure TBorionWindowPlugin.CmdSetMinSize(Call: TBorionCall);
var
  J: TJanela;
  W, H: Integer;
begin
  W := Inteiro(Call, 'width', 0);
  H := Inteiro(Call, 'height', 0);
  J := TJanela(Alvo(Call));
  J.F.Constraints.MinWidth := W;
  J.F.Constraints.MinHeight := H;
end;

procedure TBorionWindowPlugin.CmdSetMaxSize(Call: TBorionCall);
var
  J: TJanela;
  W, H: Integer;
begin
  W := Inteiro(Call, 'width', 0);
  H := Inteiro(Call, 'height', 0);
  J := TJanela(Alvo(Call));
  J.F.Constraints.MaxWidth := W;
  J.F.Constraints.MaxHeight := H;
end;

procedure TBorionWindowPlugin.CmdSetFullscreen(Call: TBorionCall);
var
  J: TJanela;
  B: Boolean;
begin
  B := Logica(Call, 'fullscreen');
  J := TJanela(Alvo(Call));
  if B then
    J.EntrarTelaCheia
  else
    J.SairTelaCheia;
end;

procedure TBorionWindowPlugin.CmdSetAlwaysOnTop(Call: TBorionCall);
var
  J: TJanela;
  B: Boolean;
begin
  B := Logica(Call, 'alwaysOnTop');
  J := TJanela(Alvo(Call));
  if B then
    J.F.FormStyle := fsStayOnTop
  else
    J.F.FormStyle := fsNormal;
end;

procedure TBorionWindowPlugin.CmdSetResizable(Call: TBorionCall);
var
  J: TJanela;
  B: Boolean;
begin
  B := Logica(Call, 'resizable');
  J := TJanela(Alvo(Call));
  J.SetRedimensionavel(B);
  if J.FFullscreen then
  begin
    { em tela cheia, vale ao sair dela }
    if J.FSavedBorder = bsNone then
      Exit
    else if B then
      J.FSavedBorder := bsSizeable
    else
      J.FSavedBorder := bsSingle;
  end
  else if J.F.BorderStyle <> bsNone then
    J.AplicarBorda(True)
  else
    J.AvisarBordaDaPagina;
end;

procedure TBorionWindowPlugin.CmdSetDecorations(Call: TBorionCall);
var
  J: TJanela;
  D: Boolean;
begin
  D := Logica(Call, 'decorations');
  J := TJanela(Alvo(Call));
  if not J.FFullscreen then
    J.AplicarBorda(D)
  { em tela cheia, vale ao sair dela }
  else if not D then
    J.FSavedBorder := bsNone
  else if J.Redimensionavel then
    J.FSavedBorder := bsSizeable
  else
    J.FSavedBorder := bsSingle;
end;

procedure TBorionWindowPlugin.CmdStartDragging(Call: TBorionCall);
var
  J: TJanela;
begin
  J := TJanela(Alvo(Call));
  if not J.FFullscreen then
    J.Arrastar(HTCAPTION);
end;

procedure TBorionWindowPlugin.CmdStartResizeDragging(Call: TBorionCall);
const
  Direcoes: array[0..7] of string = ('West', 'East', 'North', 'NorthWest', 'NorthEast',
    'South', 'SouthWest', 'SouthEast');
  HitTests: array[0..7] of Integer = (HTLEFT, HTRIGHT, HTTOP, HTTOPLEFT, HTTOPRIGHT,
    HTBOTTOM, HTBOTTOMLEFT, HTBOTTOMRIGHT);
var
  J: TJanela;
  D: string;
  I: Integer;
begin
  D := Call.ArgStr('direction');
  I := High(Direcoes);
  while (I >= 0) and (Direcoes[I] <> D) do
    Dec(I);
  if I < 0 then
    raise EBorionError.Create('INVALID_ARGS', '"direction" deve ser North, South, East, West, ' +
      'NorthEast, NorthWest, SouthEast ou SouthWest');
  J := TJanela(Alvo(Call));
  if J.Redimensionavel and not J.FFullscreen and (J.F.WindowState = wsNormal) then
    J.Arrastar(HitTests[I]);
end;

{ o duplo clique na região de arrastar, como na barra de título do Windows }
procedure TBorionWindowPlugin.CmdInternalToggleMaximize(Call: TBorionCall);
var
  J: TJanela;
begin
  J := TJanela(Alvo(Call));
  if J.Redimensionavel and not J.FFullscreen then
    CmdToggleMaximize(Call);
end;

procedure TBorionWindowPlugin.CmdInternalResizeBorder(Call: TBorionCall);
begin
  Call.Result.AsObject.Put('enabled', TJanela(Alvo(Call)).BordaDaPagina);
end;

procedure TBorionWindowPlugin.CmdState(Call: TBorionCall);
var
  O: TJsonObject;
  J: TJanela;
begin
  J := TJanela(Alvo(Call));
  O := Call.Result.AsObject;
  O.Put('label', J.FLabel);
  O.Put('title', J.F.Caption);
  O.Put('x', J.F.Left);
  O.Put('y', J.F.Top);
  O.Put('width', J.F.Width);
  O.Put('height', J.F.Height);
  O.Put('minimized', J.Minimizada);
  O.Put('maximized', J.F.WindowState = wsMaximized);
  O.Put('fullscreen', J.FFullscreen);
  O.Put('visible', J.F.Visible);
  O.Put('focused', J.F.HandleAllocated and (GetForegroundWindow = J.F.Handle));
  O.Put('alwaysOnTop', J.F.FormStyle = fsStayOnTop);
  O.Put('resizable', J.Redimensionavel);
  if J.FFullscreen then
    O.Put('decorations', J.FSavedBorder <> bsNone)
  else
    O.Put('decorations', J.F.BorderStyle <> bsNone);
end;

procedure TBorionWindowPlugin.CmdClose(Call: TBorionCall);
begin
  PostMessage(TJanela(Alvo(Call)).F.Handle, WM_CLOSE, 0, 0);
end;

procedure TBorionWindowPlugin.CmdDestroy(Call: TBorionCall);
var
  J: TJanela;
begin
  J := TJanela(Alvo(Call));
  J.CancelarPedido;
  J.FecharDeVerdade;
end;

procedure TBorionWindowPlugin.CmdInterceptClose(Call: TBorionCall);
var
  J: TJanela;
begin
  J := TJanela(Alvo(Call));
  J.FIntercept := Logica(Call, 'enabled');
  if not J.FIntercept then
    J.CancelarPedido;
end;

procedure TBorionWindowPlugin.CmdCloseAck(Call: TBorionCall);
var
  J: TJanela;
begin
  { a página recebeu o pedido: a decisão pode levar o tempo que precisar }
  J := TJanela(Alvo(Call));
  if (J.FPendingId <> 0) and (Call.ArgInt('id') = J.FPendingId) then
    KillTimer(FTimer, J.FPendingId);
end;

procedure TBorionWindowPlugin.CmdCloseResolve(Call: TBorionCall);
var
  J: TJanela;
begin
  J := TJanela(Alvo(Call));
  if (J.FPendingId = 0) or (Call.ArgInt('id') <> J.FPendingId) then
    Exit;  { resposta a um pedido antigo }
  J.CancelarPedido;
  if Call.ArgBool('close') then
    J.FecharDeVerdade;
end;

procedure TBorionWindowPlugin.CmdList(Call: TBorionCall);
var
  A: TJsonArray;
  O: TJsonObject;
  I: Integer;
  J: TJanela;
begin
  A := Call.Result.AsArray;
  for I := 0 to FJanelas.Count - 1 do
  begin
    J := TJanela(FJanelas[I]);
    if J.FForm = nil then
      Continue;
    O := A.Add.AsObject;
    O.Put('label', J.FLabel);
    O.Put('title', J.FForm.Caption);
    O.Put('visible', J.FForm.Visible);
    O.Put('main', (Ipc.WindowCount > 0) and (Ipc.WindowLabel(0) = J.FLabel) or
      ((Ipc.WindowCount = 0) and (I = 0)));
  end;
end;

procedure TBorionWindowPlugin.CmdCreate(Call: TBorionCall);
var
  C: TBorionWindowConfig;
  L: string;
begin
  if BorionWindows = nil then
    raise EBorionError.Create('NOT_SUPPORTED', 'criar janelas exige o app montado pelo TBorionBuilder');
  L := Call.ArgStr('label');
  if not BorionIsValidWindowLabel(L) then
    raise EBorionError.Create('INVALID_LABEL', 'rótulo de janela inválido: "' + L +
      '" (use letras, dígitos, "-" e "_")');
  if Ipc.WindowBrowser(L) <> nil then
    raise EBorionError.Create('WINDOW_EXISTS', 'a janela "' + L + '" já está aberta');
  { a definição do app.json, se houver; os argumentos vencem }
  if not BorionWindows.Definition(L, C) then
  begin
    C := BorionDefaultWindow;
    C.WindowLabel := L;
  end;
  if Call.HasArg('url') then
  begin
    C.Url := Call.ArgStr('url');
    if (Copy(C.Url, 1, 1) <> '/') or (Copy(C.Url, 1, 2) = '//') then
      raise EBorionError.Create('INVALID_ARGS', '"url" deve ser um caminho do app começando com "/"');
  end;
  if Call.HasArg('title') then C.Title := Call.ArgStr('title');
  if Call.HasArg('width') then C.Width := Inteiro(Call, 'width', 1);
  if Call.HasArg('height') then C.Height := Inteiro(Call, 'height', 1);
  if Call.HasArg('minWidth') then C.MinWidth := Inteiro(Call, 'minWidth', 0);
  if Call.HasArg('minHeight') then C.MinHeight := Inteiro(Call, 'minHeight', 0);
  if Call.HasArg('maxWidth') then C.MaxWidth := Inteiro(Call, 'maxWidth', 0);
  if Call.HasArg('maxHeight') then C.MaxHeight := Inteiro(Call, 'maxHeight', 0);
  if Call.HasArg('resizable') then C.Resizable := Logica(Call, 'resizable');
  if Call.HasArg('center') then C.Center := Logica(Call, 'center');
  if Call.HasArg('maximized') then C.Maximized := Logica(Call, 'maximized');
  if Call.HasArg('decorations') then C.Decorations := Logica(Call, 'decorations');
  if Call.HasArg('alwaysOnTop') then C.AlwaysOnTop := Logica(Call, 'alwaysOnTop');
  if Call.HasArg('visible') then C.Visible := Logica(Call, 'visible');
  BorionWindows.CreateWindow(C);
  Call.Result.AsObject.Put('label', L);
end;

{ --- script da página ------------------------------------------------------ }

function BorionWindowDragScript: WideString;
begin
  { JS só com aspas duplas, para não precisar escapar no Pascal }
  Result :=
    '(function () {' + #10 +
    '  "use strict";' + #10 +
    '  if (window.__BORION_DRAG__ || window !== window.top) return;' + #10 +
    '  var b = window.__BORION__;' + #10 +
    '  if (!b) return;' + #10 +
    '  Object.defineProperty(window, "__BORION_DRAG__", { value: true });' + #10 +
    '  var ATTR = "data-borion-drag-region", EDGE = 5;' + #10 +
    '  var CURSORS = { North: "ns", South: "ns", East: "ew", West: "ew",' + #10 +
    '    NorthWest: "nwse", SouthEast: "nwse", NorthEast: "nesw", SouthWest: "nesw" };' + #10 +
    '  var border = false, cursor = "", style = null;' + #10 +
    '  function ignore() {}' + #10 +
    '  function cmd(name, args) { b.invoke("window:" + name, args).catch(ignore); }' + #10 +
    '  function setCursor(c) {' + #10 +
    '    var root = document.documentElement;' + #10 +
    '    if (c === cursor || !root) return;' + #10 +
    '    cursor = c;' + #10 +
    '    if (c && !style) {' + #10 +
    '      style = document.createElement("style");' + #10 +
    '      style.textContent = ["ns", "ew", "nwse", "nesw"].map(function (k) {' + #10 +
    '        var s = "html[data-borion-resize=" + k + "]";' + #10 +
    '        return s + ", " + s + " * { cursor: " + k + "-resize !important; }";' + #10 +
    '      }).join("\n");' + #10 +
    '      (document.head || root).appendChild(style);' + #10 +
    '    }' + #10 +
    '    if (c) root.setAttribute("data-borion-resize", c);' + #10 +
    '    else root.removeAttribute("data-borion-resize");' + #10 +
    '  }' + #10 +
    '  function setBorder(p) {' + #10 +
    '    border = !!(p && p.enabled);' + #10 +
    '    if (!border) setCursor("");' + #10 +
    '  }' + #10 +
    '  /* a borda que redimensiona: so sem decorations, com a janela redimensionavel e normal */' + #10 +
    '  function direction(e) {' + #10 +
    '    if (!border) return "";' + #10 +
    '    var w = window.innerWidth, h = window.innerHeight, x = e.clientX, y = e.clientY;' + #10 +
    '    var n = y < EDGE, s = y >= h - EDGE, l = x < EDGE, r = x >= w - EDGE;' + #10 +
    '    /* cantos mais largos que a borda */' + #10 +
    '    if (n || s) { l = x < EDGE * 3; r = x >= w - EDGE * 3; }' + #10 +
    '    else if (l || r) { n = y < EDGE * 3; s = y >= h - EDGE * 3; }' + #10 +
    '    return (n ? "North" : s ? "South" : "") + (l ? "West" : r ? "East" : "");' + #10 +
    '  }' + #10 +
    '  b.invoke("window:internalResizeBorder").then(setBorder, ignore);' + #10 +
    '  b.listen("window:resize-border", setBorder);' + #10 +
    '  window.addEventListener("mousemove", function (e) {' + #10 +
    '    var d = direction(e);' + #10 +
    '    setCursor(d ? CURSORS[d] : "");' + #10 +
    '  }, true);' + #10 +
    '  window.addEventListener("mousedown", function (e) {' + #10 +
    '    var d = e.button === 0 ? direction(e) : "";' + #10 +
    '    if (!d) return;' + #10 +
    '    e.preventDefault();' + #10 +
    '    e.stopImmediatePropagation();' + #10 +
    '    cmd("startResizeDragging", { direction: d });' + #10 +
    '  }, true);' + #10 +
    '  /* a regiao de arrastar: o proprio elemento com o atributo, nao os filhos */' + #10 +
    '  document.addEventListener("mousedown", function (e) {' + #10 +
    '    var t = e.target, v = t && t.getAttribute ? t.getAttribute(ATTR) : null;' + #10 +
    '    if (e.button !== 0 || v === null || v === "false" || (e.detail !== 1 && e.detail !== 2)) return;' + #10 +
    '    e.preventDefault();' + #10 +
    '    e.stopImmediatePropagation();' + #10 +
    '    cmd(e.detail === 2 ? "internalToggleMaximize" : "startDragging");' + #10 +
    '  });' + #10 +
    '})();';
end;

end.
