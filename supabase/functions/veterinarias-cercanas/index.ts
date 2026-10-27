// Edge Function veterinarias-cercanas (Cambio 4). Veterinarias de
// OpenStreetMap (Overpass) del área visible del mapa: las "no aliadas".
// Cuerpo: {sur, oeste, norte, este}. La lógica está en
// ../_shared/veterinarias_osm.ts (con pruebas en functions/test/).
import { ErrorFuncion } from "../_shared/errores.ts";
import { verificarTokenFirebase } from "../_shared/google.ts";
import {
  consultarOverpass,
  consultarPhoton,
  guardarCache,
  leerCache,
  marcarPendientes,
} from "../_shared/overpass.ts";
import { rpc } from "../_shared/supabase_rest.ts";
import {
  MAX_CONSULTAS,
  MENSAJE_NO_DISPONIBLE,
  SEGUNDOS_OVERPASS_MAPA,
  VENTANA_MINUTOS,
  veterinariasEnArea,
} from "../_shared/veterinarias_osm.ts";

const PROYECTO_FIREBASE = Deno.env.get("FIREBASE_PROJECT_ID") ?? "mascoti-b27cf";

/** Lo que puede esperar a Overpass (la app espera 65 s en total). */
// Deja ~10 s para el respaldo con Photon si Overpass falla.
const PLAZO_OVERPASS_MS = (SEGUNDOS_OVERPASS_MAPA - 5) * 1000;

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
        leerCache,
        guardarCache,
        marcarPendientes,
        consultarOverpass: (consulta) => consultarOverpass(consulta, PLAZO_OVERPASS_MS),
        consultarPhoton,
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
      error: { code: "internal", message: MENSAJE_NO_DISPONIBLE },
    });
  }
});
