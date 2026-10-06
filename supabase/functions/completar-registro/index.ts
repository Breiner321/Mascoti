// Edge Function completar-registro (RF-01). Reemplaza a la Cloud Function
// completarRegistro: el plan gratuito de Firebase no permite desplegar
// Cloud Functions. La lógica está en ../_shared/registro.ts (con pruebas).
import { ErrorRegistro } from "../_shared/errores.ts";
import { nuevoIdFirestore } from "../_shared/firestore.ts";
import {
  commitFirestore,
  habilitarEnSupabase,
  leerCuentaServicio,
  verificarTokenFirebase,
} from "../_shared/google.ts";
import { completarRegistro } from "../_shared/registro.ts";

/** Proyecto de Firebase cuyos usuarios se aceptan (mismo de firebase_options.dart). */
const PROYECTO_FIREBASE = Deno.env.get("FIREBASE_PROJECT_ID") ?? "mascoti-b27cf";

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
    // La cuenta de servicio solo se lee cuando hay que escribir: así una
    // petición sin sesión responde 401 aunque falte el secreto.
    const cuenta = () => leerCuentaServicio(Deno.env.get("FIREBASE_SERVICE_ACCOUNT"));
    const cuerpo = await req.json().catch(() => null);

    const resultado = await completarRegistro(
      {
        proyecto: PROYECTO_FIREBASE,
        verificarToken: (token) => verificarTokenFirebase(token, PROYECTO_FIREBASE),
        commit: (escrituras) => commitFirestore(cuenta(), escrituras),
        habilitarEnSupabase: (uid) => habilitarEnSupabase(cuenta(), uid),
        nuevoId: () => nuevoIdFirestore((n) => crypto.getRandomValues(new Uint8Array(n))),
        log: console.warn,
      },
      req.headers.get("Authorization"),
      cuerpo,
    );
    return responder(200, resultado);
  } catch (e) {
    if (e instanceof ErrorRegistro) {
      return responder(e.estadoHttp, { error: { code: e.codigo, message: e.message } });
    }
    console.error(e);
    return responder(500, {
      error: { code: "internal", message: "No se pudo completar el registro" },
    });
  }
});
