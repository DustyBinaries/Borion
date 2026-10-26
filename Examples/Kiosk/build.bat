@echo off
rem Compila o exemplo em modo kiosk com o "borion build" (ou abra KioskDemo.dpr na IDE,
rem depois de um build: ele gera o web.res com a interface e o app.json).
setlocal
set BORION=%~dp0..\..\Tools\borion.exe
if not exist "%BORION%" call "%~dp0..\..\Tools\build.bat" || goto :erro
rem copia o @borion/api para web\borion-api, empacota web\ e o app.json em web.res,
rem compila o .rc e o .dpr (com o search path do KioskDemo.dof) e copia o loader
"%BORION%" build "%~dp0." || goto :erro
exit /b 0
:erro
echo FALHOU
exit /b 1
