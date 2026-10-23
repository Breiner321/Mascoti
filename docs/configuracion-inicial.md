# Configuración inicial (semana 0)

## A. Todos: instalar herramientas (Windows)

1. **Git** y **GitHub CLI** (`winget install Git.Git GitHub.cli`).
2. **Flutter SDK** (canal stable): https://docs.flutter.dev/get-started/install/windows/mobile. Agregar `flutter\bin` al PATH.
3. **Android Studio**: instala Android SDK, *command-line tools* y un emulador (Pixel, API 34 o superior). Luego ejecuta `flutter doctor --android-licenses`.
4. **Node.js 22 LTS** (`winget install OpenJS.NodeJS.LTS`).
5. **Java 21** (lo necesitan los emuladores de Firebase): `winget install EclipseAdoptium.Temurin.21.JDK`.
6. **Firebase CLI**: `npm install -g firebase-tools` y luego `firebase login`.
7. **FlutterFire CLI**: `dart pub global activate flutterfire_cli`.
8. **Claude Code**: https://docs.claude.com/en/docs/claude-code (luego ejecuta `claude` dentro del repo).
9. VS Code con las extensiones *Flutter* y *Dart*, o Android Studio con el plugin de Flutter.

Verifica con `flutter doctor`: todo debe salir en verde menos Chrome, iOS y Visual Studio, que no se necesitan.

## B. Dev A: crear Firebase (una sola vez)

1. En https://console.firebase.google.com crea el proyecto **mascoti-dev** (y más adelante **mascoti-prod**). Si el ID está ocupado, usa otro y actualiza `.firebaserc`.
   > **ID real del proyecto de desarrollo: `mascoti-b27cf`** (ya está en `.firebaserc`). Úsalo en lugar de `mascoti-dev` en los comandos de abajo.
2. **Authentication → Método de acceso → Google → Habilitar.** Correo de soporte: el del equipo.
3. **Firestore Database → Crear** en modo producción, ubicación `us-east1` (o `nam5`).
4. **No hace falta** Storage ni el plan Blaze de Firebase: los archivos y la lógica de servidor van en Supabase (sección C2).
6. Ejecuta el script de configuración desde la raíz del repo:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
   ```
7. Conecta la app con Firebase:
   ```powershell
   flutterfire configure --project=mascoti-dev --platforms=android --android-package-name=co.mascoti.mascoti
   ```
   Esto genera `lib/firebase_options.dart` y `android/app/google-services.json`. **Súbelos al repo**: no son secretos (la seguridad está en las reglas) y todo el equipo y el CI los necesitan.
8. Publica las reglas y la Function:
   ```powershell
   firebase deploy --only firestore:rules,firestore:indexes
   ```
9. Verifica y haz commit:
   ```powershell
   flutter analyze
   flutter test
   git add . ; git commit -m "chore: proyecto Flutter y Firebase inicial" ; git push
   ```
10. En GitHub: **Settings → Branches → proteger `main`** (PR obligatorio, 1 aprobación, checks de CI en verde).

> El esqueleto se escribió sin poder compilarlo. Si `flutter analyze` reporta algo al terminar el paso 9 (p. ej. por cambios de API en una versión nueva de un paquete), la primera tarea de Claude Code es: *"Ejecuta flutter analyze y flutter test y corrige los errores sin cambiar la arquitectura."*

## C. Todos: SHA-1 para el login con Google

Google Sign-In en Android solo funciona si el SHA-1 de la llave de firma está registrado en Firebase. **Cada computador tiene su propia llave de depuración.**

```powershell
cd android
.\gradlew signingReport
```

Copia el `SHA1` de la variante `debug` y agrégalo en Firebase → Configuración del proyecto → tu app Android → **Agregar huella digital**. Luego el Dev A vuelve a descargar `google-services.json` (o ejecuta `flutterfire configure` otra vez) y lo sube al repo.

## C2. Supabase: archivos y Edge Functions

Firebase (plan gratuito) se usa para login, base de datos y push. **Supabase** aporta Storage y las Edge Functions (`supabase/functions/`). Supabase acepta el login de Firebase, así que no hay un segundo inicio de sesión.

**Dev A (una vez), en https://supabase.com — proyecto `mascoti` (ref `tahnazumbqsupzpusrba`, North Virginia):**
1. **Authentication → Sign In / Providers → Third-party Auth → Add provider → Firebase**, con el Project ID `mascoti-b27cf`.
2. **Storage y políticas:** aplica los archivos de `supabase/migrations/` en orden (crean los buckets privados `mascoti` y `mascotas` con sus políticas). Desde la terminal:
   ```powershell
   supabase link --project-ref tahnazumbqsupzpusrba
   supabase db query --linked -f supabase/migrations/20261005000000_storage_mascoti.sql
   supabase db query --linked -f supabase/migrations/20261015000000_storage_mascotas.sql
   supabase db query --linked -f supabase/migrations/20261016000000_limite_vinculacion.sql
   supabase db query --linked -f supabase/migrations/20261016010000_storage_registros.sql
   supabase db query --linked -f supabase/migrations/20261023000000_tareas_programadas.sql   # ver paso 5
   ```
   O pega cada archivo en **SQL Editor** del panel. Se pueden ejecutar varias veces sin problema.
3. **Cuenta de servicio de Firebase** (la Edge Function la usa para escribir en Firestore): Firebase → Configuración del proyecto → Cuentas de servicio → **Generar nueva clave privada**. Guarda el JSON **fuera del repositorio** y cárgalo como secreto. Se pasa en **Base64** porque PowerShell rompe el JSON al enviarlo como argumento (error `Invalid secret pair`):
   ```powershell
   $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\Users\<tu-usuario>\secretos\cuenta-servicio.json"))
   supabase secrets set --project-ref tahnazumbqsupzpusrba FIREBASE_SERVICE_ACCOUNT=$b64
   ```
4. Despliega las Edge Functions:
   ```powershell
   supabase functions deploy completar-registro --project-ref tahnazumbqsupzpusrba --use-api
   supabase functions deploy vincular-mascota --project-ref tahnazumbqsupzpusrba --use-api
   supabase functions deploy adjuntos-historial --project-ref tahnazumbqsupzpusrba --use-api
   supabase functions deploy citas --project-ref tahnazumbqsupzpusrba --use-api
   supabase functions deploy tareas-programadas --project-ref tahnazumbqsupzpusrba --use-api
   ```
5. **Tareas programadas** (no-show y solicitudes expiradas cada 30 min; recordatorios diarios, RF-13). Las ejecuta pg_cron en Supabase llamando a `tareas-programadas`, protegida con un secreto compartido:
   ```powershell
   # Un valor largo y aleatorio; NO lo subas al repo.
   $secreto = [Convert]::ToBase64String((1..32 | ForEach-Object { Get-Random -Maximum 256 }) -as [byte[]])
   supabase secrets set --project-ref tahnazumbqsupzpusrba CRON_SECRET=$secreto
   ```
   En **SQL Editor** guarda el mismo valor en el Vault (una vez) y luego aplica la migración:
   ```sql
   select vault.create_secret('<el mismo valor>', 'cron_secret');
   ```
   Revisa las ejecuciones en **Integrations → Cron** (o `select * from cron.job_run_details order by start_time desc limit 10;`).

**Todos, en su computador:**
1. Copia `env/dev.example.json` como `env/dev.json` y pon la **publishable key** (`sb_publishable_...`, en Supabase → Project Settings → API Keys). Es pública; **nunca** pongas ahí la *secret* / *service_role* key.
2. Corre la app con `flutter run --dart-define-from-file=env/dev.json`.

`env/dev.json` está en `.gitignore`. Sin él la app abre igual, pero "Finalizar Registro" muestra "El registro no está disponible en esta versión de la app".

**Direcciones y mapas:** OpenStreetMap (Photon), gratis y **sin API key**. La UI muestra la atribución "Datos © colaboradores de OpenStreetMap", que exige la licencia de los datos.

## C3. Mapa del directorio (RF-09)

El directorio de clínicas usa **OpenStreetMap** con `flutter_map`: **no necesita API key ni cuenta de facturación**, así que no hay nada que configurar. (Se evaluó Google Maps, pero el equipo no tiene acceso a Google Cloud.)

- **Mosaicos del mapa:** `tile.openstreetmap.org`. Su política de uso exige identificar la app (`userAgentPackageName: co.mascoti.mascoti`, ya configurado) y mostrar la atribución "© colaboradores de OpenStreetMap" (la muestra el mapa). Es para uso moderado: si la app crece, se cambia `DirectoryMapView.tileUrl` por un proveedor propio o pago.
- **Búsqueda por dirección o ciudad** (sin permiso de ubicación): el mismo buscador Photon de `core/places` que usa el registro de la clínica.
- **"Cómo llegar":** abre la app de mapas del teléfono (`geo:`); si no hay ninguna, la ruta en openstreetmap.org.
- **Ubicación en el emulador:** ⋮ → **Location**, escribe una dirección (p. ej. Medellín) y pulsa **Set location**; luego vuelve a abrir la pestaña "Mapa".
- **Una clínica no aparece:** debe tener `estado: activo` (haber terminado su perfil de atención, RF-04) y el campo `geo`. Revísalo con `npm run verificar-geo` en `functions/`.

## D. Todos: correr la app

```powershell
git pull
flutter pub get
flutter run --dart-define-from-file=env/dev.json    # Firebase mascoti-b27cf + Supabase (ver C2)
```

Con emuladores locales (recomendado para desarrollar sin tocar datos reales):

```powershell
# Terminal 1
firebase emulators:start
# Terminal 2
flutter run --dart-define=USE_EMULATORS=true
# En un celular físico, usa la IP del PC:
flutter run --dart-define=USE_EMULATORS=true --dart-define=EMULATOR_HOST=192.168.1.20
```

La interfaz de los emuladores (usuarios, datos, logs) queda en http://localhost:4000.

> Con emuladores, el registro (Edge Function en la nube) no acepta los usuarios del emulador de Auth. Para probar el registro usa Firebase real; los emuladores sirven para el resto de pantallas y para las pruebas de reglas.

## E. Problemas comunes

| Síntoma | Solución |
|---|---|
| Error `ApiException: 10` o `DEVELOPER_ERROR` al iniciar sesión | Falta el SHA-1 de tu PC en Firebase (sección C). |
| `minSdkVersion 21 cannot be smaller than 23` | En `android/app/build.gradle.kts`, pon `minSdk = 23`. |
| La app no conecta con los emuladores | Revisa `EMULATOR_HOST` y que el firewall de Windows permita los puertos 8080 y 9099. |
| "El registro no está disponible en esta versión de la app" | Falta `env/dev.json` o no corriste con `--dart-define-from-file=env/dev.json` (sección C2). |
| "No se pudo completar el registro" al finalizar | Falta el secreto `FIREBASE_SERVICE_ACCOUNT` o la función no está desplegada (sección C2). Mira los logs en Supabase → Edge Functions → completar-registro. |
| La app se queda en "Estamos tardando en conectar" | Firestore no está creado o las reglas no están desplegadas (paso B.3 y B.8). |
| `project is paused` / el registro dejó de funcionar | El plan gratuito de Supabase pausa el proyecto tras 7 días sin uso: reactívalo en el panel de Supabase (**Restore project**). |
| El mapa del directorio se ve gris o en blanco | El teléfono o emulador no tiene internet, o OpenStreetMap limitó el uso por un momento. La lista de clínicas funciona igual; reintenta más tarde (sección C3). |
| "El buscador de direcciones no está disponible" | Photon (OpenStreetMap) no respondió o limitó el uso; espera un momento y toca Reintentar. |
| google_sign_in pide `serverClientId` | Pásalo con `--dart-define=GOOGLE_SERVER_CLIENT_ID=<client ID web>` (Firebase → Authentication → Google → Configuración del SDK web). |
