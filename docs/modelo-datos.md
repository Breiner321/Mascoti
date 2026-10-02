# Modelo de datos (Cloud Firestore)

Fuente única de verdad del esquema. **Todo PR que agregue o cambie colecciones o campos debe actualizar este archivo y `firestore.rules`.**

Convenciones: nombres de campos en español como en los RF; fechas como `Timestamp`; dinero en COP como `number` entero (sin decimales) salvo que el RF diga otra cosa; ids generados por Firestore salvo que se indique.

## `users/{uid}`  — RF-01, RF-02 · *se crea solo con la Function `completarRegistro`*

| Campo | Tipo | Notas |
|---|---|---|
| uid | string | = id de Firebase Auth |
| email, displayName, photoURL | string | de Google |
| role | `'dueno' \| 'clinica'` | inmutable (las reglas lo leen con `hasRole()`) |
| estado | `'activo' \| 'suspendido'` | solo lo cambia un administrador (Admin SDK). Al pasar a `suspendido`, la Function `sincronizarSuspension` deshabilita la cuenta en Firebase Auth y revoca sus tokens; al volver a `activo` la habilita. Una cuenta suspendida solo puede leer su propio perfil |
| clinicId | string? | solo si role = clinica |
| telefono, ciudad, direccion | string? | perfil del dueño (RF-10, RF-12) |
| createdAt, lastLoginAt | Timestamp | |

Subcolecciones: `devices/{deviceId}` `{fcmToken, plataforma, updatedAt, valido}` (RF-13) · `cart/{productId}` `{clinicId, cantidad, addedAt}` (RF-12) · `favoriteClinics/{clinicId}` (RF-10).

## `clinics/{clinicId}` — RF-01, RF-04, RF-09

| Campo | Tipo | Notas |
|---|---|---|
| ownerUid | string | uid del usuario clínica |
| nombre, telefono, direccion | string | teléfono de 10 dígitos |
| lat, lng | number | desde Google Places |
| geo | map `{geohash, geopoint}` \| null | para `geoflutterfire_plus` (RF-09). Lo calcula `completarRegistro` con `geofire-common` (geohash de 10 caracteres); `null` si faltan lat/lng |
| tiposAnimales | string[] | `perros, gatos, aves, roedores, reptiles, granja, exoticos` |
| atencionEmergencias | bool | RF-10 |
| horarioBase | map `{apertura:'08:00', cierre:'18:00', duracionSlotMin:30}` | RF-06 |
| calificacion | number? | promedio (futuro) |
| estado | `'incompleto' \| 'activo'` | pasa a activo en RF-04 |
| createdAt | Timestamp | |

Subcolecciones:
- `services/{serviceId}` — RF-05: `{nombre, categoria, descripcion, precio, duracionMin, activo, createdAt, updatedAt}`; `categoria ∈ vacunacion, peluqueria, bano, cirugia, consulta_general, otro`.
- `slots/{slotId}` — RF-06: `{fecha:'2026-10-15', hora:'09:30', inicio:Timestamp, serviceId?, precio?, estado}`; `estado ∈ disponible, no_disponible, reservado_temporal, ocupado`. Id determinístico `{fecha}_{hora}` para evitar duplicados.
- `products/{productId}` — RF-07: `{nombre, categoria, descripcion, precio, stock, fotoUrl, estado:'activo'|'agotado'|'inactivo', createdAt}`.

## `pets/{petId}` — soporte para RF-08, RF-14, RF-17, RF-18

`{ownerUid, nombre, especie, raza, fechaNacimiento, sexo, fotoUrl, alergias:string[], condiciones:string[], contactoEmergencia:{nombre, telefono}, createdAt}`

Subcolección `medicalRecords/{recordId}` — RF-08 (la escribe la **clínica**):
`{clinicId, clinicNombre, appointmentId?, fecha, diagnostico, tratamiento, vacunas:[{nombre, lote, fechaAplicacion, fechaProximaDosis}], adjuntos:[{url, tipo:'imagen'|'pdf', nombre}], createdAt}`

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

## Índices compuestos previstos (`firestore.indexes.json`)

- `appointments`: `clinicId ASC, estado ASC, inicio ASC` · `ownerUid ASC, inicio DESC`
- `slots` (collection group): `fecha ASC, estado ASC`
- `notifications`: `uid ASC, createdAt DESC`
- `clinics`: `estado ASC, geo.geohash ASC`
