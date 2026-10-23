unit BorionWindowState;

(*
  Borion — Native Application Engine
  Plugin "window-state": lembra o tamanho, a posição e o maximizado de cada
  janela entre uma execução e outra (como o window-state do Tauri).

    .Plugin(TBorionWindowStatePlugin.Create)                   // no TBorionBuilder
    .Plugin(TBorionWindowStatePlugin.Create.Ignore('splash'))  // menos essa janela

  Restaura quando a janela entra no IPC (a principal no Run, as outras ao
  abrir), antes de ela aparecer: a janela não pula de lugar. O app.json e os
  métodos do builder valem até a primeira gravação. Grava quando a janela
  fecha (o app terminando fecha todas).

  Arquivo: %APPDATA%\<pasta>\.window-state.json, onde a pasta é o AppName ou,
  sem ele, o identifier do app.json (ou o nome do exe). Uma entrada por rótulo:
    {"main": {"x": 100, "y": 80, "width": 1000, "height": 700, "maximized": false}}

  Flags, o que é restaurado (padrão: tudo):
    wsfSize       width e height (só numa janela redimensionável)
    wsfPosition   x e y, se a barra de título ainda cair num monitor (senão,
                  fica a posição do app.json)
    wsfMaximized  maximized
  Maximizada, minimizada ou em tela cheia, o tamanho e a posição gravados são
  os do estado normal (TBorionWindow.NormalBounds; num form comum, os da
  última vez em que ele estava normal). Minimizada e tela cheia não voltam.
  Janela que nunca apareceu não é gravada.

  Comandos:
    window-state:save               grava agora as janelas abertas
    window-state:restore {label?}   aplica o estado gravado (à janela que chamou)
                                    -> false se não houver estado dela
    window-state:filename           -> caminho do arquivo
*)

interface

uses
  Windows, SysUtils, Classes, Controls, Forms, Jsons, BorionIpc, WebView2Browser;

type
  TBorionWindowStateFlag = (wsfSize, wsfPosition, wsfMaximized);
  TBorionWindowStateFlags = set of TBorionWindowStateFlag;

const
  BORION_WINDOW_STATE_ALL = [wsfSize, wsfPosition, wsfMaximized];
  BORION_WINDOW_STATE_FILE = '.window-state.json';

type
  TBorionWindowStatePlugin = class(TBorionPlugin)
  private
    FFileName: string;
    FFlags: TBorionWindowStateFlags;
    FIgnored: TStringList;
    FStates: TStringList;  { rótulo -> TEstadoJanela }
    FLoaded: Boolean;
    procedure Carregar;
    procedure Gravar;
    function Achar(const WindowLabel: string): TObject;
    procedure Acompanhar(const WindowLabel: string; ABrowser: TWebView2Browser);
    procedure Guardar(E: TObject);
    function Aplicar(const WindowLabel: string): Boolean;
    procedure CmdSave(Call: TBorionCall);
    procedure CmdRestore(Call: TBorionCall);
    procedure CmdFilename(Call: TBorionCall);
  protected
    procedure Install; override;
    procedure WindowAdded(const WindowLabel: string; ABrowser: TWebView2Browser); override;
    procedure WindowRemoved(const WindowLabel: string; ABrowser: TWebView2Browser); override;
  public
    { AppName: a pasta em %APPDATA% (padrão: o identifier do app.json ou, sem
      ele, o nome do exe; o título do app pode ter caracteres inválidos num
      nome de pasta) }
    constructor Create(const AppName: string = ''; AFlags: TBorionWindowStateFlags = BORION_WINDOW_STATE_ALL);
    destructor Destroy; override;
    function Name: string; override;
    { Não restaura nem grava essa janela. Devolve o próprio plugin. }
    function Ignore(const WindowLabel: string): TBorionWindowStatePlugin;
    { Grava agora o estado das janelas abertas }
    procedure SaveState;
    { Aplica o estado gravado à janela; False se não houver estado dela }
    function RestoreState(const WindowLabel: string): Boolean;
    property FileName: string read FFileName write FFileName;
    property Flags: TBorionWindowStateFlags read FFlags write FFlags;
  end;

implementation

uses
  BorionJson, BorionScope, BorionConfig, Borion;

type
  { acesso às propriedades protegidas do TCustomForm (Position, BorderStyle) }
  TFormAcesso = class(TCustomForm);

  { O estado de uma janela: o gravado e, aberta, o form dela (com o aviso de
    form liberado) }
  TEstadoJanela = class(TComponent)
  private
    FForm: TCustomForm;
    FSaved: Boolean;  { há estado: lido do arquivo ou guardado nesta execução }
    FBounds: TRect;
    FHasBounds: Boolean;
    FMaximized: Boolean;
    procedure SetForm(AForm: TCustomForm);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  end;

procedure TEstadoJanela.SetForm(AForm: TCustomForm);
begin
  if FForm <> nil then
    FForm.RemoveFreeNotification(Self);
  FForm := AForm;
  if FForm <> nil then
    FForm.FreeNotification(Self);
end;

procedure TEstadoJanela.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FForm) then
    FForm := nil;
end;

function Logico(B: Boolean): string;
begin
  if B then
    Result := 'true'
  else
    Result := 'false';
end;

function Redimensionavel(F: TCustomForm): Boolean;
begin
  if TObject(F) is TBorionWindow then
    Result := TBorionWindow(F).Resizable
  else
    Result := TFormAcesso(F).BorderStyle in [bsSizeable, bsSizeToolWin];
end;

{ a barra de título (os 30 px de cima) aparece em algum monitor: pelo menos
  100 px dela (ou ela inteira, numa janela estreita) na área de trabalho }
function NaTela(const R: TRect): Boolean;
var
  Barra, I: TRect;
  M: TMonitor;
  Minimo: Integer;
begin
  Barra := Rect(R.Left, R.Top, R.Right, R.Top + 30);
  M := Screen.MonitorFromRect(Barra, mdNull);
  Minimo := R.Right - R.Left;
  if Minimo > 100 then
    Minimo := 100;
  Result := (M <> nil) and IntersectRect(I, Barra, M.WorkareaRect) and (I.Right - I.Left >= Minimo);
end;

{ Position := poDesigned sem recriar a janela. O TCustomForm recria o handle a
  cada mudança da Position (menos em design), mas poScreenCenter e poDesigned
  só diferem no Show; e o form principal já tem handle desde o
  Application.CreateForm: recriar seria trabalho à toa e quebraria quem já
  guardou o handle (um plugin instalado antes). }
procedure FixarPosicao(F: TFormAcesso);
begin
  F.SetDesigning(True, False);
  try
    F.Position := poDesigned;
  finally
    F.SetDesigning(False, False);
  end;
end;

{ inteiro de -32767 a 32767 }
function LerInteiro(O: TJsonObject; const Nome: string; out N: Integer): Boolean;
var
  I: Integer;
  V: TJsonValue;
begin
  Result := False;
  I := O.Find(Nome);
  if I < 0 then
    Exit;
  V := O.Items[I].Value;
  if (V.ValueType <> jvNumber) or (Frac(V.AsNumber) <> 0) or (Abs(V.AsNumber) > 32767) then
    Exit;
  N := Trunc(V.AsNumber);
  Result := True;
end;

{ TBorionWindowStatePlugin }

constructor TBorionWindowStatePlugin.Create(const AppName: string; AFlags: TBorionWindowStateFlags);
begin
  inherited Create;
  if AppName <> '' then
    FFileName := BorionBaseDirPath(bdAppData, AppName) + '\' + BORION_WINDOW_STATE_FILE;
  FFlags := AFlags;
  FIgnored := TStringList.Create;
  FStates := TStringList.Create;
  FStates.CaseSensitive := True;
end;

destructor TBorionWindowStatePlugin.Destroy;
var
  I: Integer;
begin
  for I := 0 to FStates.Count - 1 do
    FStates.Objects[I].Free;
  FStates.Free;
  FIgnored.Free;
  inherited;
end;

function TBorionWindowStatePlugin.Name: string;
begin
  Result := 'window-state';
end;

function TBorionWindowStatePlugin.Ignore(const WindowLabel: string): TBorionWindowStatePlugin;
begin
  FIgnored.Add(WindowLabel);
  Result := Self;
end;

procedure TBorionWindowStatePlugin.Install;
var
  I: Integer;
  Pasta: string;
begin
  if FFileName = '' then
  begin
    Pasta := BorionAppConfig.Identifier;
    if Pasta = '' then
      Pasta := ChangeFileExt(ExtractFileName(ParamStr(0)), '');
    FFileName := BorionBaseDirPath(bdAppData, Pasta) + '\' + BORION_WINDOW_STATE_FILE;
  end;
  { as janelas que já estavam no IPC (a principal, no TBorionBuilder) }
  for I := 0 to Ipc.WindowCount - 1 do
    Acompanhar(Ipc.WindowLabel(I), Ipc.WindowBrowser(Ipc.WindowLabel(I)));
  Command('save', CmdSave);
  Command('restore', CmdRestore);
  Command('filename', CmdFilename);
end;

procedure TBorionWindowStatePlugin.WindowAdded(const WindowLabel: string; ABrowser: TWebView2Browser);
begin
  Acompanhar(WindowLabel, ABrowser);
end;

procedure TBorionWindowStatePlugin.WindowRemoved(const WindowLabel: string; ABrowser: TWebView2Browser);
var
  E: TEstadoJanela;
begin
  E := TEstadoJanela(Achar(WindowLabel));
  if (E = nil) or (E.FForm = nil) then
    Exit;
  Guardar(E);
  E.SetForm(nil);
  try
    Gravar;
  except
    { fechando: não há a quem avisar }
  end;
end;

function TBorionWindowStatePlugin.Achar(const WindowLabel: string): TObject;
var
  I: Integer;
begin
  I := FStates.IndexOf(WindowLabel);
  if I >= 0 then
    Result := FStates.Objects[I]
  else
    Result := nil;
end;

procedure TBorionWindowStatePlugin.Acompanhar(const WindowLabel: string; ABrowser: TWebView2Browser);
var
  E: TEstadoJanela;
  F: TCustomForm;
begin
  if FIgnored.IndexOf(WindowLabel) >= 0 then
    Exit;
  F := GetParentForm(ABrowser);
  if F = nil then
    Exit;
  Carregar;
  E := TEstadoJanela(Achar(WindowLabel));
  if E = nil then
  begin
    E := TEstadoJanela.Create(nil);
    FStates.AddObject(WindowLabel, E);
  end;
  E.SetForm(F);
  Aplicar(WindowLabel);
end;

{ Lê o arquivo uma vez. Ilegível ou corrompido: começa vazio (a próxima
  gravação o substitui). }
procedure TBorionWindowStatePlugin.Carregar;
var
  Raiz, O: TJsonObject;
  S: TStringList;
  E: TEstadoJanela;
  I, X, Y, W, H: Integer;
  V: TJsonValue;
begin
  if FLoaded then
    Exit;
  FLoaded := True;
  if not FileExists(FFileName) then
    Exit;
  S := TStringList.Create;
  Raiz := TJsonObject.Create;
  try
    try
      S.LoadFromFile(FFileName);
      Raiz.Parse(S.Text);
    except
      Exit;
    end;
    for I := 0 to Raiz.Count - 1 do
    begin
      V := Raiz.Items[I].Value;
      if V.ValueType <> jvObject then
        Continue;
      O := V.AsObject;
      E := TEstadoJanela.Create(nil);
      E.FSaved := True;
      FStates.AddObject(Raiz.Items[I].Name, E);
      if LerInteiro(O, 'x', X) and LerInteiro(O, 'y', Y) and LerInteiro(O, 'width', W) and
        LerInteiro(O, 'height', H) and (W > 0) and (H > 0) then
      begin
        E.FBounds := Rect(X, Y, X + W, Y + H);
        E.FHasBounds := True;
      end;
      X := O.Find('maximized');
      E.FMaximized := (X >= 0) and (O.Items[X].Value.ValueType = jvBoolean) and
        O.Items[X].Value.AsBoolean;
    end;
  finally
    Raiz.Free;
    S.Free;
  end;
end;

procedure TBorionWindowStatePlugin.Gravar;
var
  S, Temp: string;
  I, N: Integer;
  E: TEstadoJanela;
  F: TFileStream;
begin
  S := '{';
  N := 0;
  for I := 0 to FStates.Count - 1 do
  begin
    E := TEstadoJanela(FStates.Objects[I]);
    if not E.FSaved then
      Continue;
    if N > 0 then
      S := S + ',';
    Inc(N);
    S := S + #13#10'  ' + JsonQuote(FStates[I]) + ': {';
    if E.FHasBounds then
      S := S + Format('"x": %d, "y": %d, "width": %d, "height": %d, ', [E.FBounds.Left,
        E.FBounds.Top, E.FBounds.Right - E.FBounds.Left, E.FBounds.Bottom - E.FBounds.Top]);
    S := S + '"maximized": ' + Logico(E.FMaximized) + '}';
  end;
  S := S + #13#10'}'#13#10;
  { grava num temporário e troca: uma queda no meio não deixa o arquivo pela metade }
  Temp := FFileName + '.tmp';
  try
    ForceDirectories(ExtractFileDir(FFileName));
    F := TFileStream.Create(Temp, fmCreate);
    try
      F.WriteBuffer(S[1], Length(S));
    finally
      F.Free;
    end;
    if not MoveFileEx(PChar(Temp), PChar(FFileName), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
      RaiseLastOSError;
  except
    on Ex: Exception do
    begin
      DeleteFile(Temp);
      raise EBorionError.Create('IO_ERROR', 'não foi possível gravar ' + FFileName + ': ' + Ex.Message);
    end;
  end;
end;

{ Copia o estado do form para a entrada. Só lê campos do form (nada de
  Handle): na saída do app, ele já está sendo destruído. }
procedure TBorionWindowStatePlugin.Guardar(E: TObject);
var
  F: TFormAcesso;
  R: TRect;
begin
  F := TFormAcesso(TEstadoJanela(E).FForm);
  { sem aparecer, o form ainda não tem a posição final (o Show centraliza) }
  if (F = nil) or (F.Position <> poDesigned) then
    Exit;
  TEstadoJanela(E).FSaved := True;
  if (F.WindowState = wsNormal) and not ((TObject(F) is TBorionWindow) and TBorionWindow(F).Fullscreen) then
    R := F.BoundsRect
  else if TObject(F) is TBorionWindow then
    R := TBorionWindow(F).NormalBounds
  else
    R := Rect(0, 0, 0, 0);  { form comum maximizado: fica o tamanho gravado antes }
  if not IsRectEmpty(R) then
  begin
    TEstadoJanela(E).FBounds := R;
    TEstadoJanela(E).FHasBounds := True;
  end;
  { minimizada: fica o maximizado de antes }
  if F.WindowState <> wsMinimized then
    TEstadoJanela(E).FMaximized := F.WindowState = wsMaximized;
end;

function TBorionWindowStatePlugin.Aplicar(const WindowLabel: string): Boolean;
var
  E: TEstadoJanela;
  F: TFormAcesso;
  Atual, R, P: TRect;
  Mover: Boolean;
  Alvo: TWindowState;
begin
  E := TEstadoJanela(Achar(WindowLabel));
  Result := (E <> nil) and E.FSaved;
  if not Result or (E.FForm = nil) then
    Exit;
  F := TFormAcesso(E.FForm);
  { minimizada ou em tela cheia, não mexe: valem ao voltar }
  if (F.WindowState = wsMinimized) or ((TObject(F) is TBorionWindow) and TBorionWindow(F).Fullscreen) then
    Exit;
  Alvo := F.WindowState;
  if wsfMaximized in FFlags then
    if E.FMaximized then
      Alvo := wsMaximized
    else
      Alvo := wsNormal;
  Mover := False;
  { maximizada, o tamanho a mudar é o do estado normal }
  Atual := F.BoundsRect;
  if (F.WindowState = wsMaximized) and (TObject(F) is TBorionWindow) and
    not IsRectEmpty(TBorionWindow(F).NormalBounds) then
    Atual := TBorionWindow(F).NormalBounds;
  R := Atual;
  if E.FHasBounds then
  begin
    if (wsfSize in FFlags) and Redimensionavel(F) then
    begin
      R.Right := R.Left + E.FBounds.Right - E.FBounds.Left;
      R.Bottom := R.Top + E.FBounds.Bottom - E.FBounds.Top;
    end;
    if wsfPosition in FFlags then
    begin
      P := R;
      OffsetRect(P, E.FBounds.Left - R.Left, E.FBounds.Top - R.Top);
      if NaTela(P) then
      begin
        R := P;
        Mover := True;
      end;
    end;
  end;
  { senão o Show centraliza de novo (mesmo que o lugar gravado seja o atual) }
  if Mover and (F.Position <> poDesigned) then
    FixarPosicao(F);
  if not EqualRect(R, Atual) then
  begin
    if F.WindowState = wsMaximized then
      F.WindowState := wsNormal;
    F.BoundsRect := R;
    if TObject(F) is TBorionWindow then
      TBorionWindow(F).NormalBounds := F.BoundsRect;
  end;
  F.WindowState := Alvo;
end;

procedure TBorionWindowStatePlugin.SaveState;
var
  I: Integer;
begin
  Carregar;
  for I := 0 to FStates.Count - 1 do
    Guardar(FStates.Objects[I]);
  Gravar;
end;

function TBorionWindowStatePlugin.RestoreState(const WindowLabel: string): Boolean;
begin
  Carregar;
  Result := Aplicar(WindowLabel);
end;

{ --- comandos -------------------------------------------------------------- }

procedure TBorionWindowStatePlugin.CmdSave(Call: TBorionCall);
begin
  SaveState;
end;

procedure TBorionWindowStatePlugin.CmdRestore(Call: TBorionCall);
var
  L: string;
begin
  L := Call.ArgStr('label', Call.Window);
  if Ipc.WindowBrowser(L) = nil then
    raise EBorionError.Create('WINDOW_NOT_FOUND', 'nenhuma janela "' + L + '"');
  Call.Result.AsBoolean := RestoreState(L);
end;


procedure TBorionWindowStatePlugin.CmdFilename(Call: TBorionCall);
begin
  Call.Result.AsString := FFileName;
end;

end.
