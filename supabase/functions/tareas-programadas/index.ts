// Edge Function tareas-programadas. La llama pg_cron (Postgres de Supabase,
// ver supabase/migrations/*_tareas_programadas.sql) en lugar de las funciones
// programadas de Firebase, que necesitan el plan Blaze.
//   {tarea: "vencidas"}      cada 30 min: no-show y solicitudes expiradas (RF-14).
//   {tarea: "recordatorios"} 8:00 a. m. hora Colombia: citas de mañana y
//                            vacunas de los próximos 3 días (RF-13).
//   {tarea: "veterinarias-osm"} cada 2 h: precarga la caché de veterinarias
//                            de OpenStreetMap (Cambio 4). Corre en segundo
//                            plano (responde 202 enseguida); con
//                            {esperar: true} responde el resumen al terminar.
// Solo responde si trae el encabezado x-cron-secret = secreto CRON_SECRET.
import { procesarCitasVencidas } from "../_shared/citas.ts";
import type { BaseDatos } from "../_shared/cliente_firestore.ts";
import { leerCuentaServicio } from "../_shared/cuenta_servicio.ts";
import { clienteFirestore, dependenciasNotificaciones } from "../_shared/google.ts";
import { enviarRecordatoriosDiarios, notificarCambioCita } from "../_shared/notificaciones.ts";
import { consultarOverpass, cuadrosPorRenovar, guardarCache, leerCache } from "../_shared/overpass.ts";
import {
  precargarVeterinarias,
  type ResumenPrecarga,
  SEGUNDOS_OVERPASS_PRECARGA,
} from "../_shared/veterinarias_osm.ts";

/** Tareas en segundo plano de Supabase (sigue después de responder). */
declare const EdgeRuntime: { waitUntil(promesa: Promise<unknown>): void } | undefined;

/** El plan gratuito corta una función a los 150 s: deja margen. */
const LIMITE_PRECARGA_MS = 110_000;

function precargar(db: BaseDatos): Promise<ResumenPrecarga> {
  return precargarVeterinarias({
    clinicas: async () =>
      (await db.consultar({
        coleccion: "clinics",
        filtros: [{ campo: "estado", op: "EQUAL", valor: "activo" }],
      }))
        .map((d) => ({ lat: d.datos.lat, lng: d.datos.lng }))
        .filter((p): p is { lat: number; lng: number } =>
          typeof p.lat === "number" && typeof p.lng === "number"
        ),
    cuadrosPorRenovar,
    leerCache,
    guardarCache,
    consultarOverpass: (consulta) => consultarOverpass(consulta, (SEGUNDOS_OVERPASS_PRECARGA + 5) * 1000),
    ahora: () => new Date(),
    log: console.warn,
  }, LIMITE_PRECARGA_MS);
}

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
    const cuerpo = await req.json().catch(() => ({})) as { tarea?: string; esperar?: boolean };
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
      case "veterinarias-osm": {
        const tarea = precargar(clienteFirestore(cuenta));
        if (cuerpo.esperar || typeof EdgeRuntime === "undefined") return responder(200, await tarea);
        EdgeRuntime.waitUntil(
          tarea.then((r) => console.log("Precarga OSM", JSON.stringify(r))).catch((e) => console.error(e)),
        );
        return responder(202, { iniciada: true });
      }
      default:
        return responder(400, { error: "Tarea desconocida" });
    }
  } catch (e) {
    console.error(e);
    return responder(500, { error: String(e) });
  }
});
