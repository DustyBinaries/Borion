@echo off
rem Compila a CLI do Borion (borion.exe).
setlocal
if "%DELPHI%"=="" set DELPHI=C:\bin\Borland\Delphi7
if "%JSON4DELPHI%"=="" set JSON4DELPHI=C:\dev\lib\ACBr\Fontes\Terceiros\json4delphi\src
if "%ACBR_COMUM%"=="" set ACBR_COMUM=C:\dev\lib\ACBr\Fontes\ACBrComum
cd /d "%~dp0"
if not exist "%JSON4DELPHI%\Jsons.pas" echo ERRO: Jsons.pas nao encontrada em %JSON4DELPHI% (defina JSON4DELPHI) & goto :erro
if not exist dcu mkdir dcu
"%DELPHI%\Bin\dcc32.exe" -B -Q -CC "-N%~dp0dcu" "-U%JSON4DELPHI%" "-I%ACBR_COMUM%" borion.dpr || goto :erro
echo OK
exit /b 0
:erro
echo FALHOU
exit /b 1
