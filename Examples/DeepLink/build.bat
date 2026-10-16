@echo off
rem Compila o exemplo do plugin deep-link (ou abra DeepLinkDemo.dpr na IDE do Delphi 7).
setlocal
if "%DELPHI%"=="" set DELPHI=C:\bin\Borland\Delphi7
rem Jsons.pas (json4delphi, distribuida com o ACBr) e o ACBr.inc que ela inclui
if "%JSON4DELPHI%"=="" set JSON4DELPHI=C:\dev\lib\ACBr\Fontes\Terceiros\json4delphi\src
if "%ACBR_COMUM%"=="" set ACBR_COMUM=C:\dev\lib\ACBr\Fontes\ACBrComum
set BORION=%~dp0..\..\Tools\borion.exe
cd /d "%~dp0"
if not exist "%JSON4DELPHI%\Jsons.pas" echo ERRO: Jsons.pas nao encontrada em %JSON4DELPHI% & goto :erro
if not exist "%BORION%" call "%~dp0..\..\Tools\build.bat" || goto :erro
rem os modulos do @borion/api (Borion\js) vao junto da pagina; o import map do
rem index.html resolve "@borion/api/..." para eles
if not exist web\borion-api mkdir web\borion-api
copy /y ..\..\js\*.js web\borion-api\ >nul || goto :erro
if not exist DeepLinkDemo.res "%DELPHI%\Bin\brcc32.exe" DeepLinkDemo.rc || goto :erro
"%BORION%" pack web web.res || goto :erro
"%DELPHI%\Bin\dcc32.exe" -B -Q "-U%JSON4DELPHI%" "-I%ACBR_COMUM%" DeepLinkDemo.dpr || goto :erro
rem o loader x86 precisa ficar ao lado do exe
if not exist WebView2Loader.dll copy /y ..\..\WebView2\WebView2Loader.dll . >nul || goto :erro
echo OK: DeepLinkDemo.exe
exit /b 0
:erro
echo FALHOU
exit /b 1
