# Plan de desarrollo — 8 semanas, 3 desarrolladores

Fechas sugeridas (ajustar al calendario real): **Semana 0** del 29 sep al 2 oct de 2026; **semanas 1–8** del 5 oct al 27 nov de 2026.

## Roles del equipo

| Rol | Persona | Responsable de |
|---|---|---|
| **Dev A: Core y Backend** (líder técnico) | _nombre_ | Kernel, auth, reglas de seguridad, Edge Functions (Supabase), notificaciones, pagos, PDF, CI. Revisa todos los PR que tocan `core/`, `firestore.rules` o `functions/`. |
| **Dev B: Módulo Clínica** | _nombre_ | Perfil de atención, servicios, agenda, registros médicos, bandeja de solicitudes, inventario. |
| **Dev C: Módulo Dueño** | _nombre_ | Mascotas, historial, directorio/mapa, reservas (lado dueño), tienda, SOS, QR. |

Cada persona trabaja con **su propia sesión de Claude Code en su propia rama**. Cada PR lo revisa al menos otra persona.

## Semana 0: preparación (esta semana)

- [x] `CLAUDE.md`, documentación y RF en Markdown en el repo
- [x] Esqueleto Flutter con kernel microkernel, reglas y Functions base
- [x] **Dev A:** crear el proyecto Firebase de desarrollo (ID real: `mascoti-b27cf`, en `.firebaserc`), app Android `co.mascoti.mascoti` registrada con `flutterfire configure` y Auth con Google habilitado
- [x] **Dev A:** crear Firestore en `mascoti-b27cf` (plan gratuito)
- [x] **Decisión:** Firebase gratuito + Supabase (Storage y Edge Functions) + OpenStreetMap, en lugar de Blaze y Google Maps
- [ ] **Dev A:** desplegar reglas de Firestore; en Supabase: Third-party Auth con Firebase, migración de Storage, secreto `FIREBASE_SERVICE_ACCOUNT` (sección C2 de `docs/configuracion-inicial.md`); crear `mascoti-prod` más adelante
- [x] `scripts/setup.ps1` ejecutado: plataforma Android, paquetes, `flutter analyze` sin issues, `flutter test` y pruebas de Functions/reglas en verde
- [ ] **Todos:** instalar Flutter, Android Studio, Node 22, Firebase CLI, FlutterFire CLI y Claude Code y correr la app en un emulador Android (✔ Breiner, 29 sep 2026)
- [ ] **Todos:** registrar el SHA-1 de su llave de depuración en Firebase — necesario para el login con Google (✔ Breiner, 29 sep 2026: login con Google probado hasta la pantalla de registro)
- [ ] **Dev A:** proteger la rama `main` en GitHub (PR obligatorio + CI en verde)

## Semanas 1–8

| Sem. | Dev A: Core y Backend | Dev B: Clínica | Dev C: Dueño | Entregable demostrable |
|---|---|---|---|---|
| **1** | Desplegar `completar-registro` (Supabase) y reglas; pruebas de reglas en CI; revisar RF-02/03 contra el esqueleto (suspensión, errores, pruebas del `AuthRepository`) | RF-01: autocompletado Google Places en el formulario de clínica; UI de bienvenida/registro igual al mockup LOGIN | Home del dueño según el mockup (tarjeta de mascota, próxima cita, accesos) + onboarding de 3 pasos (RF-01) | Registrarse como dueño o clínica, entrar al home de su rol y cerrar sesión |
| **2** | Reglas + pruebas de reglas para `services`/`slots`; emuladores en CI | RF-04 perfil de atención · RF-05 catálogo de servicios · RF-06 agenda | Registro/edición de **mascotas** (sin RF, necesario) + subida de foto a Storage | La clínica configura servicios y horarios; el dueño registra mascotas |
| **3** | Índices y reglas de `pets`/`medicalRecords`; geohash en `clinics` | **Registro médico** (clínica crea consultas y vacunas) | RF-08 historial (timeline) · RF-09 directorio con mapa | El dueño ve clínicas cercanas y el historial de su mascota |
| **4** | RF-13: FCM, `devices`, triggers de push, jobs programados (recordatorios, no-show) | RF-14 lado clínica: bandeja de solicitudes, aprobar/rechazar | RF-14 lado dueño: agendar (mockup "Agendar cita"), "Mis citas", cancelar | Ciclo completo de una cita con notificación push |
| **5** | RF-15 núcleo del chat: modelo, reglas, repositorio, estado no leído | RF-16 adjuntos (Storage + reglas) + vista clínica del chat | RF-15 UI del chat del dueño, "escribiendo…", offline | Dueño y clínica conversan e intercambian archivos |
| **6** | RF-12 backend: Wompi sandbox, webhook, transacción de stock, `orders` | RF-07 inventario (fotos comprimidas, stock, agotado) + pedidos recibidos | RF-12 UI: catálogo (mockup "Tienda"), carrito, checkout | Compra de prueba de punta a punta |
| **7** | RF-18 PDF (`pdf-lib`) + RF-17 página pública del QR (Hosting + Function) | RF-11 chatbot (árbol de decisión local) **o** apoyo a QA si hay retraso | RF-10 SOS · RF-17 UI de placa QR · RF-18 UI de documentos | Emergencia, placa QR y carnet PDF funcionando |
| **8** | Auditoría de reglas de seguridad, `flutter build apk --release`, firma del APK | Pruebas de extremo a extremo del flujo clínica, corrección de errores | Pruebas de extremo a extremo del flujo dueño, pulido visual contra mockups | **APK final** + demo |

## Ritual semanal

- **Lunes (30 min):** planear. Cada persona elige sus RF y crea sus ramas.
- **Diario (10 min):** qué hice, qué haré y qué me bloquea.
- **Viernes:** demo del entregable en un celular real, merge de los PR aprobados a `main` y etiqueta `v0.<semana>` (p. ej. `v0.3`).

## Si hay retraso (en este orden)

1. **RF-11 Chatbot:** dejar solo FAQ local o quitar el plugin del manifiesto.
2. **RF-17:** mostrar el número enmascarado en la página pública, sin servicio de reenvío (ya previsto).
3. **RF-12:** pagos solo en sandbox, sin tarjetas guardadas.
4. **RF-16:** adjuntos solo como archivo nuevo, sin "Adjuntar desde historial".
5. **RF-18:** solo carnet de vacunación, sin certificado de viaje.

## Avance

| RF | Estado | PR |
|---|---|---|
| RF-01 | 🟨 | backend, interfaz de registro (LOGIN + Places), paso obligatorio de la clínica, home y onboarding del dueño. Direcciones con OpenStreetMap; registro con la Edge Function `completar-registro`. Falta: secreto de Supabase y prueba de punta a punta |
| RF-02 | 🟨 | errores tipados, suspensión (reglas + Function) y pruebas |
| RF-03 | ✅ | logout local sin red; borra el token FCM del dispositivo antes de salir (RF-13) |
| RF-04 | 🟨 | pantalla `/clinica/perfil-atencion` (especies, emergencias, horario base), `ClinicRepository` en tiempo real, paso de `incompleto` a `activo`, enlace desde el perfil y la agenda, pruebas. Falta: prueba de punta a punta en el emulador con Firebase |
| RF-05 | 🟨 | `/clinica/servicios`: lista en tiempo real, formulario crear/editar en bottom sheet, borrado lógico con confirmación, animación y snackbar, reintento ante fallo de red; `ServicesRepository` y pruebas. Falta: advertencia de citas activas (TODO, depende de RF-14) y prueba de punta a punta |
| RF-06 | 🟨 | agenda "Mi día": calendario (`table_calendar`), franjas según `horarioBase`, selección múltiple Disponible (con servicio y copia del precio) / No disponible / Quitar, guardado en `WriteBatch`, validación de solapamientos por duración del servicio, franjas ocupadas y pasadas de solo lectura; lógica pura en `plugins/clinica/domain/day_schedule.dart` con pruebas. Las citas del día y "Próximas citas" llegaron con RF-14. Falta: prueba de punta a punta |
| RF-07 | ⬜ | |
| RF-08 | 🟨 | base (Dev A): vinculación con código de paciente, reglas del historial, `MedicalRecordsRepository`, adjuntos firmados. Lado dueño: pestaña "Historial médico" del perfil con línea de tiempo en tiempo real (más reciente arriba), tarjetas expandibles (tratamiento, vacunas con lote y próxima dosis, adjuntos), imagen a pantalla completa con zoom, PDF con `url_launcher`, "Archivo no disponible" por adjunto con reintento, estado vacío; código MSC-XXXX con copiar y "Clínicas con acceso" con revocar; datos de ejemplo (`npm run seed:historial`, ver `docs/datos-prueba.md`); pruebas. Falta: prueba de punta a punta con adjuntos reales en Supabase |
| RF-09 | 🟨 | base (Dev A): `ClinicsGeoRepository` (radio, filtros, distancia) y `categoriasServicio`. Plugin `directorio` (pestaña "Mapa"): mapa de OpenStreetMap (`flutter_map`, sin API key) centrado en el usuario con marcadores del tema, chips (tipo de animal, servicio, 24 horas = emergencias, distancia), lista con "Agendar" (Próximamente hasta RF-14), tarjeta del marcador, sin permiso → búsqueda por dirección o ciudad (Photon), aviso de precisión > 500 m, sin resultados con radio 5–50 km, perfil público `/directorio/clinica/:id` con servicios, "Llamar" y "Cómo llegar"; pruebas. Falta: prueba de punta a punta con clínicas reales |
| RF-10 | ⬜ | |
| RF-11 | ⬜ | |
| RF-12 | ⬜ | |
| RF-13 | 🟨 | (Dev A) cliente en `lib/core/notificaciones`: permiso, token en `users/{uid}/devices` con `onTokenRefresh`, borrado al cerrar sesión, navegación al tocar (app cerrada, en segundo plano o abierta), campana con contador y `/notificaciones`; servidor: `enviarNotificacion` (documento + push FCM v1, tokens inválidos), avisos de cada cambio de cita, recordatorios diarios 8:00 a. m. (citas de mañana, vacunas en 3 días) sin duplicados; reglas y pruebas. Falta: probar push en un celular real con el ciclo completo |
| RF-14 | 🟨 | backend (Dev A): Edge Function `citas` (solicitar, responder, cancelar, completar) con transacción optimista y prueba de carrera en el emulador; tarea cada 30 min (`no_asistio`, `expirada`) con pg_cron; modelo `Appointment` con máquina de estados; `AppointmentsRepository` (mis citas, solicitudes pendientes, agenda del día, acciones) en `lib/core/data`; reglas e índices. Lado dueño (Dev C): `/reservas/nueva` (servicios con precio, mascota, calendario con días disponibles, horas en tiempo real, comentario; sin clínica → "Tus clínicas" o mapa), confirmación con aviso del historial y manejo de horario tomado, "Mis citas" (Próximas/Historial con chip de estado), detalle `/reservas/:id` (Cómo llegar, Llamar, Cancelar hasta 2 h antes) y tarjeta "Próxima cita" del home; lógica en `plugins/reservas/presentation/dueno/booking_logic.dart` con pruebas. Lado clínica: pestaña "Solicitudes" con contador (pendientes en tiempo real con mascota, especie, dueño, servicio, fecha y comentario), detalle `/reservas/:id` con historial de la mascota, Aprobar, Rechazar (motivo obligatorio), Cancelar (motivo obligatorio y aviso al dueño), Marcar como atendida (desde la hora de inicio) → Registrar consulta con `appointmentId`, aviso si otra persona ya respondió; en la Agenda las franjas reservadas muestran la cita y abren su detalle, y "Próximas citas" de hoy y mañana (mockup "Mi día"); pruebas. Falta: favoritas (RF-10) y prueba de punta a punta |
| RF-15 | ⬜ | |
| RF-16 | ⬜ | |
| RF-17 | ⬜ | |
| RF-18 | ⬜ | |
| Mascotas (soporte) | 🟨 | formulario crear/editar (`/mascotas/nueva`, `/mascotas/perfil/:petId/editar`) con foto (cámara o galería, compresión a ≤ 1 MB, JPG/PNG), alergias y condiciones en chips, contacto de emergencia (10 dígitos); `PetsRepository` (stream, crear, editar, foto en Supabase por etapas y guardado sin foto con "Reintentar" si falla); perfil `/mascotas/perfil/:petId` con pestañas vacías para RF-08 y RF-17/18; tarjeta "Mi mascota" con mascota activa y selector; pruebas. Falta: prueba de punta a punta con Supabase en el emulador |
| Registros médicos (soporte) | 🟨 | pestaña "Pacientes" de la clínica (`/clinica/pacientes`): lista en tiempo real con buscador y estado vacío; "Vincular paciente" con el código MSC-XXXX (`vincular-mascota`, mensajes de código inexistente y límite de intentos) y nombre del dueño en `clinics/{id}/pacientes`; perfil del paciente de solo lectura con alergias y condiciones en rojo e historial; formulario de consulta (fecha, diagnóstico, tratamiento, vacunas con lote y próxima dosis, adjuntos JPG/PNG/PDF ≤ 10 MB con reintento) que se corrige 24 h y luego es de solo lectura; pruebas. Falta: desplegar las reglas, vista de PDF en la app y prueba de punta a punta con Supabase |

Leyenda: ⬜ pendiente · 🟨 en curso · 🟩 integrado en `main`

## Cambios de alcance (después de las pruebas del equipo)

Detalle en [cambios-alcance.md](cambios-alcance.md).

| # | Cambio | Estado | Notas |
|---|---|---|---|
| 1 | Nombre del dueño | ✅ | `users.nombre` y `telefono` en el registro, `nombreVisible` como única fuente, "Completa tu perfil", "Editar perfil"; citas, vinculación y notificaciones con el nombre real |
| 2 | Disponibilidad automática según el horario | ✅ | `horarioSemanal` + `reservas` + `excepciones`; `Availability` (Dart) = `disponibilidad.ts` con casos compartidos; `citas/solicitar` aparta todas las franjas del servicio; agenda de excepciones con festivos; aviso de citas fuera del horario; `npm run migrar-horario` |
| 3 | Accesibilidad y modo oscuro | ✅ | 4 paletas AA (claro = mockups, oscuro, alto contraste), Perfil → Accesibilidad, lector de pantalla, 48 dp, texto al 200 %, sin depender del color, reducir animaciones; verificadores de Flutter en las pantallas principales; `docs/accesibilidad.md` |
| 4 | Mapa con todas las veterinarias | ⬜ | |
