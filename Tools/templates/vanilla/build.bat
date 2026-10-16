@echo off
rem Compila o {{PROGRAM}}.exe: empacota web\ e compila o Delphi (ou abra {{PROGRAM}}.dpr na IDE).
setlocal
if "%DELPHI%"=="" set DELPHI=C:\bin\Borland\Delphi7
rem onde estao o Borion, o WebView2 e a Jsons.pas (o ACBr.inc ao lado); troque pelas variaveis
if "%BORION_HOME%"=="" set BORION_HOME={{BORION_HOME}}
if "%WEBVIEW2_HOME%"=="" set WEBVIEW2_HOME={{WEBVIEW2_HOME}}
if "%JSON4DELPHI%"=="" set JSON4DELPHI={{JSON4DELPHI}}
if "%ACBR_COMUM%"=="" set ACBR_COMUM={{ACBR_COMUM}}
set BORION=%BORION_HOME%\Tools\borion.exe
set FONTES=%JSON4DELPHI%;%BORION_HOME%;%BORION_HOME%\Plugins;%WEBVIEW2_HOME%
cd /d "%~dp0"
if not exist "%BORION_HOME%\Borion.pas" echo ERRO: Borion nao encontrado em %BORION_HOME% & goto :erro
if not exist "%JSON4DELPHI%\Jsons.pas" echo ERRO: Jsons.pas nao encontrada em %JSON4DELPHI% & goto :erro
if not exist "%BORION%" call "%BORION_HOME%\Tools\build.bat" || goto :erro

echo === Interface (web\)
rem os modulos do @borion/api vao junto da pagina; o import map do index.html os encontra
if not exist web\borion-api mkdir web\borion-api
copy /y "%BORION_HOME%\js\*.js" web\borion-api\ >nul || goto :erro
"%BORION%" pack web web.res || goto :erro

echo === Delphi
if not exist {{PROGRAM}}.res "%DELPHI%\Bin\brcc32.exe" {{PROGRAM}}.rc || goto :erro
"%DELPHI%\Bin\dcc32.exe" -B -Q "-U%FONTES%" "-I%ACBR_COMUM%" {{PROGRAM}}.dpr || goto :erro
rem o loader x86 precisa ficar ao lado do exe
if not exist WebView2Loader.dll copy /y "%WEBVIEW2_HOME%\WebView2Loader.dll" . >nul || goto :erro
echo OK: {{PROGRAM}}.exe
exit /b 0
:erro
echo FALHOU
exit /b 1
