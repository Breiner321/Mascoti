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
4. **Storage → Comenzar** (misma región).
5. **Uso y facturación → plan Blaze** + **alerta de presupuesto** de USD 5 (lo exigen Cloud Functions y Cloud Scheduler).
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
   firebase deploy --only firestore:rules,firestore:indexes,storage,functions
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

## D. Todos: correr la app

```powershell
git pull
flutter pub get
flutter run                                         # contra Firebase mascoti-dev
```

Con emuladores locales (recomendado para desarrollar sin tocar datos reales):

```powershell
# Terminal 1
cd functions ; npm install ; npm run build ; cd ..
firebase emulators:start
# Terminal 2
flutter run --dart-define=USE_EMULATORS=true
# En un celular físico, usa la IP del PC:
flutter run --dart-define=USE_EMULATORS=true --dart-define=EMULATOR_HOST=192.168.1.20
```

La interfaz de los emuladores (usuarios, datos, logs) queda en http://localhost:4000.

## E. Problemas comunes

| Síntoma | Solución |
|---|---|
| Error `ApiException: 10` o `DEVELOPER_ERROR` al iniciar sesión | Falta el SHA-1 de tu PC en Firebase (sección C). |
| `minSdkVersion 21 cannot be smaller than 23` | En `android/app/build.gradle.kts`, pon `minSdk = 23`. |
| La app no conecta con los emuladores | Revisa `EMULATOR_HOST` y que el firewall de Windows permita los puertos 8080, 9099 y 5001. |
| `completarRegistro` responde `NOT_FOUND` | La Function no está desplegada (paso B.8) o la región no coincide (`us-east1` en `env.dart` y en `functions/src/config.ts`). |
| google_sign_in pide `serverClientId` | Pásalo con `--dart-define=GOOGLE_SERVER_CLIENT_ID=<client ID web>` (Firebase → Authentication → Google → Configuración del SDK web). |
