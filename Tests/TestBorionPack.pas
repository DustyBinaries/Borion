unit TestBorionPack;

{ Testes do pacote de assets (BorionPack) e do servidor (BorionAssets). Os
  arquivos de origem são criados numa pasta temporária ao lado do exe. }

interface

uses
  Windows, SysUtils, Classes, TestFramework, WebView2Browser, BorionPack, BorionAssets;

type
  TTestBorionPack = class(TTestCase)
  private
    FPasta: string;
    function Arquivo(const Relativo: string): string;
    function Empacotar(Comprimir: Boolean): TMemoryStream;
    function Abrir(Comprimir: Boolean = True): TBorionPack;
    function Extrair(Pack: TBorionPack; const Caminho: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEmpacotaERelTodosOsArquivos;
    procedure TestComprimeTexto;
    procedure TestNaoComprimeFormatoJaComprimido;
    procedure TestSemCompressao;
    procedure TestArquivoVazio;
    procedure TestCaminhosComBarraEUtf8;
    procedure TestFindSemDiferenciarMaiusculas;
    procedure TestFindInexistente;
    procedure TestPacoteDeterministico;
    procedure TestPacoteInvalidoLevantaErro;
    procedure TestPacoteTruncadoLevantaErro;
    procedure TestResIdaEVolta;
    procedure TestUrlDecode;
  end;

  TTestBorionAssets = class(TTestCase)
  private
    FPasta: string;
    FAssets: TBorionAssets;
    FResp: TWV2WebResourceResponse;
    function Corpo: string;
    function Header(const Nome: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestRaizServeIndex;
    procedure TestArquivoComumComMime;
    procedure TestCaminhoCodificado;
    procedure TestSpaFallback;
    procedure TestSpaFallbackDesligado;
    procedure TestInexistenteComExtensao404;
    procedure TestHeadersPadrao;
    procedure TestCspECacheConfiguraveis;
    procedure TestSemPacote404;
    procedure TestMimeTypes;
    procedure TestDevUrlFrom;
    procedure TestStartUrlEOrigem;
  end;

implementation

const
  INDEX_HTML = '<!doctype html><title>t</title><div id="app"></div>';

function TextoRepetitivo: string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to 200 do
    Result := Result + 'function f' + IntToStr(I) + '() { return "borion"; }'#13#10;
end;

function BytesAleatorios(N: Integer): string;
var
  I: Integer;
begin
  RandSeed := 42;
  SetLength(Result, N);
  for I := 1 to N do
    Result[I] := Chr(Random(256));
end;

procedure ApagarPasta(const Pasta: string);
var
  SR: TSearchRec;
begin
  if FindFirst(IncludeTrailingPathDelimiter(Pasta) + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      if SR.Attr and faDirectory <> 0 then
        ApagarPasta(IncludeTrailingPathDelimiter(Pasta) + SR.Name)
      else
        DeleteFile(IncludeTrailingPathDelimiter(Pasta) + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  RemoveDir(Pasta);
end;

procedure CriarArquivo(const Pasta, Relativo, Conteudo: string);
var
  F: TFileStream;
  Nome: string;
begin
  Nome := IncludeTrailingPathDelimiter(Pasta) + Relativo;
  ForceDirectories(ExtractFilePath(Nome));
  F := TFileStream.Create(Nome, fmCreate);
  try
    if Conteudo <> '' then
      F.WriteBuffer(Conteudo[1], Length(Conteudo));
  finally
    F.Free;
  end;
end;

procedure CriarFrontend(const Pasta: string);
begin
  ApagarPasta(Pasta);
  CriarArquivo(Pasta, 'index.html', INDEX_HTML);
  CriarArquivo(Pasta, 'assets\app.js', TextoRepetitivo);
  CriarArquivo(Pasta, 'assets\dados.json', '{"a":1}');
  CriarArquivo(Pasta, 'img\logo.png', BytesAleatorios(4096));
  CriarArquivo(Pasta, 'vazio.txt', '');
  CriarArquivo(Pasta, 'acentuação.txt', 'conteúdo');
end;

function PastaTemp(const Nome: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'out\' + Nome;
end;

function StreamComoTexto(S: TStream): string;
begin
  SetLength(Result, S.Size);
  S.Position := 0;
  if S.Size > 0 then
    S.ReadBuffer(Result[1], S.Size);
end;

{ TTestBorionPack }

procedure TTestBorionPack.SetUp;
begin
  FPasta := PastaTemp('pack-src');
  CriarFrontend(FPasta);
end;

procedure TTestBorionPack.TearDown;
begin
  ApagarPasta(FPasta);
end;

function TTestBorionPack.Arquivo(const Relativo: string): string;
var
  F: TFileStream;
begin
  F := TFileStream.Create(IncludeTrailingPathDelimiter(FPasta) + Relativo, fmOpenRead);
  try
    Result := StreamComoTexto(F);
  finally
    F.Free;
  end;
end;

function TTestBorionPack.Empacotar(Comprimir: Boolean): TMemoryStream;
var
  Op: TBorionPackOptions;
begin
  Op.Compress := Comprimir;
  Result := TMemoryStream.Create;
  BorionPackFolder(FPasta, Result, Op);
end;

function TTestBorionPack.Abrir(Comprimir: Boolean): TBorionPack;
var
  M: TMemoryStream;
begin
  M := Empacotar(Comprimir);
  try
    Result := TBorionPack.FromStream(M);
  finally
    M.Free;
  end;
end;

function TTestBorionPack.Extrair(Pack: TBorionPack; const Caminho: string): string;
var
  I: Integer;
  M: TMemoryStream;
begin
  I := Pack.Find(Caminho);
  Check(I >= 0, 'não está no pacote: ' + Caminho);
  M := TMemoryStream.Create;
  try
    Pack.ExtractTo(I, M);
    Result := StreamComoTexto(M);
  finally
    M.Free;
  end;
end;

procedure TTestBorionPack.TestEmpacotaERelTodosOsArquivos;
var
  P: TBorionPack;
begin
  P := Abrir;
  try
    CheckEquals(6, P.Count);
    CheckEquals(INDEX_HTML, Extrair(P, 'index.html'));
    CheckEquals(Arquivo('assets\app.js'), Extrair(P, 'assets/app.js'));
    CheckEquals('{"a":1}', Extrair(P, 'assets/dados.json'));
    CheckEquals(Arquivo('img\logo.png'), Extrair(P, 'img/logo.png'));
  finally
    P.Free;
  end;
end;

procedure TTestBorionPack.TestComprimeTexto;
var
  P: TBorionPack;
  E: TBorionPackEntry;
begin
  P := Abrir;
  try
    E := P[P.Find('assets/app.js')];
    CheckEquals(BORION_PACK_FLAG_ZLIB, E.Flags);
    Check(E.StoredSize < E.OriginalSize div 4, 'texto repetitivo deveria comprimir bem');
  finally
    P.Free;
  end;
end;

procedure TTestBorionPack.TestNaoComprimeFormatoJaComprimido;
var
  P: TBorionPack;
begin
  P := Abrir;
  try
    CheckEquals(0, P[P.Find('img/logo.png')].Flags);
    CheckEquals(4096, Integer(P[P.Find('img/logo.png')].StoredSize));
  finally
    P.Free;
  end;
end;

procedure TTestBorionPack.TestSemCompressao;
var
  P: TBorionPack;
  I: Integer;
begin
  P := Abrir(False);
  try
    for I := 0 to P.Count - 1 do
      CheckEquals(0, P[I].Flags, P[I].Path);
    CheckEquals(Arquivo('assets\app.js'), Extrair(P, 'assets/app.js'));
  finally
    P.Free;
  end;
end;

procedure TTestBorionPack.TestArquivoVazio;
var
  P: TBorionPack;
begin
  P := Abrir;
  try
    CheckEquals('', Extrair(P, 'vazio.txt'));
  finally
    P.Free;
  end;
end;

procedure TTestBorionPack.TestCaminhosComBarraEUtf8;
var
  P: TBorionPack;
  Utf8: string;
begin
  P := Abrir;
  try
    CheckEquals(-1, P.Find('assets\app.js'), 'o pacote usa "/"');
    Utf8 := UTF8Encode(WideString('acentuação.txt'));
    Check(P.Find(Utf8) >= 0, 'caminho guardado em UTF-8');
    CheckEquals('conteúdo', Extrair(P, Utf8));
  finally
    P.Free;
  end;
end;

procedure TTestBorionPack.TestFindSemDiferenciarMaiusculas;
var
  P: TBorionPack;
begin
  P := Abrir;
  try
    CheckEquals(P.Find('index.html'), P.Find('INDEX.HTML'));
    CheckEquals(P.Find('assets/app.js'), P.Find('Assets/App.JS'));
  finally
    P.Free;
  end;
end;

procedure TTestBorionPack.TestFindInexistente;
var
  P: TBorionPack;
begin
  P := Abrir;
  try
    CheckEquals(-1, P.Find('nao/existe.js'));
    CheckEquals(-1, P.Find(''));
  finally
    P.Free;
  end;
end;

procedure TTestBorionPack.TestPacoteDeterministico;
var
  A, B: TMemoryStream;
begin
  A := Empacotar(True);
  B := Empacotar(True);
  try
    CheckEquals(A.Size, B.Size);
    Check(CompareMem(A.Memory, B.Memory, A.Size), 'mesmo conteúdo deve gerar o mesmo pacote');
  finally
    B.Free;
    A.Free;
  end;
end;

procedure TTestBorionPack.TestPacoteInvalidoLevantaErro;
var
  M: TStringStream;
begin
  M := TStringStream.Create('isto não é um pacote');
  try
    try
      TBorionPack.FromStream(M).Free;
      Fail('deveria levantar EBorionPack');
    except
      on EBorionPack do ;
    end;
  finally
    M.Free;
  end;
end;

procedure TTestBorionPack.TestPacoteTruncadoLevantaErro;
var
  M: TMemoryStream;
begin
  M := Empacotar(True);
  try
    M.Size := M.Size - 10;
    try
      TBorionPack.FromStream(M).Free;
      Fail('deveria levantar EBorionPack');
    except
      on EBorionPack do ;
    end;
  finally
    M.Free;
  end;
end;

procedure TTestBorionPack.TestResIdaEVolta;
var
  Pacote, Lido: TMemoryStream;
  Res: string;
begin
  Res := PastaTemp('teste.res');
  Pacote := Empacotar(True);
  Lido := TMemoryStream.Create;
  try
    BorionWriteRes(Res, BORION_PACK_RESOURCE, Pacote);
    Check(BorionReadRes(Res, 'borion_assets', Lido), 'nome do recurso não diferencia maiúsculas');
    CheckEquals(Pacote.Size, Lido.Size);
    Check(CompareMem(Pacote.Memory, Lido.Memory, Pacote.Size));
    Lido.Clear;
    CheckFalse(BorionReadRes(Res, 'OUTRO', Lido));
  finally
    Lido.Free;
    Pacote.Free;
    DeleteFile(Res);
  end;
end;

procedure TTestBorionPack.TestUrlDecode;
begin
  CheckEquals(UTF8Encode(WideString('ação.png')), BorionUrlDecode('a%C3%A7%C3%A3o.png'));
  CheckEquals('a b', BorionUrlDecode('a%20b'));
  CheckEquals('a+b', BorionUrlDecode('a+b'), '"+" não é espaço no caminho');
  CheckEquals('100%', BorionUrlDecode('100%'));
  CheckEquals('%zz', BorionUrlDecode('%zz'));
end;

{ TTestBorionAssets }

procedure TTestBorionAssets.SetUp;
var
  M: TMemoryStream;
  Op: TBorionPackOptions;
begin
  FPasta := PastaTemp('assets-src');
  CriarFrontend(FPasta);
  FAssets := TBorionAssets.Create(nil, nil);
  FAssets.DevUrl := '';
  Op.Compress := True;
  M := TMemoryStream.Create;
  try
    BorionPackFolder(FPasta, M, Op);
    FAssets.SetPack(TBorionPack.FromStream(M));
  finally
    M.Free;
  end;
  FResp := TWV2WebResourceResponse.Create;
end;

procedure TTestBorionAssets.TearDown;
begin
  FResp.Free;
  FAssets.Free;
  ApagarPasta(FPasta);
end;

function TTestBorionAssets.Corpo: string;
begin
  Result := StreamComoTexto(FResp.Content);
end;

function TTestBorionAssets.Header(const Nome: string): string;
begin
  Result := FResp.Headers.Values[Nome];
end;

procedure TTestBorionAssets.TestRaizServeIndex;
begin
  FAssets.ServePath('', FResp);
  CheckEquals(200, FResp.StatusCode);
  CheckEquals(INDEX_HTML, Corpo);
  CheckEquals('text/html; charset=utf-8', Header('Content-Type'));
  FAssets.ServePath('/', FResp);
  CheckEquals(INDEX_HTML, Corpo);
end;

procedure TTestBorionAssets.TestArquivoComumComMime;
begin
  FAssets.ServePath('assets/app.js', FResp);
  CheckEquals(200, FResp.StatusCode);
  CheckEquals('text/javascript; charset=utf-8', Header('Content-Type'));
  Check(Pos('function f200()', Corpo) > 0, 'conteúdo descomprimido');
end;

procedure TTestBorionAssets.TestCaminhoCodificado;
begin
  FAssets.ServePath('acentua%C3%A7%C3%A3o.txt', FResp);
  CheckEquals(200, FResp.StatusCode);
  CheckEquals('conteúdo', Corpo);
end;

procedure TTestBorionAssets.TestSpaFallback;
begin
  FAssets.ServePath('clientes/7', FResp);
  CheckEquals(200, FResp.StatusCode, 'rota do app deve servir o index.html');
  CheckEquals(INDEX_HTML, Corpo);
  CheckEquals('text/html; charset=utf-8', Header('Content-Type'));
end;

procedure TTestBorionAssets.TestSpaFallbackDesligado;
begin
  FAssets.SpaFallback := False;
  FAssets.ServePath('clientes/7', FResp);
  CheckEquals(404, FResp.StatusCode);
end;

procedure TTestBorionAssets.TestInexistenteComExtensao404;
begin
  FAssets.ServePath('assets/nao-existe.js', FResp);
  CheckEquals(404, FResp.StatusCode, 'arquivo ausente não pode virar index.html');
  FAssets.ServePath('pasta.v2/rota', FResp);
  CheckEquals(200, FResp.StatusCode, 'só a extensão do último segmento conta');
end;

procedure TTestBorionAssets.TestHeadersPadrao;
begin
  FAssets.ServePath('index.html', FResp);
  CheckEquals('nosniff', Header('X-Content-Type-Options'));
  CheckEquals('no-cache', Header('Cache-Control'));
  CheckEquals('', Header('Content-Security-Policy'));
end;

procedure TTestBorionAssets.TestCspECacheConfiguraveis;
begin
  FAssets.ContentSecurityPolicy := 'default-src ''self''';
  FAssets.CacheControl := '';
  FAssets.ServePath('index.html', FResp);
  CheckEquals('default-src ''self''', Header('Content-Security-Policy'));
  CheckEquals(-1, FResp.Headers.IndexOfName('Cache-Control'));
end;

procedure TTestBorionAssets.TestSemPacote404;
var
  A: TBorionAssets;
begin
  A := TBorionAssets.Create(nil, nil);
  try
    Check(A.Pack = nil, 'o exe de testes não tem BORION_ASSETS');
    Check(A.PackError <> '');
    A.ServePath('index.html', FResp);
    CheckEquals(404, FResp.StatusCode);
    Check(Pos('pacote', Corpo) > 0, Corpo);
  finally
    A.Free;
  end;
end;

procedure TTestBorionAssets.TestMimeTypes;
begin
  CheckEquals('text/css; charset=utf-8', BorionMimeType('a/b/estilo.css'));
  CheckEquals('image/webp', BorionMimeType('foto.WEBP'));
  CheckEquals('application/wasm', BorionMimeType('mod.wasm'));
  CheckEquals('font/woff2', BorionMimeType('f.woff2'));
  CheckEquals('application/json; charset=utf-8', BorionMimeType('app.js.map'));
  CheckEquals('application/octet-stream', BorionMimeType('arquivo.xyz'));
  CheckEquals('application/octet-stream', BorionMimeType('semextensao'));
end;

procedure TTestBorionAssets.TestDevUrlFrom;
var
  P: TStringList;
begin
  P := TStringList.Create;
  try
    CheckEquals('', BorionDevUrlFrom(P, ''));
    CheckEquals('http://env:1', BorionDevUrlFrom(P, 'http://env:1'));
    P.Add('--dev-url=http://localhost:5173');
    CheckEquals('http://localhost:5173', BorionDevUrlFrom(P, 'http://env:1'), 'parâmetro vence o ambiente');
    P.Clear;
    P.Add('--outro');
    P.Add('--DEV-URL');
    P.Add('http://h:2/');
    CheckEquals('http://h:2/', BorionDevUrlFrom(P, ''));
    P.Clear;
    P.Add('--dev-url');  { sem valor }
    CheckEquals('', BorionDevUrlFrom(P, ''));
  finally
    P.Free;
  end;
end;

procedure TTestBorionAssets.TestStartUrlEOrigem;
var
  A: TBorionAssets;
begin
  CheckEquals('https://app.local', FAssets.Origin);
  CheckEquals('https://app.local/', FAssets.StartUrl, 'raiz, não /index.html (rota desconhecida em SPAs)');
  CheckFalse(FAssets.IsDev);
  FAssets.DevUrl := 'http://localhost:5173';
  Check(FAssets.IsDev);
  CheckEquals('http://localhost:5173', FAssets.StartUrl);
  A := TBorionAssets.Create(nil, nil, 'MeuApp.Local');
  try
    CheckEquals('https://meuapp.local', A.Origin);
    CheckEquals('https://meuapp.local/x.js', A.Url('x.js'));
  finally
    A.Free;
  end;
end;

initialization
  RegisterTest('BorionPack', TTestBorionPack.Suite);
  RegisterTest('BorionAssets', TTestBorionAssets.Suite);

end.
