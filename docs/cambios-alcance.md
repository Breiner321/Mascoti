# Cambios de alcance

Cambios de producto que pidió el equipo después de probar la app y que modifican lo que dicen los RF. Cada RF afectado tiene una nota en su sección **Adaptación a Firebase**, que prevalece sobre el texto original.

| # | Cambio | RF afectados | Estado |
|---|---|---|---|
| 1 | Nombre del dueño en las notificaciones y en toda la app | RF-01, RF-03, RF-13, RF-14 | ✅ |
| 2 | Disponibilidad automática según el horario de la clínica | RF-04, RF-06, RF-14 | ✅ |
| 3 | Accesibilidad (WCAG 2.1 AA) | Todos | ⬜ |
| 4 | Mapa con todas las veterinarias y "Aliados Mascoti" | RF-09, RF-10 | ⬜ |

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
