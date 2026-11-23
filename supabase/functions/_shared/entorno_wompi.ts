// Solo para Deno (Edge Functions). Lee la configuración de Wompi de los
// secretos de Supabase (supabase secrets set ...). Nunca van en la app.
import type { ConfigWompi } from "./pedidos.ts";

/** Ruta del webhook-wompi que muestra "vuelve a la app" al terminar el pago. */
export const RUTA_RETORNO = "/functions/v1/webhook-wompi/retorno";

function secreto(nombre: string): string {
  const valor = Deno.env.get(nombre)?.trim();
  if (!valor) throw new Error(`Falta el secreto ${nombre}`);
  return valor;
}

/**
 * WOMPI_PUBLIC_KEY (pub_test_… en sandbox), WOMPI_INTEGRITY_SECRET,
 * WOMPI_EVENTS_SECRET y, opcional, WOMPI_REDIRECT_URL (por defecto, la ruta
 * de retorno de webhook-wompi en este proyecto de Supabase).
 */
export function configWompi(): ConfigWompi {
  const base = Deno.env.get("SUPABASE_URL")?.replace(/\/+$/, "") ??
    "https://tahnazumbqsupzpusrba.supabase.co";
  return {
    llavePublica: secreto("WOMPI_PUBLIC_KEY"),
    secretoIntegridad: secreto("WOMPI_INTEGRITY_SECRET"),
    secretoEventos: secreto("WOMPI_EVENTS_SECRET"),
    urlRegreso: Deno.env.get("WOMPI_REDIRECT_URL")?.trim() || `${base}${RUTA_RETORNO}`,
  };
}
