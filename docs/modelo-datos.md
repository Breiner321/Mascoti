# Modelo de datos (Cloud Firestore)

Fuente única de verdad del esquema. **Todo PR que agregue o cambie colecciones o campos debe actualizar este archivo y `firestore.rules`.**

Modelos en Dart: `lib/core/domain/` (`Clinic`, `ClinicService`, `Slot`, `Pet`), compartidos por todos los plugins. Los enums guardan en Firestore el valor en español de esta página.

Horas (`hora`, `horarioBase.apertura/cierre`): se **guardan** en 24 h `HH:mm`; la app las **muestra** en 12 h con a. m./p. m. (`TimeFormat` en `lib/core/format`).

Convenciones: nombres de campos en español como en los RF; fechas como `Timestamp`; dinero en COP como `number` entero (sin decimales) salvo que el RF diga otra cosa; ids generados por Firestore salvo que se indique.

## `users/{uid}`  — RF-01, RF-02 · *se crea solo con la Edge Function `completar-registro` (Supabase)*

| Campo | Tipo | Notas |
|---|---|---|
| uid | string | = id de Firebase Auth |
| email, displayName, photoURL | string | de Google |
| role | `'dueno' \| 'clinica'` | inmutable (las reglas lo leen con `hasRole()`) |
| estado | `'activo' \| 'suspendido'` | solo lo cambia un administrador (Admin SDK). Se cambia con el script `npm run suspender -- <uid> [--reactivar]` (`functions/admin/`), que además deshabilita la cuenta en Firebase Auth y revoca sus sesiones (o la habilita al reactivar). Una cuenta suspendida solo puede leer su propio perfil |
| clinicId | string? | solo si role = clinica |
| telefono, ciudad, direccion | string? | perfil del dueño (RF-10, RF-12) |
| onboardingVisto | bool | RF-01 paso 14. `false` al registrarse; el dueño lo pone en `true` al terminar o saltar el onboarding (las reglas solo aceptan un `bool`). Si falta, la app lo trata como `false` |
| createdAt, lastLoginAt | Timestamp | |
| estadoActualizadoEn | Timestamp? | lo pone el script de suspensión |

Subcolecciones: `devices/{deviceId}` `{fcmToken, plataforma, updatedAt, valido}` (RF-13) · `cart/{productId}` `{clinicId, cantidad, addedAt}` (RF-12) · `favoriteClinics/{clinicId}` (RF-10).

## `clinics/{clinicId}` — RF-01, RF-04, RF-09

| Campo | Tipo | Notas |
|---|---|---|
| ownerUid | string | uid del usuario clínica |
| nombre, telefono, direccion | string | teléfono de 10 dígitos |
| lat, lng | number | desde OpenStreetMap (buscador de direcciones); obligatorios (los valida `completar-registro`) |
| geo | map `{geohash, geopoint}` | para `geoflutterfire_plus` (RF-09). Lo calcula `completar-registro` (geohash de 10 caracteres, igual a `geofire-common`) |
| tiposAnimales | string[] | `perros, gatos, aves, roedores, reptiles, granja, exoticos` |
| atencionEmergencias | bool | RF-10 |
| horarioBase | map `{apertura:'08:00', cierre:'18:00', duracionSlotMin:30}` | RF-06. Horas `HH:mm` (24 h); duración entera 5–480 (la app ofrece 15, 30 o 60 min en RF-04). `OpeningHours.slotTimes()` genera las franjas del día |
| calificacion | number? | promedio (futuro) |
| estado | `'incompleto' \| 'activo'` | pasa a activo en RF-04. Mientras sea `incompleto`, la app obliga a la clínica a ir a `/clinica/perfil-atencion` |
| createdAt | Timestamp | |

Subcolecciones:
- `services/{serviceId}` — RF-05: `{nombre, categoria, descripcion, precio, duracionMin, activo, createdAt, updatedAt}`; `precio` en COP: la app solo envía enteros (decisión del equipo; el RF permitía 2 decimales) y las reglas aceptan cualquier número > 0; `categoria ∈ vacunacion, peluqueria, bano, cirugia, consulta_general, otro`.
- `slots/{fecha}_{hora}` (p. ej. `2026-10-15_09:30`, ver `Slot.idFor`) — RF-06: `{fecha:'2026-10-15', hora:'09:30', inicio:Timestamp, serviceId?, precio?, estado}`; `estado ∈ disponible, no_disponible, reservado_temporal, ocupado`. Id determinístico `{fecha}_{hora}` para evitar duplicados. Una franja `disponible` ocupa de `hora` a `hora + duracionMin` del servicio: las franjas que quedan dentro de ese rango no tienen documento (la app las muestra como "cubiertas") y la app no permite guardar si el rango pisa otra franja o pasa del cierre (`DaySchedule.conflicts`). Una franja sin documento no se ofrece a los dueños.
- `products/{productId}` — RF-07: `{nombre, categoria, descripcion, precio, stock, fotoUrl, estado:'activo'|'agotado'|'inactivo', createdAt}`.

## `pets/{petId}` — soporte para RF-08, RF-14, RF-17, RF-18

Reglas: el **dueño** (rol `dueno`, activo) crea, lee, edita y borra sus mascotas; obligatorios `nombre` (1–40), `especie` y (al crear) `codigoPaciente`; `ownerUid` y `codigoPaciente` no cambian. Las **clínicas autorizadas** (activas) la leen; consultan `where('clinicasAutorizadas', 'array-contains', clinicId)`. La app consulta `where('ownerUid', '==', uid)` y ordena por `createdAt` en el cliente (sin índice compuesto).

`{ownerUid, nombre, especie, raza?, fechaNacimiento?, sexo?, sexoDetalle?, fotoPath?, codigoPaciente, clinicasAutorizadas:string[], alergias:string[], condiciones:string[], contactoEmergencia?:{nombre, telefono}, createdAt}`

- `codigoPaciente`: código corto `MSC-XXXX` (sin 0/O, 1/I ni L; `PatientCode`) que el dueño le da a su veterinaria. Se asigna al crear la mascota, en el **mismo lote** que `codigosPaciente/{codigo}`, y nunca cambia. A las mascotas de la semana 2 se les asigna al abrir su perfil.
- `clinicasAutorizadas`: ids de las clínicas que pueden leer la mascota y su historial (RF-08). Solo la Edge Function `vincular-mascota` **agrega**; el dueño solo puede **quitar** (revocar). Empieza vacía.
- `especie ∈ perro, gato, ave, roedor, reptil, granja, exotico` (singular). Cada una corresponde a un valor de `clinics.tiposAnimales` (`PetSpecies.animalType`), para mostrar solo clínicas que atienden esa especie.
- `sexo ∈ macho, hembra, indeterminado, otro`. Con `otro` es obligatorio `sexoDetalle` (texto de 1–30 caracteres, p. ej. "hermafrodita"); con cualquier otro valor `sexoDetalle` no se guarda.
- `fotoPath` (antes `fotoUrl`): **ruta** en el bucket `mascotas` de Supabase Storage, `{ownerUid}/{petId}/foto.jpg|png` (`StorageRepository.petPhotoPath`). El bucket es privado, así que no hay una URL fija: la app pide un enlace temporal con `StorageRepository.signedUrl`. Las reglas exigen que la ruta sea de la carpeta del dueño y de esa mascota.

Subcolección `medicalRecords/{recordId}` — RF-08 (la escribe la **clínica**):
`{clinicId, clinicNombre, appointmentId?, fecha, diagnostico, tratamiento, vacunas:[{nombre, lote, fechaAplicacion, fechaProximaDosis}], adjuntos:[{url, tipo:'imagen'|'pdf', nombre}], createdAt}`

## `codigosPaciente/{codigo}` — semana 3 · *nadie lo lee desde la app*

`{petId, ownerUid, createdAt}`. El id del documento (`MSC-XXXX`) hace único el código: las reglas solo permiten **crearlo** (junto con la mascota que lo usa), así que si ya existe el lote completo falla y la app prueba otro código. Lo lee la Edge Function `vincular-mascota` con la cuenta de servicio.

### Límite de intentos de vinculación (Postgres de Supabase)

Tabla `public.intentos_vinculacion (clinic_id, intentado_en)` y función `registrar_intento_vinculacion`: máximo **10 búsquedas de código por clínica por hora**. Solo la usa la Edge Function (RLS sin políticas). No guarda datos de la app. Migración: `supabase/migrations/20261016000000_limite_vinculacion.sql`.

## `appointments/{appointmentId}` — RF-14

`{clinicId, clinicNombre, ownerUid, petId, petNombre, serviceId, serviceNombre, precioAcordado, slotId, inicio:Timestamp, comentario, estado, motivoRechazo?, motivoCancelacion?, createdAt, updatedAt}`
`estado ∈ pendiente, confirmada, rechazada, cancelada, completada, no_asistio`

## `chats/{ownerUid_clinicId}` — RF-15

`{participantes:[ownerUid, clinicOwnerUid], ownerUid, clinicId, lastMessage, updatedAt, typing:{uid:bool}, noLeidos:{uid:number}}`
Subcolección `messages/{messageId}`: `{senderUid, tipo:'texto'|'adjunto', texto?, adjuntoURL?, adjuntoTipo?, adjuntoNombre?, referenciaHistorialId?, timestamp, leido}`

## `orders/{orderId}` — RF-12 · *la crea solo la Function del webhook de pago*

`{ownerUid, clinicId, items:[{productId, nombre, precio, cantidad}], total, direccionEntrega, estado:'confirmado'|'preparando'|'entregado'|'cancelado', pagoRef, createdAt}`

## `notifications/{notificationId}` — RF-13

`{uid, tipo:'recordatorio_cita'|'vacuna'|'cita_aprobada'|'cita_rechazada'|'pedido'|'mensaje', titulo, cuerpo, referenciaId, leido, createdAt}`

## `qrTags/{qrId}` — RF-17

`{petId, ownerUid, activo, createdAt}` · Datos públicos se leen solo a través de la Function `verPlacaQr` (nunca directo desde la web).

## `auditEvents/{id}` — RF-10

`{tipo:'emergencyTriggered', uid, lat?, lng?, createdAt}`

## Archivos (Supabase Storage, bucket privado `mascoti`)

Reemplaza a Firebase Storage. Políticas en `supabase/migrations/*_storage_mascoti.sql`.

| Ruta | Quién escribe/lee | Uso |
|---|---|---|
| `usuarios/{uidFirebase}/...` | solo ese usuario | adjuntos del chat, PDF y demás archivos de cada persona |

### Bucket `mascotas` (fotos de mascotas)

Políticas en `supabase/migrations/20261015000000_storage_mascotas.sql`.

| Ruta | Escribe | Lee | Límites |
|---|---|---|---|
| `{ownerUid}/{petId}/foto.jpg\|png` | solo el dueño (su carpeta) | cualquier usuario con sesión (enlace firmado) | JPG/PNG, máximo 5 MB |

- Bucket `mascoti`: máximo 10 MB por archivo; solo `image/jpeg`, `image/png`, `image/webp` y `application/pdf`.
- En Firestore se guarda la **ruta** (p. ej. `fotoPath`), no una URL: para mostrar el archivo se pide un enlace firmado temporal con `StorageRepository.signedUrl`.
- Para compartir con otra persona (chat, historial) se entrega un enlace firmado; si hay que validar permisos, lo genera una Edge Function.

## Índices compuestos previstos (`firestore.indexes.json`)

- `appointments`: `clinicId ASC, estado ASC, inicio ASC` · `ownerUid ASC, inicio DESC`
- `slots` (collection group): `fecha ASC, estado ASC`
- `notifications`: `uid ASC, createdAt DESC`
- `clinics`: `estado ASC, geo.geohash ASC`
