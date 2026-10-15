unit BorionJson;

{
  Borion — Native Application Engine
  Fronteira de JSON entre o JavaScript (UTF-16) e o Delphi 7 (ANSI).

  A biblioteca Jsons (json4delphi) trabalha com string ANSI e tem dois
  comportamentos que quebram texto não-ASCII na ponte com o WebView2:

    - Stringify escreve todo caractere > #127 como \u00XX usando o BYTE ANSI.
      Certo para cp1252 $A0..$FF (coincide com Latin-1), errado para $80..$9F
      (€ ‚ „ … “ ” – — ™ ...), que viram caracteres de controle no JS.
    - Parse decodifica \uXXXX com Chr(), que trunca valores > $FF.

  Estas funções corrigem os dois lados. Caracteres fora da página de código do
  sistema (emoji, CJK...) viram '?' ao entrar no Delphi: o Delphi 7 não os
  representa em string.
}

interface

uses
  Windows, SysUtils, Jsons;

{ JS -> Delphi: JSON recebido do WebView2 -> string ANSI pronta para TJson*.Parse }
function WideJsonToAnsi(const Json: WideString): string;

{ Delphi -> JS: saída do Stringify -> JSON correto para o WebView2 }
function AnsiJsonToWide(const Json: string): WideString;

{ Texto como literal JSON entre aspas, ex.: JsonQuote('a"b') = '"a\"b"' }
function JsonQuote(const S: string): string;

{ --- JSON só com ASCII: Unicode completo pela ponte ---------------------------
  Uma string ANSI não guarda emoji nem caracteres fora da página de código. Para
  texto que precisa passar intacto (clipboard, store), o @borion/api manda JSON
  só com ASCII, com o resto como \uXXXX. O Delphi guarda esse texto como está ou
  o converte direto para WideString, sem passar pela página de código. }

{ WideString -> literal JSON só com ASCII, com aspas: 'é' -> '"\u00e9"' }
function WideToJsonLiteral(const W: WideString): string;
{ Literal JSON de string (com aspas) -> WideString. False se Lit não for um
  literal válido só com ASCII. }
function JsonLiteralToWide(const Lit: string; out W: WideString): Boolean;
{ True se S é exatamente um valor JSON válido só com ASCII (espaços nas pontas
  são aceitos). Profundidade máxima de 256 níveis. }
function IsAsciiJson(const S: string): Boolean;
{ Lê um valor JSON a partir de S[I] (pulando espaços antes) e devolve a posição
  logo depois dele; 0 se não houver um valor válido só com ASCII ali. }
function ScanJsonValue(const S: string; I: Integer): Integer;
{ Lê um literal de string a partir de S[I] (que deve ser '"'); 0 se inválido }
function ScanJsonString(const S: string; I: Integer): Integer;
{ Pula espaços JSON a partir de S[I] }
function SkipJsonSpace(const S: string; I: Integer): Integer;

implementation

function HexDigitValue(C: WideChar): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

{ Lê 4 dígitos hexadecimais a partir de S[Index]; -1 se inválido }
function ReadHex4(const S: WideString; Index: Integer): Integer;
var
  I, D: Integer;
begin
  Result := -1;
  if Index + 3 > Length(S) then
    Exit;
  Result := 0;
  for I := Index to Index + 3 do
  begin
    D := HexDigitValue(S[I]);
    if D < 0 then
    begin
      Result := -1;
      Exit;
    end;
    Result := Result * 16 + D;
  end;
end;

function WideJsonToAnsi(const Json: WideString): string;
var
  W: WideString;
  I, J, N, Code: Integer;
begin
  { Troca os escapes \uXXXX >= $80 pelo próprio caractere; os demais escapes
    (\", \\, \n, A...) passam intactos para a Jsons tratar. }
  N := Length(Json);
  SetLength(W, N);
  I := 1;
  J := 0;
  while I <= N do
  begin
    if (Json[I] = '\') and (I < N) then
    begin
      if Json[I + 1] = 'u' then
      begin
        Code := ReadHex4(Json, I + 2);
        if Code >= $80 then
        begin
          Inc(J);
          W[J] := WideChar(Code);
          Inc(I, 6);
          Continue;
        end;
      end;
      { escape comum: copia a barra e o caractere seguinte juntos }
      Inc(J);
      W[J] := Json[I];
      Inc(J);
      W[J] := Json[I + 1];
      Inc(I, 2);
      Continue;
    end;
    Inc(J);
    W[J] := Json[I];
    Inc(I);
  end;
  SetLength(W, J);
  Result := W;  { conversão pela página de código do sistema }
end;

function AnsiJsonToWide(const Json: string): WideString;
var
  S, Hex: string;
  I, N, Code: Integer;
  Ch: WideString;
begin
  { O Stringify só gera ASCII; corrige os \u00XX (XX >= $80), que carregam
    um byte ANSI, para o code point Unicode real. \u00XX e \uXXXX têm o
    mesmo tamanho, então a troca é feita no lugar. }
  S := Json;
  UniqueString(S);
  N := Length(S);
  I := 1;
  while I <= N do
  begin
    if (S[I] = '\') and (I < N) then
    begin
      if S[I + 1] = 'u' then
      begin
        Code := ReadHex4(WideString(Copy(S, I + 2, 4)), 1);
        if (Code >= $80) and (Code <= $FF) then
        begin
          Ch := WideString(AnsiChar(Code));  { byte ANSI -> Unicode }
          if Ch <> '' then
          begin
            Hex := LowerCase(IntToHex(Ord(Ch[1]), 4));
            Move(Hex[1], S[I + 2], 4);
          end;
        end;
        Inc(I, 6);
        Continue;
      end;
      Inc(I, 2);  { escape comum: pula a barra e o caractere seguinte }
      Continue;
    end;
    Inc(I);
  end;
  Result := S;
end;

function JsonQuote(const S: string): string;
var
  V: TJsonValue;
begin
  V := TJsonValue.Create(nil);
  try
    V.AsString := S;
    Result := V.Stringify;
  finally
    V.Free;
  end;
end;

{ --- JSON só com ASCII ------------------------------------------------------- }

const
  PROFUNDIDADE_MAXIMA = 256;

function WideToJsonLiteral(const W: WideString): string;
var
  I: Integer;
  C: Word;
begin
  Result := '"';
  for I := 1 to Length(W) do
  begin
    C := Ord(W[I]);
    if C = Ord('"') then
      Result := Result + '\"'
    else if C = Ord('\') then
      Result := Result + '\\'
    else if (C >= 32) and (C <= 126) then
      Result := Result + Chr(C)
    else
      case C of
        8: Result := Result + '\b';
        9: Result := Result + '\t';
        10: Result := Result + '\n';
        12: Result := Result + '\f';
        13: Result := Result + '\r';
      else
        Result := Result + '\u' + LowerCase(IntToHex(C, 4));
      end;
  end;
  Result := Result + '"';
end;

function SkipJsonSpace(const S: string; I: Integer): Integer;
begin
  while (I <= Length(S)) and (S[I] in [' ', #9, #10, #13]) do
    Inc(I);
  Result := I;
end;

function ScanJsonString(const S: string; I: Integer): Integer;
var
  N: Integer;
begin
  Result := 0;
  N := Length(S);
  if (I > N) or (S[I] <> '"') then
    Exit;
  Inc(I);
  while I <= N do
  begin
    case S[I] of
      '"':
        begin
          Result := I + 1;
          Exit;
        end;
      '\':
        begin
          if I = N then
            Exit;
          case S[I + 1] of
            '"', '\', '/', 'b', 'f', 'n', 'r', 't': Inc(I, 2);
            'u':
              begin
                if ReadHex4(WideString(Copy(S, I + 2, 4)), 1) < 0 then
                  Exit;
                Inc(I, 6);
              end;
          else
            Exit;
          end;
        end;
      #0..#31, #127..#255: Exit;  { controle cru e não-ASCII não são aceitos }
    else
      Inc(I);
    end;
  end;
end;

function ScanDigitos(const S: string; I: Integer): Integer;
begin
  while (I <= Length(S)) and (S[I] in ['0'..'9']) do
    Inc(I);
  Result := I;
end;

function ScanNumero(const S: string; I: Integer): Integer;
var
  J: Integer;
begin
  Result := 0;
  if (I <= Length(S)) and (S[I] = '-') then
    Inc(I);
  if I > Length(S) then
    Exit;
  if S[I] = '0' then
    Inc(I)
  else if S[I] in ['1'..'9'] then
    I := ScanDigitos(S, I)
  else
    Exit;
  if (I <= Length(S)) and (S[I] = '.') then
  begin
    J := ScanDigitos(S, I + 1);
    if J = I + 1 then
      Exit;
    I := J;
  end;
  if (I <= Length(S)) and (S[I] in ['e', 'E']) then
  begin
    Inc(I);
    if (I <= Length(S)) and (S[I] in ['+', '-']) then
      Inc(I);
    J := ScanDigitos(S, I);
    if J = I then
      Exit;
    I := J;
  end;
  Result := I;
end;

function ScanValor(const S: string; I, Profundidade: Integer): Integer;

  function Literal(const Palavra: string): Integer;
  begin
    if Copy(S, I, Length(Palavra)) = Palavra then
      Result := I + Length(Palavra)
    else
      Result := 0;
  end;

begin
  Result := 0;
  if Profundidade > PROFUNDIDADE_MAXIMA then
    Exit;
  I := SkipJsonSpace(S, I);
  if I > Length(S) then
    Exit;
  case S[I] of
    '"': Result := ScanJsonString(S, I);
    '-', '0'..'9': Result := ScanNumero(S, I);
    't': Result := Literal('true');
    'f': Result := Literal('false');
    'n': Result := Literal('null');
    '[':
      begin
        I := SkipJsonSpace(S, I + 1);
        if (I <= Length(S)) and (S[I] = ']') then
        begin
          Result := I + 1;
          Exit;
        end;
        while True do
        begin
          I := ScanValor(S, I, Profundidade + 1);
          if I = 0 then
            Exit;
          I := SkipJsonSpace(S, I);
          if I > Length(S) then
            Exit;
          if S[I] = ']' then
          begin
            Result := I + 1;
            Exit;
          end;
          if S[I] <> ',' then
            Exit;
          Inc(I);
        end;
      end;
    '{':
      begin
        I := SkipJsonSpace(S, I + 1);
        if (I <= Length(S)) and (S[I] = '}') then
        begin
          Result := I + 1;
          Exit;
        end;
        while True do
        begin
          I := ScanJsonString(S, SkipJsonSpace(S, I));
          if I = 0 then
            Exit;
          I := SkipJsonSpace(S, I);
          if (I > Length(S)) or (S[I] <> ':') then
            Exit;
          I := ScanValor(S, I + 1, Profundidade + 1);
          if I = 0 then
            Exit;
          I := SkipJsonSpace(S, I);
          if I > Length(S) then
            Exit;
          if S[I] = '}' then
          begin
            Result := I + 1;
            Exit;
          end;
          if S[I] <> ',' then
            Exit;
          Inc(I);
        end;
      end;
  end;
end;

function ScanJsonValue(const S: string; I: Integer): Integer;
begin
  Result := ScanValor(S, I, 0);
end;

function IsAsciiJson(const S: string): Boolean;
var
  Fim: Integer;
begin
  Fim := ScanJsonValue(S, 1);
  Result := (Fim > 0) and (SkipJsonSpace(S, Fim) > Length(S));
end;

function JsonLiteralToWide(const Lit: string; out W: WideString): Boolean;
var
  I, J, N: Integer;
begin
  W := '';
  N := Length(Lit);
  Result := (N >= 2) and (ScanJsonString(Lit, 1) = N + 1);
  if not Result then
    Exit;
  SetLength(W, N);  { nunca maior que o literal }
  J := 0;
  I := 2;
  while I < N do
  begin
    Inc(J);
    if Lit[I] = '\' then
    begin
      case Lit[I + 1] of
        'b': W[J] := #8;
        't': W[J] := #9;
        'n': W[J] := #10;
        'f': W[J] := #12;
        'r': W[J] := #13;
        'u':
          begin
            W[J] := WideChar(ReadHex4(WideString(Copy(Lit, I + 2, 4)), 1));
            Inc(I, 4);
          end;
      else
        W[J] := WideChar(Ord(Lit[I + 1]));  { \" \\ \/ }
      end;
      Inc(I, 2);
    end
    else
    begin
      W[J] := WideChar(Ord(Lit[I]));
      Inc(I);
    end;
  end;
  SetLength(W, J);
end;

end.
