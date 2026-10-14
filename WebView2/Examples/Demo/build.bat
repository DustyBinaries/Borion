@echo off
rem Compila o exemplo do WebView2 (ou abra WebView2Demo.dpr na IDE do Delphi 7).
setlocal
if "%DELPHI%"=="" set DELPHI=C:\bin\Borland\Delphi7
cd /d "%~dp0"
if not exist WebView2Demo.res "%DELPHI%\Bin\brcc32.exe" WebView2Demo.rc || goto :erro
rem web.res e sempre regerado, para pegar as alteracoes da pasta web\
"%DELPHI%\Bin\brcc32.exe" web.rc || goto :erro
"%DELPHI%\Bin\dcc32.exe" -B -Q WebView2Demo.dpr || goto :erro
rem o loader x86 precisa ficar ao lado do exe
if not exist WebView2Loader.dll copy /y ..\..\WebView2Loader.dll . >nul || goto :erro
echo OK
exit /b 0
:erro
echo FALHOU
exit /b 1
