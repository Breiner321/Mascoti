# Cambios de alcance

Cambios de producto que pidió el equipo después de probar la app y que modifican lo que dicen los RF. Cada RF afectado tiene una nota en su sección **Adaptación a Firebase**, que prevalece sobre el texto original.

| # | Cambio | RF afectados | Estado |
|---|---|---|---|
| 1 | Nombre del dueño en las notificaciones y en toda la app | RF-01, RF-03, RF-13, RF-14 | ✅ |
| 2 | Disponibilidad automática según el horario de la clínica | RF-04, RF-06, RF-14 | ✅ |
| 3 | Accesibilidad (WCAG 2.1 AA) y modo oscuro | Todos | ✅ |
| 4 | Mapa con todas las veterinarias y "Aliados Mascoti" | RF-09, RF-10 | ✅ |

---

## Cambio 1 — Nombre del dueño

**Qué decía el RF.** RF-01 registraba al dueño solo con su cuenta de Google: el sistema guardaba el `displayName` de Google y no pedía más datos. Las notificaciones (RF-13) y las citas (RF-14) mostraban ese nombre, que muchas veces es un apodo o el usuario del correo.

**Qué cambia.**
- En el registro, el **dueño** escribe su **nombre completo** (obligatorio, 3–60 caracteres, prellenado con el nombre de Google y editable) y su **teléfono** (10 dígitos). Se guardan en `users/{uid}.nombre` y `users/{uid}.telefono`, y la Edge Function `completar-registro` los valida igual que la app.
- **Una sola fuente del nombre visible:** `AppUser.nombreVisible` (`nombre` → nombre de Google → "Usuario"; nunca el correo) y `displayNameProvider`. Para una **clínica** el nombre visible es siempre el comercial (`clinics/{id}.nombre`). En el servidor, `nombreVisible()` en `supabase/functions/_shared/nombres.ts`, con las mismas reglas.
- Las citas copian `ownerNombre` con ese nombre, y las notificaciones lo heredan de la cita. La vinculación de pacientes (`vincular-mascota`) devuelve `duenoNombre` con ese nombre.
- El dueño edita su nombre y teléfono en **Perfil → Editar perfil**.
- **Usuarios registrados antes del cambio:** al iniciar sesión, un dueño sin `nombre` va a la pantalla obligatoria **"Completa tu perfil"** (nombre y teléfono, ambos obligatorios) antes de cualquier otra pantalla. No hace falta un script de migración.
- **Copias históricas:** si el dueño cambia su nombre, las citas y los pacientes ya creados conservan el nombre de cuando se crearon (decisión del equipo).

**Por qué.** Las clínicas recibían solicitudes y notificaciones con nombres de cuentas de Google o correos, y no sabían quién era el cliente.

**Compatibilidad.** Un APK anterior al cambio ya no puede registrar dueños: la Edge Function responde "Actualiza la app para completar tu registro".

---

## Cambio 2 — Disponibilidad automática según el horario

**Qué decía el RF.** RF-06 pedía que la clínica marcara franja por franja, día por día, cuáles estaban disponibles y para qué servicio. Sin ese trabajo diario, la clínica no recibía citas. RF-04 tenía un solo horario (`horarioBase`) para todos los días.

**Qué cambia.**
- **Horario semanal** en el perfil de atención (RF-04): por día, abierto o cerrado, apertura, cierre y descanso opcional. Además, duración de la franja (15/30/60 min), hasta cuántos días antes se puede reservar (30 por defecto) y la anticipación mínima (2 horas por defecto). `clinics.horarioSemanal` y `clinics.reservas` reemplazan a `horarioBase`.
- **Disponible por defecto:** cualquier franja dentro del horario sirve para cualquier servicio activo, salvo que tenga una cita pendiente o confirmada, la clínica la haya bloqueado, o el servicio no alcance a terminar antes del cierre o del descanso. Un servicio de 60 min con franjas de 30 aparta 2 franjas.
- **La agenda (RF-06) es para excepciones:** bloquear una franja, un rango o el día completo (con motivo opcional) y abrir horario extra. Muestra los **festivos de Colombia** de los próximos 90 días para bloquearlos con un toque. Se calculan en la app (fechas fijas, Ley Emiliani y Pascua) sin depender de una API.
- **Una sola lógica de disponibilidad** en hora de Colombia: `Availability` (`lib/core/domain/availability.dart`) en la app y `disponibilidad.ts` en la Edge Function `citas`. Las dos pasan los mismos casos de `test/fixtures/disponibilidad.json`.
- **Franjas creadas solo al reservar:** `slots/{fecha}_{hora}` es el candado de la transacción de `solicitar`, que crea o actualiza todas las franjas que ocupa el servicio en un solo commit. Se descartó generar franjas por adelantado con una tarea programada: crearía cientos de documentos por clínica, habría que regenerarlos con cada cambio de horario y quedarían ventanas desactualizadas.
- **Cambio de horario con citas existentes:** la app lista las citas que quedan por fuera y permite guardar igual. Las citas se mantienen y el horario nuevo solo aplica a reservas nuevas (decisión del equipo).
- **Migración:** `npm run migrar-horario -- --aplicar` (en `functions/`) convierte `horarioBase` en `horarioSemanal` con todos los días abiertos con el mismo horario (decisión del equipo), así nada cambia para las clínicas existentes. Mientras no se ejecute, la app y el servidor leen `horarioBase` de la misma forma.

**Por qué.** Marcar franjas a diario era demasiado trabajo para las clínicas, y una clínica que no lo hacía quedaba sin citas.

**Límite técnico.** Las reglas de Firestore solo validan la **estructura** de `horarioSemanal`: comparar las 28 horas de la semana supera el máximo de 1000 expresiones por evaluación. El formato y la coherencia de las horas los validan la app (`WeeklySchedule.validate`) y el servidor, que trata como cerrado un día con horas inválidas.

---

## Cambio 3 — Accesibilidad y modo oscuro

**Qué decían los RF.** Nada sobre accesibilidad: solo los colores de los mockups, algunos por debajo del contraste mínimo (por ejemplo el texto gris claro sobre el fondo morado claro: 3.95:1).

**Qué cambia.** Guía completa en [accesibilidad.md](accesibilidad.md).
- Se mantiene el diseño de los mockups como **tema claro**, con los colores que no cumplían oscurecidos lo justo para llegar a 4.5:1.
- **Modo oscuro** y **alto contraste** (claro u oscuro) en Perfil → Accesibilidad, junto con el tamaño de texto (100–150 %, combinado con el del sistema hasta 200 %) y "Reducir animaciones". Se guardan en el teléfono. "Sistema" sigue al tema de Android.
- `AppColors` lee la **paleta activa** (antes eran constantes): así el modo oscuro cubre toda la app, también los widgets de los plugins. Por eso `AppColors` ya no se puede usar dentro de `const`.
- Lector de pantalla: etiquetas en botones de ícono, fotos ("Foto de Luna"), flechas del calendario, estados anunciados ("9:30 a. m., disponible", "Estado: Confirmada"); el SOS se anuncia primero en el encabezado.
- Áreas táctiles de 48 dp, estados con ícono y texto (no solo color), pantallas que se desplazan con texto grande.
- Pruebas automáticas en las pantallas principales: `androidTapTargetGuideline`, `labeledTapTargetGuideline`, `textContrastGuideline` y texto al 200 % sin desbordes; contraste de las 4 paletas.

**Por qué.** El equipo quiere que la app sea usable con TalkBack, texto grande, baja visión o daltonismo, y que ofrezca modo oscuro sin perder el diseño.

**Límites.** El encabezado morado crece solo hasta 130 % con el texto grande (logo e íconos); el resto de la app llega a 200 %. table_calendar no etiqueta sus flechas ni los huecos de otros meses: se reemplazaron por botones propios y celdas vacías con nombre.

## Cambio 4 — Mapa con todas las veterinarias y "Aliados Mascoti"

**Qué decían los RF.** RF-09 mostraba solo las clínicas registradas en Mascoti, en un radio fijo alrededor del usuario, con Google Maps y Google Places.

**Qué cambia.**
- El mapa muestra también las **veterinarias que aún no usan Mascoti**, tomadas de **OpenStreetMap** (`amenity=veterinary`) por la Edge Function `veterinarias-cercanas`, que consulta la API Overpass. Es gratis y no necesita cuenta de Google Cloud (el equipo no tiene).
- **Aliados Mascoti:** círculo morado con huella (rojo SOS si atiende emergencias) y el distintivo "Aliado Mascoti" en la lista, la tarjeta y el perfil. **Otras veterinarias:** círculo gris más pequeño con cruz médica. Se distinguen por forma y tamaño, no solo por color. Hay una leyenda bajo el mapa y el lector de pantalla dice "Aliado Mascoti: …" o "Veterinaria sin Mascoti: …".
- La tarjeta de una veterinaria no aliada muestra nombre, dirección, distancia, horario (traducido de OSM: "Lu-Vi 8:00 a. m.–6:00 p. m."), teléfono, "Cómo llegar" y "Llamar" (solo si OSM tiene el teléfono), y el aviso "Esta veterinaria aún no usa Mascoti: no tiene citas ni servicios en la app." **No tiene "Agendar"** ni servicios.
- **Recarga automática al mover el mapa** (decisión del equipo): 0,7 s después de mover o hacer zoom se buscan aliados y otras veterinarias en el área visible. El chip de distancia fija el zoom inicial.
- Chip **"Solo aliados"**. Los filtros de especie, servicio y "24 horas" solo existen para los aliados: con ellos activos las otras veterinarias se ocultan y se explica con un aviso.
- **Sin duplicados:** una clínica aliada que también está en OSM aparece una sola vez, como aliada. Son la misma si la clínica tiene ese `osmId` (lo pone `npm run vincular-osm`) o, sin él, si están a menos de 50 m y el nombre se parece (≥ 0,5 de palabras en común, sin contar "clínica", "veterinaria", etc.). Dos veterinarias vecinas con nombres distintos no se unen.
- "Abierto/Cerrado" del directorio usa ahora el horario semanal del Cambio 2 en hora de Colombia (antes, `horarioBase` en la hora del teléfono).

**Cuidado del servicio gratuito.** Los resultados se guardan en Postgres de Supabase por cuadros de ~5 km. Los servidores públicos de Overpass a veces tardan más de 40 s (lo comprobamos al probar), así que:
- **Precarga** (tarea `veterinarias-osm` de `tareas-programadas`, cada 2 h, en segundo plano): renueva los cuadros de más de 20 h, los "pendientes" y los alrededores (~10 km) de las clínicas activas y de las 15 ciudades principales, con una consulta por bloque de ~20 km y hasta 110 s por vuelta; lo que no alcanza sigue en la siguiente.
- **Al abrir el mapa** se sirve la caché aunque esté vieja. Solo los cuadros que nunca se han cargado van a Overpass (hasta ~50 s; la app espera 65 s). Si Overpass falla, quedan "pendientes" para la precarga y se responde con lo que haya; si no hay nada, "No se pudieron cargar otras veterinarias." con "Reintentar".
- **Respaldo con Photon** (el buscador de direcciones, mismos datos de OSM, sin llave): si Overpass falla, se busca "veterinaria", "veterinario", "vet", "pet" y "mascotas" con el filtro `amenity=veterinary`. Trae menos (en Medellín, 27 de 51, y sin teléfono ni horario), así que se guarda como vencido y la precarga lo reemplaza con Overpass cuando vuelva. En la precarga solo llena cuadros sin datos, uno por uno.
- Límite de 60 consultas por usuario por hora y áreas de máximo 30 km de lado ("Acerca el mapa para ver otras veterinarias."). Servidores de Overpass: `overpass-api.de` y `maps.mail.ru` (`overpass.kumi.systems` se quitó: cuando falla no responde y se come el plazo).

**Por qué.** El dueño quiere ver todas las veterinarias de su zona, sobre todo en una urgencia, aunque no usen Mascoti; y la distinción "Aliado Mascoti" muestra a las clínicas el valor de registrarse.

**Límites.** Los datos de OSM los mantiene la comunidad: pueden faltar veterinarias o tener datos viejos (la tarjeta dice "Datos de OpenStreetMap"). El SOS (RF-10) aún no existe como pantalla; cuando se construya puede usar `nearbyVetPlacesProvider`, `VetMatching` y `ExternalLinks` del core.
