unit TestBorionJson;

{ Testes da fronteira de JSON entre o JS (Unicode) e o Delphi 7 (ANSI).
  Os casos com acentos assumem a página de código do Windows em cp1252
  (português, inglês e demais idiomas da Europa Ocidental). }

interface

uses
  Windows, SysUtils, TestFramework, Jsons, BorionJson;

type
  TTestBorionJson = class(TTestCase)
  private
    procedure ExigirCp1252;
  published
    { JS -> Delphi }
    procedure TestWideToAnsi_AsciiInalterado;
    procedure TestWideToAnsi_EscapeLatin1ViraCaractere;
    procedure TestWideToAnsi_EscapeCp1252AltoViraCaractere;
    procedure TestWideToAnsi_EscapesBaixosMantidos;
    procedure TestWideToAnsi_BarraEscapadaNaoEhEscape;
    procedure TestWideToAnsi_CaractereLiteral;
    procedure TestWideToAnsi_ForaDaPaginaViraInterrogacao;
    procedure TestWideToAnsi_EscapeIncompletoMantido;
    { Delphi -> JS }
    procedure TestAnsiToWide_Cp1252Corrigido;
    procedure TestAnsiToWide_Latin1Mantido;
    procedure TestAnsiToWide_BarraEscapadaNaoEhEscape;
    procedure TestAnsiToWide_SemEscapes;
    procedure TestAnsiToWide_SaidaSoAscii;
    { utilitários e ida e volta }
    procedure TestJsonQuote;
    procedure TestIdaEVoltaComJsons;
  end;

implementation

function W(Code: Word): WideString;
begin
  Result := WideChar(Code);
end;

procedure TTestBorionJson.ExigirCp1252;
begin
  Check(GetACP = 1252, Format('estes testes assumem cp1252; a página do sistema é %d', [GetACP]));
end;

procedure TTestBorionJson.TestWideToAnsi_AsciiInalterado;
const
  J = '{"a":1,"b":[true,null],"c":"x y"}';
begin
  CheckEquals(J, WideJsonToAnsi(J));
end;

procedure TTestBorionJson.TestWideToAnsi_EscapeLatin1ViraCaractere;
begin
  ExigirCp1252;
  CheckEquals('"S'#227'o"', WideJsonToAnsi('"S\u00e3o"'));
end;

procedure TTestBorionJson.TestWideToAnsi_EscapeCp1252AltoViraCaractere;
begin
  ExigirCp1252;
  { a Jsons faria Chr($201C) e Chr($20AC), truncando para lixo }
  CheckEquals('"'#147'x'#148' '#128'"', WideJsonToAnsi('"\u201cx\u201d \u20ac"'));
end;

procedure TTestBorionJson.TestWideToAnsi_EscapesBaixosMantidos;
const
  J = '"\"\\\/\b\f\n\r\t\u0041\u001f"';
begin
  { escapes < $80 ficam para a Jsons decodificar }
  CheckEquals(J, WideJsonToAnsi(J));
end;

procedure TTestBorionJson.TestWideToAnsi_BarraEscapadaNaoEhEscape;
const
  J = '"C:\\u00e3"';  { barra literal seguida do texto u00e3, não um escape }
begin
  CheckEquals(J, WideJsonToAnsi(J));
end;

procedure TTestBorionJson.TestWideToAnsi_CaractereLiteral;
begin
  ExigirCp1252;
  { JSON.stringify não escapa acentos: eles chegam como caracteres }
  CheckEquals('"a'#231#227'o '#147'"', WideJsonToAnsi('"a' + W($E7) + W($E3) + 'o ' + W($201C) + '"'));
end;

procedure TTestBorionJson.TestWideToAnsi_ForaDaPaginaViraInterrogacao;
begin
  ExigirCp1252;
  CheckEquals('"?"', WideJsonToAnsi('"\u4e2d"'));
  CheckEquals('"?"', WideJsonToAnsi('"' + W($4E2D) + '"'));
end;

procedure TTestBorionJson.TestWideToAnsi_EscapeIncompletoMantido;
begin
  CheckEquals('"\u00"', WideJsonToAnsi('"\u00"'));
  CheckEquals('"\uzzzz"', WideJsonToAnsi('"\uzzzz"'));
end;

procedure TTestBorionJson.TestAnsiToWide_Cp1252Corrigido;
begin
  ExigirCp1252;
  { a Jsons escreve o byte ANSI: $93 (“) viraria U+0093, um caractere de controle }
  CheckEqualsWideString('"\u201cx\u201d \u20ac \u2014"', AnsiJsonToWide('"\u0093x\u0094 \u0080 \u0097"'));
end;

procedure TTestBorionJson.TestAnsiToWide_Latin1Mantido;
begin
  ExigirCp1252;
  CheckEqualsWideString('"S\u00e3o \u00e7"', AnsiJsonToWide('"S\u00e3o \u00e7"'));
end;

procedure TTestBorionJson.TestAnsiToWide_BarraEscapadaNaoEhEscape;
const
  J = '"x\\u0093"';
begin
  CheckEqualsWideString(J, AnsiJsonToWide(J));
end;

procedure TTestBorionJson.TestAnsiToWide_SemEscapes;
const
  J = '{"a":[1,2],"b":"\"q\""}';
begin
  CheckEqualsWideString(J, AnsiJsonToWide(J));
end;

procedure TTestBorionJson.TestAnsiToWide_SaidaSoAscii;
var
  O: TJsonObject;
  S: WideString;
  I: Integer;
begin
  O := TJsonObject.Create;
  try
    O.Put('t', 'a'#227#147#128#255);
    S := AnsiJsonToWide(O.Stringify);
  finally
    O.Free;
  end;
  for I := 1 to Length(S) do
    Check(Ord(S[I]) < 128, Format('caractere não-ASCII na posição %d', [I]));
end;

procedure TTestBorionJson.TestJsonQuote;
begin
  CheckEquals('"a\"b\\c"', JsonQuote('a"b\c'));
  CheckEquals('"x\ny"', JsonQuote('x'#10'y'));
  CheckEquals('""', JsonQuote(''));
end;

procedure TTestBorionJson.TestIdaEVoltaComJsons;
const
  Texto = 'S'#227'o Jo'#227'o '#147'aspas'#148' '#150' '#151' '#133' '#128' 1,00 \ "fim"';
var
  O, Lido: TJsonObject;
  NaRede: WideString;
begin
  ExigirCp1252;
  O := TJsonObject.Create;
  Lido := TJsonObject.Create;
  try
    O.Put('t', Texto);
    NaRede := AnsiJsonToWide(O.Stringify);        { Delphi -> JS }
    Lido.Parse(WideJsonToAnsi(NaRede));           { JS -> Delphi }
    CheckEquals(Texto, Lido['t'].AsString);
  finally
    Lido.Free;
    O.Free;
  end;
end;

initialization
  RegisterTest('BorionJson', TTestBorionJson.Suite);

end.
