# ============================================================================
#  Mascoti - configuración inicial del proyecto Flutter
#  La ejecuta UNA sola vez el Dev A (líder técnico), desde la raíz del repo:
#     powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
#  Después hace commit de todo lo generado. El resto del equipo solo necesita
#  `git pull` + `flutter pub get`.
# ============================================================================
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

function Run($cmd) {
    Write-Host "> $cmd" -ForegroundColor DarkGray
    Invoke-Expression $cmd
    if ($LASTEXITCODE -ne 0) { throw "Falló: $cmd" }
}

foreach ($tool in "flutter", "npm") {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "No se encontró '$tool' en el PATH. Instálalo (docs/configuracion-inicial.md, sección A) y abre una terminal nueva."
    }
}

Write-Host "`n[0/5] Instalando el comando /rf de Claude Code y el CI de GitHub..." -ForegroundColor Cyan
# (Estos archivos viven en scripts/plantillas porque las carpetas .claude y .github
#  no se pudieron escribir directamente al preparar el repositorio.)
New-Item -ItemType Directory -Force -Path ".claude\commands", ".github\workflows" | Out-Null
Copy-Item "scripts\plantillas\claude\commands\rf.md" ".claude\commands\rf.md" -Force
Copy-Item "scripts\plantillas\claude\settings.json" ".claude\settings.json" -Force
Copy-Item "scripts\plantillas\github\workflows\ci.yml" ".github\workflows\ci.yml" -Force

Write-Host "`n[1/5] Generando la plataforma Android (no sobrescribe lib/ ni test/)..." -ForegroundColor Cyan
Run "flutter create . --org co.mascoti --project-name mascoti --platforms android"

Write-Host "`n[2/5] Agregando paquetes (pub elige versiones compatibles)..." -ForegroundColor Cyan
Run "flutter pub add firebase_core firebase_auth cloud_firestore cloud_functions `"google_sign_in:>=7.1.0 <8.0.0`" flutter_riverpod go_router intl"
# Nota: no usar "^" en las restricciones: flutter es un .bat y cmd.exe se come el "^"
# (quedaría fijada la versión exacta). Se usa un rango con espacio para que las comillas lleguen.
Run "flutter pub add dev:flutter_lints dev:mocktail dev:fake_cloud_firestore dev:firebase_auth_mocks"

Write-Host "`n[3/5] Ajustando minSdk a 23 (requerido por Firebase Auth)..." -ForegroundColor Cyan
$gradle = Join-Path (Get-Location) "android\app\build.gradle.kts"
if (Test-Path $gradle) {
    $content = [IO.File]::ReadAllText($gradle)
    $content = $content -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23'
    [IO.File]::WriteAllText($gradle, $content)
    Select-String -Path $gradle -Pattern 'minSdk' | ForEach-Object { Write-Host $_.Line }
} else {
    Write-Warning "No se encontró $gradle. Ajusta minSdk = 23 manualmente."
}

Write-Host "`n[4/5] Instalando dependencias de Cloud Functions..." -ForegroundColor Cyan
Push-Location functions
Run "npm install"
Run "npm run build"
Pop-Location

Write-Host "`n[5/5] Listo." -ForegroundColor Green
Write-Host @"

Siguientes pasos (ver docs/configuracion-inicial.md):
  1. firebase login
  2. dart pub global activate flutterfire_cli
  3. flutterfire configure --project=<ID-de-mascoti-dev> --platforms=android --android-package-name=co.mascoti.mascoti
  4. flutter analyze   (debe quedar en 0)
  5. flutter test
  6. git add . ; git commit -m "chore: proyecto Flutter y Firebase inicial"
"@
