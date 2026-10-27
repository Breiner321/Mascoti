// Solo para Deno (Edge Functions). Cliente de Overpass (OpenStreetMap) y
// acceso a la caché de veterinarias en Postgres (Cambio 4), compartidos por
// veterinarias-cercanas y la precarga de tareas-programadas.
import type { Area, EntradaCache, VeterinariaOsm } from "./veterinarias_osm.ts";
import { filas, guardar, seleccionar } from "./supabase_rest.ts";

/** Servidores públicos de Overpass, en orden: si uno falla, el siguiente. */
// Sin overpass.kumi.systems: cuando falla se queda sin responder y se come
// el plazo; estos contestan el error en segundos (y queda el respaldo Photon).
const SERVIDORES = [
  "https://overpass-api.de/api/interpreter",
  "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
];

/** La política de uso de Overpass pide identificar la aplicación. */
const USER_AGENT = "Mascoti/1.0 (app de veterinarias; https://github.com/Breiner321/Mascoti)";

/**
 * Ejecuta [consulta] probando los servidores en orden, con [plazoMs] en
 * total: el primero puede usar casi todo el plazo (los servidores públicos a
 * veces tardan más de 40 s) y los siguientes lo que quede.
 */
export async function consultarOverpass(consulta: string, plazoMs: number): Promise<unknown> {
  const fin = Date.now() + plazoMs;
  let ultimo: unknown = new Error("Sin tiempo para consultar Overpass");
  for (const servidor of SERVIDORES) {
    const queda = fin - Date.now();
    if (queda < 3_000) break;
    try {
      const respuesta = await fetch(servidor, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded", "User-Agent": USER_AGENT },
        body: new URLSearchParams({ data: consulta }),
        signal: AbortSignal.timeout(queda),
      });
      if (respuesta.ok) return await respuesta.json();
      ultimo = new Error(`Overpass ${new URL(servidor).host} ${respuesta.status}`);
      await respuesta.body?.cancel();
    } catch (e) {
      ultimo = e;
    }
  }
  throw ultimo;
}

/** Búsqueda de Photon (respaldo de Overpass), solo `amenity=veterinary`. */
export async function consultarPhoton(texto: string, area: Area): Promise<unknown> {
  const parametros = new URLSearchParams({
    q: texto,
    osm_tag: "amenity:veterinary",
    bbox: [area.oeste, area.sur, area.este, area.norte].join(","),
    limit: "50",
  });
  const respuesta = await fetch(`https://photon.komoot.io/api/?${parametros}`, {
    headers: { "User-Agent": USER_AGENT },
    signal: AbortSignal.timeout(10_000),
  });
  if (!respuesta.ok) {
    await respuesta.body?.cancel();
    throw new Error(`Photon ${respuesta.status}`);
  }
  return await respuesta.json();
}

const TABLA = "cache_veterinarias_osm";

interface FilaCache {
  cuadro: string;
  datos: VeterinariaOsm[];
  actualizado: string;
  pendiente: boolean;
}

export async function leerCache(cuadros: string[]): Promise<Map<string, EntradaCache>> {
  const mapa = new Map<string, EntradaCache>();
  // Por partes: la lista va en la URL.
  for (let i = 0; i < cuadros.length; i += 150) {
    for (const f of await seleccionar<FilaCache>(TABLA, "cuadro", cuadros.slice(i, i + 150))) {
      mapa.set(f.cuadro, { datos: f.datos, actualizado: new Date(f.actualizado), pendiente: f.pendiente });
    }
  }
  return mapa;
}

export function guardarCache(entradas: Map<string, VeterinariaOsm[]>, fecha = new Date()): Promise<void> {
  const actualizado = fecha.toISOString();
  return guardar(
    TABLA,
    [...entradas].map(([cuadro, datos]) => ({ cuadro, datos, actualizado, pendiente: false })),
  );
}

/** Solo crea o marca la fila: no borra los datos que tuviera. */
export function marcarPendientes(cuadros: string[]): Promise<void> {
  return guardar(TABLA, cuadros.map((cuadro) => ({ cuadro, pendiente: true })));
}

/** Cuadros pendientes o actualizados antes de [antesDe] (los más viejos primero). */
export async function cuadrosPorRenovar(antesDe: Date): Promise<string[]> {
  const consulta = `select=cuadro&or=(pendiente.is.true,actualizado.lt.${encodeURIComponent(antesDe.toISOString())})` +
    "&order=actualizado.asc&limit=500";
  return (await filas<{ cuadro: string }>(TABLA, consulta)).map((f) => f.cuadro);
}
