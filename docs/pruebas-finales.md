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

## Limitaciones conocidas

- **Reembolsos:** la app no devuelve dinero. Si la clínica cancela un pedido pagado, el dueño recibe el aviso de que la clínica lo contactará (Cambio 5). Los pagos son simulados.
- **Asistente virtual (RF-11):** fuera de la versión 1.0 (Cambio 6).
