// Solo para Deno (Edge Functions). Contador de intentos en el Postgres de
// Supabase (supabase/migrations/*_limite_vinculacion.sql): un incremento
// atómico en SQL es más simple y seguro que hacerlo con transacciones REST de
// Firestore. No guarda datos de la app, solo marcas de tiempo por clínica.
import type { ResultadoIntento } from "./vinculacion.ts";

export async function registrarIntentoVinculacion(
  clinicId: string,
  maximo: number,
  ventanaMinutos: number,
): Promise<ResultadoIntento> {
  const url = Deno.env.get("SUPABASE_URL");
  const llave = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !llave) throw new Error("Faltan SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY");

  const respuesta = await fetch(`${url}/rest/v1/rpc/registrar_intento_vinculacion`, {
    method: "POST",
    headers: {
      "apikey": llave,
      "Authorization": `Bearer ${llave}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_clinic_id: clinicId, p_maximo: maximo, p_ventana_minutos: ventanaMinutos }),
  });
  if (!respuesta.ok) throw new Error(`Límite de intentos ${respuesta.status}: ${await respuesta.text()}`);
  const filas = await respuesta.json() as { permitido: boolean; reintentar_en_segundos: number }[];
  const fila = filas[0] ?? { permitido: false, reintentar_en_segundos: 60 };
  return { permitido: fila.permitido, reintentarEnSegundos: fila.reintentar_en_segundos };
}
