/**
 * Wompi (pasarela de pagos, RF-12), en modo SANDBOX. Sin dependencias:
 * SHA-256 con `crypto.subtle` (existe en Deno y en Node 22, donde corren
 * las pruebas).
 *
 * Documentación (verificada en nov. 2026):
 * - Web Checkout y firma de integridad:
 *   https://docs.wompi.co/docs/colombia/widget-checkout-web/
 * - Eventos (webhook) y su checksum: https://docs.wompi.co/docs/colombia/eventos/
 * - Datos de prueba: https://docs.wompi.co/docs/colombia/datos-de-prueba-en-sandbox/
 */

export const URL_CHECKOUT = "https://checkout.wompi.co/p/";
export const MONEDA = "COP";

/** Pesos (entero) → centavos para Wompi (`amount_in_cents = pesos × 100`). */
export function centavos(pesos: number): number {
  if (!Number.isSafeInteger(pesos) || pesos <= 0) {
    throw new Error(`Monto inválido: ${pesos}`);
  }
  return pesos * 100;
}

/** SHA-256 en hexadecimal (minúsculas). */
export async function sha256Hex(texto: string): Promise<string> {
  const bytes = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(texto)),
  );
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export interface DatosIntegridad {
  referencia: string;
  montoEnCentavos: number;
  moneda?: string;
  /** ISO 8601 (p. ej. `2026-11-18T15:15:00.000Z`), si el checkout expira. */
  expiracion?: string;
  secretoIntegridad: string;
}

/**
 * Firma de integridad del Web Checkout:
 * SHA-256 de `<Referencia><Monto en centavos><Moneda>[<FechaExpiracion>]<SecretoIntegridad>`.
 */
export function firmaIntegridad(d: DatosIntegridad): Promise<string> {
  return sha256Hex(
    `${d.referencia}${d.montoEnCentavos}${d.moneda ?? MONEDA}${d.expiracion ?? ""}${d.secretoIntegridad}`,
  );
}

export interface DatosCheckout {
  llavePublica: string;
  referencia: string;
  montoEnCentavos: number;
  firma: string;
  redirectUrl: string;
  expiracion?: string;
  correo?: string;
  nombre?: string;
  telefono?: string;
}

/**
 * URL del Web Checkout (GET con los mismos campos del formulario de la
 * documentación). Al terminar, Wompi redirige a `redirect-url?id=<transacción>`
 * solo como aviso: el estado real llega por el webhook.
 */
export function urlCheckout(d: DatosCheckout): string {
  const parametros = new URLSearchParams({
    "public-key": d.llavePublica,
    "currency": MONEDA,
    "amount-in-cents": String(d.montoEnCentavos),
    "reference": d.referencia,
    "signature:integrity": d.firma,
    "redirect-url": d.redirectUrl,
  });
  if (d.expiracion) parametros.set("expiration-time", d.expiracion);
  if (d.correo) parametros.set("customer-data:email", d.correo);
  if (d.nombre) parametros.set("customer-data:full-name", d.nombre);
  if (d.telefono) {
    parametros.set("customer-data:phone-number", d.telefono);
  }
  return `${URL_CHECKOUT}?${parametros.toString()}`;
}

// ---------------------------------------------------------------------------
// Eventos (webhook)
// ---------------------------------------------------------------------------

/** Estados finales de una transacción en `transaction.updated`. */
export type EstadoTransaccion = "APPROVED" | "DECLINED" | "VOIDED" | "ERROR" | "PENDING";

export interface TransaccionWompi {
  id: string;
  reference: string;
  amount_in_cents: number;
  currency: string;
  status: string;
  customer_email?: string;
  payment_method_type?: string;
}

export interface EventoWompi {
  event: string;
  data: { transaction?: TransaccionWompi } & Record<string, unknown>;
  environment?: string;
  signature: { properties: string[]; checksum: string };
  timestamp: number;
  sent_at?: string;
}

/** Valor de `data` en la ruta `transaction.id` (como lo indica `properties`). */
function valorEnRuta(datos: unknown, ruta: string): unknown {
  let actual: unknown = datos;
  for (const parte of ruta.split(".")) {
    if (typeof actual !== "object" || actual === null) return undefined;
    actual = (actual as Record<string, unknown>)[parte];
  }
  return actual;
}

/** Compara dos textos sin cortar en la primera diferencia. */
function igualesSeguro(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diferencia = 0;
  for (let i = 0; i < a.length; i++) diferencia |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diferencia === 0;
}

/** Checksum de un evento: valores de `properties` + `timestamp` + secreto de eventos. */
export async function checksumEvento(
  evento: Pick<EventoWompi, "data" | "signature" | "timestamp">,
  secretoEventos: string,
): Promise<string> {
  const valores = evento.signature.properties
    .map((p) => String(valorEnRuta(evento.data, p) ?? ""))
    .join("");
  return sha256Hex(`${valores}${evento.timestamp}${secretoEventos}`);
}

/**
 * Valida la forma del evento y su firma (`signature.checksum` y, si llega,
 * el encabezado `X-Event-Checksum`). Devuelve el evento tipado o null si
 * no es válido: un evento sin firma correcta se ignora.
 */
export async function verificarEvento(
  cuerpo: unknown,
  secretoEventos: string,
  encabezadoChecksum?: string | null,
): Promise<EventoWompi | null> {
  if (!secretoEventos) return null;
  if (typeof cuerpo !== "object" || cuerpo === null) return null;
  const evento = cuerpo as Partial<EventoWompi>;
  const firma = evento.signature;
  if (
    typeof evento.event !== "string" ||
    typeof evento.data !== "object" || evento.data === null ||
    (typeof evento.timestamp !== "number" && typeof evento.timestamp !== "string") ||
    typeof firma !== "object" || firma === null ||
    !Array.isArray(firma.properties) || firma.properties.length === 0 ||
    !firma.properties.every((p) => typeof p === "string") ||
    typeof firma.checksum !== "string"
  ) {
    return null;
  }
  const esperado = await checksumEvento(evento as EventoWompi, secretoEventos);
  if (!igualesSeguro(esperado, firma.checksum.toLowerCase())) return null;
  if (encabezadoChecksum && !igualesSeguro(esperado, encabezadoChecksum.toLowerCase())) return null;
  return evento as EventoWompi;
}
