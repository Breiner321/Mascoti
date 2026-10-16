@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Mascoti - rama Luna

set "PROJECT_DIR=C:\Users\Lunal\OneDrive\Escritorio\Mascoti clon\Mascoti"
set "BRANCH=Luna"
set "FLUTTER_DIR=C:\Users\Lunal\dev\flutter\bin"

where flutter >nul 2>&1 || set "PATH=%FLUTTER_DIR%;%PATH%"

echo [1/4] Entrando a "%PROJECT_DIR%"...
cd /d "%PROJECT_DIR%" 2>nul
if errorlevel 1 ( echo ERROR: no se encontro la carpeta del proyecto. & goto :fail )

echo.
echo [2/4] Cambiando a la rama "%BRANCH%"...
git fetch origin --prune
git show-ref --verify --quiet "refs/heads/%BRANCH%"
if !errorlevel! equ 0 (
    git checkout "%BRANCH%"
) else (
    git checkout -b "%BRANCH%" --track "origin/%BRANCH%"
)
if errorlevel 1 ( echo ERROR: no se pudo cambiar de rama. Revisa con: git status & goto :fail )
for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD') do set "CURRENT=%%b"
if /i not "!CURRENT!"=="%BRANCH%" ( echo ERROR: la rama actual es "!CURRENT!". & goto :fail )
echo OK: rama "!CURRENT!".

echo.
echo [3/4] Instalando dependencias de Flutter...
call flutter pub get
if errorlevel 1 ( echo ERROR: fallo flutter pub get. & goto :fail )

echo.
echo [4/4] Ejecutando la app ^(r = recargar, q = salir^)...
if exist "env\dev.json" (
    call flutter run --dart-define-from-file=env/dev.json
) else (
    echo AVISO: falta env\dev.json ^(copia env\dev.example.json y pon tu publishable key^).
    echo        La app abre, pero el registro con Supabase no funcionara.
    call flutter run
)
goto :end

:fail
echo.
echo El script se detuvo por un error.
:end
pause
endlocal
