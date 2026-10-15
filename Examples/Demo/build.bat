@echo off
rem Compila o exemplo do Borion (ou abra BorionDemo.dpr na IDE do Delphi 7).
setlocal
if "%DELPHI%"=="" set DELPHI=C:\bin\Borland\Delphi7
rem Jsons.pas (json4delphi, distribuida com o ACBr) e o ACBr.inc que ela inclui
if "%JSON4DELPHI%"=="" set JSON4DELPHI=C:\dev\lib\ACBr\Fontes\Terceiros\json4delphi\src
if "%ACBR_COMUM%"=="" set ACBR_COMUM=C:\dev\lib\ACBr\Fontes\ACBrComum
set BORION=%~dp0..\..\Tools\borion.exe
cd /d "%~dp0"
if not exist "%JSON4DELPHI%\Jsons.pas" echo ERRO: Jsons.pas nao encontrada em %JSON4DELPHI% & goto :erro
rem a CLI do Borion empacota a pasta web\; compila a CLI se ainda nao existir
if not exist "%BORION%" call "%~dp0..\..\Tools\build.bat" || goto :erro
if not exist BorionDemo.res "%DELPHI%\Bin\brcc32.exe" BorionDemo.rc || goto :erro
rem web.res e sempre regerado, para pegar as alteracoes da pasta web\
"%BORION%" pack web web.res || goto :erro
"%DELPHI%\Bin\dcc32.exe" -B -Q "-U%JSON4DELPHI%" "-I%ACBR_COMUM%" BorionDemo.dpr || goto :erro
rem o loader x86 precisa ficar ao lado do exe
if not exist WebView2Loader.dll copy /y ..\..\WebView2\WebView2Loader.dll . >nul || goto :erro
echo OK
exit /b 0
:erro
echo FALHOU
exit /b 1
