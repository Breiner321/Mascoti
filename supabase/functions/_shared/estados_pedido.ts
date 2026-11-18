/**
 * Máquina de estados de un pedido (RF-12). Igual a OrderStatus en
 * lib/core/domain/order.dart: las dos pasan los casos de
 * test/fixtures/estados_pedido.json (si cambias una, cambia la otra).
 *
 * ```
 * pendiente_pago → pagado | pago_rechazado | expirado        (webhook / tarea)
 * pagado         → preparando | cancelado                    (clínica)
 * preparando     → listo (recoger) | enviado (domicilio) | cancelado
 * listo | enviado → entregado
 * ```
 */
export const ESTADOS_PEDIDO = [
  "pendiente_pago",
  "pagado",
  "pago_rechazado",
  "expirado",
  "preparando",
  "listo",
  "enviado",
  "entregado",
  "cancelado",
] as const;

export type EstadoPedido = typeof ESTADOS_PEDIDO[number];

export const TIPOS_ENTREGA = ["recoger", "domicilio"] as const;
export type TipoEntrega = typeof TIPOS_ENTREGA[number];

const TRANSICIONES: Record<EstadoPedido, readonly EstadoPedido[]> = {
  pendiente_pago: ["pagado", "pago_rechazado", "expirado"],
  pagado: ["preparando", "cancelado"],
  pago_rechazado: [],
  expirado: [],
  preparando: ["listo", "enviado", "cancelado"],
  listo: ["entregado"],
  enviado: ["entregado"],
  entregado: [],
  cancelado: [],
};

/** Estados que solo pone la clínica (con `actualizar-pedido`). */
export const ESTADOS_DE_LA_CLINICA: readonly EstadoPedido[] = [
  "preparando",
  "listo",
  "enviado",
  "entregado",
  "cancelado",
];

/** Pedidos que la clínica ve (ya pagados); los demás son del dueño. */
export const ESTADOS_VISIBLES_CLINICA: readonly EstadoPedido[] = [
  "pagado",
  "preparando",
  "listo",
  "enviado",
  "entregado",
  "cancelado",
];

export function esEstadoPedido(valor: unknown): valor is EstadoPedido {
  return typeof valor === "string" && (ESTADOS_PEDIDO as readonly string[]).includes(valor);
}

export function esTipoEntrega(valor: unknown): valor is TipoEntrega {
  return typeof valor === "string" && (TIPOS_ENTREGA as readonly string[]).includes(valor);
}

/**
 * true si un pedido en [de] puede pasar a [a]. `listo` solo aplica a
 * pedidos para recoger y `enviado` solo a domicilios.
 */
export function puedeTransicionarPedido(de: unknown, a: EstadoPedido, entrega: unknown): boolean {
  if (!esEstadoPedido(de) || !esTipoEntrega(entrega)) return false;
  if (!TRANSICIONES[de].includes(a)) return false;
  // `listo` solo existe para recoger y `enviado` solo para domicilio (como
  // origen y como destino).
  const encaja = (e: EstadoPedido) =>
    (e !== "listo" || entrega === "recoger") && (e !== "enviado" || entrega === "domicilio");
  return encaja(de) && encaja(a);
}

/** Estados en los que el pedido ya no cambia. */
export function esFinalPedido(estado: EstadoPedido): boolean {
  return TRANSICIONES[estado].length === 0;
}

/** Texto del estado para notificaciones (igual a OrderStatus.label). */
export const ETIQUETA_ESTADO: Record<EstadoPedido, string> = {
  pendiente_pago: "Pendiente de pago",
  pagado: "Pagado",
  pago_rechazado: "Pago rechazado",
  expirado: "Expirado",
  preparando: "En preparación",
  listo: "Listo para recoger",
  enviado: "Enviado",
  entregado: "Entregado",
  cancelado: "Cancelado",
};
