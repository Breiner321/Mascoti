// Edge Function actualizar-pedido (RF-12). La clínica cambia el estado de un
// pedido respetando la máquina de estados (../_shared/estados_pedido.ts);
// el dueño recibe un push en cada cambio. Cancelar (con motivo) devuelve el
// stock. Cuerpo: {orderId, estado, motivo?}. Lógica en ../_shared/pedidos.ts.
import { leerCuentaServicio } from "../_shared/cuenta_servicio.ts";
import { ErrorFuncion } from "../_shared/errores.ts";
import {
  clienteFirestore,
  dependenciasNotificaciones,
  verificarTokenFirebase,
} from "../_shared/google.ts";
import { enviarNotificacion } from "../_shared/notificaciones.ts";
import { actualizarPedido } from "../_shared/pedidos.ts";

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
    const notificaciones = dependenciasNotificaciones(cuenta);
    const resultado = await actualizarPedido(
      {
        db: clienteFirestore(cuenta),
        verificarToken: (token) => verificarTokenFirebase(token, PROYECTO_FIREBASE),
        ahora: () => new Date(),
        notificar: async (aviso) => {
          await enviarNotificacion(notificaciones, aviso);
        },
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
      error: { code: "internal", message: "No se pudo actualizar el pedido. Intenta de nuevo." },
    });
  }
});
