@echo off
rem Compila o exemplo do plugin app com o "borion build" (ou abra AppDemo.dpr na IDE, depois
rem de um build: ele gera o web.res com a interface, o app.json e o ícone).
setlocal
set BORION=%~dp0..\..\Tools\borion.exe
if not exist "%BORION%" call "%~dp0..\..\Tools\build.bat" || goto :erro
"%BORION%" build "%~dp0." || goto :erro
exit /b 0
:erro
echo FALHOU
exit /b 1
