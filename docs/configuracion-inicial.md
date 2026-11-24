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
   supabase db query --linked -f supabase/migrations/20261110000000_storage_chats.sql
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
   supabase functions deploy notificar-mensaje --project-ref tahnazumbqsupzpusrba --use-api
   supabase functions deploy adjuntos-chat --project-ref tahnazumbqsupzpusrba --use-api
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

## C3b. Migrar el horario de las clínicas (Cambio 2)

Después de publicar las reglas y desplegar `citas`, convierte el `horarioBase` de las clínicas existentes en `horarioSemanal` (todos los días abiertos con el mismo horario):
```powershell
cd functions
$env:GOOGLE_APPLICATION_CREDENTIALS="C:\Users\<tu-usuario>\secretos\cuenta-servicio.json"
npm run migrar-horario               # solo muestra qué haría
npm run migrar-horario -- --aplicar  # escribe los cambios
```
Se puede ejecutar varias veces. Sin migrar, la app y el servidor siguen leyendo `horarioBase` igual.

## C3c. Otras veterinarias en el mapa (Cambio 4)

Las veterinarias que aún no usan Mascoti salen de OpenStreetMap (API Overpass): gratis y **sin API key**; no hay que activar ninguna API de Google.
1. Aplica, en orden, `supabase/migrations/20261028000000_veterinarias_osm.sql` (tablas de caché y límite) y `20261029000000_precarga_veterinarias_osm.sql` (columna `pendiente` y la precarga cada 2 h en pg_cron; necesita la migración de tareas programadas). Si `supabase db push` no conecta, pega cada archivo en Supabase → **SQL Editor** → Run. Se pueden ejecutar varias veces.
2. Despliega la función. No necesita secretos nuevos (`SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` los pone Supabase; el proyecto de Firebase es `mascoti-b27cf` salvo que definas `FIREBASE_PROJECT_ID`):
   ```powershell
   supabase functions deploy veterinarias-cercanas --project-ref tahnazumbqsupzpusrba --use-api
   ```
   `verify_jwt = false` en `supabase/config.toml`: la función verifica el token de Firebase por su cuenta. Despliega también `tareas-programadas` (hace la precarga).
   Para llenar la caché sin esperar al cron (tarda hasta ~2 min; repítelo hasta que `quedan` sea 0):
   ```powershell
   curl.exe -X POST https://tahnazumbqsupzpusrba.supabase.co/functions/v1/tareas-programadas -H "x-cron-secret: <CRON_SECRET>" -H "Content-Type: application/json" -d '{\"tarea\":\"veterinarias-osm\",\"esperar\":true}'
   ```
3. (Opcional) Vincula las clínicas aliadas con su lugar de OSM para que nunca salgan dos veces:
   ```powershell
   cd functions
   $env:GOOGLE_APPLICATION_CREDENTIALS="C:\Users\<tu-usuario>\secretos\cuenta-servicio.json"
   npm run vincular-osm               # solo muestra qué haría
   npm run vincular-osm -- --aplicar  # escribe clinics.osmId
   ```

Sin la función desplegada, el mapa muestra los aliados y el aviso "No se pudieron cargar otras veterinarias." con "Reintentar". Sin `env/dev.json` (Supabase no configurado) solo muestra los aliados, sin aviso.

## C4. Notificaciones push (RF-13)

No hay que configurar nada en Firebase: FCM viene con el proyecto y es gratis en el plan Spark. Las Edge Functions envían los push con la cuenta de servicio (secreto `FIREBASE_SERVICE_ACCOUNT`).

**En el emulador de Android:** usa una imagen **con Google Play** (en Device Manager, la columna "Play Store" debe tener el ícono). Sin Google Play no hay token FCM y solo funciona el centro de notificaciones de la app.
1. Corre la app, inicia sesión y acepta el permiso de notificaciones (Android 13+).
2. Revisa en Firestore `users/{uid}/devices`: debe haber un documento con `fcmToken` y `valido: true`.
3. Para probar el ciclo completo usa dos sesiones (un dueño y una clínica, p. ej. emulador + celular). Al solicitar, aprobar, rechazar o cancelar una cita llega el push al otro.
4. Prueba los tres casos: app abierta (aparece arriba), en segundo plano y cerrada (en la bandeja del sistema). Al tocarla debe abrir la cita o el perfil de la mascota.
5. Para enviar un push manual a un token: Firebase → **Messaging → Nueva campaña → Mensaje de prueba**, pega el `fcmToken`. Agrega los datos personalizados `tipo = cita_aprobada` y `referenciaId = <id de una cita>` para probar la navegación.

**En un celular real:** instala el APK (`flutter build apk --release` o `flutter run`), inicia sesión y acepta el permiso. Si no llegan, revisa en Ajustes → Apps → Mascoti → Notificaciones que estén activas (y que el ahorro de batería no la restrinja).

**Recordatorios de las 8:00 a. m.:** para probarlos sin esperar, llama a la tarea a mano (con el mismo `CRON_SECRET`):
```powershell
curl.exe -X POST https://tahnazumbqsupzpusrba.supabase.co/functions/v1/tareas-programadas -H "x-cron-secret: <CRON_SECRET>" -H "Content-Type: application/json" -d '{\"tarea\":\"recordatorios\"}'
```

## C5. Tienda y pagos con Wompi Sandbox (RF-07, RF-12)

**Por ahora los pagos son simulados** (Cambio 5): no hace falta configurar Wompi. Sin el secreto `PASARELA_PAGO` (o con `PASARELA_PAGO=simulada`), `crear-pedido` no devuelve enlace de pago y el dueño paga en la pantalla de pago de prueba de la app, que llama a `pagar-pedido-simulado`. Para desplegar solo lo necesario con pagos simulados, sigue los pasos 1 a 3 de abajo (en el paso 3 incluye `pagar-pedido-simulado`; `webhook-wompi` y el paso 4 se pueden dejar para cuando se active Wompi).

**Activar Wompi más adelante:** configura sus tres secretos (abajo), `supabase secrets set --project-ref tahnazumbqsupzpusrba PASARELA_PAGO=wompi`, vuelve a desplegar `crear-pedido` y `pagar-pedido-simulado` si cambiaron, y haz el paso 4. Con Wompi activo, `pagar-pedido-simulado` responde "Los pagos de prueba están desactivados".

Con Wompi, los pagos son **solo en sandbox**. Los tres secretos de Wompi ya están en Supabase (`WOMPI_PUBLIC_KEY` = `pub_test_…`, `WOMPI_INTEGRITY_SECRET`, `WOMPI_EVENTS_SECRET`); si hay que cambiarlos, en el panel de Wompi Sandbox → **Desarrolladores → Secretos para integración técnica**:
```powershell
supabase secrets set --project-ref tahnazumbqsupzpusrba WOMPI_PUBLIC_KEY=pub_test_... WOMPI_INTEGRITY_SECRET=test_integrity_... WOMPI_EVENTS_SECRET=test_events_...
```
Opcional: `WOMPI_REDIRECT_URL` (a dónde vuelve el checkout). Por defecto es `https://tahnazumbqsupzpusrba.supabase.co/functions/v1/webhook-wompi/retorno/{orderId}`, que solo dice "vuelve a la app"; la app cierra el WebView al llegar ahí (`ShopRepository.isCheckoutReturn`).

**Desplegar, en este orden** (cada paso necesita el anterior):
1. Reglas e índices de Firestore: `firebase deploy --only firestore:rules,firestore:indexes` (los índices de `orders` tardan unos minutos en construirse).
2. Migraciones de Supabase (SQL Editor o `supabase db push`): `20261118000000_storage_productos.sql` (bucket de fotos) y `20261118010000_pedidos_vencidos.sql` (pg_cron cada 10 min; usa el `cron_secret` del Vault de C2).
3. Edge Functions:
   ```powershell
   supabase functions deploy crear-pedido --project-ref tahnazumbqsupzpusrba --use-api
   supabase functions deploy pagar-pedido-simulado --project-ref tahnazumbqsupzpusrba --use-api
   supabase functions deploy actualizar-pedido --project-ref tahnazumbqsupzpusrba --use-api
   supabase functions deploy webhook-wompi --project-ref tahnazumbqsupzpusrba --use-api --no-verify-jwt
   supabase functions deploy tareas-programadas --project-ref tahnazumbqsupzpusrba --use-api
   ```
   `webhook-wompi` **debe** ir sin verificación JWT (la llama Wompi; su seguridad es la firma del evento). Está en `supabase/config.toml`; `--no-verify-jwt` lo asegura.
4. En el panel de **Wompi Sandbox → Desarrolladores → URL de eventos**, pon:
   `https://tahnazumbqsupzpusrba.supabase.co/functions/v1/webhook-wompi`
5. La app (APK nuevo con el plugin `tienda`).

**Probar una compra de punta a punta (sandbox):** con un dueño, agrega productos al carrito, "Confirmar compra" y en el checkout de Wompi usa los datos de prueba de su documentación (https://docs.wompi.co/docs/colombia/datos-de-prueba-en-sandbox/):

| Método | Aprobada | Rechazada |
|---|---|---|
| Tarjeta | `4242 4242 4242 4242` | `4111 1111 1111 1111` |
| Nequi | `3991111111` | `3992222222` |
| PSE | banco que aprueba | banco que rechaza |

Tarjetas: cualquier fecha futura y cualquier CVC de 3 dígitos; cualquier otro número termina en `ERROR`. Revisa en Firestore que el pedido pase a `pagado` (o `pago_rechazado`), el stock y `stockReservado`, y los avisos "Pago aprobado" / "Nuevo pedido". En **Supabase → Edge Functions → webhook-wompi → Logs** se ve cada evento ("Evento Wompi {...}").

**Expirar a mano** (sin esperar 10 min):
```powershell
curl.exe -X POST https://tahnazumbqsupzpusrba.supabase.co/functions/v1/tareas-programadas -H "x-cron-secret: <CRON_SECRET>" -H "Content-Type: application/json" -d '{\"tarea\":\"pedidos-vencidos\"}'
```

## C6. Placa QR (RF-17)

La página pública de la placa es **HTML estático en Firebase Hosting** (gratis en Spark): `hosting/q.html`, `q.css` y `q.js`. `firebase.json` reenvía `/q/**` a `q.html`, que llama a la Edge Function `placa-publica` (Supabase, sin sesión). La URL que va en el QR es `https://mascoti-b27cf.web.app/q/{qrId}` (`PublicLinks` en `lib/core/config`).

**Desplegar, en este orden:**
1. Reglas de Firestore (agregan `qrTags`): `firebase deploy --only firestore:rules --project mascoti-b27cf`
2. Migración del límite de "Ver teléfono" (SQL Editor o `supabase db query --linked -f`): `supabase/migrations/20261123000000_limite_placa_qr.sql`
3. Edge Function (sin JWT: la llama la web pública):
   ```powershell
   supabase functions deploy placa-publica --project-ref tahnazumbqsupzpusrba --use-api --no-verify-jwt
   ```
4. Hosting: `firebase deploy --only hosting --project mascoti-b27cf`
5. La app (APK nuevo).

**Probar:** en la app, Mascota → Documentos → "Crear placa QR". Escanea el código con otro teléfono (o abre `https://mascoti-b27cf.web.app/q/<id>`): debe mostrar la ficha, "Ver teléfono" y "Llamar". Al desactivar la placa, la página dice "Esta placa no está activa". Localmente: `firebase emulators:start --only hosting` sirve la página en http://127.0.0.1:5000/q/<id> (consulta la función ya desplegada).

## C7. Carnet de vacunas en PDF (RF-18)

La Edge Function `generar-carnet` dibuja el PDF con `pdf-lib` (`npm:pdf-lib@1.17.1`, Supabase lo descarga al desplegar), lo guarda en el bucket privado `documentos` y devuelve un enlace firmado de 15 minutos. Usa los secretos que ya existen (`FIREBASE_SERVICE_ACCOUNT`; `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` los pone Supabase).

**Desplegar, en este orden:**
1. Reglas de Firestore (agregan `pets/{petId}/documentos`): `firebase deploy --only firestore:rules --project mascoti-b27cf`
2. Bucket `documentos` (SQL Editor o `supabase db query --linked -f`): `supabase/migrations/20261124000000_storage_documentos.sql`
3. Edge Function (verifica el token de Firebase por su cuenta):
   ```powershell
   supabase functions deploy generar-carnet --project-ref tahnazumbqsupzpusrba --use-api --no-verify-jwt
   ```
4. La app (APK nuevo).

**Probar:** con una mascota que tenga vacunas en su historial, Mascota → Documentos (o "Carnet · Vacunas y controles" en el home) → "Generar carnet PDF". Debe abrirse el PDF en el visor del teléfono; "Compartir" lo envía por WhatsApp o correo. En Supabase → Storage → `documentos` aparece `pets/<petId>/documentos/carnet-<fecha>.pdf` y en Firestore `pets/<petId>/documentos/carnet`.

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
| No llegan las notificaciones push | Emulador sin Google Play, permiso denegado o `valido: false` en `users/{uid}/devices` (cierra sesión y vuelve a entrar para registrar el token). Mira los logs de la Edge Function `citas` o `tareas-programadas` en Supabase (sección C4). |
| google_sign_in pide `serverClientId` | Pásalo con `--dart-define=GOOGLE_SERVER_CLIENT_ID=<client ID web>` (Firebase → Authentication → Google → Configuración del SDK web). |
