// Edge Function tareas-programadas. La llama pg_cron (Postgres de Supabase,
// ver supabase/migrations/*_tareas_programadas.sql) en lugar de las funciones
// programadas de Firebase, que necesitan el plan Blaze.
//   {tarea: "vencidas"}      cada 30 min: no-show y solicitudes expiradas (RF-14).
//   {tarea: "recordatorios"} 8:00 a. m. hora Colombia: citas de mañana y
//                            vacunas de los próximos 3 días (RF-13).
// Solo responde si trae el encabezado x-cron-secret = secreto CRON_SECRET.
import { procesarCitasVencidas } from "../_shared/citas.ts";
import { leerCuentaServicio } from "../_shared/cuenta_servicio.ts";
import { clienteFirestore, dependenciasNotificaciones } from "../_shared/google.ts";
import { enviarRecordatoriosDiarios, notificarCambioCita } from "../_shared/notificaciones.ts";

function responder(estado: number, cuerpo: unknown): Response {
  return new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  const secreto = Deno.env.get("CRON_SECRET");
  if (!secreto || req.headers.get("x-cron-secret") !== secreto) {
    return responder(401, { error: "No autorizado" });
  }

  try {
    const cuerpo = await req.json().catch(() => ({})) as { tarea?: string };
    const cuenta = leerCuentaServicio(Deno.env.get("FIREBASE_SERVICE_ACCOUNT"));
    const notificaciones = dependenciasNotificaciones(cuenta);
    switch (cuerpo.tarea) {
      case "vencidas":
        return responder(200, await procesarCitasVencidas({
          db: clienteFirestore(cuenta),
          ahora: () => new Date(),
          alCambiar: (cambio) => notificarCambioCita(notificaciones, cambio),
          log: console.warn,
        }));
      case "recordatorios":
        return responder(200, await enviarRecordatoriosDiarios(notificaciones));
      default:
        return responder(400, { error: "Tarea desconocida" });
    }
  } catch (e) {
    console.error(e);
    return responder(500, { error: String(e) });
  }
});
