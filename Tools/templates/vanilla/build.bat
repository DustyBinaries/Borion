@echo off
rem Compila o {{PROGRAM}}.exe com o "borion build" (ou abra {{PROGRAM}}.dpr na IDE).
rem O mesmo que, nesta pasta: borion build
setlocal
if "%BORION_HOME%"=="" set BORION_HOME={{BORION_HOME}}
if not exist "%BORION_HOME%\Tools\borion.exe" call "%BORION_HOME%\Tools\build.bat" || exit /b 1
"%BORION_HOME%\Tools\borion.exe" build "%~dp0."
