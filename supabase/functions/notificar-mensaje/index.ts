// Edge Function notificar-mensaje (RF-15). La app la llama después de enviar
// un mensaje del chat; si falla, el mensaje igual quedó enviado. Cuerpo:
// {chatId, messageId}. Lógica en ../_shared/mensajes.ts (pruebas en
// functions/test/mensajes.test.ts).
import { leerCuentaServicio } from "../_shared/cuenta_servicio.ts";
import { ErrorFuncion } from "../_shared/errores.ts";
import { dependenciasNotificaciones, verificarTokenFirebase } from "../_shared/google.ts";
import { notificarMensaje } from "../_shared/mensajes.ts";

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
    const cuenta = leerCuentaServicio(Deno.env.get("FIREBASE_SERVICE_ACCOUNT"));
    const resultado = await notificarMensaje(
      {
        ...dependenciasNotificaciones(cuenta),
        verificarToken: (token) => verificarTokenFirebase(token, PROYECTO_FIREBASE),
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
      error: { code: "internal", message: "No se pudo enviar la notificación." },
    });
  }
});
