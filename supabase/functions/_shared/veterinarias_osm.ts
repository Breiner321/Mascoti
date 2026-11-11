import { ErrorFuncion } from "./errores.ts";
import type { UsuarioFirebase } from "./registro.ts";
import type { ResultadoIntento } from "./vinculacion.ts";

/**
 * Veterinarias de OpenStreetMap (Cambio 4): las que aún no usan Mascoti y
 * aparecen en el mapa como "no aliadas". Lógica de la Edge Function
 * `veterinarias-cercanas`, sin dependencias (pruebas en functions/test/).
 *
 * - Fuente: Overpass API, `amenity=veterinary` (nodos y edificios).
 * - Caché: el área se divide en cuadros de [TAM_CUADRO]° (~5 km) guardados
 *   en Postgres. Al abrir el mapa se sirve lo que haya en caché (aunque sea
 *   viejo) y solo se consulta Overpass por los cuadros que faltan: los
 *   servidores públicos de Overpass a veces tardan más de 40 s.
 * - Respaldo: si Overpass falla, Photon (el buscador de direcciones, mismos
 *   datos de OSM) por texto con el filtro amenity=veterinary. Trae menos
 *   (solo nombres con "veterinaria", "pet"…, ~10 por búsqueda y sin teléfono
 *   ni horario), así que se guarda como vencido: la precarga lo reemplaza
 *   con Overpass cuando vuelva.
 * - Precarga ([precargarVeterinarias], tarea programada cada 2 h): renueva
 *   los cuadros de más de [HORAS_CACHE] h, los pendientes (Overpass falló
 *   al abrir el mapa) y los alrededores de las clínicas y las ciudades
 *   principales, en segundo plano.
 * - Límite: [MAX_CONSULTAS] consultas por usuario por hora.
 * - Licencia ODbL: se muestra con la atribución "© colaboradores de
 *   OpenStreetMap"; la caché es interna y no se publica.
 */

export const TAM_CUADRO = 0.05;
export const HORAS_CACHE = 24;
/** La precarga renueva un poco antes de las 24 h (corre cada 2 h). */
export const HORAS_RENOVAR = 20;
export const MAX_CONSULTAS = 60;
export const VENTANA_MINUTOS = 60;
/** Lado máximo del área visible que se consulta. */
export const MAX_LADO_KM = 30;

export const MENSAJE_ACERCA = "Acerca el mapa para ver otras veterinarias.";
export const MENSAJE_NO_DISPONIBLE = "No se pudieron cargar otras veterinarias.";

/** Segundos que Overpass puede tardar al abrir el mapa y en la precarga. */
export const SEGUNDOS_OVERPASS_MAPA = 45;
export const SEGUNDOS_OVERPASS_PRECARGA = 60;

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
  /** Overpass falló al pedirlo: no tiene datos y la precarga lo llena. */
  pendiente?: boolean;
}

export interface DependenciasOsm {
  verificarToken(token: string): Promise<UsuarioFirebase>;
  /** Cuenta una consulta del usuario (atómico, en Postgres). */
  registrarConsulta(uid: string): Promise<ResultadoIntento>;
  leerCache(cuadros: string[]): Promise<Map<string, EntradaCache>>;
  /** [actualizado] por defecto: ahora. */
  guardarCache(entradas: Map<string, VeterinariaOsm[]>, actualizado?: Date): Promise<void>;
  /** Marca cuadros sin datos para que la precarga los llene. */
  marcarPendientes(cuadros: string[]): Promise<void>;
  /** Ejecuta una consulta Overpass QL y devuelve el JSON. */
  consultarOverpass(consulta: string): Promise<unknown>;
  /** Búsqueda de Photon por [texto] en [area] (respaldo); devuelve el JSON. */
  consultarPhoton(texto: string, area: Area): Promise<unknown>;
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
export function consultaOverpass(area: Area, segundos = SEGUNDOS_OVERPASS_MAPA): string {
  const bbox = [area.sur, area.oeste, area.norte, area.este].map(redondear).join(",");
  return `[out:json][timeout:${segundos}];nwr["amenity"="veterinary"](${bbox});out center tags;`;
}

// ---------------------------------------------------------------------------
// Respaldo: Photon
// ---------------------------------------------------------------------------

/** Palabras con las que se busca en Photon (cubren la mayoría de nombres). */
export const PALABRAS_PHOTON = ["veterinaria", "veterinario", "vet", "pet", "mascotas"];

interface ElementoPhoton {
  geometry?: { coordinates?: [number, number] };
  properties?: Record<string, unknown>;
}

const TIPO_OSM: Record<string, string> = { N: "node", W: "way", R: "relation" };

function texto(v: unknown): string | undefined {
  return typeof v === "string" ? limpio(v) : undefined;
}

/** JSON de Photon → veterinarias (solo `amenity=veterinary`). */
export function leerPhoton(json: unknown): VeterinariaOsm[] {
  const elementos = (json as { features?: ElementoPhoton[] })?.features ?? [];
  const vistas = new Map<string, VeterinariaOsm>();
  for (const e of elementos) {
    const p = e.properties ?? {};
    const [lng, lat] = e.geometry?.coordinates ?? [];
    const tipo = TIPO_OSM[String(p.osm_type)];
    if (typeof lat !== "number" || typeof lng !== "number" || !tipo || p.osm_id === undefined) continue;
    if (p.osm_key !== "amenity" || p.osm_value !== "veterinary") continue;
    const vet: VeterinariaOsm = { osmId: `${tipo}/${p.osm_id}`, nombre: texto(p.name) ?? "Veterinaria", lat, lng };
    const calle = texto(p.street);
    const numero = texto(p.housenumber);
    const linea = calle ? (numero ? `${calle} # ${numero}` : calle) : undefined;
    const direccion = [linea, texto(p.city)].filter((x): x is string => Boolean(x)).join(", ");
    if (direccion) vet.direccion = direccion;
    vistas.set(vet.osmId, vet);
  }
  return [...vistas.values()];
}

/**
 * Busca en Photon con todas las [PALABRAS_PHOTON] a la vez. Falla solo si
 * fallan todas las búsquedas.
 */
export async function buscarConPhoton(
  deps: Pick<DependenciasOsm, "consultarPhoton">,
  area: Area,
): Promise<VeterinariaOsm[]> {
  const respuestas = await Promise.allSettled(PALABRAS_PHOTON.map((p) => deps.consultarPhoton(p, area)));
  const exitos = respuestas.filter((r): r is PromiseFulfilledResult<unknown> => r.status === "fulfilled");
  if (exitos.length === 0) throw (respuestas[0] as PromiseRejectedResult).reason;
  const vistas = new Map<string, VeterinariaOsm>();
  for (const r of exitos) for (const v of leerPhoton(r.value)) vistas.set(v.osmId, v);
  return [...vistas.values()].filter((v) => dentro(v, area));
}

/** Lo que trae Photon se guarda como vencido: la precarga lo renueva con Overpass. */
function fechaRespaldo(ahora: Date): Date {
  return new Date(ahora.getTime() - (HORAS_RENOVAR + 1) * 60 * 60 * 1000);
}

/** Reparte las veterinarias de Overpass en sus cuadros (todos los pedidos, también vacíos). */
function repartir(cuadros: string[], veterinarias: VeterinariaOsm[]): Map<string, VeterinariaOsm[]> {
  const porCuadro = new Map<string, VeterinariaOsm[]>(cuadros.map((c) => [c, []]));
  for (const v of veterinarias) porCuadro.get(cuadroDe(v.lat, v.lng))?.push(v);
  return porCuadro;
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
 * Veterinarias de OSM del área visible del mapa. Sirve la caché aunque sea
 * vieja (la renueva la precarga) y solo consulta Overpass, en una sola
 * consulta, por los cuadros que no están o están pendientes. Si Overpass
 * falla, marca esos cuadros como pendientes y responde con lo que haya
 * (`incompleto: true`); si no hay nada, error "No se pudieron cargar…".
 *
 * Errores: unauthenticated, invalid-argument (área), failed-precondition
 * (área muy grande: "Acerca el mapa…"), resource-exhausted (límite),
 * internal (Overpass no respondió y no hay caché).
 */
export async function veterinariasEnArea(
  deps: DependenciasOsm,
  autorizacion: string | null,
  cuerpo: unknown,
): Promise<{ veterinarias: VeterinariaOsm[]; incompleto?: boolean }> {
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
  const faltan = cuadros.filter((c) => {
    const entrada = cache.get(c);
    return !entrada || entrada.pendiente === true;
  });

  const resultado = new Map<string, VeterinariaOsm>();
  for (const c of cuadros) {
    if (faltan.includes(c)) continue;
    for (const v of cache.get(c)!.datos) resultado.set(v.osmId, v);
  }
  const respuesta = () => [...resultado.values()].filter((v) => dentro(v, area));

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
    let nuevas: VeterinariaOsm[];
    let actualizado: Date | undefined;
    try {
      nuevas = leerOverpass(await deps.consultarOverpass(consultaOverpass(unionDe(faltan))));
    } catch (e) {
      deps.log?.(`Overpass no respondió (${faltan.length} cuadros): ${e}`);
      try {
        nuevas = await buscarConPhoton(deps, unionDe(faltan));
        actualizado = fechaRespaldo(deps.ahora());
      } catch (e2) {
        deps.log?.(`Photon tampoco respondió: ${e2}`);
        try {
          await deps.marcarPendientes(faltan);
        } catch (e3) {
          deps.log?.(`No se pudieron marcar los cuadros pendientes: ${e3}`);
        }
        if (faltan.length === cuadros.length) throw new ErrorFuncion("internal", MENSAJE_NO_DISPONIBLE);
        return { veterinarias: respuesta(), incompleto: true };
      }
    }
    const porCuadro = repartir(faltan, nuevas);
    for (const lista of porCuadro.values()) for (const v of lista) resultado.set(v.osmId, v);
    try {
      await deps.guardarCache(porCuadro, actualizado);
    } catch (e) {
      deps.log?.(`No se pudo guardar la caché de OSM: ${e}`);
    }
    // Con Photon pueden faltar veterinarias (nombres sin "veterinaria"…).
    if (actualizado) return { veterinarias: respuesta(), incompleto: true };
  }

  return { veterinarias: respuesta() };
}

// ---------------------------------------------------------------------------
// Precarga (tarea programada)
// ---------------------------------------------------------------------------

export interface Punto {
  lat: number;
  lng: number;
}

/**
 * Ciudades principales de Colombia: se precargan aunque no tengan clínicas
 * aliadas, para que el mapa abra rápido donde más se usa.
 */
export const CIUDADES: (Punto & { nombre: string })[] = [
  { nombre: "Bogotá", lat: 4.65, lng: -74.1 },
  { nombre: "Bogotá norte", lat: 4.75, lng: -74.05 },
  { nombre: "Bogotá sur", lat: 4.55, lng: -74.13 },
  { nombre: "Medellín", lat: 6.24, lng: -75.58 },
  { nombre: "Cali", lat: 3.43, lng: -76.52 },
  { nombre: "Barranquilla", lat: 10.98, lng: -74.8 },
  { nombre: "Cartagena", lat: 10.4, lng: -75.5 },
  { nombre: "Bucaramanga", lat: 7.12, lng: -73.12 },
  { nombre: "Pereira", lat: 4.81, lng: -75.69 },
  { nombre: "Manizales", lat: 5.07, lng: -75.51 },
  { nombre: "Ibagué", lat: 4.44, lng: -75.22 },
  { nombre: "Santa Marta", lat: 11.23, lng: -74.2 },
  { nombre: "Villavicencio", lat: 4.14, lng: -73.63 },
  { nombre: "Cúcuta", lat: 7.89, lng: -72.5 },
  { nombre: "Pasto", lat: 1.21, lng: -77.28 },
  { nombre: "Montería", lat: 8.75, lng: -75.88 },
  { nombre: "Neiva", lat: 2.93, lng: -75.28 },
  { nombre: "Armenia", lat: 4.53, lng: -75.68 },
];

/** Cuadros alrededor de cada punto: ±2 cuadros (~10 km a cada lado). */
export const RADIO_PRECARGA = 2;
/** Cuadros por lado de cada consulta de la precarga (~20 km). */
export const LADO_BLOQUE = 4;

export interface DependenciasPrecarga {
  /** Ubicación de las clínicas activas. */
  clinicas(): Promise<Punto[]>;
  /** Cuadros en caché vencidos (antes de [antesDe]) o pendientes. */
  cuadrosPorRenovar(antesDe: Date): Promise<string[]>;
  leerCache(cuadros: string[]): Promise<Map<string, EntradaCache>>;
  guardarCache(entradas: Map<string, VeterinariaOsm[]>, actualizado?: Date): Promise<void>;
  consultarOverpass(consulta: string): Promise<unknown>;
  consultarPhoton(texto: string, area: Area): Promise<unknown>;
  ahora(): Date;
  log?(mensaje: string): void;
}

export interface ResumenPrecarga {
  porRenovar: number;
  consultas: number;
  actualizados: number;
  /** Cuadros llenados con Photon (respaldo) porque Overpass falló. */
  conPhoton: number;
  errores: number;
  /** Cuadros que quedan para la próxima vuelta (se acabó el tiempo). */
  quedan: number;
}

export function cuadrosAlrededor(p: Punto, radio = RADIO_PRECARGA): string[] {
  const f0 = indice(p.lat);
  const c0 = indice(p.lng);
  const claves: string[] = [];
  for (let f = f0 - radio; f <= f0 + radio; f++) {
    for (let c = c0 - radio; c <= c0 + radio; c++) claves.push(`${f}_${c}`);
  }
  return claves;
}

function bloqueDe(cuadro: string): string {
  const [f, c] = cuadro.split("_").map(Number);
  return `${Math.floor(f / LADO_BLOQUE)}_${Math.floor(c / LADO_BLOQUE)}`;
}

/**
 * Llena y renueva la caché en segundo plano. Prioridad: pendientes, los que
 * no están y los más viejos. Agrupa los cuadros en bloques de
 * [LADO_BLOQUE]² (una consulta a Overpass por bloque) y para al llegar a
 * [limiteMs]: lo que falte queda para la próxima vuelta.
 *
 * Si Overpass falla en un bloque, los cuadros sin datos (pendientes o que no
 * están) se llenan con Photon, uno por uno; los que ya tienen datos viejos se
 * dejan como están. Tras 3 fallos seguidos de Overpass ya no se le pregunta
 * en esta vuelta (está caído) y se sigue solo con Photon.
 */
export async function precargarVeterinarias(
  deps: DependenciasPrecarga,
  limiteMs = 110_000,
): Promise<ResumenPrecarga> {
  const inicio = deps.ahora().getTime();
  const renovarAntes = new Date(inicio - HORAS_RENOVAR * 60 * 60 * 1000);

  let clinicas: Punto[] = [];
  try {
    clinicas = await deps.clinicas();
  } catch (e) {
    deps.log?.(`No se pudieron leer las clínicas: ${e}`);
  }
  const candidatos = new Set<string>(await deps.cuadrosPorRenovar(renovarAntes));
  for (const p of [...CIUDADES, ...clinicas]) for (const c of cuadrosAlrededor(p)) candidatos.add(c);

  const cache = await deps.leerCache([...candidatos]);
  const prioridad = (c: string): number => {
    const e = cache.get(c);
    if (!e) return 1; // no está
    if (e.pendiente) return 0;
    return 2 + e.actualizado.getTime() / 1e15; // los más viejos primero
  };
  const porRenovar = [...candidatos]
    .filter((c) => {
      const e = cache.get(c);
      return !e || e.pendiente === true || e.actualizado.getTime() < renovarAntes.getTime();
    })
    .sort((a, b) => prioridad(a) - prioridad(b));

  // Bloques en el orden de su cuadro más urgente.
  const bloques = new Map<string, string[]>();
  for (const c of porRenovar) {
    const b = bloqueDe(c);
    bloques.set(b, [...(bloques.get(b) ?? []), c]);
  }

  const resumen: ResumenPrecarga = {
    porRenovar: porRenovar.length, consultas: 0, actualizados: 0, conPhoton: 0, errores: 0, quedan: 0,
  };
  const sinTiempo = () => deps.ahora().getTime() - inicio >= limiteMs;
  let fallosSeguidos = 0;
  for (const cuadros of bloques.values()) {
    if (sinTiempo()) {
      resumen.quedan += cuadros.length;
      continue;
    }
    if (fallosSeguidos < 3) {
      resumen.consultas++;
      try {
        const json = await deps.consultarOverpass(consultaOverpass(unionDe(cuadros), SEGUNDOS_OVERPASS_PRECARGA));
        await deps.guardarCache(repartir(cuadros, leerOverpass(json)));
        resumen.actualizados += cuadros.length;
        fallosSeguidos = 0;
        continue;
      } catch (e) {
        resumen.errores++;
        fallosSeguidos++;
        deps.log?.(`Precarga OSM: Overpass falló en un bloque de ${cuadros.length} cuadros: ${e}`);
      }
    }
    // Respaldo: Photon, solo para los cuadros que no tienen datos.
    for (const c of cuadros) {
      const e = cache.get(c);
      if ((e && !e.pendiente) || sinTiempo()) {
        resumen.quedan++;
        continue;
      }
      try {
        const vets = await buscarConPhoton(deps, areaDeCuadro(c));
        await deps.guardarCache(new Map([[c, vets]]), fechaRespaldo(deps.ahora()));
        resumen.conPhoton++;
      } catch (e2) {
        resumen.quedan++;
        deps.log?.(`Precarga OSM: Photon falló en el cuadro ${c}: ${e2}`);
      }
    }
  }
  return resumen;
}
