@echo off
rem Compila a CLI do Borion (borion.exe).
setlocal
if "%DELPHI%"=="" set DELPHI=C:\bin\Borland\Delphi7
cd /d "%~dp0"
if not exist dcu mkdir dcu
"%DELPHI%\Bin\dcc32.exe" -B -Q -CC "-N%~dp0dcu" borion.dpr || goto :erro
echo OK
exit /b 0
:erro
echo FALHOU
exit /b 1
