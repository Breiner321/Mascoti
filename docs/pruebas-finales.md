# Pruebas finales (entrega del 27 de noviembre de 2026)

Lista de verificación manual antes de la entrega. Cada desarrollador completa la sección de su módulo y la ejecuta en el emulador **con Google Play** y, si se puede, en un celular real con el APK de release (`flutter build apk --release --dart-define-from-file=env/dev.json`).

Cómo reportar un error: pasos para reproducirlo, qué esperabas, qué pasó y una captura. Lo que no se alcance a corregir se anota al final en **Limitaciones conocidas**.

Cuentas de prueba: un **dueño** (con al menos una mascota con foto) y una **clínica** activa con horario, servicios y productos. Para notificaciones y chat hacen falta dos dispositivos (o emulador + celular).

---

## Dev A — Núcleo y servidor

Inicio de sesión, registro, navegación, notificaciones, reglas de seguridad, Edge Functions, tienda/pagos y placa QR.

### 1. Inicio de sesión y registro (RF-01, RF-02, RF-03)

**Dueño nuevo**
- [ ] Abrir la app sin sesión → pantalla de bienvenida con "Continuar con Google".
- [ ] Elegir una cuenta de Google nueva → pantalla de registro.
- [ ] Elegir "Dueño": el nombre viene prellenado con el de Google y se puede editar.
- [ ] Nombre de 2 letras → mensaje de error; nombre válido (3–60) y teléfono de 10 dígitos → "Finalizar registro".
- [ ] Aparece el onboarding de 3 pasos; "Saltar" o terminarlo lleva al inicio del dueño.
- [ ] Cerrar y volver a abrir la app → entra directo, sin volver a pedir registro ni onboarding.

**Clínica nueva**
- [ ] Registrar con rol "Clínica": nombre, teléfono y dirección buscada con el buscador (elegir una sugerencia).
- [ ] Al terminar, la app obliga a ir a "Perfil de atención" (no deja usar otras pestañas hasta completarlo).
- [ ] Completar tipos de animales y horario → ya se ven las pestañas de la clínica.

**Sesión**
- [ ] Perfil → "Cerrar sesión" → vuelve a la bienvenida; atrás no regresa a la app.
- [ ] Dueño registrado antes del Cambio 1 (sin nombre) → "Completa tu perfil" antes de cualquier otra pantalla.
- [ ] Perfil → "Editar perfil": cambiar nombre y teléfono, guardar; se ve el cambio en el perfil.
- [ ] Cuenta suspendida (`npm run suspender` en `functions/`) → pantalla de cuenta suspendida con el mensaje y "Cerrar sesión".

**Errores**
- [ ] **Sin conexión** al pulsar "Continuar con Google" → mensaje de conexión, sin quedarse cargando.
- [ ] **Sin conexión** en "Finalizar registro" → mensaje en español y se puede reintentar.
- [ ] **Sin conexión** al abrir la app con sesión → a los 10 s: "Estamos tardando en conectar…" con "Reintentar" y "Cerrar sesión" (sin texto técnico en inglés).
- [ ] Cancelar la ventana de Google → vuelve a la bienvenida sin error.
- [ ] **Sin permiso de ubicación** en el registro de la clínica → la dirección se busca escribiéndola.
- [ ] Teléfono con letras o de 9 dígitos → no deja continuar.

### 2. Navegación

- [ ] Dueño: pestañas Principal, Mapa, Tienda, Citas, Mensajes; encabezado con carrito, SOS, campana y perfil.
- [ ] Clínica: Solicitudes, Agenda, Pacientes, Servicios, Inventario y Mensajes; sin carrito ni SOS en el encabezado.
- [ ] Atrás del sistema en una pantalla de detalle vuelve a la anterior; en una pestaña principal no cierra la sesión.
- [ ] Ningún botón queda sin hacer nada; ningún acceso dice "Próximamente" si la pantalla ya existe.

### 3. Notificaciones (RF-13)

- [ ] Primer inicio en Android 13+ → pide permiso de notificaciones; aceptarlo.
- [ ] Con dos dispositivos: el dueño solicita una cita → a la clínica le llega "Nueva solicitud de cita".
- [ ] La clínica aprueba / rechaza (con motivo) / cancela → al dueño le llega el aviso correspondiente.
- [ ] Probar el push con la app **abierta**, **en segundo plano** y **cerrada**; tocarlo abre la cita.
- [ ] Mensaje de chat → push que abre la conversación; con la conversación abierta, no llega aviso.
- [ ] Pedido pagado → al dueño "Pago aprobado" (abre el pedido) y a la clínica "Nuevo pedido" (abre sus pedidos).
- [ ] Campana con el número de no leídas; abrir el centro de notificaciones, tocar una → se marca leída y baja el número.
- [ ] **Permiso negado** → no llegan push, pero las notificaciones sí aparecen en la campana.
- [ ] Cerrar sesión en un dispositivo → ya no le llegan push de esa cuenta.

### 4. Tienda y pagos (RF-07, RF-12)

**Clínica (inventario)**
- [ ] Inventario → "Nuevo Producto": nombre, categoría, precio, stock y foto → aparece en la lista.
- [ ] Botones +/− del stock; al llegar a 0 → "Agotado"; al subir → vuelve a "Activo".
- [ ] Desactivar un producto → ya no lo ve el dueño.
- [ ] Datos inválidos: nombre de 2 letras, precio 0 o con decimales, stock negativo → mensajes de error, no guarda.

**Dueño (compra)**
- [ ] Tienda → elegir clínica → catálogo con buscador y filtros por categoría.
- [ ] Producto → cantidad (no deja pasar de lo disponible) → "Agregar al carrito"; el carrito del encabezado muestra el número.
- [ ] Agregar un producto de **otra clínica** → pregunta "Tu carrito tiene productos de otra clínica. ¿Vaciarlo?"; Cancelar no cambia nada, Aceptar vacía y agrega.
- [ ] Carrito: cambiar cantidades, quitar un producto, subtotal de referencia.
- [ ] "Continuar con la compra" → **Recoger**: muestra la dirección de la clínica; **Domicilio**: pide dirección y teléfono.
- [ ] Pagar → pantalla "Pagar pedido" (pago de prueba) → "Pagar $…" → pedido `pagado`, aviso "Pago aprobado", carrito vacío, stock descontado; "Ver mi pedido" abre el detalle.
- [ ] Repetir y pulsar "Simular pago rechazado" → "Tu pago no pudo ser procesado. Tus productos siguen en el carrito."; el stock no baja.
- [ ] "Mis pedidos" muestra los pedidos con su estado.
- [ ] Dejar un pedido sin pagar 15 min → pasa a "Expirado" y el stock vuelve a estar disponible (la tarea corre cada 10 min).

**Clínica (pedidos)**
- [ ] Pedidos recibidos: solo los pagados. Avanzar: En preparación → Listo para recoger (recoger) o Enviado (domicilio) → Entregado; el dueño recibe un aviso en cada cambio.
- [ ] Cancelar un pedido pagado **sin motivo** → no deja; con motivo → el dueño recibe "Tu pedido fue cancelado: <motivo>…" y el stock vuelve.

**Errores**
- [ ] **Sin conexión** al confirmar la compra → mensaje de conexión, el botón se puede volver a pulsar.
- [ ] Dos dueños compran la **última unidad** a la vez → uno paga; el otro ve "… ya no tiene unidades disponibles".
- [ ] Carrito con un producto que la clínica agotó → aviso en el carrito y no deja continuar.
- [ ] Domicilio con dirección vacía o teléfono inválido → no deja pagar.

### 5. Placa QR (RF-17)

- [ ] Mascota **sin foto** → Documentos → la tarjeta pide "Agregar foto".
- [ ] Mascota con foto → "Crear placa QR" → interruptores (mi nombre, mi teléfono, alergias) y mensaje; la vista previa cambia con cada interruptor.
- [ ] Apagar el teléfono sin mensaje → "Muestra tu teléfono o escribe un mensaje…"; con mensaje → crea la placa.
- [ ] Se ve el QR, el nombre de la mascota y el estado "Activa" con ícono.
- [ ] "Compartir imagen" → se abre el menú de compartir con un PNG `placa_<nombre>.png`.
- [ ] Escanear el QR con otro teléfono → abre `https://mascoti-b27cf.web.app/q/…` con nombre, especie, foto y solo lo elegido; el teléfono aparece como `300 *** **67`.
- [ ] "Ver teléfono" → muestra el número; "Llamar" abre el marcador.
- [ ] Pulsar "Ver teléfono" en 6 placas en menos de una hora desde la misma red → "Ya viste varios teléfonos…".
- [ ] "Qué se muestra" → cambiar opciones → la página pública cambia al recargar.
- [ ] "Desactivar placa" → confirmación → estado "Desactivada"; la página dice "Esta placa no está activa". "Volver a activar" la recupera.
- [ ] Página pública **sin conexión** → "No pudimos cargar la placa" con "Reintentar".

### 6. Seguridad (con la app o la consola)

- [ ] Un dueño no ve citas, pedidos, carritos, mascotas ni placas de otro dueño.
- [ ] Una clínica no ve pedidos pendientes de pago ni datos de otra clínica.
- [ ] La app no puede marcar un pedido como pagado ni cambiar precios o stock reservado (lo prueban `npm run test:rules`).

### 7. Accesibilidad (Cambio 3)

Activar **TalkBack** y recorrer: bienvenida, registro, inicio, tienda (catálogo, producto, carrito, confirmar compra, pago), notificaciones, perfil y Documentos (placa QR).
- [ ] Cada botón de ícono se anuncia con su nombre (carrito con el número de productos, campana con las no leídas, SOS primero en el encabezado).
- [ ] El QR se anuncia como "Código QR de la placa de <nombre>…"; el estado como "Estado: Activa/Desactivada".
- [ ] Los estados no dependen solo del color (ícono o texto): agotado, activa/desactivada, estado del pedido.

**Letra al 200 %** (Ajustes del teléfono → tamaño de fuente al máximo + Perfil → Accesibilidad → 150 %):
- [ ] Las mismas pantallas se leen completas, sin texto cortado ni superpuesto; todo se puede desplazar.

**Modo oscuro y alto contraste** (Perfil → Accesibilidad):
- [ ] Las mismas pantallas se ven legibles en modo oscuro y en alto contraste.
- [ ] La imagen de la placa QR sigue siendo clara (fondo blanco) en modo oscuro.
- [ ] La página pública de la placa en un teléfono con modo oscuro se ve legible.

---

## Dev B — Clínica y botón SOS

**Revisión automática (26 nov, Dev B):** `flutter analyze` 0 issues · `flutter test` en verde · `functions`: `npm run lint`, `npm test` y `npm run test:rules` (emulador de Firestore) en verde. `deno check` no se corrió en este equipo (Deno no instalado).

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
- [ ] Enviar dos veces seguidas el mismo texto (p. ej. `hola` y `hola`) y dos mensajes largos parecidos: los dos se envían (requiere las reglas desplegadas después del 26/11).
- [ ] Si un envío falla, aparece "No se pudo enviar el mensaje. Intenta de nuevo." y el texto vuelve al campo.
- [ ] Notificaciones: el dueño recibe push del primer mensaje; los que lleguen en los 30 s siguientes se agrupan sin push nuevo (comportamiento esperado de `notificar-mensaje`).
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
- `fix(chat)`: si el servidor rechazaba un mensaje, desaparecía sin aviso y se perdía el texto. Ahora avisa y devuelve el texto al campo.
- `fix(reglas)`: Firestore rechazaba el envío cuando el mismo remitente repetía un texto o mandaba dos mensajes largos con la misma vista previa (la regla exigía que `lastMessage` cambiara). **Hay que desplegar las reglas** (`firebase deploy --only firestore:rules`) para que llegue al proyecto.

---

---

## Limitaciones conocidas

- **Reembolsos:** la app no devuelve dinero. Si la clínica cancela un pedido pagado, el dueño recibe el aviso de que la clínica lo contactará (Cambio 5). Los pagos son simulados.
- **Asistente virtual (RF-11):** fuera de la versión 1.0 (Cambio 6).
- RF-10 sin la cuenta regresiva de 3 s del RF (ver `cambios-alcance.md`).
