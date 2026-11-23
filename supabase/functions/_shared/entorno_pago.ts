// Solo para Deno (Edge Functions). Elige la pasarela de pago con el secreto
// PASARELA_PAGO ("simulada" por defecto, o "wompi"). Ver ./pasarela.ts.
import { configWompi } from "./entorno_wompi.ts";
import { type NombrePasarela, nombrePasarela, type Pasarela, pasarelaSimulada, pasarelaWompi } from "./pasarela.ts";

export function pasarelaActiva(): NombrePasarela {
  return nombrePasarela(Deno.env.get("PASARELA_PAGO"));
}

/** Pasarela activa lista para usar (Wompi lee sus llaves solo si se activa). */
export function pasarelaDesdeEntorno(): Pasarela {
  return pasarelaActiva() === "wompi" ? pasarelaWompi(configWompi()) : pasarelaSimulada;
}
