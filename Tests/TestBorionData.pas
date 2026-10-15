unit TestBorionData;

{ Testes do JSON só com ASCII (BorionJson) e dos plugins clipboard e store.
  Os testes do clipboard usam a área de transferência de verdade: guardam o
  texto que estava nela e o devolvem no fim. }

interface

uses
  Windows, SysUtils, Classes, TestFramework, Jsons,
  BorionJson, BorionIpc, BorionClipboard, BorionStore, TestBorionPlugins;

type
  TTestJsonAscii = class(TTestCase)
  published
    procedure TestLiteral;
    procedure TestLiteralIdaEVolta;
    procedure TestLiteralInvalido;
    procedure TestIsAsciiJsonValidos;
    procedure TestIsAsciiJsonInvalidos;
  end;

  TTestBorionClipboard = class(TTesteComIpc)
  private
    FPlugin: TBorionClipboardPlugin;
    FTinha: Boolean;
    FAntes: WideString;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTextoIdaEVolta;
    procedure TestSemTextoDevolveNull;
    procedure TestHtml;
    procedure TestCfHtmlPosicoes;
    procedure TestArgsInvalidos;
    procedure TestLeituraDesligada;
  end;

  TTestBorionStore = class(TTesteComIpc)
  private
    FDir: string;
    FStore: TBorionStorePlugin;
    function Arquivo(const Nome: string): string;
    function Ler(const Nome: string): string;
    procedure Criar(const Nome, Conteudo: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSetGetHas;
    procedure TestPersisteEmArquivo;
    procedure TestUnicodeEChaveCanonica;
    procedure TestValoresInvalidos;
    procedure TestNomesDeStore;
    procedure TestDeleteClearEntries;
    procedure TestEventos;
    procedure TestArquivoCorrompido;
    procedure TestArquivoEditadoAMao;
    procedure TestSemAutoSave;
    procedure TestApiDelphi;
  end;

implementation

const
  { 'olá ' + emoji (U+1F600, par substituto) }
  OLA_LIT = '"ol\u00e1 \ud83d\ude00"';
  { o mesmo literal dentro de um argumento JSON (barras dobradas, aspas escapadas) }
  OLA_ARG = '"\"ol\\u00e1 \\ud83d\\ude00\""';

function Ola: WideString;
begin
  Result := WideString('ol') + WideChar($E1) + ' ' + WideChar($D83D) + WideChar($DE00);
end;

{ TTestJsonAscii }

procedure TTestJsonAscii.TestLiteral;
begin
  CheckEquals('"a\"b\\c\n\t"', WideToJsonLiteral(WideString('a"b\c') + #10#9));
  CheckEquals(OLA_LIT, WideToJsonLiteral(Ola));
  CheckEquals('"\u0001\u007f"', WideToJsonLiteral(WideString(#1#127)));
  CheckEquals('""', WideToJsonLiteral(''));
end;

procedure TTestJsonAscii.TestLiteralIdaEVolta;
var
  W: WideString;
begin
  Check(JsonLiteralToWide(OLA_LIT, W));
  Check(W = Ola, 'emoji e acento');
  Check(JsonLiteralToWide('"a\"b\\c\/\n\u00E9"', W));
  Check(W = WideString('a"b\c/') + #10 + WideChar($E9));
  Check(JsonLiteralToWide('""', W));
  CheckEquals(0, Length(W));
end;

procedure TTestJsonAscii.TestLiteralInvalido;
var
  W: WideString;
begin
  Check(not JsonLiteralToWide('abc', W), 'sem aspas');
  Check(not JsonLiteralToWide('"abc', W), 'sem aspas no fim');
  Check(not JsonLiteralToWide('"a"b"', W), 'aspas no meio');
  Check(not JsonLiteralToWide('"' + #233 + '"', W), 'não-ASCII cru');
  Check(not JsonLiteralToWide('"a' + #10 + '"', W), 'controle cru');
  Check(not JsonLiteralToWide('"\x"', W), 'escape desconhecido');
  Check(not JsonLiteralToWide('"\u12"', W), '\u curto');
  Check(not JsonLiteralToWide('', W), 'vazio');
end;

procedure TTestJsonAscii.TestIsAsciiJsonValidos;
const
  VALIDOS: array[0..10] of string = ('null', 'true', 'false', ' 1.5e-3 ', '-0', '"x"',
    '[]', '{}', '[1, "a", null]', '{"a":[1,{"b":null}],"c":"\u00e9"}', '  {"x" : { } }  ');
var
  I: Integer;
begin
  for I := Low(VALIDOS) to High(VALIDOS) do
    Check(IsAsciiJson(VALIDOS[I]), VALIDOS[I]);
end;

procedure TTestJsonAscii.TestIsAsciiJsonInvalidos;
const
  INVALIDOS: array[0..13] of string = ('', '   ', '01', '1.', '.5', '{a:1}', '[1,]',
    '{"a":1,}', '"' + #233 + '"', 'nul', '1 2', '{"a"}', '[1}', '"\q"');
var
  I: Integer;
begin
  for I := Low(INVALIDOS) to High(INVALIDOS) do
    Check(not IsAsciiJson(INVALIDOS[I]), INVALIDOS[I]);
  { profundidade: 300 níveis passam do limite, 200 não }
  Check(not IsAsciiJson(StringOfChar('[', 300) + StringOfChar(']', 300)), 'profundo demais');
  Check(IsAsciiJson(StringOfChar('[', 200) + StringOfChar(']', 200)), '200 níveis');
end;

{ TTestBorionClipboard }

procedure TTestBorionClipboard.SetUp;
begin
  inherited;
  FTinha := BorionClipboardReadText(FAntes);
  FPlugin := TBorionClipboardPlugin(FIpc.AddPlugin(TBorionClipboardPlugin.Create));
end;

procedure TTestBorionClipboard.TearDown;
begin
  if FTinha then
    BorionClipboardWriteText(FAntes)
  else
    BorionClipboardClear;
  inherited;
end;

procedure TTestBorionClipboard.TestTextoIdaEVolta;
var
  W: WideString;
begin
  CheckEquals('null', Ok('clipboard:writeText', '{"text":' + OLA_ARG + '}'));
  Check(BorionClipboardReadText(W));
  Check(W = Ola, 'o Windows recebeu o emoji intacto');
  CheckEquals(OLA_ARG, Ok('clipboard:readText', ''));
  { texto gravado por outro programa (aqui, pelo Delphi) }
  BorionClipboardWriteText(WideString('linha 1') + #13#10 + 'linha 2');
  CheckEquals('"\"linha 1\\r\\nlinha 2\""', Ok('clipboard:readText', ''));
end;

procedure TTestBorionClipboard.TestSemTextoDevolveNull;
begin
  Ok('clipboard:clear', '');
  CheckEquals('null', Ok('clipboard:readText', ''));
end;

procedure TTestBorionClipboard.TestHtml;
var
  W: WideString;
  CF: UINT;
begin
  CF := RegisterClipboardFormat('HTML Format');
  Ok('clipboard:writeHtml', '{"html":"\"<b>ol\\u00e1</b>\"","altText":"\"ol\\u00e1\""}');
  Check(IsClipboardFormatAvailable(CF), 'HTML Format');
  Check(BorionClipboardReadText(W));
  Check(W = WideString('ol') + WideChar($E1), 'texto alternativo');
  { sem altText: só o HTML }
  Ok('clipboard:writeHtml', '{"html":"\"<i>x</i>\""}');
  Check(IsClipboardFormatAvailable(CF));
  CheckEquals('null', Ok('clipboard:readText', ''));
end;

procedure TTestBorionClipboard.TestCfHtmlPosicoes;
var
  S: string;

  function Numero(const Campo: string): Integer;
  var
    P: Integer;
  begin
    P := Pos(Campo + ':', S);
    Check(P > 0, Campo);
    Result := StrToInt(Copy(S, P + Length(Campo) + 1, 10));
  end;

begin
  S := BorionCfHtml(WideString('<b>') + WideChar($E9) + '</b>');
  CheckEquals('<html>', Copy(S, Numero('StartHTML') + 1, 6));
  CheckEquals('<b>'#$C3#$A9'</b>', Copy(S, Numero('StartFragment') + 1,
    Numero('EndFragment') - Numero('StartFragment')), 'fragmento em UTF-8');
  CheckEquals(Length(S), Numero('EndHTML'));
end;

procedure TTestBorionClipboard.TestArgsInvalidos;
begin
  CheckEquals('INVALID_ARGS', Erro('clipboard:writeText', '{}'));
  CheckEquals('INVALID_ARGS', Erro('clipboard:writeText', '{"text":"sem aspas"}'));
  CheckEquals('INVALID_ARGS', Erro('clipboard:writeText', '{"text":5}'));
  CheckEquals('INVALID_ARGS', Erro('clipboard:writeHtml', '{"altText":"\"x\""}'));
end;

procedure TTestBorionClipboard.TestLeituraDesligada;
begin
  FPlugin.AllowRead := False;
  CheckEquals('FORBIDDEN', Erro('clipboard:readText', ''));
  Ok('clipboard:writeText', '{"text":"\"escrever continua valendo\""}');
end;

{ TTestBorionStore }

procedure TTestBorionStore.SetUp;
var
  R: TSearchRec;
begin
  inherited;
  FDir := ExtractFilePath(ParamStr(0)) + 'out\store';
  ForceDirectories(FDir);
  if FindFirst(FDir + '\*', faAnyFile, R) = 0 then
  begin
    repeat
      if (R.Attr and faDirectory) = 0 then
        DeleteFile(FDir + '\' + R.Name);
    until FindNext(R) <> 0;
    FindClose(R);
  end;
  FStore := TBorionStorePlugin(FIpc.AddPlugin(TBorionStorePlugin.Create('ignorado')));
  FStore.Dir := FDir;
end;

procedure TTestBorionStore.TearDown;
begin
  inherited;
end;

function TTestBorionStore.Arquivo(const Nome: string): string;
begin
  Result := FDir + '\' + Nome;
end;

function TTestBorionStore.Ler(const Nome: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(Arquivo(Nome), fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

procedure TTestBorionStore.Criar(const Nome, Conteudo: string);
var
  F: TFileStream;
begin
  F := TFileStream.Create(Arquivo(Nome), fmCreate);
  try
    if Conteudo <> '' then
      F.WriteBuffer(Conteudo[1], Length(Conteudo));
  finally
    F.Free;
  end;
end;

procedure TTestBorionStore.TestSetGetHas;
begin
  CheckEquals('0', Ok('store:load', '{"store":"settings.json"}'));
  Ok('store:set', '{"store":"settings.json","key":"\"tema\"","value":"\"escuro\""}');
  Ok('store:set', '{"store":"settings","key":"\"janela\"","value":"{\"w\":800,\"h\":600}"}');
  CheckEquals('"\"escuro\""', Ok('store:get', '{"store":"settings.json","key":"\"tema\""}'));
  CheckEquals('"{\"w\":800,\"h\":600}"', Ok('store:get', '{"store":"Settings.JSON","key":"\"janela\""}'));
  CheckEquals('null', Ok('store:get', '{"store":"settings","key":"\"nada\""}'));
  CheckEquals('true', Ok('store:has', '{"store":"settings","key":"\"tema\""}'));
  CheckEquals('false', Ok('store:has', '{"store":"settings","key":"\"nada\""}'));
  { o valor null é diferente de "não existe" }
  Ok('store:set', '{"store":"settings","key":"\"vazio\"","value":"null"}');
  CheckEquals('"null"', Ok('store:get', '{"store":"settings","key":"\"vazio\""}'));
  CheckEquals('3', Ok('store:load', '{"store":"settings"}'));
end;

procedure TTestBorionStore.TestPersisteEmArquivo;
var
  Outro: TBorionStorePlugin;
begin
  Ok('store:set', '{"store":"prefs","key":"\"tema\"","value":"\"escuro\""}');
  Ok('store:set', '{"store":"prefs","key":"\"zoom\"","value":"1.25"}');
  CheckEquals('{'#13#10'  "tema": "escuro",'#13#10'  "zoom": 1.25'#13#10'}'#13#10, Ler('prefs.json'));
  Check(not FileExists(Arquivo('prefs.json.tmp')), 'temporário removido');
  { outra instância (como numa nova execução do app) lê o mesmo arquivo }
  Outro := TBorionStorePlugin.Create('ignorado');
  try
    Outro.Dir := FDir;
    Check(Outro.ReadString('prefs', 'tema') = 'escuro');
  finally
    Outro.Free;
  end;
end;

procedure TTestBorionStore.TestUnicodeEChaveCanonica;
begin
  Ok('store:set', '{"store":"u","key":"\"chave \\u00e9\"","value":' + OLA_ARG + '}');
  { o mesmo texto com hexa maiúsculo é a mesma chave }
  CheckEquals(OLA_ARG, Ok('store:get', '{"store":"u","key":"\"chave \\u00E9\""}'));
  { o arquivo é ASCII: nada passou pela página de código }
  CheckEquals('{'#13#10'  "chave \u00e9": "ol\u00e1 \ud83d\ude00"'#13#10'}'#13#10, Ler('u.json'));
  Check(FStore.ReadString('u', 'chave ' + #233) = Ola, 'API Delphi com chave ANSI');
end;

procedure TTestBorionStore.TestValoresInvalidos;
begin
  CheckEquals('INVALID_ARGS', Erro('store:set', '{"store":"s","key":"\"a\"","value":"{a:1}"}'));
  CheckEquals('INVALID_ARGS', Erro('store:set', '{"store":"s","key":"\"a\"","value":"1 2"}'));
  CheckEquals('INVALID_ARGS', Erro('store:set', '{"store":"s","key":"\"a\"","value":5}'));
  CheckEquals('INVALID_ARGS', Erro('store:set', '{"store":"s","key":"\"a\""}'));
  CheckEquals('INVALID_ARGS', Erro('store:set', '{"store":"s","key":"sem aspas","value":"1"}'));
  CheckEquals('INVALID_ARGS', Erro('store:get', '{"store":"s"}'));
  CheckEquals('0', Ok('store:load', '{"store":"s"}'));
  Check(not FileExists(Arquivo('s.json')), 'nada foi gravado');
end;

procedure TTestBorionStore.TestNomesDeStore;
const
  INVALIDOS: array[0..7] of string = ('', '..', '.oculto', 'a/b', 'a\\b', 'c:x', '..\\fora', 'com espaço');
var
  I: Integer;
begin
  for I := Low(INVALIDOS) to High(INVALIDOS) do
    CheckEquals('INVALID_STORE', Erro('store:load', '{"store":"' + INVALIDOS[I] + '"}'), INVALIDOS[I]);
  CheckEquals('INVALID_STORE', Erro('store:load', '{}'));
  CheckEquals('INVALID_STORE', Erro('store:load', '{"store":"' + StringOfChar('a', 70) + '"}'));
  CheckEquals('settings.json', BorionStoreFileName('Settings'));
  CheckEquals('dados.v2.json', BorionStoreFileName('dados.v2.JSON'));
end;

procedure TTestBorionStore.TestDeleteClearEntries;
begin
  Ok('store:set', '{"store":"e","key":"\"b\"","value":"2"}');
  Ok('store:set', '{"store":"e","key":"\"a\"","value":"1"}');
  Ok('store:set', '{"store":"e","key":"\"c\"","value":"3"}');
  Ok('store:set', '{"store":"e","key":"\"b\"","value":"20"}');  { mantém a posição }
  CheckEquals('[["\"b\"","20"],["\"a\"","1"],["\"c\"","3"]]', Ok('store:entries', '{"store":"e"}'));
  CheckEquals('true', Ok('store:delete', '{"store":"e","key":"\"a\""}'));
  CheckEquals('false', Ok('store:delete', '{"store":"e","key":"\"a\""}'));
  CheckEquals('[["\"b\"","20"],["\"c\"","3"]]', Ok('store:entries', '{"store":"e"}'));
  Ok('store:clear', '{"store":"e"}');
  CheckEquals('[]', Ok('store:entries', '{"store":"e"}'));
  CheckEquals('{}'#13#10, Ler('e.json'));
end;

procedure TTestBorionStore.TestEventos;
begin
  FPosts.Clear;
  Ok('store:set', '{"store":"ev","key":"\"x\"","value":"[1,2]"}');
  Ok('store:delete', '{"store":"ev","key":"\"x\""}');
  Ok('store:set', '{"store":"ev","key":"\"y\"","value":"true"}');
  Ok('store:clear', '{"store":"ev"}');
  { cada invoke posta a resposta; os eventos vêm antes dela }
  CheckEquals('{"__borion":1,"kind":"event","event":"store:change","payload":' +
    '{"store":"ev.json","key":"\"x\"","value":"[1,2]"}}', FPosts[0]);
  CheckEquals('{"__borion":1,"kind":"event","event":"store:change","payload":' +
    '{"store":"ev.json","key":"\"x\"","value":null}}', FPosts[2]);
  Check(Pos('"key":"\"y\"","value":null', FPosts[6]) > 0, 'clear apaga cada chave: ' + FPosts[6]);
  { alterações feitas pelo Delphi também avisam a página }
  FPosts.Clear;
  FStore.WriteString('ev', 'z', 'zz');
  CheckEquals(1, FPosts.Count);
  Check(Pos('"key":"\"z\"","value":"\"zz\""', FPosts[0]) > 0, FPosts[0]);
end;

procedure TTestBorionStore.TestArquivoCorrompido;
begin
  Criar('ruim.json', '{"a": 1, lixo');
  CheckEquals('0', Ok('store:load', '{"store":"ruim"}'));
  Check(FileExists(Arquivo('ruim.json.corrupt')), 'o original foi guardado');
  CheckEquals('{"a": 1, lixo', Ler('ruim.json.corrupt'));
  Ok('store:set', '{"store":"ruim","key":"\"a\"","value":"2"}');
  CheckEquals('"2"', Ok('store:get', '{"store":"ruim","key":"\"a\""}'));
  { outros formatos que não são um objeto }
  Criar('lista.json', '[1,2]');
  CheckEquals('0', Ok('store:load', '{"store":"lista"}'));
  Check(FileExists(Arquivo('lista.json.corrupt')));
end;

procedure TTestBorionStore.TestArquivoEditadoAMao;
begin
  { UTF-8 com BOM, acento cru, espaços e chave repetida (vale a última) }
  Criar('mao.json', #$EF#$BB#$BF'{ "nome" : "Jos'#$C3#$A9'", "n": [1, 2],'#10'  "nome": "Jo'#$C3#$A3'o" }');
  CheckEquals('2', Ok('store:load', '{"store":"mao"}'));
  CheckEquals('"\"Jo\\u00e3o\""', Ok('store:get', '{"store":"mao","key":"\"nome\""}'));
  CheckEquals('"[1, 2]"', Ok('store:get', '{"store":"mao","key":"\"n\""}'));
  Check(not FileExists(Arquivo('mao.json.corrupt')));
end;

procedure TTestBorionStore.TestSemAutoSave;
begin
  FStore.AutoSave := False;
  Ok('store:set', '{"store":"lento","key":"\"a\"","value":"1"}');
  Check(not FileExists(Arquivo('lento.json')), 'ainda não gravou');
  Ok('store:save', '{"store":"lento"}');
  Check(FileExists(Arquivo('lento.json')));
  Ok('store:set', '{"store":"lento","key":"\"a\"","value":"2"}');
  { reload descarta o que não foi gravado }
  CheckEquals('1', Ok('store:reload', '{"store":"lento"}'));
  CheckEquals('"1"', Ok('store:get', '{"store":"lento","key":"\"a\""}'));
  { pendências são gravadas ao destruir o plugin }
  Ok('store:set', '{"store":"lento","key":"\"b\"","value":"3"}');
  FreeAndNil(FIpc);  { libera os plugins }
  Check(Pos('"b": 3', Ler('lento.json')) > 0, Ler('lento.json'));
  FIpc := TBorionIpc.Create(nil, nil);  { para o TearDown }
end;

procedure TTestBorionStore.TestApiDelphi;
var
  Json: string;
begin
  FStore.WriteJson('api', 'lista', '[1, 2, 3]');
  FStore.WriteString('api', 'nome', Ola);
  Check(FStore.ReadJson('api', 'lista', Json));
  CheckEquals('[1, 2, 3]', Json);
  Check(FStore.ReadString('api', 'nome') = Ola);
  CheckEquals('padrão', FStore.ReadString('api', 'nada', 'padrão'));
  Check(FStore.Delete('api', 'nome'));
  Check(not FStore.ReadJson('api', 'nome', Json));
  try
    FStore.WriteJson('api', 'x', 'não é json');
    Fail('devia recusar');
  except
    on E: EBorionError do
      CheckEquals('INVALID_ARGS', E.Code);
  end;
  CheckEquals('"[1, 2, 3]"', Ok('store:get', '{"store":"api","key":"\"lista\""}'));
end;

initialization
  RegisterTest('BorionJson', TTestJsonAscii.Suite);
  RegisterTest('Plugins', TTestBorionClipboard.Suite);
  RegisterTest('Plugins', TTestBorionStore.Suite);

end.
