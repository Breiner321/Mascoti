# Mascoti

App veterinaria móvil (APK Android) con **arquitectura microkernel** para la gestión de clínicas veterinarias y la atención de mascotas en tiempo real: agenda, directorio con GPS, e-commerce, carnet QR, chat y módulo de emergencias SOS.

**Stack:** Flutter (Dart) · Riverpod · go_router · Firebase (Auth con Google, Firestore, Storage, Cloud Messaging, Cloud Functions en TypeScript).

## Documentación

| Documento | Contenido |
|---|---|
| [CLAUDE.md](CLAUDE.md) | Reglas del proyecto para Claude Code (y para el equipo) |
| [docs/configuracion-inicial.md](docs/configuracion-inicial.md) | Instalación y configuración de Firebase **(empieza aquí)** |
| [docs/plan.md](docs/plan.md) | Plan de 8 semanas, responsables y avance |
| [docs/flujo-trabajo.md](docs/flujo-trabajo.md) | Cómo desarrollar cada RF con Claude Code |
| [docs/stack.md](docs/stack.md) | Lenguajes, frameworks y paquetes |
| [docs/arquitectura.md](docs/arquitectura.md) | Microkernel: core, plugins y reglas |
| [docs/modelo-datos.md](docs/modelo-datos.md) | Colecciones de Firestore |
| [docs/requerimientos/](docs/requerimientos/README.md) | RF-01 a RF-18 en Markdown |
| [docs/mockups/](docs/mockups/mockups_Mascoti.pdf) | Mockups |

## Estructura

```
lib/
  core/        kernel: plugins, auth, router, tema, widgets comunes
  plugins/     un módulo funcional por carpeta (mascotas, clinica, reservas, …)
functions/     Cloud Functions (TypeScript)
firestore.rules · storage.rules · firebase.json
docs/          documentación y requerimientos
.claude/       comando /rf y permisos de Claude Code
```

## Comandos rápidos

```bash
flutter pub get
flutter run --dart-define=USE_EMULATORS=true
flutter analyze && flutter test
firebase emulators:start
```

En Claude Code: `/rf RF-05` implementa un requerimiento siguiendo el flujo del equipo.
