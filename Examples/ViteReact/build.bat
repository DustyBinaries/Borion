@echo off
rem Build de producao: frontend (Vite) -> pacote de assets -> exe.
setlocal
if "%DELPHI%"=="" set DELPHI=C:\bin\Borland\Delphi7
rem Jsons.pas (json4delphi, distribuida com o ACBr) e o ACBr.inc que ela inclui
if "%JSON4DELPHI%"=="" set JSON4DELPHI=C:\dev\lib\ACBr\Fontes\Terceiros\json4delphi\src
if "%ACBR_COMUM%"=="" set ACBR_COMUM=C:\dev\lib\ACBr\Fontes\ACBrComum
set BORION=%~dp0..\..\Tools\borion.exe
cd /d "%~dp0"
if not exist "%JSON4DELPHI%\Jsons.pas" echo ERRO: Jsons.pas nao encontrada em %JSON4DELPHI% & goto :erro
where npm >nul 2>&1 || (echo ERRO: Node.js/npm nao encontrado & goto :erro)
if not exist "%BORION%" call "%~dp0..\..\Tools\build.bat" || goto :erro

echo === Frontend (Vite)
pushd frontend
if not exist node_modules call npm install || (popd & goto :erro)
call npm run build || (popd & goto :erro)
popd

echo === Empacotando frontend\dist
"%BORION%" pack frontend\dist app.res || goto :erro

echo === Delphi
if not exist ViteReact.res "%DELPHI%\Bin\brcc32.exe" ViteReact.rc || goto :erro
"%DELPHI%\Bin\dcc32.exe" -B -Q "-U%JSON4DELPHI%" "-I%ACBR_COMUM%" ViteReact.dpr || goto :erro
rem o loader x86 precisa ficar ao lado do exe
if not exist WebView2Loader.dll copy /y ..\..\WebView2\WebView2Loader.dll . >nul || goto :erro
echo OK: ViteReact.exe
exit /b 0
:erro
echo FALHOU
exit /b 1
