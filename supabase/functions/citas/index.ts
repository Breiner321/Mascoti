// Edge Function citas (RF-14). Reemplaza a las Callable Functions
// solicitarCita, responderCita, cancelarCita y completarCita (el plan gratuito
// de Firebase no permite Cloud Functions). Cuerpo: {accion, ...}.
// La lógica está en ../_shared/citas.ts (con pruebas en functions/test/).
import { ejecutarAccionCita } from "../_shared/citas.ts";
import { leerCuentaServicio } from "../_shared/cuenta_servicio.ts";
import { ErrorFuncion } from "../_shared/errores.ts";
import { nuevoIdFirestore } from "../_shared/firestore.ts";
import { clienteFirestore, verificarTokenFirebase } from "../_shared/google.ts";

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
    const cuerpo = await req.json().catch(() => null);
    const resultado = await ejecutarAccionCita(
      {
        db: clienteFirestore(leerCuentaServicio(Deno.env.get("FIREBASE_SERVICE_ACCOUNT"))),
        verificarToken: (token) => verificarTokenFirebase(token, PROYECTO_FIREBASE),
        ahora: () => new Date(),
        nuevoId: () => nuevoIdFirestore((n) => crypto.getRandomValues(new Uint8Array(n))),
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
    return responder(500, {
      error: { code: "internal", message: "No se pudo completar la acción. Intenta de nuevo." },
    });
  }
});
