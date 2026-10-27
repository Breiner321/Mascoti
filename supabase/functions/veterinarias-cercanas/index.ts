// Edge Function veterinarias-cercanas (Cambio 4). Veterinarias de
// OpenStreetMap (Overpass) del área visible del mapa: las "no aliadas".
// Cuerpo: {sur, oeste, norte, este}. La lógica está en
// ../_shared/veterinarias_osm.ts (con pruebas en functions/test/).
import { ErrorFuncion } from "../_shared/errores.ts";
import { verificarTokenFirebase } from "../_shared/google.ts";
import { guardar, rpc, seleccionar } from "../_shared/supabase_rest.ts";
import {
  type EntradaCache,
  MAX_CONSULTAS,
  VENTANA_MINUTOS,
  type VeterinariaOsm,
  veterinariasEnArea,
} from "../_shared/veterinarias_osm.ts";

const PROYECTO_FIREBASE = Deno.env.get("FIREBASE_PROJECT_ID") ?? "mascoti-b27cf";

/** Servidores públicos de Overpass: si el principal falla, el alterno. */
const OVERPASS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
];

/** La política de uso de Overpass pide identificar la aplicación. */
const USER_AGENT = "Mascoti/1.0 (app de veterinarias; https://github.com/Breiner321/Mascoti)";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function responder(estado: number, cuerpo: unknown): Response {
  return new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

async function consultarOverpass(consulta: string): Promise<unknown> {
  let ultimo: unknown;
  for (const servidor of OVERPASS) {
    try {
      const respuesta = await fetch(servidor, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded", "User-Agent": USER_AGENT },
        body: new URLSearchParams({ data: consulta }),
        signal: AbortSignal.timeout(30_000),
      });
      if (respuesta.ok) return await respuesta.json();
      ultimo = new Error(`Overpass ${respuesta.status}`);
    } catch (e) {
      ultimo = e;
    }
  }
  throw ultimo;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") {
    return responder(405, { error: { code: "invalid-argument", message: "Usa POST" } });
  }

  try {
    const cuerpo = await req.json().catch(() => null);
    const resultado = await veterinariasEnArea(
      {
        verificarToken: (token) => verificarTokenFirebase(token, PROYECTO_FIREBASE),
        registrarConsulta: async (uid) => {
          const filas = await rpc<{ permitido: boolean; reintentar_en_segundos: number }[]>(
            "registrar_consulta_mapa",
            { p_uid: uid, p_maximo: MAX_CONSULTAS, p_ventana_minutos: VENTANA_MINUTOS },
          );
          const fila = filas[0] ?? { permitido: false, reintentar_en_segundos: 60 };
          return { permitido: fila.permitido, reintentarEnSegundos: fila.reintentar_en_segundos };
        },
        leerCache: async (cuadros) => {
          const filas = await seleccionar<{ cuadro: string; datos: VeterinariaOsm[]; actualizado: string }>(
            "cache_veterinarias_osm",
            "cuadro",
            cuadros,
          );
          return new Map<string, EntradaCache>(
            filas.map((f) => [f.cuadro, { datos: f.datos, actualizado: new Date(f.actualizado) }]),
          );
        },
        guardarCache: (entradas) =>
          guardar(
            "cache_veterinarias_osm",
            [...entradas].map(([cuadro, datos]) => ({
              cuadro,
              datos,
              actualizado: new Date().toISOString(),
            })),
          ),
        consultarOverpass,
        ahora: () => new Date(),
        log: console.warn,
      },
      req.headers.get("Authorization"),
      cuerpo,
    );
    return responder(200, resultado);
  } catch (e) {
    if (e instanceof ErrorFuncion) {
      return responder(e.estadoHttp, { error: { code: e.codigo, message: e.message } });
    }
    console.error(e);
    return responder(503, {
      error: { code: "internal", message: "No se pudieron cargar otras veterinarias." },
    });
  }
});
