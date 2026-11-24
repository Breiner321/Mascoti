// Edge Function generar-carnet (RF-18): carnet de vacunas en PDF. Solo el
// dueño de la mascota. Cuerpo: {petId}. Devuelve {url (firmada, 15 min),
// expiraEnSegundos, path, generadoEn, vacunas}. Va sin verificación JWT de
// Supabase (supabase/config.toml): verifica el token de Firebase.
// Lógica en ../_shared/carnet.ts (pruebas en functions/test/carnet.test.ts).
import { PDFDocument, rgb, StandardFonts } from "npm:pdf-lib@1.17.1";

import { BUCKET_DOCUMENTOS, generarCarnet, type LibPdf } from "../_shared/carnet.ts";
import { leerCuentaServicio } from "../_shared/cuenta_servicio.ts";
import { ErrorFuncion } from "../_shared/errores.ts";
import { clienteFirestore, verificarTokenFirebase } from "../_shared/google.ts";
import { firmarLectura, subirArchivo } from "../_shared/storage_admin.ts";

const PROYECTO_FIREBASE = Deno.env.get("FIREBASE_PROJECT_ID") ?? "mascoti-b27cf";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function responder(estado: number, cuerpo: unknown): Response {
  return new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { ...CORS, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

const pdf = { PDFDocument, StandardFonts, rgb } as unknown as LibPdf;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") {
    return responder(405, { error: { code: "invalid-argument", message: "Usa POST" } });
  }
  try {
    const cuerpo = await req.json().catch(() => null);
    const cuenta = leerCuentaServicio(Deno.env.get("FIREBASE_SERVICE_ACCOUNT"));
    const resultado = await generarCarnet(
      {
        verificarToken: (token) => verificarTokenFirebase(token, PROYECTO_FIREBASE),
        db: clienteFirestore(cuenta),
        pdf,
        subir: (path, bytes) => subirArchivo(BUCKET_DOCUMENTOS, path, bytes, "application/pdf"),
        firmarLectura: (path, segundos) => firmarLectura(BUCKET_DOCUMENTOS, path, segundos),
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
      error: { code: "internal", message: "No pudimos generar el carnet. Intenta de nuevo." },
    });
  }
});
