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

end.
