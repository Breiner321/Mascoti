// Edge Function adjuntos-historial (semana 3, RF-08). Entrega enlaces
// firmados para subir (clínica autorizada) o ver (dueño y clínicas
// autorizadas) los adjuntos del historial médico. Lógica en
// ../_shared/adjuntos.ts.
import { gestionarAdjunto } from "../_shared/adjuntos.ts";
import { leerCuentaServicio } from "../_shared/cuenta_servicio.ts";
import { ErrorFuncion } from "../_shared/errores.ts";
import { nuevoIdFirestore } from "../_shared/firestore.ts";
import { leerDocumentoFirestore, verificarTokenFirebase } from "../_shared/google.ts";
import { firmarLectura, firmarSubida } from "../_shared/storage_admin.ts";

const PROYECTO_FIREBASE = Deno.env.get("FIREBASE_PROJECT_ID") ?? "mascoti-b27cf";
const BUCKET = "registros";

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
    const cuenta = () => leerCuentaServicio(Deno.env.get("FIREBASE_SERVICE_ACCOUNT"));
    const cuerpo = await req.json().catch(() => null);
    const resultado = await gestionarAdjunto(
      {
        verificarToken: (token) => verificarTokenFirebase(token, PROYECTO_FIREBASE),
        leer: (ruta) => leerDocumentoFirestore(cuenta(), ruta),
        firmarSubida: (path) => firmarSubida(BUCKET, path),
        firmarLectura: (path, segundos) => firmarLectura(BUCKET, path, segundos),
        nuevoId: () => nuevoIdFirestore((n) => crypto.getRandomValues(new Uint8Array(n))),
        ahora: () => new Date(),
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
      error: { code: "internal", message: "No se pudo procesar el archivo. Intenta de nuevo." },
    });
  }
});
