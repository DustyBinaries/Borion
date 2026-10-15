@echo off
rem Compila o exemplo do Borion (ou abra BorionDemo.dpr na IDE do Delphi 7).
setlocal
if "%DELPHI%"=="" set DELPHI=C:\bin\Borland\Delphi7
rem Jsons.pas (json4delphi, distribuida com o ACBr) e o ACBr.inc que ela inclui
if "%JSON4DELPHI%"=="" set JSON4DELPHI=C:\dev\lib\ACBr\Fontes\Terceiros\json4delphi\src
if "%ACBR_COMUM%"=="" set ACBR_COMUM=C:\dev\lib\ACBr\Fontes\ACBrComum
cd /d "%~dp0"
if not exist "%JSON4DELPHI%\Jsons.pas" echo ERRO: Jsons.pas nao encontrada em %JSON4DELPHI% & goto :erro
if not exist BorionDemo.res "%DELPHI%\Bin\brcc32.exe" BorionDemo.rc || goto :erro
rem web.res e sempre regerado, para pegar as alteracoes da pasta web\
"%DELPHI%\Bin\brcc32.exe" web.rc || goto :erro
"%DELPHI%\Bin\dcc32.exe" -B -Q "-U%JSON4DELPHI%" "-I%ACBR_COMUM%" BorionDemo.dpr || goto :erro
rem o loader x86 precisa ficar ao lado do exe
if not exist WebView2Loader.dll copy /y ..\..\WebView2\WebView2Loader.dll . >nul || goto :erro
echo OK
exit /b 0
:erro
echo FALHOU
exit /b 1
