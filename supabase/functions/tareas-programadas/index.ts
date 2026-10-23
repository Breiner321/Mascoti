// Edge Function tareas-programadas. La llama pg_cron (Postgres de Supabase,
// ver supabase/migrations/*_tareas_programadas.sql) en lugar de las funciones
// programadas de Firebase, que necesitan el plan Blaze.
//   {tarea: "vencidas"}  cada 30 min: no-show y solicitudes expiradas (RF-14).
// Solo responde si trae el encabezado x-cron-secret = secreto CRON_SECRET.
import { procesarCitasVencidas } from "../_shared/citas.ts";
import { leerCuentaServicio } from "../_shared/cuenta_servicio.ts";
import { clienteFirestore } from "../_shared/google.ts";

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
    const deps = {
      db: clienteFirestore(leerCuentaServicio(Deno.env.get("FIREBASE_SERVICE_ACCOUNT"))),
      ahora: () => new Date(),
      log: console.warn,
    };
    switch (cuerpo.tarea) {
      case "vencidas":
        return responder(200, await procesarCitasVencidas(deps));
      default:
        return responder(400, { error: "Tarea desconocida" });
    }
  } catch (e) {
    console.error(e);
    return responder(500, { error: String(e) });
  }
});
