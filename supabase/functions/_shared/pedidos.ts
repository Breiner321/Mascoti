import type { BaseDatos, DocumentoLeido, Escritura } from "./cliente_firestore.ts";
import { ErrorFuncion } from "./errores.ts";
import {
  ESTADOS_DE_LA_CLINICA,
  ETIQUETA_ESTADO,
  esEstadoPedido,
  esTipoEntrega,
  type EstadoPedido,
  puedeTransicionarPedido,
  type TipoEntrega,
} from "./estados_pedido.ts";
import {
  actualizarCampos,
  borrarDocumento,
  crearDocumento,
  HORA_SERVIDOR,
  type ValorCampo,
} from "./firestore.ts";
import { nombreVisible } from "./nombres.ts";
import type { Aviso } from "./notificaciones.ts";
import {
  type NombrePasarela,
  type Pasarela,
  pasarelaDelPedido,
  PREFIJO_TRANSACCION_SIMULADA,
} from "./pasarela.ts";
import type { UsuarioFirebase } from "./registro.ts";
import { type EventoWompi, MONEDA, verificarEvento } from "./wompi.ts";

export type { ConfigWompi } from "./pasarela.ts";

/**
 * Pedidos de la tienda (RF-12): lógica de las Edge Functions `crear-pedido`,
 * `pagar-pedido-simulado`, `webhook-wompi` y `actualizar-pedido`, y de la
 * tarea de pedidos vencidos.
 *
 * Reglas de oro: la app nunca calcula el total ni marca un pedido como
 * pagado; precio y stock se leen aquí; el resultado del pago lo registra
 * SOLO el servidor ([registrarPago]): hoy con pagos simulados
 * (`pagar-pedido-simulado`) y, cuando se active, con el webhook de Wompi
 * (ver ./pasarela.ts).
 *
 * Cada cambio es UN commit con precondición `updateTime` sobre el pedido y
 * cada producto que toca (transacción optimista, como `citas.ts`): si otra
 * petición cambió algo en medio, se vuelve a leer y se decide de nuevo. Así,
 * de dos compras simultáneas de la última unidad solo una gana, y un evento
 * de Wompi repetido no descuenta stock dos veces (el segundo ya encuentra el
 * pedido `pagado`).
 *
 * Stock: `products.stockReservado` aparta las unidades de los pedidos
 * `pendiente_pago`; lo disponible es `stock - stockReservado`.
 */

/** Minutos que se aparta el stock mientras el dueño paga. */
export const MINUTOS_RESERVA = 15;
/** Pedidos `pendiente_pago` simultáneos por dueño (contra el abuso). */
export const MAX_PENDIENTES = 3;
export const MAX_ITEMS = 30;
export const MAX_CANTIDAD = 99;
export const MAX_MOTIVO = 300;
export const MIN_DIRECCION = 5;
export const MAX_DIRECCION = 200;
/** Prefijo de la referencia de pago: `MSC-{orderId}`. */
export const PREFIJO_REFERENCIA = "MSC-";

const MAX_INTENTOS = 5;
const MINUTO_MS = 60 * 1000;

export const MENSAJE_PAGO_RECHAZADO = "Tu pago no pudo ser procesado";

export interface DependenciasPedidos {
  db: BaseDatos;
  ahora(): Date;
  /** Envía una notificación (documento + push, RF-13). Si falla, el cambio igual queda. */
  notificar?(aviso: Aviso): Promise<void>;
  log?(mensaje: string): void;
}

export interface DependenciasCrearPedido extends DependenciasPedidos {
  verificarToken(token: string): Promise<UsuarioFirebase>;
  nuevoId(): string;
  /** Pasarela activa (`PASARELA_PAGO`): por ahora la simulada. */
  pasarela: Pasarela;
}

export interface DependenciasPagoSimulado extends DependenciasPedidos {
  verificarToken(token: string): Promise<UsuarioFirebase>;
  /** Pasarela activa: el pago simulado solo funciona si es la simulada. */
  pasarelaActiva: NombrePasarela;
}

type Cuerpo = Record<string, unknown>;
type Datos = Record<string, unknown>;

const texto = (v: unknown): string => (typeof v === "string" ? v : "");
const entero = (v: unknown): number => (typeof v === "number" && Number.isInteger(v) ? v : 0);

// ---------------------------------------------------------------------------
// Cálculos puros (con pruebas en functions/test/pedidos.test.ts)
// ---------------------------------------------------------------------------

export interface ItemPedido {
  productId: string;
  nombre: string;
  precio: number;
  cantidad: number;
}

/** Total en pesos: suma de precio × cantidad, con enteros. */
export function calcularTotal(items: readonly { precio: number; cantidad: number }[]): number {
  let total = 0;
  for (const item of items) {
    if (!Number.isSafeInteger(item.precio) || item.precio <= 0) {
      throw new Error(`Precio inválido: ${item.precio}`);
    }
    if (!Number.isInteger(item.cantidad) || item.cantidad <= 0) {
      throw new Error(`Cantidad inválida: ${item.cantidad}`);
    }
    total += item.precio * item.cantidad;
  }
  if (!Number.isSafeInteger(total)) throw new Error("Total demasiado grande");
  return total;
}

export interface Entrega {
  tipo: TipoEntrega;
  direccion?: string;
  telefono: string;
}

/** Valida la entrega con los mismos mensajes que `OrderDelivery.validate`. */
export function validarEntrega(valor: unknown): Entrega {
  const e = (typeof valor === "object" && valor !== null ? valor : {}) as Cuerpo;
  if (!esTipoEntrega(e.tipo)) {
    throw new ErrorFuncion("invalid-argument", "Elige si recoges el pedido o lo envían a domicilio.");
  }
  const telefono = texto(e.telefono).trim();
  if (!/^\d{10}$/.test(telefono)) {
    throw new ErrorFuncion("invalid-argument", "El teléfono debe tener 10 dígitos");
  }
  if (e.tipo === "recoger") return { tipo: "recoger", telefono };
  const direccion = texto(e.direccion).trim();
  if (direccion.length < MIN_DIRECCION || direccion.length > MAX_DIRECCION) {
    throw new ErrorFuncion(
      "invalid-argument",
      `Escribe la dirección de entrega (entre ${MIN_DIRECCION} y ${MAX_DIRECCION} caracteres)`,
    );
  }
  return { tipo: "domicilio", direccion, telefono };
}

/** Mensaje cuando no hay unidades suficientes de un producto. */
export function mensajeStock(nombre: string, disponibles: number): string {
  if (disponibles <= 0) return `${nombre} ya no tiene unidades disponibles`;
  return `Solo ${disponibles === 1 ? "queda 1 unidad" : `quedan ${disponibles} unidades`} de ${nombre}`;
}

/** `MSC-{orderId}` → orderId, o null si no es una referencia de Mascoti. */
export function pedidoDeReferencia(referencia: unknown): string | null {
  if (typeof referencia !== "string" || !referencia.startsWith(PREFIJO_REFERENCIA)) return null;
  const id = referencia.slice(PREFIJO_REFERENCIA.length);
  return /^[A-Za-z0-9]{1,128}$/.test(id) ? id : null;
}

function itemsDe(pedido: Datos): ItemPedido[] {
  const items = Array.isArray(pedido.items) ? pedido.items : [];
  return items
    .filter((i): i is Datos => typeof i === "object" && i !== null)
    .map((i) => ({
      productId: texto(i.productId),
      nombre: texto(i.nombre),
      precio: entero(i.precio),
      cantidad: entero(i.cantidad),
    }))
    .filter((i) => i.productId.length > 0 && i.cantidad > 0);
}

/** Unidades por producto de un pedido. */
function cantidades(items: readonly ItemPedido[]): Map<string, number> {
  const mapa = new Map<string, number>();
  for (const i of items) mapa.set(i.productId, (mapa.get(i.productId) ?? 0) + i.cantidad);
  return mapa;
}

/** Estado de un producto que no está inactivo según su stock. */
function estadoPorStock(estadoActual: unknown, stock: number): string {
  if (estadoActual === "inactivo") return "inactivo";
  return stock === 0 ? "agotado" : "activo";
}

// ---------------------------------------------------------------------------
// Sesión
// ---------------------------------------------------------------------------

async function usuarioActivo(
  deps: DependenciasCrearPedido | (DependenciasPedidos & { verificarToken(t: string): Promise<UsuarioFirebase> }),
  autorizacion: string | null,
): Promise<{ uid: string; email?: string; perfil: Datos }> {
  const token = autorizacion?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) throw new ErrorFuncion("unauthenticated", "Debes iniciar sesión con Google.");
  let usuario: UsuarioFirebase;
  try {
    usuario = await deps.verificarToken(token);
  } catch {
    throw new ErrorFuncion("unauthenticated", "Debes iniciar sesión con Google.");
  }
  const perfil = (await deps.db.leer(`users/${usuario.uid}`))?.datos;
  if (!perfil) throw new ErrorFuncion("permission-denied", "Completa tu registro para continuar.");
  if (perfil.estado !== "activo") {
    throw new ErrorFuncion("permission-denied", "Tu cuenta ha sido suspendida. Contacta a soporte");
  }
  return { uid: usuario.uid, email: usuario.email, perfil };
}

function idDe(cuerpo: Cuerpo, campo: string): string {
  const valor = cuerpo[campo];
  if (typeof valor !== "string" || valor.length === 0 || valor.length > 128 || valor.includes("/")) {
    throw new ErrorFuncion("invalid-argument", `Falta ${campo}.`);
  }
  return valor;
}

async function conReintentos<T>(intento: () => Promise<T | "conflicto">): Promise<T> {
  for (let i = 0; i < MAX_INTENTOS; i++) {
    const resultado = await intento();
    if (resultado !== "conflicto") return resultado;
  }
  throw new ErrorFuncion("aborted", "Hay mucha gente comprando en este momento. Intenta de nuevo.");
}

async function avisar(deps: DependenciasPedidos, avisos: Aviso[]): Promise<void> {
  if (!deps.notificar) return;
  for (const aviso of avisos) {
    if (!aviso.uid) continue;
    try {
      await deps.notificar(aviso);
    } catch (e) {
      deps.log?.(`No se pudo notificar ${aviso.tipo} a ${aviso.uid}: ${e}`);
    }
  }
}

// ---------------------------------------------------------------------------
// Productos: leer y armar las escrituras de stock
// ---------------------------------------------------------------------------

/**
 * Lee los productos [ids] de la clínica y arma, para cada uno, la escritura
 * con precondición `updateTime` que aplica [cambio] a su stock. `cambio`
 * recibe el documento actual y devuelve los campos nuevos (o null si no
 * cambia nada).
 */
async function escriturasDeStock(
  db: BaseDatos,
  clinicId: string,
  ids: Iterable<string>,
  cambio: (producto: DocumentoLeido) => Record<string, ValorCampo> | null,
): Promise<Escritura[]> {
  const escrituras: Escritura[] = [];
  for (const productId of ids) {
    const producto = await db.leer(`clinics/${clinicId}/products/${productId}`);
    if (!producto) continue; // No se borran, pero por si acaso.
    const campos = cambio(producto);
    if (!campos) continue;
    escrituras.push(
      actualizarCampos(db.proyecto, producto.ruta, { ...campos, updatedAt: HORA_SERVIDOR }, {
        updateTime: producto.updateTime,
      }),
    );
  }
  return escrituras;
}

/** Devuelve la reserva de [pedido] (pago rechazado, expirado o reemplazado). */
function liberarReserva(db: BaseDatos, pedido: Datos): Promise<Escritura[]> {
  const porProducto = cantidades(itemsDe(pedido));
  return escriturasDeStock(db, texto(pedido.clinicId), porProducto.keys(), (p) => {
    const reservado = entero(p.datos.stockReservado);
    return { stockReservado: Math.max(0, reservado - (porProducto.get(p.id) ?? 0)) };
  });
}

/** Cambio de estado de un pedido con precondición sobre lo leído. */
function escrituraPedido(
  db: BaseDatos,
  pedido: DocumentoLeido,
  campos: Record<string, ValorCampo | undefined>,
): Escritura {
  return actualizarCampos(db.proyecto, pedido.ruta, { ...campos, updatedAt: HORA_SERVIDOR }, {
    updateTime: pedido.updateTime,
  });
}

// ---------------------------------------------------------------------------
// crear-pedido
// ---------------------------------------------------------------------------

export interface ResultadoCrearPedido {
  orderId: string;
  referencia: string;
  total: number;
  /** Con qué se paga: `simulada` (pantalla de prueba en la app) o `wompi`. */
  pasarela: NombrePasarela;
  /** Página de la pasarela; null con pagos simulados. */
  checkoutUrl: string | null;
  redirectUrl: string | null;
  expiraEn: string;
  /** true si se reutilizó un pedido pendiente idéntico. */
  reutilizado: boolean;
}

/** Mismos productos, cantidades y entrega. */
function mismoPedido(pedido: Datos, items: ItemPedido[], entrega: Entrega): boolean {
  const a = cantidades(itemsDe(pedido));
  const b = cantidades(items);
  if (a.size !== b.size) return false;
  for (const [id, n] of b) if (a.get(id) !== n) return false;
  const e = (pedido.entrega ?? {}) as Datos;
  return e.tipo === entrega.tipo && texto(e.telefono) === entrega.telefono &&
    texto(e.direccion) === (entrega.direccion ?? "");
}

async function checkoutDe(
  deps: DependenciasCrearPedido,
  orderId: string,
  total: number,
  expiraEn: Date,
  contacto: { correo?: string; nombre?: string; telefono?: string },
): Promise<Omit<ResultadoCrearPedido, "reutilizado">> {
  const referencia = `${PREFIJO_REFERENCIA}${orderId}`;
  const inicio = await deps.pasarela.iniciarPago({ orderId, referencia, total, expiraEn, contacto });
  return {
    orderId,
    referencia,
    total,
    pasarela: deps.pasarela.nombre,
    ...inicio,
    expiraEn: expiraEn.toISOString(),
  };
}

/**
 * "Confirmar compra" (RF-12 pasos 6-7). Lee el carrito y los productos,
 * valida clínica activa, productos activos y stock suficiente, calcula el
 * total y, en UN commit, crea el pedido `pendiente_pago` y aparta el stock
 * por 15 minutos. Devuelve cómo pagar según la pasarela activa (pago
 * simulado o Web Checkout de Wompi firmado).
 */
export async function crearPedido(
  deps: DependenciasCrearPedido,
  autorizacion: string | null,
  cuerpo: unknown,
): Promise<ResultadoCrearPedido> {
  const datos = (typeof cuerpo === "object" && cuerpo !== null ? cuerpo : {}) as Cuerpo;
  const sesion = await usuarioActivo(deps, autorizacion);
  if (sesion.perfil.role !== "dueno") {
    throw new ErrorFuncion("permission-denied", "Solo los dueños de mascotas pueden comprar en la tienda.");
  }
  const clinicId = idDe(datos, "clinicId");
  const entrega = validarEntrega(datos.entrega);

  const clinica = await deps.db.leer(`clinics/${clinicId}`);
  if (!clinica || clinica.datos.estado !== "activo") {
    throw new ErrorFuncion("failed-precondition", "Esta clínica no está vendiendo en este momento.");
  }

  // Carrito (solo cantidades: nombre y precio se leen de los productos).
  const carrito = await deps.db.consultar({ padre: `users/${sesion.uid}`, coleccion: "cart", filtros: [] });
  if (carrito.length === 0) throw new ErrorFuncion("failed-precondition", "Tu carrito está vacío.");
  if (carrito.some((c) => c.datos.clinicId !== clinicId)) {
    throw new ErrorFuncion(
      "failed-precondition",
      "Tu carrito tiene productos de otra clínica. Vacíalo antes de pagar.",
    );
  }
  if (carrito.length > MAX_ITEMS) {
    throw new ErrorFuncion("invalid-argument", `Tu carrito no puede tener más de ${MAX_ITEMS} productos.`);
  }
  const pedidas = new Map<string, number>();
  for (const c of carrito) {
    const n = c.datos.cantidad;
    if (typeof n !== "number" || !Number.isInteger(n) || n < 1 || n > MAX_CANTIDAD) {
      throw new ErrorFuncion("invalid-argument", "Revisa las cantidades de tu carrito.");
    }
    pedidas.set(c.id, n);
  }

  const ahora = deps.ahora();
  const pendientes = await deps.db.consultar({
    coleccion: "orders",
    filtros: [
      { campo: "ownerUid", op: "EQUAL", valor: sesion.uid },
      { campo: "estado", op: "EQUAL", valor: "pendiente_pago" },
    ],
  });
  const contacto = {
    correo: sesion.email,
    nombre: nombreVisible(sesion.perfil),
    telefono: entrega.telefono,
  };

  return await conReintentos(async () => {
    // Productos frescos en cada intento.
    const productos = new Map<string, DocumentoLeido>();
    for (const productId of pedidas.keys()) {
      const p = await deps.db.leer(`clinics/${clinicId}/products/${productId}`);
      if (p) productos.set(productId, p);
    }

    // Pedidos pendientes de esta clínica: uno idéntico y vigente se
    // reutiliza; los demás se reemplazan (expiran y liberan su reserva).
    const deEstaClinica = pendientes.filter((p) => p.datos.clinicId === clinicId);
    const itemsActuales: ItemPedido[] = [...pedidas].map(([productId, cantidad]) => ({
      productId,
      nombre: texto(productos.get(productId)?.datos.nombre),
      precio: entero(productos.get(productId)?.datos.precio),
      cantidad,
    }));
    const vigente = deEstaClinica.find((p) =>
      p.datos.expiraEn instanceof Date &&
      p.datos.expiraEn.getTime() > ahora.getTime() + MINUTO_MS &&
      pasarelaDelPedido(p.datos.pasarela) === deps.pasarela.nombre &&
      mismoPedido(p.datos, itemsActuales, entrega)
    );
    if (vigente) {
      return {
        ...await checkoutDe(deps, vigente.id, entero(vigente.datos.total), vigente.datos.expiraEn as Date, contacto),
        reutilizado: true,
      };
    }
    const reemplazados: DocumentoLeido[] = [];
    for (const p of deEstaClinica) {
      const fresco = await deps.db.leer(p.ruta);
      if (fresco?.datos.estado === "pendiente_pago") reemplazados.push(fresco);
    }
    if (pendientes.length - reemplazados.length >= MAX_PENDIENTES) {
      throw new ErrorFuncion(
        "resource-exhausted",
        `Tienes ${MAX_PENDIENTES} pagos pendientes. Termínalos o espera ${MINUTOS_RESERVA} minutos.`,
      );
    }
    // Lo que liberan los pedidos reemplazados, por producto.
    const liberado = new Map<string, number>();
    for (const r of reemplazados) {
      for (const [id, n] of cantidades(itemsDe(r.datos))) liberado.set(id, (liberado.get(id) ?? 0) + n);
    }

    // Validar productos y stock (todos los problemas juntos).
    const problemas: string[] = [];
    const items: ItemPedido[] = [];
    for (const [productId, cantidad] of pedidas) {
      const p = productos.get(productId);
      const nombre = texto(p?.datos.nombre) || "Un producto";
      if (!p || p.datos.clinicId !== clinicId || p.datos.estado === "inactivo") {
        problemas.push(`${nombre} ya no está disponible`);
        continue;
      }
      const precio = p.datos.precio;
      if (typeof precio !== "number" || !Number.isSafeInteger(precio) || precio <= 0) {
        problemas.push(`${nombre} ya no está disponible`);
        continue;
      }
      const reservado = Math.max(0, entero(p.datos.stockReservado) - (liberado.get(productId) ?? 0));
      const disponibles = Math.max(0, entero(p.datos.stock) - reservado);
      if (cantidad > disponibles) {
        problemas.push(mensajeStock(nombre, disponibles));
        continue;
      }
      items.push({ productId, nombre, precio, cantidad });
    }
    if (problemas.length > 0) throw new ErrorFuncion("failed-precondition", problemas.join("\n"));

    const total = calcularTotal(items);
    const orderId = deps.nuevoId();
    const expiraEn = new Date(ahora.getTime() + MINUTOS_RESERVA * MINUTO_MS);

    // Stock: + lo pedido, − lo que liberan los reemplazados. Una escritura
    // por producto, con precondición.
    const tocados = new Set([...pedidas.keys(), ...liberado.keys()]);
    const escriturasProductos: Escritura[] = [];
    for (const productId of tocados) {
      const p = productos.get(productId) ?? await deps.db.leer(`clinics/${clinicId}/products/${productId}`);
      if (!p) continue;
      const nuevo = Math.max(
        0,
        entero(p.datos.stockReservado) + (pedidas.get(productId) ?? 0) - (liberado.get(productId) ?? 0),
      );
      escriturasProductos.push(
        actualizarCampos(deps.db.proyecto, p.ruta, { stockReservado: nuevo, updatedAt: HORA_SERVIDOR }, {
          updateTime: p.updateTime,
        }),
      );
    }

    const resultado = await deps.db.commit([
      crearDocumento(deps.db.proyecto, `orders/${orderId}`, {
        ownerUid: sesion.uid,
        ownerNombre: nombreVisible(sesion.perfil),
        clinicId,
        clinicNombre: texto(clinica.datos.nombre),
        clinicOwnerUid: texto(clinica.datos.ownerUid),
        items: items.map((i) => ({ ...i })),
        total,
        entrega: { ...entrega },
        estado: "pendiente_pago",
        pasarela: deps.pasarela.nombre,
        referenciaPago: `${PREFIJO_REFERENCIA}${orderId}`,
        expiraEn,
        createdAt: HORA_SERVIDOR,
        updatedAt: HORA_SERVIDOR,
      }),
      ...reemplazados.map((r) => escrituraPedido(deps.db, r, { estado: "expirado" })),
      ...escriturasProductos,
    ]);
    if (resultado === "conflicto") return "conflicto";
    return { ...await checkoutDe(deps, orderId, total, expiraEn, contacto), reutilizado: false };
  });
}

// ---------------------------------------------------------------------------
// webhook-wompi
// ---------------------------------------------------------------------------

export interface ResultadoWebhook {
  /** Qué se hizo; siempre se responde 200 a un evento con firma válida. */
  resultado:
    | "pagado"
    | "pago_rechazado"
    | "pago_tardio"
    | "duplicado"
    | "ignorado";
  orderId?: string;
  motivo?: string;
}

const RECHAZOS = new Set(["DECLINED", "VOIDED", "ERROR"]);

/**
 * Evento de Wompi (`transaction.updated`). Rechaza (401) un evento sin
 * firma válida. Es idempotente: el mismo evento dos veces no descuenta el
 * stock dos veces. Verifica referencia, moneda y monto contra el pedido.
 */
export async function procesarEventoWompi(
  deps: DependenciasPedidos & { secretoEventos: string },
  cuerpo: unknown,
  encabezadoChecksum?: string | null,
): Promise<ResultadoWebhook> {
  const evento = await verificarEvento(cuerpo, deps.secretoEventos, encabezadoChecksum);
  if (!evento) throw new ErrorFuncion("unauthenticated", "Firma del evento inválida.");
  return await aplicarEvento(deps, evento);
}

async function aplicarEvento(deps: DependenciasPedidos, evento: EventoWompi): Promise<ResultadoWebhook> {
  if (evento.event !== "transaction.updated") return { resultado: "ignorado", motivo: "evento" };
  const tx = evento.data.transaction;
  if (!tx || typeof tx !== "object") return { resultado: "ignorado", motivo: "sin transacción" };
  const orderId = pedidoDeReferencia(tx.reference);
  if (!orderId) return { resultado: "ignorado", motivo: "referencia ajena" };
  const estadoTx = texto(tx.status);
  if (estadoTx !== "APPROVED" && !RECHAZOS.has(estadoTx)) {
    return { resultado: "ignorado", orderId, motivo: `estado ${estadoTx}` };
  }

  return await conReintentos<ResultadoWebhook>(async () => {
    const pedido = await deps.db.leer(`orders/${orderId}`);
    if (!pedido) return { resultado: "ignorado", orderId, motivo: "pedido inexistente" };
    const d = pedido.datos;
    if (
      d.referenciaPago !== tx.reference ||
      tx.currency !== MONEDA ||
      tx.amount_in_cents !== entero(d.total) * 100
    ) {
      deps.log?.(
        `Evento Wompi ${tx.id} no coincide con el pedido ${orderId}: ` +
          `${tx.reference} ${tx.amount_in_cents} ${tx.currency} vs total ${d.total}`,
      );
      return { resultado: "ignorado", orderId, motivo: "monto o referencia no coinciden" };
    }
    return await registrarPago(deps, pedido, orderId, {
      aprobado: estadoTx === "APPROVED",
      transaccionId: texto(tx.id),
      estadoPasarela: estadoTx,
      // Campos de siempre del webhook (los leen la app y las pruebas).
      camposPasarela: { wompiTransactionId: texto(tx.id), wompiEstado: estadoTx },
    });
  });
}

/** Resultado de un pago que informa una pasarela (real o simulada). */
interface ResultadoPago {
  aprobado: boolean;
  transaccionId: string;
  /** Estado tal como lo reporta la pasarela (`APPROVED`, `DECLINED`…). */
  estadoPasarela: string;
  /** Campos propios de la pasarela que se guardan en el pedido. */
  camposPasarela?: Record<string, ValorCampo>;
}

/**
 * Registra el resultado del pago de [pedido], igual para toda pasarela:
 * aprobado → `pagado`, descuenta el stock (y la reserva), pasa a `agotado`
 * lo que llega a 0 y vacía del carrito lo comprado; rechazado →
 * `pago_rechazado` y libera la reserva. Un pedido que ya no está pendiente
 * no se toca (idempotente); si se aprueba un pago de un pedido expirado o
 * rechazado se marca `pagoTardio` para el reembolso.
 */
async function registrarPago(
  deps: DependenciasPedidos,
  pedido: DocumentoLeido,
  orderId: string,
  pago: ResultadoPago,
): Promise<ResultadoWebhook | "conflicto"> {
  const d = pedido.datos;
  const campos = {
    transaccionId: pago.transaccionId,
    estadoPasarela: pago.estadoPasarela,
    ...pago.camposPasarela,
  };

  if (d.estado !== "pendiente_pago") {
    // Pago aprobado de un pedido que ya expiró, fue reemplazado o tuvo un
    // intento rechazado antes (un reintento en el mismo checkout usa la
    // misma referencia): no se revive (son estados finales) ni se
    // descuenta stock; se marca y se avisa para el reembolso.
    if (
      pago.aprobado &&
      (d.estado === "expirado" || d.estado === "pago_rechazado") &&
      d.pagoTardio !== true
    ) {
      const r = await deps.db.commit([escrituraPedido(deps.db, pedido, { pagoTardio: true, ...campos })]);
      if (r === "conflicto") return "conflicto";
      await avisar(deps, avisosPedido(orderId, d, "pago_tardio"));
      return { resultado: "pago_tardio", orderId };
    }
    return { resultado: "duplicado", orderId };
  }

  const porProducto = cantidades(itemsDe(d));
  const clinicId = texto(d.clinicId);
  if (pago.aprobado) {
    const productos = await escriturasDeStock(deps.db, clinicId, porProducto.keys(), (p) => {
      const n = porProducto.get(p.id) ?? 0;
      const stock = Math.max(0, entero(p.datos.stock) - n);
      return {
        stock,
        stockReservado: Math.max(0, entero(p.datos.stockReservado) - n),
        estado: estadoPorStock(p.datos.estado, stock),
      };
    });
    const r = await deps.db.commit([
      escrituraPedido(deps.db, pedido, { estado: "pagado", ...campos }),
      ...productos,
      // Vaciar del carrito lo que se compró.
      ...[...porProducto.keys()].map((id) =>
        borrarDocumento(deps.db.proyecto, `users/${texto(d.ownerUid)}/cart/${id}`)
      ),
    ]);
    if (r === "conflicto") return "conflicto";
    await avisar(deps, avisosPedido(orderId, { ...d, estado: "pagado" }, "pagado"));
    return { resultado: "pagado", orderId };
  }

  const r = await deps.db.commit([
    escrituraPedido(deps.db, pedido, { estado: "pago_rechazado", ...campos }),
    ...await liberarReserva(deps.db, d),
  ]);
  if (r === "conflicto") return "conflicto";
  await avisar(deps, avisosPedido(orderId, { ...d, estado: "pago_rechazado" }, "pago_rechazado"));
  return { resultado: "pago_rechazado", orderId };
}

// ---------------------------------------------------------------------------
// pagar-pedido-simulado
// ---------------------------------------------------------------------------

/** Resultados que puede pedir el dueño en la pantalla de pago de prueba. */
export const RESULTADOS_SIMULADOS = ["aprobado", "rechazado"] as const;

/**
 * Pago de PRUEBA (sin dinero real) mientras no haya pasarela. El dueño del
 * pedido elige "aprobado" o "rechazado" y se registra exactamente como lo
 * haría el webhook de una pasarela real ([registrarPago]).
 *
 * Solo funciona con la pasarela simulada activa, para pedidos creados con
 * ella, del mismo dueño, `pendiente_pago` y sin vencer.
 * Cuerpo: `{orderId, resultado: "aprobado" | "rechazado"}`.
 */
export async function pagarPedidoSimulado(
  deps: DependenciasPagoSimulado,
  autorizacion: string | null,
  cuerpo: unknown,
): Promise<ResultadoWebhook> {
  if (deps.pasarelaActiva !== "simulada") {
    throw new ErrorFuncion("failed-precondition", "Los pagos de prueba están desactivados.");
  }
  const datos = (typeof cuerpo === "object" && cuerpo !== null ? cuerpo : {}) as Cuerpo;
  const sesion = await usuarioActivo(deps, autorizacion);
  const orderId = idDe(datos, "orderId");
  const resultado = datos.resultado;
  if (!(RESULTADOS_SIMULADOS as readonly unknown[]).includes(resultado)) {
    throw new ErrorFuncion("invalid-argument", "Indica si el pago de prueba se aprueba o se rechaza.");
  }

  return await conReintentos<ResultadoWebhook>(async () => {
    const pedido = await deps.db.leer(`orders/${orderId}`);
    if (!pedido || pedido.datos.ownerUid !== sesion.uid) {
      throw new ErrorFuncion("not-found", "No encontramos este pedido.");
    }
    const d = pedido.datos;
    if (pasarelaDelPedido(d.pasarela) !== "simulada") {
      throw new ErrorFuncion("failed-precondition", "Este pedido no admite pagos de prueba.");
    }
    if (d.estado === "pagado") return { resultado: "duplicado", orderId };
    if (d.estado !== "pendiente_pago") {
      throw new ErrorFuncion("failed-precondition", "Este pedido ya no se puede pagar.");
    }
    if (!(d.expiraEn instanceof Date) || d.expiraEn.getTime() <= deps.ahora().getTime()) {
      throw new ErrorFuncion(
        "failed-precondition",
        "El tiempo para pagar este pedido terminó. Vuelve a confirmar la compra.",
      );
    }
    const aprobado = resultado === "aprobado";
    return await registrarPago(deps, pedido, orderId, {
      aprobado,
      transaccionId: `${PREFIJO_TRANSACCION_SIMULADA}${orderId}`,
      estadoPasarela: aprobado ? "APPROVED" : "DECLINED",
    });
  });
}

// ---------------------------------------------------------------------------
// actualizar-pedido
// ---------------------------------------------------------------------------

/** Mensaje cuando el pedido ya no permite el cambio pedido. */
function yaNoSePuede(estado: unknown, a: EstadoPedido, entrega: unknown): ErrorFuncion {
  if (a === "listo" && entrega === "domicilio") {
    return new ErrorFuncion("failed-precondition", "Este pedido es a domicilio: márcalo como enviado.");
  }
  if (a === "enviado" && entrega === "recoger") {
    return new ErrorFuncion("failed-precondition", "Este pedido es para recoger: márcalo como listo.");
  }
  if (a === "cancelado") {
    return new ErrorFuncion(
      "failed-precondition",
      "Solo puedes cancelar un pedido pagado o en preparación.",
    );
  }
  const actual = esEstadoPedido(estado) ? ETIQUETA_ESTADO[estado].toLowerCase() : "desconocido";
  return new ErrorFuncion(
    "failed-precondition",
    `Este pedido está ${actual}: no se puede pasar a ${ETIQUETA_ESTADO[a].toLowerCase()}.`,
  );
}

/**
 * La clínica cambia el estado del pedido respetando la máquina de estados;
 * el dueño recibe un push en cada cambio. Cancelar (solo `pagado` o
 * `preparando`, con motivo) devuelve el stock.
 */
export async function actualizarPedido(
  deps: DependenciasPedidos & { verificarToken(token: string): Promise<UsuarioFirebase> },
  autorizacion: string | null,
  cuerpo: unknown,
): Promise<{ ok: true; estado: EstadoPedido }> {
  const datos = (typeof cuerpo === "object" && cuerpo !== null ? cuerpo : {}) as Cuerpo;
  const sesion = await usuarioActivo(deps, autorizacion);
  if (sesion.perfil.role !== "clinica" || typeof sesion.perfil.clinicId !== "string") {
    throw new ErrorFuncion("permission-denied", "Solo la clínica puede actualizar pedidos.");
  }
  const clinicId = sesion.perfil.clinicId;
  const orderId = idDe(datos, "orderId");
  const estado = datos.estado;
  if (!esEstadoPedido(estado) || !ESTADOS_DE_LA_CLINICA.includes(estado)) {
    throw new ErrorFuncion("invalid-argument", "Estado no válido.");
  }
  const motivo = typeof datos.motivo === "string" ? datos.motivo.trim() : "";
  if (estado === "cancelado" && motivo.length === 0) {
    throw new ErrorFuncion("invalid-argument", "Indica el motivo de la cancelación.");
  }
  if (motivo.length > MAX_MOTIVO) {
    throw new ErrorFuncion("invalid-argument", `El motivo no puede superar ${MAX_MOTIVO} caracteres.`);
  }

  return await conReintentos(async () => {
    const pedido = await deps.db.leer(`orders/${orderId}`);
    if (!pedido) throw new ErrorFuncion("not-found", "No encontramos el pedido.");
    const d = pedido.datos;
    if (d.clinicId !== clinicId) {
      throw new ErrorFuncion("permission-denied", "Este pedido no es de tu clínica.");
    }
    const entrega = (d.entrega as Datos | undefined)?.tipo;
    if (!puedeTransicionarPedido(d.estado, estado, entrega)) throw yaNoSePuede(d.estado, estado, entrega);

    const extra: Escritura[] = [];
    if (estado === "cancelado") {
      // El stock vuelve (el pedido ya estaba pagado: se había descontado).
      const porProducto = cantidades(itemsDe(d));
      extra.push(...await escriturasDeStock(deps.db, clinicId, porProducto.keys(), (p) => {
        const stock = entero(p.datos.stock) + (porProducto.get(p.id) ?? 0);
        return { stock, estado: estadoPorStock(p.datos.estado, stock) };
      }));
    }
    const r = await deps.db.commit([
      escrituraPedido(deps.db, pedido, {
        estado,
        ...(estado === "cancelado" ? { motivoCancelacion: motivo } : {}),
      }),
      ...extra,
    ]);
    if (r === "conflicto") return "conflicto";
    await avisar(deps, avisosPedido(orderId, { ...d, estado, motivoCancelacion: motivo }, estado));
    return { ok: true as const, estado };
  });
}

// ---------------------------------------------------------------------------
// Tarea programada (cada 10 min)
// ---------------------------------------------------------------------------

/**
 * Pedidos `pendiente_pago` de más de 15 minutos → `expirado`, y liberan su
 * reserva. Si otra petición cambió el pedido en medio (p. ej. llegó el
 * pago), se deja para la próxima vez.
 */
export async function expirarPedidos(deps: DependenciasPedidos, limite = 200): Promise<{ expirados: number }> {
  // expiraEn = creación + 15 min (lo pone crear-pedido con la misma hora
  // que firma el checkout de Wompi).
  const vencidos = await deps.db.consultar({
    coleccion: "orders",
    filtros: [
      { campo: "estado", op: "EQUAL", valor: "pendiente_pago" },
      { campo: "expiraEn", op: "LESS_THAN", valor: deps.ahora() },
    ],
    ordenarPor: "expiraEn",
    limite,
  });
  let expirados = 0;
  for (const pedido of vencidos) {
    const escrituras = [
      escrituraPedido(deps.db, pedido, { estado: "expirado" }),
      ...await liberarReserva(deps.db, pedido.datos),
    ];
    if (await deps.db.commit(escrituras) === "ok") expirados++;
  }
  return { expirados };
}

// ---------------------------------------------------------------------------
// Notificaciones (RF-13)
// ---------------------------------------------------------------------------

type CambioAvisado = EstadoPedido | "pago_tardio";

/**
 * Avisos de un cambio de pedido. Ids fijos (`pedido_{id}_{cambio}`): si un
 * evento o una petición se repite, no se duplica la notificación.
 */
export function avisosPedido(orderId: string, pedido: Datos, cambio: CambioAvisado): Aviso[] {
  const dueno = texto(pedido.ownerUid);
  const clinica = texto(pedido.clinicNombre) || "La clínica";
  const aviso = (titulo: string, cuerpo: string, prioridadAlta = false): Aviso => ({
    id: `pedido_${orderId}_${cambio}`,
    uid: dueno,
    tipo: "pedido",
    titulo,
    cuerpo,
    referenciaId: orderId,
    prioridadAlta,
  });
  switch (cambio) {
    case "pagado": {
      const unidades = itemsDe(pedido).reduce((t, i) => t + i.cantidad, 0);
      return [
        aviso("Pago aprobado", `¡Pedido realizado con éxito! ${clinica} ya recibió tu pedido.`),
        {
          id: `pedido_nuevo_${orderId}`,
          uid: texto(pedido.clinicOwnerUid),
          tipo: "pedido_nuevo",
          titulo: "Nuevo pedido",
          cuerpo: `${texto(pedido.ownerNombre) || "Un cliente"} compró ${unidades} ` +
            `${unidades === 1 ? "producto" : "productos"} (${pesos(entero(pedido.total))}). ` +
            ((pedido.entrega as Datos | undefined)?.tipo === "domicilio" ? "Envío a domicilio." : "Recoge en la clínica."),
          referenciaId: orderId,
        },
      ];
    }
    case "pago_rechazado":
      return [aviso(MENSAJE_PAGO_RECHAZADO, "Tus productos siguen en el carrito. Puedes intentarlo de nuevo.")];
    case "pago_tardio":
      return [aviso(
        "Recibimos un pago de un pedido no activo",
        `Tu pago llegó cuando el pedido ya había expirado o había sido rechazado. ` +
          `${clinica} se comunicará contigo para el reembolso.`,
        true,
      )];
    case "preparando":
      return [aviso("Tu pedido está en preparación", `${clinica} está preparando tu pedido.`)];
    case "listo":
      return [aviso("Tu pedido está listo", `Ya puedes recogerlo en ${clinica}.`)];
    case "enviado":
      return [aviso("Tu pedido va en camino", `${clinica} envió tu pedido.`)];
    case "entregado":
      return [aviso("Pedido entregado", `Gracias por comprar en ${clinica}.`)];
    case "cancelado":
      return [aviso(
        "Tu pedido fue cancelado",
        `Tu pedido fue cancelado: ${texto(pedido.motivoCancelacion)}. ` +
          "La clínica se comunicará contigo para el reembolso",
        true,
      )];
    default:
      return [];
  }
}

/** 45000 → "$45.000". */
export function pesos(valor: number): string {
  return `$${String(valor).replace(/\B(?=(\d{3})+(?!\d))/g, ".")}`;
}
