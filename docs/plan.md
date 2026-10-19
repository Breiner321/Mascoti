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
| RF-03 | 🟨 | logout local sin red; falta borrar token FCM (RF-13) |
| RF-04 | 🟨 | pantalla `/clinica/perfil-atencion` (especies, emergencias, horario base), `ClinicRepository` en tiempo real, paso de `incompleto` a `activo`, enlace desde el perfil y la agenda, pruebas. Falta: prueba de punta a punta en el emulador con Firebase |
| RF-05 | 🟨 | `/clinica/servicios`: lista en tiempo real, formulario crear/editar en bottom sheet, borrado lógico con confirmación, animación y snackbar, reintento ante fallo de red; `ServicesRepository` y pruebas. Falta: advertencia de citas activas (TODO, depende de RF-14) y prueba de punta a punta |
| RF-06 | 🟨 | agenda "Mi día": calendario (`table_calendar`), franjas según `horarioBase`, selección múltiple Disponible (con servicio y copia del precio) / No disponible / Quitar, guardado en `WriteBatch`, validación de solapamientos por duración del servicio, franjas ocupadas y pasadas de solo lectura; lógica pura en `plugins/clinica/domain/day_schedule.dart` con pruebas. Falta: lista de citas del día (RF-14) y prueba de punta a punta |
| RF-07 | ⬜ | |
| RF-08 | ⬜ | base lista (Dev A): vinculación con código de paciente, reglas del historial, `MedicalRecordsRepository`, adjuntos firmados |
| RF-09 | ⬜ | base lista (Dev A): `ClinicsGeoRepository` (radio, filtros, distancia) y `categoriasServicio` |
| RF-10 | ⬜ | |
| RF-11 | ⬜ | |
| RF-12 | ⬜ | |
| RF-13 | ⬜ | |
| RF-14 | ⬜ | |
| RF-15 | ⬜ | |
| RF-16 | ⬜ | |
| RF-17 | ⬜ | |
| RF-18 | ⬜ | |
| Mascotas (soporte) | 🟨 | formulario crear/editar (`/mascotas/nueva`, `/mascotas/perfil/:petId/editar`) con foto (cámara o galería, compresión a ≤ 1 MB, JPG/PNG), alergias y condiciones en chips, contacto de emergencia (10 dígitos); `PetsRepository` (stream, crear, editar, foto en Supabase por etapas y guardado sin foto con "Reintentar" si falla); perfil `/mascotas/perfil/:petId` con pestañas vacías para RF-08 y RF-17/18; tarjeta "Mi mascota" con mascota activa y selector; pruebas. Falta: prueba de punta a punta con Supabase en el emulador |
| Registros médicos (soporte) | 🟨 | pestaña "Pacientes" de la clínica (`/clinica/pacientes`): lista en tiempo real con buscador y estado vacío; "Vincular paciente" con el código MSC-XXXX (`vincular-mascota`, mensajes de código inexistente y límite de intentos) y nombre del dueño en `clinics/{id}/pacientes`; perfil del paciente de solo lectura con alergias y condiciones en rojo e historial; formulario de consulta (fecha, diagnóstico, tratamiento, vacunas con lote y próxima dosis, adjuntos JPG/PNG/PDF ≤ 10 MB con reintento) que se corrige 24 h y luego es de solo lectura; pruebas. Falta: desplegar las reglas, vista de PDF en la app y prueba de punta a punta con Supabase |

Leyenda: ⬜ pendiente · 🟨 en curso · 🟩 integrado en `main`
