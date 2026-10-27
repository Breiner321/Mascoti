# Cambios de alcance

Cambios de producto que pidió el equipo después de probar la app y que modifican lo que dicen los RF. Cada RF afectado tiene una nota en su sección **Adaptación a Firebase**, que prevalece sobre el texto original.

| # | Cambio | RF afectados | Estado |
|---|---|---|---|
| 1 | Nombre del dueño en las notificaciones y en toda la app | RF-01, RF-03, RF-13, RF-14 | ✅ |
| 2 | Disponibilidad automática según el horario de la clínica | RF-04, RF-06, RF-14 | ⬜ |
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
