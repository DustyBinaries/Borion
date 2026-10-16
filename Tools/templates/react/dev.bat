@echo off
rem Modo dev com o "borion dev": o Vite com hot-reload (porta {{DEV_PORT}}) e o app ligado a ele.
rem Mudou o Delphi? O app é recompilado e reaberto. Feche o app para encerrar.
rem O mesmo que, nesta pasta: borion dev
setlocal
if "%BORION_HOME%"=="" set BORION_HOME={{BORION_HOME}}
if not exist "%BORION_HOME%\Tools\borion.exe" call "%BORION_HOME%\Tools\build.bat" || exit /b 1
"%BORION_HOME%\Tools\borion.exe" dev "%~dp0." %*
