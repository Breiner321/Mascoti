# CLAUDE.md — Mascoti

Instrucciones para Claude Code en este repositorio. Léelas completas antes de cada tarea.

## Qué es Mascoti

App móvil (**solo APK Android** por ahora) que conecta **dueños de mascotas** con **clínicas veterinarias**: agenda, historial médico, directorio con mapa, tienda, chat, SOS, placa QR y carnet PDF. Hay 2 roles: `dueno` y `clinica`.

- Requerimientos: `docs/requerimientos/RF-XX.md` (la sección **Adaptación a Firebase** de cada RF prevalece sobre el texto original).
- Arquitectura: `docs/arquitectura.md` · Modelo de datos: `docs/modelo-datos.md` · Stack: `docs/stack.md` · Plan: `docs/plan.md` · Configuración: `docs/configuracion-inicial.md` · Flujo con Claude Code: `docs/flujo-trabajo.md`.
- Mockups: `docs/mockups/mockups_Mascoti.pdf` (la pantalla de LOGIN está en espejo horizontal).

## Stack (no cambiar sin aprobación del equipo)

- **App:** Flutter (Dart 3) · Material 3 · `flutter_riverpod` (estado + inyección de dependencias) · `go_router` (navegación).
- **Backend:** Firebase plan gratuito — Auth (proveedor Google), Cloud Firestore, Cloud Messaging. **Supabase** — Storage (bucket `mascoti`) y **Edge Functions en TypeScript** (`supabase/functions/`, Deno), que escriben en Firestore con una cuenta de servicio. Supabase acepta el login de Firebase (Third-party Auth).
- **Mapas y direcciones:** OpenStreetMap (búsqueda con Photon en `core/places`; mapa con `flutter_map`). Sin API key.
- **Sin generación de código:** no usar `freezed`, `json_serializable` ni `riverpod_generator`. Los modelos son clases inmutables escritas a mano con `fromMap`/`toMap`/`copyWith`.
- **No hay backend REST propio ni JWT propio.** Las URLs tipo `POST /auth/login` o `PATCH /clinics/{id}` del documento original se traducen a: escritura directa a Firestore protegida por `firestore.rules`, **o** una Edge Function de Supabase cuando se necesita lógica de confianza (transacciones entre colecciones, pagos, PDF, envío de push). Su lógica va en `supabase/functions/_shared/` sin dependencias, con pruebas en `functions/test/`.

## Arquitectura microkernel (reglas obligatorias)

```
lib/
  core/            ← el KERNEL: nada de lógica de negocio de módulos
    kernel/        MascotiPlugin, PluginRegistry, manifiesto de plugins
    domain/        modelos que usan varios plugins (Clinic, ClinicService, Slot, Pet)
    auth/          sesión, login/logout Google, roles (RF-01..03)
    router/        GoRouter construido con las rutas de los plugins
    theme/         colores y tipografía de los mockups
    widgets/       componentes compartidos (AppShell, SosButton, estados vacíos…)
    firebase/      inicialización y emuladores
  plugins/
    <modulo>/      un plugin por módulo funcional
      <modulo>_plugin.dart   ← implementa MascotiPlugin
      data/        repositorios (acceso a Firestore, Storage y Edge Functions)
      domain/      modelos
      presentation/ páginas, widgets y providers de UI
```

1. **Un plugin nunca importa otro plugin.** Si dos plugins necesitan algo común, va al `core` (o se comunica por rutas de `go_router`, p. ej. `context.push('/reservas/nueva?clinicId=…')`).
2. **El core no importa plugins**, salvo el manifiesto `lib/core/kernel/plugin_manifest.dart`, que es el único lugar donde se registran.
3. Cada plugin declara: `id`, `roles` que lo ven, `routes()` y `destinations(role)` (pestañas de la barra inferior).
4. Las pantallas nunca llaman a `FirebaseFirestore.instance` directamente: usan un **repositorio** del plugin, expuesto con un `Provider`.
5. Las rutas de un plugin empiezan con su prefijo (`/clinica/...`, `/mascotas/...`).

## Convenciones

- Código (clases, variables) en **inglés**; textos de UI, colecciones/campos de Firestore y documentación en **español** tal como aparecen en los RF (`tiposAnimales`, `estado`, `ownerUid`…).
- Archivos `snake_case.dart`; un widget público por archivo.
- Estados de la UI siempre cubiertos: cargando, vacío, error (con reintento) y datos.
- Validaciones de formularios exactamente como dicen los RF (longitudes, rangos, mensajes).
- Mensajes al usuario: los textos literales de los RF.
- Colores solo desde `AppColors` / `Theme.of(context)`; nada de colores sueltos. `AppColors` lee la paleta activa (claro, oscuro, alto contraste): no se usa dentro de `const`.
- Accesibilidad (WCAG 2.1 AA, ver `docs/accesibilidad.md`): `tooltip` en botones de ícono, 48 dp, estados con ícono o texto (no solo color), sin alturas fijas con texto; las pantallas nuevas llevan las pruebas de `test/a11y.dart`.
- Fechas en Firestore como `Timestamp`; en Dart como `DateTime`.

## Seguridad (obligatorio en cada PR que toque datos)

- Toda colección nueva o campo nuevo → actualizar `firestore.rules` (y las políticas de Storage en `supabase/migrations/` si hay archivos) **y** `docs/modelo-datos.md`.
- El rol se lee en las reglas desde `users/{uid}.role` (función `hasRole()` de `firestore.rules`); ese documento solo lo crea la Edge Function `completar-registro` y el rol es inmutable. No se usan custom claims para el rol (el único claim, `role: "authenticated"`, es un requisito técnico de Supabase).
- Nunca poner secretos (llaves de pasarela de pago, Dialogflow) en la app: van en las Edge Functions como secretos (`supabase secrets set`).
- La app nunca confía en datos del cliente para precios/stock/estado de pago: eso lo hace una Edge Function.

## Comandos

```bash
flutter pub get
flutter analyze                  # debe quedar en 0 issues
flutter test                     # pruebas unitarias y de widgets
flutter run --dart-define-from-file=env/dev.json   # app contra Firebase + Supabase
flutter run --dart-define=USE_EMULATORS=true      # app contra emuladores locales (Auth + Firestore)
flutter build apk --release

cd functions && npm install && npm run lint && npm test   # lógica de Edge Functions (+ npm run test:rules con Java)
deno check supabase/functions/*/index.ts
supabase functions deploy <nombre> --project-ref tahnazumbqsupzpusrba --use-api
firebase emulators:start         # auth, firestore (UI en http://localhost:4000)
```

## Cómo trabajar una tarea (flujo esperado de Claude Code)

1. Leer el RF completo en `docs/requerimientos/` y los docs de arquitectura y modelo de datos.
2. Proponer un plan corto (archivos a crear/modificar, colecciones, reglas, pruebas) y **esperar aprobación** antes de escribir código.
3. Implementar dentro del plugin correspondiente, respetando las reglas del microkernel.
4. Escribir pruebas: repositorio (con `fake_cloud_firestore`), lógica de validación y al menos una prueba de widget de la pantalla principal. Para reglas de seguridad, pruebas en `functions/test/` contra el emulador.
5. Ejecutar `flutter analyze` y `flutter test` (y `npm test` en `functions/` si aplica) hasta que pasen.
6. Actualizar `docs/modelo-datos.md` si cambió el modelo y marcar el avance en `docs/plan.md`.
7. Commit en español con prefijo convencional: `feat(clinica): RF-05 catálogo de servicios`.

No hagas push ni merge a `main`; el equipo revisa por Pull Request.
