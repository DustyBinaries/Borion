Arquivos

┌────────────────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│        Arquivo         │                                                 O que é                                                  │
├────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ WebView2.pas           │ As interfaces do WebView2 e o carregamento dinâmico do WebView2Loader.dll                                │
├────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│                        │ TWebView2Browser, um controle VCL que guarda o navegador. Tem navegação, ExecuteScript, PostWebMessage,  │
│ WebView2Browser.pas    │ DevTools e os eventos OnInitialized, OnNavigationCompleted, OnSourceChanged, OnTitleChanged,             │
│                        │ OnWebMessageReceived e OnScriptResult                                                                    │
├────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ uPrincipal.pas/.dfm    │ A tela de demonstração: barra de endereço, painel para trocar mensagens com a página e um log            │
├────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ demo.html              │ A página local usada no teste                                                                            │
├────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ WebView2Demo.dpr,      │ O projeto e um script para compilar pela linha de comando                                                │
│ build.bat              │                                                                                                          │
├────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ WebView2Loader.dll     │ Versão 32 bits, tirada do pacote NuGet oficial                                                           │
└────────────────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────────┘

O que foi testado

- Delphi → JS: ExecuteScript('somar(20, 22)') devolveu 42, e PostWebMessage apareceu na página.
- JS → Delphi: chrome.webview.postMessage('hora') chegou ao Delphi e foi respondido. Um objeto enviado pela página chegou como JSON: {"acao":"salvar","id":123,...}.

Pontos de atenção para quem usar no Delphi 7

1. BOOL: no Delphi, True vale -1, mas o WebView2 só aceita 1. No primeiro teste, put_IsScriptEnabled(True) acabou desligando o JavaScript da página. Por isso, os métodos que recebem um BOOL usam agora o tipo WV2BOOL com a função BoolToWV2(). Use o mesmo padrão se declarar outros métodos.
2. Ponto flutuante: a unit chama Set8087CW($133F) para mascarar as exceções de ponto flutuante. Sem isso, o Chromium gera erros "Invalid floating point operation" aleatórios.
3. Callbacks: o Delphi 7 não tem métodos anônimos, então cada callback é uma classe pequena. Elas são desligadas no Destroy do controle, para que um callback que chegue depois não acesse um objeto já liberado.
4. Implantação: o WebView2Loader.dll (x86) tem que ficar junto do .exe, e o WebView2 Runtime precisa estar instalado. Ele já vem no Windows 11; para o Windows 10 existe o instalador "Evergreen". Os dados do navegador ficam em %LOCALAPPDATA%\WebView2Demo\WebView2.

Para compilar, abra o WebView2Demo.dpr na IDE ou rode o build.bat. Os arquivos .pas e .dfm estão em ANSI (cp1252) com quebra de linha CRLF, como o Delphi 7 espera.