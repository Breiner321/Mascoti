# Modelo de datos (Cloud Firestore)

Fuente única de verdad del esquema. **Todo PR que agregue o cambie colecciones o campos debe actualizar este archivo y `firestore.rules`.**

Modelos en Dart: `lib/core/domain/` (`Clinic`, `ClinicService`, `Slot`, `Pet`, `MedicalRecord`, `Appointment`), compartidos por todos los plugins. Los enums guardan en Firestore el valor en español de esta página.

Horas (`hora`, `horarioBase.apertura/cierre`): se **guardan** en 24 h `HH:mm`; la app las **muestra** en 12 h con a. m./p. m. (`TimeFormat` en `lib/core/format`).

**Zona horaria:** todas las fechas de agenda y citas se calculan en hora de Colombia (**America/Bogota, UTC−5 sin horario de verano**), aunque el teléfono esté en otra zona: `BogotaTime` en `lib/core/format` y `hora_bogota.ts` en las Edge Functions.

Convenciones: nombres de campos en español como en los RF; fechas como `Timestamp`; dinero en COP como `number` entero (sin decimales) salvo que el RF diga otra cosa; ids generados por Firestore salvo que se indique.

## `users/{uid}`  — RF-01, RF-02 · *se crea solo con la Edge Function `completar-registro` (Supabase)*

| Campo | Tipo | Notas |
|---|---|---|
| uid | string | = id de Firebase Auth |
| email, displayName, photoURL | string | de Google. **No se muestran como nombre de la persona**: usa `AppUser.nombreVisible` (Cambio 1) |
| nombre | string? | nombre completo del **dueño** (Cambio 1): obligatorio al registrarse, 3–60 caracteres sin espacios en los extremos. Lo valida `completar-registro` y las reglas; el dueño lo edita en Perfil. Falta en dueños registrados antes del cambio (la app los lleva a "Completa tu perfil"). La clínica no lo usa: su nombre visible es `clinics.nombre` |
| role | `'dueno' \| 'clinica'` | inmutable (las reglas lo leen con `hasRole()`) |
| estado | `'activo' \| 'suspendido'` | solo lo cambia un administrador (Admin SDK). Se cambia con el script `npm run suspender -- <uid> [--reactivar]` (`functions/admin/`), que además deshabilita la cuenta en Firebase Auth y revoca sus sesiones (o la habilita al reactivar). Una cuenta suspendida solo puede leer su propio perfil |
| clinicId | string? | solo si role = clinica |
| telefono | string? | 10 dígitos. Obligatorio para el dueño desde el Cambio 1 (registro y "Completa tu perfil") |
| ciudad, direccion | string? | perfil del dueño (RF-10, RF-12) |
| onboardingVisto | bool | RF-01 paso 14. `false` al registrarse; el dueño lo pone en `true` al terminar o saltar el onboarding (las reglas solo aceptan un `bool`). Si falta, la app lo trata como `false` |
| createdAt, lastLoginAt | Timestamp | |
| estadoActualizadoEn | Timestamp? | lo pone el script de suspensión |

Subcolecciones: `devices/{deviceId}` `{fcmToken, plataforma, updatedAt, valido}` (RF-13: `deviceId` es un id aleatorio por instalación guardado en el teléfono; la app lo guarda siempre con `valido: true` y `updatedAt` = hora del servidor, y lo borra al cerrar sesión; solo el servidor lo marca `valido: false` cuando FCM rechaza el token; `DeviceRegistry` en `lib/core/notificaciones`) · `cart/{productId}` `{clinicId, cantidad, addedAt}` (RF-12) · `favoriteClinics/{clinicId}` (RF-10).

## `clinics/{clinicId}` — RF-01, RF-04, RF-09

| Campo | Tipo | Notas |
|---|---|---|
| ownerUid | string | uid del usuario clínica |
| nombre, telefono, direccion | string | teléfono de 10 dígitos |
| lat, lng | number | desde OpenStreetMap (buscador de direcciones); obligatorios (los valida `completar-registro`) |
| geo | map `{geohash, geopoint}` | para `geoflutterfire_plus` (RF-09). Lo calcula `completar-registro` (geohash de 10 caracteres, igual a `geofire-common`) |
| tiposAnimales | string[] | `perros, gatos, aves, roedores, reptiles, granja, exoticos` |
| categoriasServicio | string[] | categorías de sus servicios **activos** (RF-05), para filtrar el directorio (RF-09). La actualiza `ServicesRepository.syncCategories` al guardar o desactivar un servicio |
| atencionEmergencias | bool | RF-10 |
| horarioBase | map `{apertura:'08:00', cierre:'18:00', duracionSlotMin:30}` | **Obsoleto (Cambio 2).** Horario único de antes; se lee solo si la clínica no tiene `horarioSemanal` (todos los días abiertos con ese horario). Lo convierte `npm run migrar-horario` |
| horarioSemanal | map `{lun…dom: {abierto, apertura, cierre, descansoInicio?, descansoFin?}}` | Cambio 2 (`WeeklySchedule`). Horas `HH:mm` en múltiplos de la franja; el descanso va dentro del horario. Las reglas validan la estructura (7 días, campos permitidos, `abierto` booleano); las horas las validan la app y el servidor |
| reservas | map `{duracionSlotMin: 15\|30\|60, anticipacionMaxDias: 1–365, anticipacionMinMin: 0–10080}` | Cambio 2 (`BookingSettings`). Por defecto 30 min, 30 días y 120 min |
| osmId | string? | Cambio 4: lugar de OpenStreetMap que corresponde a la clínica (`node/123`, `way/45`), para no mostrarla dos veces en el mapa. Lo escribe solo `npm run vincular-osm` (las reglas no dejan cambiarlo desde la app) |
| calificacion | number? | promedio (futuro) |
| estado | `'incompleto' \| 'activo'` | pasa a activo en RF-04. Mientras sea `incompleto`, la app obliga a la clínica a ir a `/clinica/perfil-atencion` |
| createdAt | Timestamp | |

Subcolecciones:
- `services/{serviceId}` — RF-05: `{nombre, categoria, descripcion, precio, duracionMin, activo, createdAt, updatedAt}`; `precio` en COP: la app solo envía enteros (decisión del equipo; el RF permitía 2 decimales) y las reglas aceptan cualquier número > 0; `categoria ∈ vacunacion, peluqueria, bano, cirugia, consulta_general, otro`.
- `excepciones/{id}` — Cambio 2 (`ScheduleException`): `{tipo:'bloqueo'|'apertura', fechaInicio, fechaFin, desde?, hasta?, motivo?, createdAt}`. Cubre las fechas `[fechaInicio, fechaFin]` y, en cada una, `[desde, hasta)`; sin horas es el día completo (solo bloqueos). La crea y la borra la clínica dueña (no se edita); la leen los usuarios con sesión. Consulta: `where('fechaFin', '>=', hoy)` (índice automático).
- `slots/{fecha}_{hora}` (p. ej. `2026-10-15_09:30`, ver `Slot.idFor`) — **desde el Cambio 2 los escribe solo la Edge Function `citas`**: son el candado de cada reserva, `{fecha, hora, inicio, estado, appointmentId?}`, uno por cada franja que ocupa la cita. Una franja sin documento (o en `disponible`) está libre si el horario la cubre. Las franjas `no_disponible` de la agenda anterior siguen contando como bloqueadas. Formato anterior (RF-06): `{fecha:'2026-10-15', hora:'09:30', inicio:Timestamp, serviceId?, precio?, estado}`; `inicio` = `fecha` + `hora` en hora de Bogotá (`Slot.at`); el servidor no confía en él y lo recalcula al agendar; `estado ∈ disponible, no_disponible, reservado_temporal, ocupado`. Id determinístico `{fecha}_{hora}` para evitar duplicados. Una franja `disponible` ocupa de `hora` a `hora + duracionMin` del servicio: las franjas que quedan dentro de ese rango no tienen documento (la app las muestra como "cubiertas") y la app no permite guardar si el rango pisa otra franja o pasa del cierre (`DaySchedule.conflicts`). Una franja sin documento no se ofrece a los dueños.
- `pacientes/{petId}` — registros médicos (semana 3): `{duenoNombre, vinculadoAt}`. Nombre del dueño de cada mascota vinculada, para la lista "Pacientes" de la clínica (la clínica no puede leer `users/{ownerUid}`). La app lo guarda con lo que devuelve la Edge Function `vincular-mascota`; las reglas solo dejan escribir a la clínica dueña y si la mascota ya la tiene en `clinicasAutorizadas`. La lista de pacientes sale de `pets where clinicasAutorizadas array-contains clinicId` (índice automático de un campo); este documento solo aporta el nombre.
- `products/{productId}` — RF-07: `{nombre, categoria, descripcion, precio, stock, fotoUrl, estado:'activo'|'agotado'|'inactivo', createdAt}`.

## `pets/{petId}` — soporte para RF-08, RF-14, RF-17, RF-18

Reglas: el **dueño** (rol `dueno`, activo) crea, lee, edita y borra sus mascotas; obligatorios `nombre` (1–40), `especie` y (al crear) `codigoPaciente`; `ownerUid` y `codigoPaciente` no cambian. Las **clínicas autorizadas** (activas) la leen; consultan `where('clinicasAutorizadas', 'array-contains', clinicId)`. La app consulta `where('ownerUid', '==', uid)` y ordena por `createdAt` en el cliente (sin índice compuesto).

`{ownerUid, nombre, especie, raza?, fechaNacimiento?, sexo?, sexoDetalle?, fotoPath?, codigoPaciente, clinicasAutorizadas:string[], alergias:string[], condiciones:string[], contactoEmergencia?:{nombre, telefono}, createdAt}`

- `codigoPaciente`: código corto `MSC-XXXX` (sin 0/O, 1/I ni L; `PatientCode`) que el dueño le da a su veterinaria. Se asigna al crear la mascota, en el **mismo lote** que `codigosPaciente/{codigo}`, y nunca cambia. A las mascotas de la semana 2 se les asigna al abrir su perfil.
- `clinicasAutorizadas`: ids de las clínicas que pueden leer la mascota y su historial (RF-08). Solo la Edge Function `vincular-mascota` **agrega**; el dueño solo puede **quitar** (revocar). Empieza vacía.
- `especie ∈ perro, gato, ave, roedor, reptil, granja, exotico` (singular). Cada una corresponde a un valor de `clinics.tiposAnimales` (`PetSpecies.animalType`), para mostrar solo clínicas que atienden esa especie.
- `sexo ∈ macho, hembra, indeterminado, otro`. Con `otro` es obligatorio `sexoDetalle` (texto de 1–30 caracteres, p. ej. "hermafrodita"); con cualquier otro valor `sexoDetalle` no se guarda.
- `fotoPath` (antes `fotoUrl`): **ruta** en el bucket `mascotas` de Supabase Storage, `{ownerUid}/{petId}/foto.jpg|png` (`StorageRepository.petPhotoPath`). El bucket es privado, así que no hay una URL fija: la app pide un enlace temporal con `StorageRepository.signedUrl`. Las reglas exigen que la ruta sea de la carpeta del dueño y de esa mascota.

Subcolección `medicalRecords/{recordId}` — RF-08 (la escribe la **clínica**; modelo `MedicalRecord` en `lib/core/domain`, repositorio `MedicalRecordsRepository` en `lib/core/data`):
`{clinicId, clinicNombre, appointmentId?, fecha, diagnostico, tratamiento, vacunas:[{nombre, lote, fechaAplicacion, fechaProximaDosis?}], adjuntos:[{path, tipo:'imagen'|'pdf', nombre}], createdAt, updatedAt?}`

- **Crea** una clínica autorizada (`clinicId` = la suya; `createdAt` = hora del servidor). **Leen** el dueño y las clínicas autorizadas. **Corrige** solo la clínica autora durante **24 h** (`updatedAt` = hora del servidor). **Nunca** se borra.
- Obligatorios: `fecha` (no futura) y `diagnostico` (1–2000). Máximo 10 vacunas (nombre 1–80, lote 1–40, `fechaProximaDosis` posterior a la aplicación) y 10 adjuntos: las reglas validan elemento por elemento porque no tienen ciclos.
- `adjuntos[].path` (antes `url`): `{petId}/{recordId}/{archivo}` en el bucket privado **`registros`** de Supabase. Se suben y se ven con enlaces firmados de la Edge Function `adjuntos-historial`, que verifica en Firestore que quien pide es el dueño o una clínica autorizada (Supabase no puede leer Firestore en sus políticas).

## `vacunasProgramadas/{recordId}_{n}` — semana 3, para RF-13

`{petId, ownerUid, clinicId, recordId, vacuna, fechaProximaDosis, notificado, createdAt}`: una por cada vacuna `n` del registro que tenga `fechaProximaDosis`. La crea la clínica **en el mismo lote** que el registro y las reglas verifican que coincida con la vacuna `n` de ese registro. Existe porque Firestore no puede buscar por fechas dentro de una lista de objetos (`vacunas[].fechaProximaDosis`). La leen el dueño y la clínica autora; `notificado` lo marca RF-13 desde el servidor.

Índices: `(ownerUid, fechaProximaDosis)` para el carnet del dueño y `(notificado, fechaProximaDosis)` para los recordatorios.

## `codigosPaciente/{codigo}` — semana 3 · *nadie lo lee desde la app*

`{petId, ownerUid, createdAt}`. El id del documento (`MSC-XXXX`) hace único el código: las reglas solo permiten **crearlo** (junto con la mascota que lo usa), así que si ya existe el lote completo falla y la app prueba otro código. Lo lee la Edge Function `vincular-mascota` con la cuenta de servicio.

### Veterinarias de OpenStreetMap (Postgres de Supabase) — Cambio 4

Las usa solo la Edge Function `veterinarias-cercanas` con la service_role key (RLS activado y sin políticas). Migración: `supabase/migrations/20261028000000_veterinarias_osm.sql`.
- `public.cache_veterinarias_osm (cuadro, datos jsonb, actualizado, pendiente)`: resultado de Overpass por cuadro de 0,05° (~5 km). `datos` = lista de `{osmId, nombre, lat, lng, direccion?, telefono?, horario?, sitioWeb?}` (datos públicos de OSM, no de usuarios). El mapa la sirve aunque sea vieja; la precarga (cada 2 h) renueva lo de más de 20 h. Lo que viene del respaldo Photon se guarda con `actualizado` vencido para que la precarga lo reemplace con Overpass. `pendiente = true`: Overpass falló al pedirlo, no tiene datos y la precarga lo llena primero (migración `20261029000000_precarga_veterinarias_osm.sql`, que también programa la tarea en pg_cron).
- `public.consultas_mapa (uid, consultado_en)` y función `registrar_consulta_mapa`: máximo **60 consultas por usuario por hora**.

En Firestore no se guardan las veterinarias de OSM.

### Límite de intentos de vinculación (Postgres de Supabase)

Tabla `public.intentos_vinculacion (clinic_id, intentado_en)` y función `registrar_intento_vinculacion`: máximo **10 búsquedas de código por clínica por hora**. Solo la usa la Edge Function (RLS sin políticas). No guarda datos de la app. Migración: `supabase/migrations/20261016000000_limite_vinculacion.sql`.

## `appointments/{appointmentId}` — RF-14 · *solo la escribe el servidor*

Modelo `Appointment` (`lib/core/domain`), repositorio `AppointmentsRepository` (`lib/core/data`). La crea y la cambia **solo** la Edge Function `citas` (y la tarea programada); las reglas niegan toda escritura desde la app. La leen el dueño de la cita y la clínica (activos).

`slotIds` (Cambio 2): ids `{fecha}_{hora}` de todas las franjas que aparta la cita (`slotId` es la primera); las citas anteriores solo tienen `slotId`.

`ownerNombre` = `nombreVisible` del dueño al solicitar (Cambio 1; copia histórica, no cambia si el dueño edita su nombre).

`{clinicId, clinicNombre, clinicOwnerUid, ownerUid, ownerNombre, petId, petNombre, serviceId, serviceNombre, precioAcordado, duracionMin?, slotId, fecha, hora, inicio:Timestamp, comentario, estado, motivoRechazo?, motivoCancelacion?, canceladoPor?, createdAt, updatedAt}`

- `estado ∈ pendiente, confirmada, rechazada, cancelada, expirada, completada, no_asistio`. Transiciones (`canTransition` en Dart, `puedeTransicionar` en TS, con pruebas de las 49 combinaciones):
  - `pendiente → confirmada | rechazada | cancelada | expirada`
  - `confirmada → completada | cancelada | no_asistio`
  - los demás son finales.
- `expirada` (no está en el RF): solicitud que la clínica no respondió antes de la hora; la tarea programada la marca y libera la franja.
- `clinicNombre`, `ownerNombre`, `petNombre`, `serviceNombre`, `precioAcordado`, `duracionMin`: copias al momento de solicitar (la clínica no puede leer `users`; el precio no cambia si la clínica lo cambia después).
- `clinicOwnerUid`: a quién avisar en la clínica (RF-13).
- `fecha` `YYYY-MM-DD`, `hora` `HH:mm` e `inicio` en hora de Bogotá; `inicio` lo calcula el servidor desde la franja.
- `motivoRechazo` (obligatorio al rechazar), `motivoCancelacion` (obligatorio si cancela la clínica), `canceladoPor ∈ dueno, clinica`. Motivos de 1–300 caracteres; `comentario` hasta 500.

Al solicitar, en **un solo commit**: crea la cita `pendiente`, la franja pasa a `reservado_temporal` y el `clinicId` se agrega a `pets/{petId}.clinicasAutorizadas` (RF-14 paso 8: la clínica puede ver el historial). Aprobar → franja `ocupado`; rechazar, cancelar o expirar → franja `disponible`.

## `chats/{ownerUid_clinicId}` — RF-15

`{participantes:[ownerUid, clinicOwnerUid], ownerUid, clinicId, lastMessage, updatedAt, typing:{uid:bool}, noLeidos:{uid:number}}`
Subcolección `messages/{messageId}`: `{senderUid, tipo:'texto'|'adjunto', texto?, adjuntoURL?, adjuntoTipo?, adjuntoNombre?, referenciaHistorialId?, timestamp, leido}`

## `orders/{orderId}` — RF-12 · *la crea solo la Function del webhook de pago*

`{ownerUid, clinicId, items:[{productId, nombre, precio, cantidad}], total, direccionEntrega, estado:'confirmado'|'preparando'|'entregado'|'cancelado', pagoRef, createdAt}`

## `notifications/{notificationId}` — RF-13 · *la crea solo el servidor*

`{uid, tipo, titulo, cuerpo, referenciaId, leido, createdAt}`

- `tipo ∈ cita_nueva, cita_aprobada, cita_rechazada, cita_cancelada, recordatorio_cita, vacuna, pedido, mensaje` (`NotificationType` en Dart, `TipoNotificacion` en TS).
- `referenciaId`: la cita (`appointmentId`) en los tipos de citas; la **mascota** (`petId`) en `vacuna`. El push lleva lo mismo en `data: {tipo, referenciaId, notificationId}` y la app navega con eso (`/reservas/:id` o `/mascotas/perfil/:petId`; si la ruta no existe, al inicio).
- La crea `enviarNotificacion` (`supabase/functions/_shared/notificaciones.ts`), **siempre**, antes de enviar el push: aunque el usuario niegue el permiso, la ve en el centro de notificaciones. Los recordatorios usan ids fijos (`recordatorio_{appointmentId}`, `vacuna_{vacunaProgramadaId}`) para no duplicarse.
- Reglas: cada usuario lee las suyas y solo puede cambiar `leido` a `true`; nadie más escribe.

## `qrTags/{qrId}` — RF-17

`{petId, ownerUid, activo, createdAt}` · Datos públicos se leen solo a través de la Function `verPlacaQr` (nunca directo desde la web).

## `auditEvents/{id}` — RF-10

`{tipo:'emergencyTriggered', uid, lat?, lng?, createdAt}`

## Archivos (Supabase Storage, bucket privado `mascoti`)

Reemplaza a Firebase Storage. Políticas en `supabase/migrations/*_storage_mascoti.sql`.

| Ruta | Quién escribe/lee | Uso |
|---|---|---|
| `usuarios/{uidFirebase}/...` | solo ese usuario | adjuntos del chat, PDF y demás archivos de cada persona |

### Bucket `registros` (adjuntos del historial médico)

| Ruta | Escribe | Lee | Límites |
|---|---|---|---|
| `{petId}/{recordId}/{archivo}` | clínica autorizada (autora del registro, 24 h) | dueño y clínicas autorizadas | JPG/PNG/PDF, máximo 10 MB |

Sin políticas para la app: todo pasa por la Edge Function `adjuntos-historial`. Migración: `supabase/migrations/20261016010000_storage_registros.sql`.

### Bucket `mascotas` (fotos de mascotas)

Políticas en `supabase/migrations/20261015000000_storage_mascotas.sql`.

| Ruta | Escribe | Lee | Límites |
|---|---|---|---|
| `{ownerUid}/{petId}/foto.jpg\|png` | solo el dueño (su carpeta) | cualquier usuario con sesión (enlace firmado) | JPG/PNG, máximo 5 MB |

- Bucket `mascoti`: máximo 10 MB por archivo; solo `image/jpeg`, `image/png`, `image/webp` y `application/pdf`.
- En Firestore se guarda la **ruta** (p. ej. `fotoPath`), no una URL: para mostrar el archivo se pide un enlace firmado temporal con `StorageRepository.signedUrl`.
- Para compartir con otra persona (chat, historial) se entrega un enlace firmado; si hay que validar permisos, lo genera una Edge Function.

## Índices compuestos previstos (`firestore.indexes.json`)

- `appointments`: `clinicId ASC, estado ASC, inicio ASC` (bandeja) · `ownerUid ASC, inicio DESC` (mis citas) · `clinicId ASC, inicio ASC` (agenda) · `estado ASC, inicio ASC` (tarea programada)
- `slots` (collection group): `fecha ASC, estado ASC`
- `notifications`: `uid ASC, createdAt DESC` (el contador de no leídas, `uid ==` y `leido ==`, no necesita índice compuesto)
- `clinics`: `estado ASC, geo.geohash ASC` (búsqueda geográfica de `ClinicsGeoRepository`, `lib/core/data`)
- `vacunasProgramadas`: `ownerUid ASC, fechaProximaDosis ASC` · `notificado ASC, fechaProximaDosis ASC`

**Ubicación de la clínica (semana 3):** `direccion` solo cambia junto con `lat`, `lng` y `geo`, y `geo.geopoint` debe coincidir con `lat`/`lng` (reglas). Usa `ClinicsGeoRepository.addressUpdate(...)`, que arma los cuatro campos. Para revisar o recalcular `geo` de clínicas existentes: `npm run verificar-geo` en `functions/`.
