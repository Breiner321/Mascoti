# Arquitectura de Mascoti: microkernel

## Idea general

La app se divide en un **núcleo (kernel)** mínimo y estable y en **plugins** independientes, uno por módulo funcional. El kernel sabe *cómo* cargar plugins, pero no *qué* hacen. Así se puede:

- trabajar en paralelo (cada persona en su plugin, con pocos conflictos de git);
- activar o desactivar un módulo completo (p. ej. dejar fuera el chatbot) editando una sola línea;
- probar cada plugin por separado.

```
┌──────────────────────────────────────────────────────────────┐
│                         APK Flutter                          │
│  ┌────────────────────────────────────────────────────────┐  │
│  │                     KERNEL (lib/core)                  │  │
│  │  PluginRegistry · Sesión/Auth · Router · Tema · Shell  │  │
│  │  Firebase bootstrap · Notificaciones · Widgets comunes │  │
│  └───────▲──────────▲──────────▲──────────▲──────────▲────┘  │
│          │          │          │          │          │       │
│   ┌──────┴───┐ ┌────┴────┐ ┌───┴────┐ ┌───┴────┐ ┌───┴────┐  │
│   │ clinica  │ │mascotas │ │reservas│ │ tienda │ │  chat  │… │
│   └──────────┘ └─────────┘ └────────┘ └────────┘ └────────┘  │
└───────────────┬──────────────────────────────────────────────┘
                │ SDK Firebase (Auth, Firestore, FCM) · supabase_flutter (Storage, Functions)
┌───────────────▼─────────────────────┐ ┌──────────────────────────────────────┐
│ Firebase (Spark): Auth con Google · │ │ Supabase: Storage (bucket mascoti +  │
│ Firestore (+firestore.rules) · FCM  │◄┤ políticas) · Edge Functions (TS/Deno)│
└─────────────────────────────────────┘ └──────────────────────────────────────┘
   Las Edge Functions escriben en Firestore (API REST + cuenta de servicio).
   Supabase acepta el ID token de Firebase (Third-party Auth): un solo login.
```

## El contrato del plugin

`lib/core/kernel/mascoti_plugin.dart`:

```dart
abstract class MascotiPlugin {
  String get id;                          // 'clinica', 'mascotas', …
  Set<UserRole> get roles;                // quién lo ve
  List<RouteBase> routes();               // rutas go_router con prefijo /<id>
  List<PluginDestination> destinations(UserRole role); // pestañas inferiores
  Future<void> initialize() async {}      // opcional: configuración al arrancar
  // opcional: ruta obligatoria para el usuario (onboarding, perfil incompleto…)
  ProviderListenable<AsyncValue<String?>>? requiredStep(AppUser user) => null;
}
```

**Pasos obligatorios sin que el core conozca los plugins.** Un plugin puede exigir que el usuario pase por una de sus rutas antes de usar la app (p. ej. `clinica` exige `/clinica/perfil-atencion` mientras `clinics/{id}.estado == 'incompleto'`). El plugin devuelve un provider desde `requiredStep`; el core (`pendingStepProvider`) solo combina esos valores y el `redirect` lleva al usuario a esa ruta (permite además `/perfil` para cerrar sesión). Mientras el plugin responde, el usuario espera en el splash.

`lib/core/kernel/plugin_manifest.dart` es la **única** lista de plugins activos:

```dart
final List<MascotiPlugin> enabledPlugins = [
  MascotasPlugin(),
  ClinicaPlugin(),
  // ChatbotPlugin(),   ← desactivado = fuera de la app
];
```

`PluginRegistry` valida que no haya ids ni rutas duplicadas, y entrega al router las rutas y al `AppShell` las pestañas según el rol del usuario.

## Plugins previstos

| Plugin | Rol | RF | Semana |
|---|---|---|---|
| `core/auth` (kernel) | ambos | 01, 02, 03 | 1 |
| `clinica` | clínica | 04, 05, 06 + registros médicos | 2–3 |
| `mascotas` | dueño | 08 + registro de mascotas | 3 |
| `directorio` | dueño | 09 | 3 |
| `reservas` | ambos | 14 | 4 |
| `core/notificaciones` (kernel) | ambos | 13 | 4 |
| `chat` | ambos | 15, 16 | 5 |
| `tienda` | ambos | 07 (clínica), 12 (dueño) | 6 |
| `sos` | dueño | 10 | 7 |
| `utilidades` | dueño | 17, 18 | 7 |
| `chatbot` | dueño | 11 | 7 (opcional) |

## Reglas de dependencia

```
plugins/*  ──►  core/*        ✔ permitido
core/*     ──►  plugins/*     ✘ prohibido (excepto plugin_manifest.dart)
plugins/a  ──►  plugins/b     ✘ prohibido → usar rutas o mover lo común al core
```

La comunicación entre plugins se hace por **rutas** (`context.push('/reservas/nueva?clinicId=abc')`) o por **datos compartidos en Firestore**, nunca con imports directos.

## Capas dentro de un plugin

```
plugins/clinica/
  clinica_plugin.dart
  domain/      Service, Clinic… (modelos inmutables con fromMap/toMap)
  data/        ServicesRepository (única clase que habla con Firestore)
  presentation/
    services_page.dart
    service_form_sheet.dart
    services_providers.dart  (StreamProvider / Notifier)
```

## Sesión y enrutamiento

1. `authStateChanges()` de Firebase → `sessionProvider` (Riverpod) produce un `SessionState`:
   - `SessionLoading` → pantalla de carga
   - `SignedOut` → `/bienvenida`
   - `NeedsRegistration` (logueado en Google pero sin `users/{uid}`) → `/registro`
   - `Suspended` → `/cuenta-suspendida` con el mensaje de RF-02 (y el botón para salir)
   - `SignedIn(AppUser)` → el paso obligatorio pendiente (`requiredStep` de algún plugin) o, si no hay, la primera pestaña del rol (según el orden `order` de las `PluginDestination`)
2. `go_router` usa `redirect` + `refreshListenable` para mover al usuario según ese estado.
3. Todos los providers de datos dependen de la sesión, así que al cerrar sesión (RF-03) los listeners se cancelan automáticamente.

## Dónde vive la lógica

| Tipo de operación | Dónde | Ejemplo |
|---|---|---|
| CRUD de datos propios | App → Firestore, protegido con `firestore.rules` | Servicios de la clínica (RF-05) |
| Transacciones entre colecciones o datos de confianza | **Edge Function** de Supabase (`supabase/functions/`) | `completar-registro` (RF-01), `solicitar-cita` (RF-14) |
| Reacciones a cambios | Dentro de la Edge Function que hace el cambio (no hay triggers de Firestore en el plan gratuito) | stock 0 → `agotado` en la función de pago (RF-07); push al aprobar cita |
| Tareas programadas | **pg_cron** de Supabase que llama a una Edge Function | recordatorios (RF-13), no-show (RF-14) |
| Integraciones externas con secretos | **Edge Function** con secretos de Supabase (`supabase secrets set`) | webhook Wompi (RF-12), PDF (RF-18), página pública del QR (RF-17) |
| Archivos | App → **Supabase Storage** con `StorageRepository` (`core/storage`) | fotos de mascotas, adjuntos del chat |
| Tareas de administración | Scripts en `functions/admin/` con la cuenta de servicio | suspender una cuenta (RF-02) |

La lógica de cada Edge Function va en `supabase/functions/_shared/` como TypeScript **sin dependencias** (se prueba con vitest desde `functions/`); el `index.ts` de la función solo la conecta con Google y Supabase.
