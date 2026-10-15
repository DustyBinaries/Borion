@echo off
rem Modo dev: servidor do Vite (hot-reload) + o app apontando para ele.
rem Edite frontend\src\*.jsx e veja a mudanca na hora, sem recompilar o Delphi.
rem Mudou o Delphi (comandos)? Feche o app e rode o build.bat de novo.
setlocal
set DEV_URL=http://localhost:5174
cd /d "%~dp0"
if not exist Editor.exe call "%~dp0build.bat" || goto :erro
if not exist frontend\node_modules (pushd frontend & call npm install & popd)

echo === Iniciando o Vite em %DEV_URL% (janela separada)
start "Vite - Borion Editor" /D "%~dp0frontend" cmd /c npm run dev

set /a TENTATIVAS=0
:espera
curl -s -o nul %DEV_URL%/ && goto :pronto
set /a TENTATIVAS+=1
if %TENTATIVAS% geq 60 echo ERRO: o Vite nao respondeu em %DEV_URL% & goto :erro
ping -n 2 127.0.0.1 >nul
goto :espera

:pronto
echo === Abrindo o app em modo dev
start "" "%~dp0Editor.exe" --dev-url=%DEV_URL%
exit /b 0
:erro
echo FALHOU
exit /b 1
