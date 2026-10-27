import { ErrorFuncion } from "./errores.ts";
import type { UsuarioFirebase } from "./registro.ts";
import type { ResultadoIntento } from "./vinculacion.ts";

/**
 * Veterinarias de OpenStreetMap (Cambio 4): las que aún no usan Mascoti y
 * aparecen en el mapa como "no aliadas". Lógica de la Edge Function
 * `veterinarias-cercanas`, sin dependencias (pruebas en functions/test/).
 *
 * - Fuente: Overpass API, `amenity=veterinary` (nodos y edificios).
 * - Caché: el área se divide en cuadros de [TAM_CUADRO]° (~5 km) que se
 *   guardan [HORAS_CACHE] h en Postgres: varias personas mirando la misma
 *   zona generan una sola consulta a Overpass (su política de uso pide no
 *   abusar de los servidores públicos).
 * - Límite: [MAX_CONSULTAS] consultas por usuario por hora.
 * - Licencia ODbL: se muestra con la atribución "© colaboradores de
 *   OpenStreetMap"; la caché es interna y no se publica.
 */

export const TAM_CUADRO = 0.05;
export const HORAS_CACHE = 24;
export const MAX_CONSULTAS = 60;
export const VENTANA_MINUTOS = 60;
/** Lado máximo del área visible que se consulta. */
export const MAX_LADO_KM = 30;

export const MENSAJE_ACERCA = "Acerca el mapa para ver otras veterinarias.";

export interface Area {
  sur: number;
  oeste: number;
  norte: number;
  este: number;
}

/** Veterinaria de OSM tal como la recibe la app (`VetPlace` en Dart). */
export interface VeterinariaOsm {
  osmId: string;
  nombre: string;
  lat: number;
  lng: number;
  direccion?: string;
  telefono?: string;
  horario?: string;
  sitioWeb?: string;
}

export interface EntradaCache {
  datos: VeterinariaOsm[];
  actualizado: Date;
}

export interface DependenciasOsm {
  verificarToken(token: string): Promise<UsuarioFirebase>;
  /** Cuenta una consulta del usuario (atómico, en Postgres). */
  registrarConsulta(uid: string): Promise<ResultadoIntento>;
  leerCache(cuadros: string[]): Promise<Map<string, EntradaCache>>;
  guardarCache(entradas: Map<string, VeterinariaOsm[]>): Promise<void>;
  /** Ejecuta una consulta Overpass QL y devuelve el JSON. */
  consultarOverpass(consulta: string): Promise<unknown>;
  ahora(): Date;
  log?(mensaje: string): void;
}

// ---------------------------------------------------------------------------
// Área y cuadros
// ---------------------------------------------------------------------------

const KM_POR_GRADO = 111.32;

function numero(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

/** Valida el área del cuerpo `{sur, oeste, norte, este}`. */
export function validarArea(cuerpo: unknown): Area {
  const c = (typeof cuerpo === "object" && cuerpo !== null ? cuerpo : {}) as Record<string, unknown>;
  const [sur, oeste, norte, este] = [c.sur, c.oeste, c.norte, c.este].map(numero);
  if (sur === null || oeste === null || norte === null || este === null ||
      sur >= norte || oeste >= este || Math.abs(sur) > 90 || Math.abs(norte) > 90 ||
      Math.abs(oeste) > 180 || Math.abs(este) > 180) {
    throw new ErrorFuncion("invalid-argument", "Área del mapa no válida.");
  }
  const latMedia = (sur + norte) / 2;
  const alto = (norte - sur) * KM_POR_GRADO;
  const ancho = (este - oeste) * KM_POR_GRADO * Math.cos((latMedia * Math.PI) / 180);
  if (alto > MAX_LADO_KM || ancho > MAX_LADO_KM) {
    throw new ErrorFuncion("failed-precondition", MENSAJE_ACERCA);
  }
  return { sur, oeste, norte, este };
}

function indice(valor: number): number {
  // Pequeño margen para que 4.10 no caiga en el cuadro anterior por redondeo.
  return Math.floor(valor / TAM_CUADRO + 1e-9);
}

/** Claves 'fila_columna' de los cuadros que cubren [area]. */
export function cuadrosDe(area: Area): string[] {
  const claves: string[] = [];
  for (let f = indice(area.sur); f <= indice(area.norte); f++) {
    for (let c = indice(area.oeste); c <= indice(area.este); c++) claves.push(`${f}_${c}`);
  }
  return claves;
}

export function areaDeCuadro(clave: string): Area {
  const [f, c] = clave.split("_").map(Number);
  return { sur: f * TAM_CUADRO, oeste: c * TAM_CUADRO, norte: (f + 1) * TAM_CUADRO, este: (c + 1) * TAM_CUADRO };
}

function cuadroDe(lat: number, lng: number): string {
  return `${indice(lat)}_${indice(lng)}`;
}

/** Área que cubre todos los [cuadros]. */
export function unionDe(cuadros: string[]): Area {
  const areas = cuadros.map(areaDeCuadro);
  return {
    sur: Math.min(...areas.map((a) => a.sur)),
    oeste: Math.min(...areas.map((a) => a.oeste)),
    norte: Math.max(...areas.map((a) => a.norte)),
    este: Math.max(...areas.map((a) => a.este)),
  };
}

function redondear(v: number): string {
  return v.toFixed(5);
}

/** Consulta Overpass QL: veterinarias (nodos, edificios y relaciones) del área. */
export function consultaOverpass(area: Area): string {
  const bbox = [area.sur, area.oeste, area.norte, area.este].map(redondear).join(",");
  return `[out:json][timeout:25];nwr["amenity"="veterinary"](${bbox});out center tags;`;
}

// ---------------------------------------------------------------------------
// Lectura de la respuesta de Overpass
// ---------------------------------------------------------------------------

interface ElementoOverpass {
  type?: string;
  id?: number;
  lat?: number;
  lon?: number;
  center?: { lat?: number; lon?: number };
  tags?: Record<string, string>;
}

function limpio(v: string | undefined): string | undefined {
  const t = v?.trim();
  return t ? t : undefined;
}

/** Primer teléfono, sin espacios ni guiones ("+57 300 123 4567" → "+573001234567"). */
export function normalizarTelefono(v: string | undefined): string | undefined {
  const primero = limpio(v?.split(/[;,/]/)[0]);
  if (!primero) return undefined;
  const t = primero.replace(/[\s\-().]/g, "");
  return /^\+?\d{7,15}$/.test(t) ? t : undefined;
}

function direccionDe(tags: Record<string, string>): string | undefined {
  const completa = limpio(tags["addr:full"]);
  if (completa) return completa;
  const calle = limpio(tags["addr:street"]);
  const numero = limpio(tags["addr:housenumber"]);
  const ciudad = limpio(tags["addr:city"]);
  const linea = calle ? (numero ? `${calle} # ${numero}` : calle) : undefined;
  const partes = [linea, ciudad].filter((p): p is string => Boolean(p));
  return partes.length > 0 ? partes.join(", ") : undefined;
}

/** JSON de Overpass → veterinarias (sin repetir por osmId). */
export function leerOverpass(json: unknown): VeterinariaOsm[] {
  const elementos = (json as { elements?: ElementoOverpass[] })?.elements ?? [];
  const vistas = new Map<string, VeterinariaOsm>();
  for (const e of elementos) {
    const lat = e.lat ?? e.center?.lat;
    const lng = e.lon ?? e.center?.lon;
    if (typeof lat !== "number" || typeof lng !== "number" || !e.type || e.id === undefined) continue;
    const tags = e.tags ?? {};
    const vet: VeterinariaOsm = {
      osmId: `${e.type}/${e.id}`,
      nombre: limpio(tags.name) ?? limpio(tags.brand) ?? "Veterinaria",
      lat,
      lng,
    };
    const direccion = direccionDe(tags);
    const telefono = normalizarTelefono(tags.phone ?? tags["contact:phone"] ?? tags.mobile);
    const horario = limpio(tags.opening_hours);
    const sitioWeb = limpio(tags.website ?? tags["contact:website"]);
    if (direccion) vet.direccion = direccion;
    if (telefono) vet.telefono = telefono;
    if (horario) vet.horario = horario;
    if (sitioWeb) vet.sitioWeb = sitioWeb;
    vistas.set(vet.osmId, vet);
  }
  return [...vistas.values()];
}

function dentro(v: VeterinariaOsm, a: Area): boolean {
  return v.lat >= a.sur && v.lat <= a.norte && v.lng >= a.oeste && v.lng <= a.este;
}

// ---------------------------------------------------------------------------
// Entrada de la Edge Function
// ---------------------------------------------------------------------------

/**
 * Veterinarias de OSM del área visible del mapa. Usa la caché por cuadros;
 * solo consulta Overpass por los cuadros que faltan o vencieron, en una
 * sola consulta.
 *
 * Errores: unauthenticated, invalid-argument (área), failed-precondition
 * (área muy grande: "Acerca el mapa…"), resource-exhausted (límite).
 */
export async function veterinariasEnArea(
  deps: DependenciasOsm,
  autorizacion: string | null,
  cuerpo: unknown,
): Promise<{ veterinarias: VeterinariaOsm[] }> {
  const token = autorizacion?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) throw new ErrorFuncion("unauthenticated", "Debes iniciar sesión con Google.");
  let usuario: UsuarioFirebase;
  try {
    usuario = await deps.verificarToken(token);
  } catch {
    throw new ErrorFuncion("unauthenticated", "Debes iniciar sesión con Google.");
  }

  const area = validarArea(cuerpo);
  const cuadros = cuadrosDe(area);
  const cache = await deps.leerCache(cuadros);
  const vence = deps.ahora().getTime() - HORAS_CACHE * 60 * 60 * 1000;
  const faltan = cuadros.filter((c) => {
    const entrada = cache.get(c);
    return !entrada || entrada.actualizado.getTime() < vence;
  });

  const resultado = new Map<string, VeterinariaOsm>();
  for (const c of cuadros) {
    if (faltan.includes(c)) continue;
    for (const v of cache.get(c)!.datos) resultado.set(v.osmId, v);
  }

  if (faltan.length > 0) {
    // Solo cuenta para el límite lo que de verdad va a Overpass.
    const intento = await deps.registrarConsulta(usuario.uid);
    if (!intento.permitido) {
      const minutos = Math.max(1, Math.ceil(intento.reintentarEnSegundos / 60));
      throw new ErrorFuncion(
        "resource-exhausted",
        `Muchas búsquedas seguidas. Intenta de nuevo en ${minutos} ${minutos === 1 ? "minuto" : "minutos"}.`,
      );
    }
    const nuevas = leerOverpass(await deps.consultarOverpass(consultaOverpass(unionDe(faltan))));
    const porCuadro = new Map<string, VeterinariaOsm[]>(faltan.map((c) => [c, []]));
    for (const v of nuevas) {
      const lista = porCuadro.get(cuadroDe(v.lat, v.lng));
      if (lista) {
        lista.push(v);
        resultado.set(v.osmId, v);
      }
    }
    try {
      await deps.guardarCache(porCuadro);
    } catch (e) {
      deps.log?.(`No se pudo guardar la caché de OSM: ${e}`);
    }
  }

  return { veterinarias: [...resultado.values()].filter((v) => dentro(v, area)) };
}
