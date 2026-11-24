// Edge Function placa-publica (RF-17). La llama la página pública de la
// placa QR (Firebase Hosting, /q/{qrId}) SIN sesión: por eso va sin
// verificación JWT (supabase/config.toml). Solo devuelve lo que el dueño
// eligió mostrar; el teléfono completo solo con {revelar: true} y con límite
// por IP. Devuelve JSON, nunca HTML. Cuerpo: {qrId, revelar?}.
// Lógica en ../_shared/placa.ts (pruebas en functions/test/).
import { leerCuentaServicio } from "../_shared/cuenta_servicio.ts";
import { ErrorFuncion } from "../_shared/errores.ts";
import { clienteFirestore } from "../_shared/google.ts";
import {
  BUCKET_FOTOS,
  consultarPlaca,
  ipDelCliente,
  MAX_REVELAR,
  SEGUNDOS_FOTO,
  VENTANA_REVELAR_MINUTOS,
} from "../_shared/placa.ts";
import { firmarLectura } from "../_shared/storage_admin.ts";
import { rpc } from "../_shared/supabase_rest.ts";

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") {
    return responder(405, { error: { code: "invalid-argument", message: "Usa POST" } });
  }
  try {
    const cuerpo = await req.json().catch(() => null);
    const cuenta = leerCuentaServicio(Deno.env.get("FIREBASE_SERVICE_ACCOUNT"));
    const ficha = await consultarPlaca(
      {
        db: clienteFirestore(cuenta),
        firmarFoto: (path) => firmarLectura(BUCKET_FOTOS, path, SEGUNDOS_FOTO),
        registrarRevelacion: async (ipHash) => {
          const filas = await rpc<{ permitido: boolean; reintentar_en_segundos: number }[]>(
            "registrar_intento_placa",
            { p_ip_hash: ipHash, p_maximo: MAX_REVELAR, p_ventana_minutos: VENTANA_REVELAR_MINUTOS },
          );
          const fila = filas[0] ?? { permitido: false, reintentar_en_segundos: 60 };
          return { permitido: fila.permitido, reintentarEnSegundos: fila.reintentar_en_segundos };
        },
        log: console.warn,
      },
      cuerpo,
      ipDelCliente(req.headers.get("x-forwarded-for")),
    );
    return responder(200, ficha);
  } catch (e) {
    if (e instanceof ErrorFuncion) {
      return responder(e.estadoHttp, { error: { code: e.codigo, message: e.message } });
    }
    console.error(e);
    return responder(500, {
      error: { code: "internal", message: "No pudimos cargar la placa. Intenta de nuevo." },
    });
  }
});
