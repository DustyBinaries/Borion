@echo off
rem Compila e roda os testes DUnit do WebView2 (nao precisa do runtime do WebView2).
setlocal
if "%DELPHI%"=="" set DELPHI=C:\bin\Borland\Delphi7
if "%DUNIT%"=="" set DUNIT=C:\dev\lib\dunit\src
cd /d "%~dp0"
if not exist "%DUNIT%\TestFramework.pas" echo ERRO: DUnit nao encontrado em %DUNIT% & goto :erro
if not exist dcu mkdir dcu
"%DELPHI%\Bin\dcc32.exe" -B -Q -CC "-N%~dp0dcu" "-U%DUNIT%" "-I%DUNIT%" WebView2Tests.dpr || goto :erro
"%~dp0WebView2Tests.exe" || goto :erro
echo TODOS OS TESTES PASSARAM
exit /b 0
:erro
echo FALHOU
exit /b 1
