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
                │ SDK Firebase (Auth, Firestore, Storage, FCM, Functions)
┌───────────────▼──────────────────────────────────────────────┐
│ Firebase: Auth · Firestore (+rules) · Storage (+rules) ·     │
│ Cloud Functions (TypeScript) · Cloud Messaging · Hosting(QR) │
└──────────────────────────────────────────────────────────────┘
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
}
```

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
   - `NeedsRegistration` (logueado en Google pero sin `users/{uid}`) → `/registro/rol`
   - `Suspended` → cerrar sesión y mostrar el mensaje de RF-02
   - `SignedIn(AppUser)` → primera pestaña del rol (según el orden `order` de las `PluginDestination`)
2. `go_router` usa `redirect` + `refreshListenable` para mover al usuario según ese estado.
3. Todos los providers de datos dependen de la sesión, así que al cerrar sesión (RF-03) los listeners se cancelan automáticamente.

## Dónde vive la lógica

| Tipo de operación | Dónde | Ejemplo |
|---|---|---|
| CRUD de datos propios | App → Firestore, protegido con `firestore.rules` | Servicios de la clínica (RF-05) |
| Transacciones entre colecciones o datos de confianza | **Callable Function** | `completarRegistro` (RF-01), `solicitarCita` (RF-14) |
| Reacciones a cambios | **Trigger de Firestore** | stock 0 → `agotado` (RF-07); push al aprobar cita |
| Tareas programadas | **onSchedule** | recordatorios (RF-13), no-show (RF-14) |
| Integraciones externas con secretos | **Function HTTPS** | webhook Wompi (RF-12), PDF (RF-18), página pública del QR (RF-17) |
