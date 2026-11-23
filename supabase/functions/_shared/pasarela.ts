// Pasarela de pago de la tienda (RF-12, Cambio 5). Sin dependencias de Deno:
// se prueba con Node en functions/test/.
//
// Por ahora la app usa pagos SIMULADOS (sin dinero real): `crear-pedido` no
// devuelve un enlace de pago y el dueño confirma o rechaza el pago de prueba
// con `pagar-pedido-simulado`. La integración con Wompi queda lista: para
// activarla basta `supabase secrets set PASARELA_PAGO=wompi` más sus llaves
// (ver docs/configuracion-inicial.md). Otra pasarela futura implementa
// [Pasarela] y se agrega a [NOMBRES_PASARELA].
import { centavos, firmaIntegridad, MONEDA, urlCheckout } from "./wompi.ts";

export type NombrePasarela = "simulada" | "wompi";

export const NOMBRES_PASARELA: readonly NombrePasarela[] = ["simulada", "wompi"];

/** Pasarela por defecto mientras no haya una real. */
export const PASARELA_POR_DEFECTO: NombrePasarela = "simulada";

/** Prefijo del id de transacción de un pago simulado. */
export const PREFIJO_TRANSACCION_SIMULADA = "SIM-";

export interface ConfigWompi {
  llavePublica: string;
  secretoIntegridad: string;
  secretoEventos: string;
  /**
   * Base de la URL de regreso del checkout; se le agrega `/{orderId}` (p. ej.
   * `https://<proyecto>.supabase.co/functions/v1/webhook-wompi/retorno`).
   */
  urlRegreso: string;
}

/** Datos del pedido recién creado (o reutilizado) para iniciar el pago. */
export interface DatosInicioPago {
  orderId: string;
  referencia: string;
  /** En pesos, calculado por el servidor. */
  total: number;
  expiraEn: Date;
  contacto: { correo?: string; nombre?: string; telefono?: string };
}

/**
 * Cómo sigue el pago en la app. Con `checkoutUrl` la app abre la página de
 * la pasarela; sin ella (pago simulado) muestra su pantalla de pago de prueba.
 */
export interface InicioPago {
  checkoutUrl: string | null;
  redirectUrl: string | null;
}

export interface Pasarela {
  readonly nombre: NombrePasarela;
  iniciarPago(datos: DatosInicioPago): Promise<InicioPago>;
}

/** Pagos de prueba: no hay página externa ni dinero real. */
export const pasarelaSimulada: Pasarela = {
  nombre: "simulada",
  iniciarPago: () => Promise.resolve({ checkoutUrl: null, redirectUrl: null }),
};

/** Web Checkout de Wompi firmado con el secreto de integridad. */
export function pasarelaWompi(
  config: Pick<ConfigWompi, "llavePublica" | "secretoIntegridad" | "urlRegreso">,
): Pasarela {
  return {
    nombre: "wompi",
    async iniciarPago(d) {
      const montoEnCentavos = centavos(d.total);
      const expiracion = d.expiraEn.toISOString();
      const firma = await firmaIntegridad({
        referencia: d.referencia,
        montoEnCentavos,
        moneda: MONEDA,
        expiracion,
        secretoIntegridad: config.secretoIntegridad,
      });
      const redirectUrl = `${config.urlRegreso.replace(/\/+$/, "")}/${d.orderId}`;
      return {
        checkoutUrl: urlCheckout({
          llavePublica: config.llavePublica,
          referencia: d.referencia,
          montoEnCentavos,
          firma,
          redirectUrl,
          expiracion,
          ...d.contacto,
        }),
        redirectUrl,
      };
    },
  };
}

/**
 * Lee el secreto `PASARELA_PAGO`. Vacío → [PASARELA_POR_DEFECTO]; un valor
 * desconocido es un error de configuración (mejor fallar que cobrar mal).
 */
export function nombrePasarela(valor: string | undefined | null): NombrePasarela {
  const v = valor?.trim().toLowerCase() ?? "";
  if (v === "") return PASARELA_POR_DEFECTO;
  if ((NOMBRES_PASARELA as readonly string[]).includes(v)) return v as NombrePasarela;
  throw new Error(`PASARELA_PAGO desconocida: ${valor}`);
}

/** Pasarela con la que se creó un pedido (los anteriores a este campo son de Wompi). */
export function pasarelaDelPedido(valor: unknown): NombrePasarela {
  return valor === "simulada" ? "simulada" : "wompi";
}
