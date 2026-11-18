// Edge Function crear-pedido (RF-12). "Confirmar compra": lee el carrito y
// los productos en Firestore, valida stock, calcula el total, crea el pedido
// 'pendiente_pago' apartando el stock 15 min y devuelve el Web Checkout de
// Wompi (sandbox) firmado. Cuerpo: {clinicId, entrega: {tipo, direccion?, telefono}}.
// Lógica en ../_shared/pedidos.ts (pruebas en functions/test/).
import { leerCuentaServicio } from "../_shared/cuenta_servicio.ts";
import { configWompi } from "../_shared/entorno_wompi.ts";
import { ErrorFuncion } from "../_shared/errores.ts";
import { nuevoIdFirestore } from "../_shared/firestore.ts";
import { clienteFirestore, verificarTokenFirebase } from "../_shared/google.ts";
import { crearPedido } from "../_shared/pedidos.ts";

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
    const resultado = await crearPedido(
      {
        db: clienteFirestore(cuenta),
        verificarToken: (token) => verificarTokenFirebase(token, PROYECTO_FIREBASE),
        ahora: () => new Date(),
        nuevoId: () => nuevoIdFirestore((n) => crypto.getRandomValues(new Uint8Array(n))),
        wompi: configWompi(),
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
      error: { code: "internal", message: "No se pudo iniciar el pago. Intenta de nuevo." },
    });
  }
});
