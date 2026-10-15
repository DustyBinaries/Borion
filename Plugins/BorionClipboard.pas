unit BorionClipboard;

(*
  Borion — Native Application Engine
  Plugin "clipboard": área de transferência do Windows (texto e HTML).

    Ipc.AddPlugin(TBorionClipboardPlugin.Create);         // ler e escrever
    Ipc.AddPlugin(TBorionClipboardPlugin.Create(False));  // só escrever

  Comandos:
    clipboard:writeText {text}             grava texto (CF_UNICODETEXT)
    clipboard:readText                     -> texto, ou null se não houver texto
    clipboard:writeHtml {html, altText?}   grava HTML ("HTML Format") e, com
                                           altText, também o texto puro
    clipboard:clear                        esvazia a área de transferência

  Unicode completo (emoji, CJK...): text, html, altText e o resultado do
  readText são literais JSON só com ASCII ('"ol\uXXXX"'), que o @borion/api
  gera e lê sozinho. O Delphi converte direto de/para UTF-16, sem passar pela
  página de código (veja WideToJsonLiteral em BorionJson).

  Ler a área de transferência expõe o que o usuário copiou de outros programas
  (senhas inclusive): crie com AllowRead = False se a página só precisa copiar.
*)

interface

uses
  Windows, Messages, SysUtils, Classes, Jsons, BorionIpc;

type
  TBorionClipboardPlugin = class(TBorionPlugin)
  private
    FAllowRead: Boolean;
    function ArgTexto(Call: TBorionCall; const Nome: string; Obrigatorio: Boolean;
      out Texto: WideString): Boolean;
    procedure CmdWriteText(Call: TBorionCall);
    procedure CmdReadText(Call: TBorionCall);
    procedure CmdWriteHtml(Call: TBorionCall);
    procedure CmdClear(Call: TBorionCall);
  protected
    procedure Install; override;
  public
    constructor Create(AAllowRead: Boolean = True);
    function Name: string; override;
    { False: clipboard:readText é recusado (FORBIDDEN) }
    property AllowRead: Boolean read FAllowRead write FAllowRead;
  end;

{ Funções da área de transferência, para usar também fora do plugin.
  Levantam EBorionError('CLIPBOARD_BUSY') se outro programa a mantiver aberta. }

{ False se não houver texto }
function BorionClipboardReadText(out Text: WideString): Boolean;
procedure BorionClipboardWriteText(const Text: WideString);
{ AltText vazio: só o HTML }
procedure BorionClipboardWriteHtml(const Html: WideString; const AltText: WideString = '');
procedure BorionClipboardClear;
{ Monta o conteúdo do formato "HTML Format" (CF_HTML): cabeçalho com as
  posições em bytes + o fragmento em UTF-8 }
function BorionCfHtml(const Html: WideString): string;

implementation

uses
  BorionJson;

type
  { Janela oculta dona da área de transferência: com OpenClipboard(0), o
    EmptyClipboard deixa a área sem dono e o SetClipboardData falha. }
  TDona = class
  private
    FHandle: HWND;
    procedure WndProc(var Message: TMessage);
  public
    constructor Create;
    destructor Destroy; override;
  end;

var
  Dona: TDona;
  CF_HTML: UINT;

constructor TDona.Create;
begin
  inherited Create;
  FHandle := Classes.AllocateHWnd(WndProc);
end;

destructor TDona.Destroy;
begin
  Classes.DeallocateHWnd(FHandle);
  inherited;
end;

procedure TDona.WndProc(var Message: TMessage);
begin
  Message.Result := DefWindowProc(FHandle, Message.Msg, Message.WParam, Message.LParam);
end;

procedure Abrir;
var
  Tentativa: Integer;
begin
  if Dona = nil then
    Dona := TDona.Create;
  { outro programa pode estar com ela aberta por alguns milissegundos }
  for Tentativa := 1 to 10 do
  begin
    if OpenClipboard(Dona.FHandle) then
      Exit;
    Sleep(15);
  end;
  raise EBorionError.Create('CLIPBOARD_BUSY', 'a área de transferência está em uso por outro programa');
end;

procedure Gravar(Formato: UINT; Dados: Pointer; Tamanho: Integer);
var
  H: HGLOBAL;
  P: Pointer;
begin
  H := GlobalAlloc(GMEM_MOVEABLE, Tamanho);
  if H = 0 then
    RaiseLastOSError;
  P := GlobalLock(H);
  Move(Dados^, P^, Tamanho);
  GlobalUnlock(H);
  if SetClipboardData(Formato, H) = 0 then
  begin
    GlobalFree(H);  { só passa a ser do sistema se o SetClipboardData der certo }
    RaiseLastOSError;
  end;
end;

procedure GravarTexto(const Text: WideString);
var
  S: WideString;
begin
  S := Text + WideChar(0);
  Gravar(CF_UNICODETEXT, PWideChar(S), Length(S) * SizeOf(WideChar));
end;

function Utf8(const W: WideString): string;
var
  N: Integer;
begin
  Result := '';
  if W = '' then
    Exit;
  N := WideCharToMultiByte(CP_UTF8, 0, PWideChar(W), Length(W), nil, 0, nil, nil);
  SetLength(Result, N);
  WideCharToMultiByte(CP_UTF8, 0, PWideChar(W), Length(W), PChar(Result), N, nil, nil);
end;

function BorionCfHtml(const Html: WideString): string;
const
  CABECALHO = 'Version:0.9'#13#10'StartHTML:%.10d'#13#10'EndHTML:%.10d'#13#10 +
    'StartFragment:%.10d'#13#10'EndFragment:%.10d'#13#10;
  ANTES = '<html><body>'#13#10'<!--StartFragment-->';
  DEPOIS = '<!--EndFragment-->'#13#10'</body></html>';
var
  Fragmento: string;
  Inicio, InicioFragmento, FimFragmento, Fim: Integer;
begin
  Fragmento := Utf8(Html);
  Inicio := Length(Format(CABECALHO, [0, 0, 0, 0]));  { números de largura fixa }
  InicioFragmento := Inicio + Length(ANTES);
  FimFragmento := InicioFragmento + Length(Fragmento);
  Fim := FimFragmento + Length(DEPOIS);
  Result := Format(CABECALHO, [Inicio, Fim, InicioFragmento, FimFragmento]) +
    ANTES + Fragmento + DEPOIS;
end;

function BorionClipboardReadText(out Text: WideString): Boolean;
var
  H: THandle;
  P: PWideChar;
  Max, N: Integer;
begin
  Text := '';
  Result := False;
  Abrir;
  try
    H := GetClipboardData(CF_UNICODETEXT);  { o Windows converte de CF_TEXT, se for o caso }
    if H = 0 then
      Exit;
    P := GlobalLock(H);
    if P = nil then
      Exit;
    try
      { não confia no #0 final: limita pelo tamanho do bloco }
      Max := Integer(GlobalSize(H)) div SizeOf(WideChar);
      N := 0;
      while (N < Max) and (P[N] <> #0) do
        Inc(N);
      SetLength(Text, N);
      if N > 0 then
        Move(P^, PWideChar(Text)^, N * SizeOf(WideChar));
      Result := True;
    finally
      GlobalUnlock(H);
    end;
  finally
    CloseClipboard;
  end;
end;

procedure BorionClipboardWriteText(const Text: WideString);
begin
  Abrir;
  try
    if not EmptyClipboard then
      RaiseLastOSError;
    GravarTexto(Text);
  finally
    CloseClipboard;
  end;
end;

procedure BorionClipboardWriteHtml(const Html: WideString; const AltText: WideString);
var
  S: string;
begin
  S := BorionCfHtml(Html) + #0;
  Abrir;
  try
    if not EmptyClipboard then
      RaiseLastOSError;
    Gravar(CF_HTML, PChar(S), Length(S));
    if AltText <> '' then
      GravarTexto(AltText);
  finally
    CloseClipboard;
  end;
end;

procedure BorionClipboardClear;
begin
  Abrir;
  try
    if not EmptyClipboard then
      RaiseLastOSError;
  finally
    CloseClipboard;
  end;
end;

{ TBorionClipboardPlugin }

constructor TBorionClipboardPlugin.Create(AAllowRead: Boolean);
begin
  inherited Create;
  FAllowRead := AAllowRead;
end;

function TBorionClipboardPlugin.Name: string;
begin
  Result := 'clipboard';
end;

procedure TBorionClipboardPlugin.Install;
begin
  Command('writeText', CmdWriteText);
  Command('readText', CmdReadText);
  Command('writeHtml', CmdWriteHtml);
  Command('clear', CmdClear);
end;

function TBorionClipboardPlugin.ArgTexto(Call: TBorionCall; const Nome: string;
  Obrigatorio: Boolean; out Texto: WideString): Boolean;
var
  V: TJsonValue;
begin
  Texto := '';
  V := Call.Arg(Nome);
  Result := (V <> nil) and not (V.ValueType in [jvNone, jvNull]);
  if not Result then
  begin
    if Obrigatorio then
      raise EBorionError.Create('INVALID_ARGS', Nome + ' é obrigatório');
    Exit;
  end;
  if (V.ValueType <> jvString) or not JsonLiteralToWide(V.AsString, Texto) then
    raise EBorionError.Create('INVALID_ARGS',
      Nome + ' deve ser um literal JSON só com ASCII (o @borion/api/clipboard gera)');
end;

procedure TBorionClipboardPlugin.CmdWriteText(Call: TBorionCall);
var
  Texto: WideString;
begin
  ArgTexto(Call, 'text', True, Texto);
  BorionClipboardWriteText(Texto);
end;

procedure TBorionClipboardPlugin.CmdReadText(Call: TBorionCall);
var
  Texto: WideString;
begin
  if not FAllowRead then
    raise EBorionError.Create('FORBIDDEN', 'a leitura da área de transferência está desligada (AllowRead)');
  if BorionClipboardReadText(Texto) then
    Call.Result.AsString := WideToJsonLiteral(Texto);  { senão: null }
end;

procedure TBorionClipboardPlugin.CmdWriteHtml(Call: TBorionCall);
var
  Html, Alt: WideString;
begin
  ArgTexto(Call, 'html', True, Html);
  ArgTexto(Call, 'altText', False, Alt);
  BorionClipboardWriteHtml(Html, Alt);
end;

procedure TBorionClipboardPlugin.CmdClear(Call: TBorionCall);
begin
  BorionClipboardClear;
end;

initialization
  CF_HTML := RegisterClipboardFormat('HTML Format');

finalization
  FreeAndNil(Dona);

end.
