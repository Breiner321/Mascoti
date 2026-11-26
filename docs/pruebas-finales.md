# Pruebas finales — entrega del 27 de noviembre de 2026

Lista de verificación manual para el APK final. Cada desarrollador completa su sección en un emulador Android o un celular real con `flutter run --dart-define-from-file=env/dev.json` (o el APK de `flutter build apk --release`).

Marca `- [x]` lo que pase. Si algo falla, anota el paso, lo que esperabas y lo que pasó, y repórtalo; lo que no se alcance a corregir va en **Limitaciones conocidas** al final.

**Revisión automática (26 nov):** `flutter analyze` 0 issues · `flutter test` en verde · `functions`: `npm run lint`, `npm test` y `npm run test:rules` (emulador de Firestore) en verde. `deno check` no se corrió en este equipo (Deno no instalado).

---

## Dev B — Clínica y botón SOS

### Preparación

- [ ] Cuenta Google A registrada como **clínica** (con dirección, teléfono y ubicación).
- [ ] Cuenta Google B registrada como **dueño** con al menos una mascota (anotar su código **MSC-XXXX** en Perfil de la mascota → Historial).
- [ ] Si se usa un solo teléfono: cerrar sesión entre cuentas (Perfil → Cerrar sesión). Ideal: dos dispositivos.

### 1. Perfil de atención y horario (RF-04)

- [ ] Entrar con la clínica recién registrada: lleva al paso obligatorio **Perfil de atención** (no deja usar la agenda antes).
- [ ] Sin elegir ningún tipo de animal, **Guardar** muestra el error de validación y no guarda.
- [ ] Elegir especies, activar/desactivar "Atención de emergencias", definir horario por día (abrir/cerrar, días cerrados).
- [ ] Una hora de cierre anterior a la de apertura muestra error y no guarda.
- [ ] Guardar → mensaje de éxito; la clínica pasa de `incompleto` a `activo` y aparecen las pestañas.
- [ ] Salir y volver a entrar: los datos guardados se conservan. Perfil → **Perfil de atención** los muestra para editar.

### 2. Servicios (RF-05)

- [ ] Pestaña **Servicios** sin servicios: estado vacío con botón para crear.
- [ ] Crear servicio: nombre, categoría, descripción, precio y duración. Probar datos inválidos (nombre vacío o muy corto, precio 0 o negativo, duración fuera de rango): cada campo muestra su mensaje y no guarda.
- [ ] Guardar → snackbar "Servicio creado"; aparece en la lista al instante.
- [ ] Editar el servicio → "Servicio actualizado".
- [ ] Eliminar un servicio **sin** citas → diálogo "¿Eliminar "<nombre>"? Se ocultará del catálogo." → desaparece.
- [ ] Eliminar un servicio **con** una cita pendiente o confirmada → el diálogo dice "Este servicio tiene N citas activas…"; al eliminar, la cita sigue visible en Solicitudes/Agenda.
- [ ] Con el dueño B, el servicio eliminado ya no aparece al agendar en esa clínica.

### 3. Agenda y excepciones (RF-06, Cambio 2)

- [ ] Pestaña **Agenda**: calendario con el día de hoy seleccionado; las franjas siguen el horario semanal.
- [ ] Los días cerrados del horario no tienen franjas.
- [ ] Marcar un día como excepción (cerrado o con horario distinto, p. ej. festivo) → guardar → al cambiar de día y volver se conserva.
- [ ] Seleccionar varias franjas y **No disponible** → con el dueño B esas horas no se ofrecen.
- [ ] **Cancelar** la selección limpia sin guardar nada.
- [ ] Franjas pasadas y ocupadas son de solo lectura; una franja reservada muestra la cita y al tocarla abre el detalle.
- [ ] Tarjeta **Próximas citas** muestra las de hoy y mañana.
- [ ] Si hay citas fuera del nuevo horario, aparece el aviso correspondiente.

### 4. Solicitudes de cita (RF-14, lado clínica)

- [ ] Con el dueño B, solicitar una cita en la clínica A.
- [ ] Clínica: la pestaña **Solicitudes** muestra el contador y la tarjeta (mascota, especie, dueño, servicio, fecha, comentario) en tiempo real, sin recargar.
- [ ] Abrir la solicitud: se ve el historial de la mascota.
- [ ] **Aprobar** → el dueño ve "Confirmada" y recibe notificación.
- [ ] Otra solicitud → **Rechazar** sin motivo: no deja enviar. Con motivo → el dueño ve "Rechazada" y el motivo.
- [ ] Cita confirmada → **Cancelar cita** con motivo obligatorio → el dueño recibe el aviso.
- [ ] Antes de la hora de inicio, **Marcar como atendida** no está disponible; después sí, y ofrece **Registrar consulta**.
- [ ] Si la solicitud ya la respondió otra persona (dos dispositivos con la misma clínica), aparece el aviso y no se duplica.
- [ ] Sin solicitudes: estado vacío.

### 5. Pacientes y consultas (RF-08 lado clínica)

- [ ] Pestaña **Pacientes** vacía: mensaje que explica pedir el código MSC-XXXX.
- [ ] **Vincular paciente** con un texto mal formado (`ABC`) → "El código debe tener el formato MSC-XXXX."
- [ ] Código bien formado pero inexistente → mensaje de código inexistente. Varios intentos fallidos → mensaje de límite de intentos.
- [ ] Código correcto del dueño B → la mascota aparece en la lista con el nombre del dueño.
- [ ] Buscador filtra por nombre de mascota o dueño.
- [ ] Perfil del paciente: alergias y condiciones resaltadas (con ícono, no solo en rojo) e historial.
- [ ] **Registrar consulta**: fecha, diagnóstico, tratamiento; probar campos vacíos o demasiado largos → mensajes del RF.
- [ ] Agregar vacuna con lote y próxima dosis (próxima dosis anterior a la aplicación → error).
- [ ] Adjuntar JPG/PNG/PDF ≤ 10 MB; un archivo > 10 MB o de otro tipo se rechaza con mensaje.
- [ ] Guardar → el dueño B ve la consulta en su historial en tiempo real.
- [ ] La consulta se puede corregir durante 24 h; después es de solo lectura.
- [ ] Desde el perfil del paciente, **Enviar mensaje** abre (o crea) el chat con el dueño.
- [ ] Si el dueño revoca el acceso, la clínica ya no ve el historial de esa mascota.

### 6. Inventario (RF-07)

- [ ] Pestaña **Inventario** vacía → estado vacío con "Agregar producto".
- [ ] Crear producto sin foto → no deja guardar. Foto > 5 MB → rechazada con mensaje.
- [ ] Nombre < 3 o > 60 caracteres, precio 0, stock negativo → mensajes de validación.
- [ ] Crear con foto de cámara y otro con galería → la foto sube (comprimida) y aparece en la lista.
- [ ] Nombre muy parecido a uno existente → aviso de duplicado.
- [ ] Botones **+ / −** de stock actualizan al instante; con stock ≤ 3 aparece el aviso de stock bajo; en 0 queda "Agotado".
- [ ] Buscador y filtro por estado funcionan.
- [ ] **Desactivar** un producto → el dueño B ya no lo ve en la tienda. **Volver a publicar** → reaparece.

### 7. Pedidos recibidos (RF-07 / RF-12)

- [ ] Con el dueño B, comprar un producto (pago simulado).
- [ ] Clínica: **Inventario → Pedidos** muestra el pedido en "Por preparar" con contador.
- [ ] Detalle → avanzar estado (preparando → listo/enviado → entregado); el dueño ve cada cambio y recibe aviso.
- [ ] **Cancelar pedido** sin motivo no deja; con motivo muestra el aviso del reembolso y el stock vuelve.
- [ ] Los pedidos entregados o cancelados quedan en "Historial".
- [ ] Un pedido pendiente de pago **no** aparece a la clínica.

### 8. Chat del lado clínica (RF-15, RF-16)

- [ ] Pestaña **Mensajes**: bandeja con foto/iniciales del dueño, mascotas, vista previa, hora y contador de no leídos.
- [ ] Buscador por dueño o mascota; filtro **Sin leer**.
- [ ] Abrir conversación: marca leídos; "escribiendo…" aparece cuando el dueño escribe.
- [ ] Enviar texto; el botón enviar está deshabilitado si está vacío; contador desde 1800 caracteres.
- [ ] Adjuntar **Foto o imagen** y **Documento PDF**; archivo > 10 MB o de otro tipo → mensaje.
- [ ] **Desde el historial**: adjunta un archivo de una consulta con la etiqueta "Del historial médico de <mascota>".
- [ ] Tocar imagen → visor con zoom; PDF → visor del teléfono.
- [ ] Desde el detalle de una cita, **Enviar mensaje** abre el chat correcto.
- [ ] Sin chats: estado vacío.

### 9. Botón SOS (RF-10, lado dueño)

- [ ] Con el dueño B, el botón de emergencia del encabezado y el acceso **Emergencia** del home abren `/sos`.
- [ ] Con ubicación: aparecen primero aliadas con emergencias, luego veterinarias 24/7 de OpenStreetMap, luego las demás, por distancia.
- [ ] **Llamar** abre el marcador con el teléfono; **Cómo llegar** abre el mapa.
- [ ] Una clínica sin teléfono no muestra "Llamar".
- [ ] La pantalla nunca queda vacía: muestra favoritas/últimas guardadas mientras llega la ubicación.

### 10. Casos de error

- [ ] **Sin conexión** (modo avión) en Agenda, Solicitudes, Pacientes, Inventario y Mensajes: muestra los datos en caché o un error con **Reintentar**; nunca pantalla en blanco ni cierre. Al volver la red, Reintentar carga.
- [ ] **Sin conexión** al guardar un servicio o un producto: mensaje de error claro, el formulario no se pierde.
- [ ] **Sin conexión** al guardar el Perfil de atención, una consulta, un bloqueo de la agenda o al eliminar un servicio: a los ~10 s aparece "Sin conexión: se guardará cuando vuelva la red." (no se queda girando). Al volver la red, el cambio aparece en el otro dispositivo.
- [ ] **Sin conexión** al aprobar/rechazar una cita: mensaje de error, la cita no cambia de estado.
- [ ] **Sin conexión** en el chat: aviso "Sin conexión, se enviará cuando vuelva la red"; al volver se envía.
- [ ] **Sin conexión** en SOS: favoritas y últimas mostradas con "Reintentar".
- [ ] **Sin permiso de ubicación** en SOS (denegar el permiso): muestra clínicas guardadas y "Activar ubicación"; al conceder, carga las cercanas.
- [ ] **Sin permiso de cámara** al tomar la foto de un producto o adjunto: mensaje, sin cierre de la app.
- [ ] **Sesión cerrada**: cerrar sesión y usar Atrás → no vuelve a pantallas de la clínica. Abrir una notificación de cita con la sesión cerrada → lleva al login.
- [ ] **Datos inválidos**: los de cada sección arriba (servicios, horario, consulta, vacunas, productos, código MSC-XXXX, motivos vacíos).
- [ ] **Rol equivocado**: con el dueño B, escribir una ruta de clínica (o abrir un enlace) no muestra pantallas de clínica.

### 11. Accesibilidad (WCAG 2.1 AA)

- [ ] **TalkBack** activado: recorrer Agenda, Solicitudes, detalle de cita, Pacientes, formulario de consulta, Servicios, Inventario, Pedidos y Mensajes. Cada botón de ícono se anuncia con su nombre (no "botón sin etiqueta"); las tarjetas se leen completas; el estado de una cita o pedido se dice en texto.
- [ ] TalkBack en SOS: el encabezado anuncia "Emergencia, botón"; la primera acción es "Llamar a <clínica más cercana>".
- [ ] **Letra al 200 %** (Ajustes → Pantalla → Tamaño de fuente al máximo, o Perfil → Accesibilidad): las mismas pantallas sin texto cortado ni superpuesto; los diálogos y bottom sheets hacen scroll.
- [ ] **Modo oscuro** (Perfil → Accesibilidad o el del sistema): todo legible, sin textos negros sobre fondo oscuro; chips de estado y calendario con contraste.
- [ ] **Alto contraste**: activar y revisar Agenda y Solicitudes.
- [ ] Botones y áreas táctiles de al menos 48 dp (los +/− del inventario, los chips del calendario).

### Correcciones de la estabilización (Dev B)

- `fix(clinica)`: RF-05, el aviso "Este servicio tiene N citas activas" nunca salía (el conteo devolvía siempre 0).
- `fix(clinica)`: sin conexión, Perfil de atención, bloqueos de la Agenda, Registrar consulta y Eliminar servicio se quedaban "guardando" para siempre (la agenda quedaba deshabilitada). Ahora, a los 10 s siguen y avisan "Sin conexión: se guardará cuando vuelva la red." (Firestore envía el cambio al volver la red).

---

## Limitaciones conocidas

- Pagos solo simulados / sandbox (Cambio 5); no hay cobros reales.
- RF-11 (chatbot) fuera de la versión 1.0 (Cambio 6).
- RF-10 sin la cuenta regresiva de 3 s del RF (ver `cambios-alcance.md`).
