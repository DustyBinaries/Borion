@echo off
rem Compila o exemplo de várias janelas com o "borion build" (ou abra MultiWindowDemo.dpr na
rem IDE, depois de um build: ele gera o web.res com a interface e o app.json).
setlocal
set BORION=%~dp0..\..\Tools\borion.exe
if not exist "%BORION%" call "%~dp0..\..\Tools\build.bat" || goto :erro
"%BORION%" build "%~dp0." || goto :erro
exit /b 0
:erro
echo FALHOU
exit /b 1
