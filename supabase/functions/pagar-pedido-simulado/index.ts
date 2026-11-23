// Edge Function pagar-pedido-simulado (RF-12, pagos de prueba). Mientras no
// haya pasarela real (PASARELA_PAGO vacío o "simulada"), el dueño confirma o
// rechaza el pago de su pedido 'pendiente_pago' desde la pantalla de pago de
// prueba de la app; se registra igual que lo haría el webhook de una
// pasarela (stock, carrito y avisos). No mueve dinero. Con
// PASARELA_PAGO=wompi responde "Los pagos de prueba están desactivados".
// Cuerpo: {orderId, resultado: "aprobado" | "rechazado"}.
// Lógica en ../_shared/pedidos.ts (pruebas en functions/test/).
import { leerCuentaServicio } from "../_shared/cuenta_servicio.ts";
import { pasarelaActiva } from "../_shared/entorno_pago.ts";
import { ErrorFuncion } from "../_shared/errores.ts";
import {
  clienteFirestore,
  dependenciasNotificaciones,
  verificarTokenFirebase,
} from "../_shared/google.ts";
import { enviarNotificacion } from "../_shared/notificaciones.ts";
import { pagarPedidoSimulado } from "../_shared/pedidos.ts";

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
    const resultado = await pagarPedidoSimulado(
      {
        db: clienteFirestore(cuenta),
        verificarToken: (token) => verificarTokenFirebase(token, PROYECTO_FIREBASE),
        ahora: () => new Date(),
        pasarelaActiva: pasarelaActiva(),
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
      error: { code: "internal", message: "No se pudo registrar el pago. Intenta de nuevo." },
    });
  }
});
