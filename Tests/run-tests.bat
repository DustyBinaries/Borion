@echo off
rem Compila e roda os testes do Borion: DUnit (Delphi) e node:test (pacote JS e ponte).
setlocal
if "%DELPHI%"=="" set DELPHI=C:\bin\Borland\Delphi7
if "%DUNIT%"=="" set DUNIT=C:\dev\lib\dunit\src
if "%JSON4DELPHI%"=="" set JSON4DELPHI=C:\dev\lib\ACBr\Fontes\Terceiros\json4delphi\src
if "%ACBR_COMUM%"=="" set ACBR_COMUM=C:\dev\lib\ACBr\Fontes\ACBrComum
cd /d "%~dp0"
if not exist "%DUNIT%\TestFramework.pas" echo ERRO: DUnit nao encontrado em %DUNIT% & goto :erro
if not exist "%JSON4DELPHI%\Jsons.pas" echo ERRO: Jsons.pas nao encontrada em %JSON4DELPHI% & goto :erro
if not exist dcu mkdir dcu

echo === Compilando testes Delphi
"%DELPHI%\Bin\dcc32.exe" -B -Q -CC "-N%~dp0dcu" "-U%DUNIT%;%JSON4DELPHI%" "-I%ACBR_COMUM%;%DUNIT%" BorionTests.dpr || goto :erro

echo === DUnit
"%~dp0BorionTests.exe" || goto :erro

echo === Testes JS (node:test)
where node >nul 2>&1 || (echo AVISO: Node.js nao encontrado; testes JS ignorados & goto :ok)
node --test "../js/test/*.test.js" || goto :erro

:ok
echo TODOS OS TESTES PASSARAM
exit /b 0
:erro
echo FALHOU
exit /b 1
