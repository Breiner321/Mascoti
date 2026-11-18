// Edge Function webhook-wompi (RF-12). La llama WOMPI (no la app), por eso
// no lleva token de Firebase ni verificación JWT de Supabase
// (verify_jwt = false en supabase/config.toml): su seguridad es la firma del
// evento (SHA-256 con WOMPI_EVENTS_SECRET), que se verifica antes de leer o
// escribir nada. Es la ÚNICA fuente de verdad del pago.
//
//   POST /functions/v1/webhook-wompi          evento transaction.updated
//        → 200 si la firma es válida (aunque se ignore), 401 si no lo es,
//          500 ante un error interno (Wompi reintenta a los 30 min, 3 h y 24 h).
//   GET  /functions/v1/webhook-wompi/retorno/{orderId}?id=...
//        → redirect-url del Web Checkout: solo dice "vuelve a la app". La app
//          cierra el WebView al llegar aquí y escucha el pedido en Firestore.
//
// Lógica en ../_shared/pedidos.ts y ../_shared/wompi.ts (pruebas en functions/test/).
import { leerCuentaServicio } from "../_shared/cuenta_servicio.ts";
import { configWompi } from "../_shared/entorno_wompi.ts";
import { ErrorFuncion } from "../_shared/errores.ts";
import { clienteFirestore, dependenciasNotificaciones } from "../_shared/google.ts";
import { enviarNotificacion } from "../_shared/notificaciones.ts";
import { procesarEventoWompi } from "../_shared/pedidos.ts";

function json(estado: number, cuerpo: unknown): Response {
  return new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "GET") {
    // Supabase sirve como texto plano lo que no es JSON: un mensaje corto.
    return new Response(
      "Mascoti: estamos confirmando tu pago. Vuelve a la app para ver el estado de tu pedido.",
      { status: 200, headers: { "Content-Type": "text/plain; charset=utf-8" } },
    );
  }
  if (req.method !== "POST") return json(405, { error: "Usa POST" });

  try {
    const cuerpo = await req.json().catch(() => null);
    const wompi = configWompi();
    const cuenta = leerCuentaServicio(Deno.env.get("FIREBASE_SERVICE_ACCOUNT"));
    const notificaciones = dependenciasNotificaciones(cuenta);
    const resultado = await procesarEventoWompi(
      {
        db: clienteFirestore(cuenta),
        ahora: () => new Date(),
        secretoEventos: wompi.secretoEventos,
        notificar: async (aviso) => {
          await enviarNotificacion(notificaciones, aviso);
        },
        log: console.warn,
      },
      cuerpo,
      req.headers.get("X-Event-Checksum"),
    );
    console.log("Evento Wompi", JSON.stringify(resultado));
    return json(200, resultado);
  } catch (e) {
    if (e instanceof ErrorFuncion) {
      console.warn(`Evento Wompi rechazado: ${e.message}`);
      return json(e.estadoHttp, { error: e.message });
    }
    console.error(e);
    return json(500, { error: "internal" });
  }
});
