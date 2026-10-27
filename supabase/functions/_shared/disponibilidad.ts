/**
 * Disponibilidad de una clínica (Cambio 2). Gemela de
 * lib/core/domain/availability.dart: si cambias una, cambia la otra. Las
 * dos pasan los casos de test/fixtures/disponibilidad.json.
 *
 * El día se divide en franjas de `reservas.duracionSlotMin` alineadas a las
 * 00:00; un servicio ocupa las franjas consecutivas que necesite. Todo en
 * hora de Colombia.
 */
import { fechaBogota, inicioDelDia, inicioEnBogota } from "./hora_bogota.ts";

export interface HorarioDia {
  abierto: boolean;
  apertura?: string;
  cierre?: string;
  descansoInicio?: string;
  descansoFin?: string;
}

/** `clinics.horarioSemanal`: lun, mar, mie, jue, vie, sab, dom. */
export type HorarioSemanal = Partial<Record<DiaSemana, HorarioDia>>;

export type DiaSemana = "lun" | "mar" | "mie" | "jue" | "vie" | "sab" | "dom";

/** Índice de Date.getUTCDay() (0 = domingo) → clave del horario. */
const DIAS: DiaSemana[] = ["dom", "lun", "mar", "mie", "jue", "vie", "sab"];

export interface ConfigReservas {
  duracionSlotMin: number;
  anticipacionMaxDias: number;
  anticipacionMinMin: number;
}

export const RESERVAS_POR_DEFECTO: ConfigReservas = {
  duracionSlotMin: 30,
  anticipacionMaxDias: 30,
  anticipacionMinMin: 120,
};

/** `clinics/{id}/excepciones/{id}`. */
export interface Excepcion {
  tipo: "bloqueo" | "apertura";
  fechaInicio: string;
  fechaFin: string;
  desde?: string;
  hasta?: string;
}

/** Estados de `slots` que ocupan la franja. */
export const ESTADOS_OCUPADOS = new Set(["reservado_temporal", "ocupado", "no_disponible"]);

const MINUTOS_DIA = 24 * 60;

type Tramo = [number, number];

export function minutos(hhmm: string): number {
  const [h, m] = hhmm.split(":").map(Number);
  return h * 60 + m;
}

export function formatoHora(min: number): string {
  return `${String(Math.floor(min / 60)).padStart(2, "0")}:${String(min % 60).padStart(2, "0")}`;
}

export function diaSemana(fecha: string): DiaSemana {
  const [a, m, d] = fecha.split("-").map(Number);
  return DIAS[new Date(Date.UTC(a, m - 1, d)).getUTCDay()];
}

const HORA = /^([01]\d|2[0-3]):[0-5]\d$/;

function esHora(valor: unknown): valor is string {
  return typeof valor === "string" && HORA.test(valor);
}

/**
 * Tramos de atención de un día según el horario semanal. Un día con horas
 * mal formadas o incoherentes se trata como cerrado, igual que en la app
 * (las reglas solo validan la estructura).
 */
function tramosDelDia(dia: HorarioDia | undefined): Tramo[] {
  if (!dia?.abierto || !esHora(dia.apertura) || !esHora(dia.cierre)) return [];
  const abre = minutos(dia.apertura);
  const cierra = minutos(dia.cierre);
  if (abre >= cierra) return [];
  if (dia.descansoInicio == null && dia.descansoFin == null) return [[abre, cierra]];
  if (!esHora(dia.descansoInicio) || !esHora(dia.descansoFin)) return [];
  const d0 = minutos(dia.descansoInicio);
  const d1 = minutos(dia.descansoFin);
  if (d0 >= d1 || d0 < abre || d1 > cierra) return [];
  return [
    ...(d0 > abre ? [[abre, d0] as Tramo] : []),
    ...(cierra > d1 ? [[d1, cierra] as Tramo] : []),
  ];
}

function cubre(e: Excepcion, fecha: string): boolean {
  return e.fechaInicio <= fecha && fecha <= e.fechaFin;
}

function diaCompleto(e: Excepcion): boolean {
  return !e.desde || !e.hasta;
}

function tramoDe(e: Excepcion): Tramo {
  return diaCompleto(e) ? [0, MINUTOS_DIA] : [minutos(e.desde!), minutos(e.hasta!)];
}

function unir(tramos: Tramo[]): Tramo[] {
  const orden = tramos.filter(([a, b]) => a < b).sort((x, y) => x[0] - y[0]);
  const resultado: Tramo[] = [];
  for (const t of orden) {
    const ultimo = resultado[resultado.length - 1];
    if (ultimo && t[0] <= ultimo[1]) ultimo[1] = Math.max(ultimo[1], t[1]);
    else resultado.push([t[0], t[1]]);
  }
  return resultado;
}

function restar(tramos: Tramo[], [c0, c1]: Tramo): Tramo[] {
  return tramos.flatMap(([a, b]): Tramo[] => {
    if (c1 <= a || b <= c0) return [[a, b]];
    return [...(a < c0 ? [[a, c0] as Tramo] : []), ...(c1 < b ? [[c1, b] as Tramo] : [])];
  });
}

function dentro(tramos: Tramo[], inicio: number, fin: number): boolean {
  return tramos.some(([a, b]) => a <= inicio && fin <= b);
}

function cuantasFranjas(duracionMin: number, slotMin: number): number {
  return duracionMin <= 0 ? 1 : Math.ceil(duracionMin / slotMin);
}

/** Tramos de atención de [fecha]: horario + aperturas extra − bloqueos. */
export function tramosAbiertos(
  fecha: string,
  horario: HorarioSemanal,
  excepciones: Excepcion[] = [],
): Tramo[] {
  const aplican = excepciones.filter((e) => cubre(e, fecha));
  let tramos = unir([
    ...tramosDelDia(horario[diaSemana(fecha)]),
    ...aplican.filter((e) => e.tipo === "apertura" && !diaCompleto(e)).map(tramoDe),
  ]);
  for (const e of aplican) {
    if (e.tipo === "bloqueo") tramos = restar(tramos, tramoDe(e));
  }
  return tramos;
}

/** Franjas ('HH:mm') que aparta un servicio que empieza a [hora]. */
export function franjasDe(hora: string, duracionMin: number, slotMin: number): string[] {
  const inicio = minutos(hora);
  return Array.from(
    { length: cuantasFranjas(duracionMin, slotMin) },
    (_, i) => formatoHora(inicio + i * slotMin),
  );
}

export interface ConsultaDisponibilidad {
  fecha: string;
  duracionMin: number;
  horario: HorarioSemanal;
  reservas: ConfigReservas;
  ahora: Date;
  excepciones?: Excepcion[];
  /** hora → estado del documento `slots/{fecha}_{hora}`. */
  franjas?: Record<string, string>;
}

/** Horas de inicio en las que se puede reservar (igual a Availability.startTimes). */
export function horasDisponibles(c: ConsultaDisponibilidad): string[] {
  const ultimoDia = fechaBogota(
    new Date(inicioDelDia(fechaBogota(c.ahora)).getTime() + c.reservas.anticipacionMaxDias * 86_400_000),
  );
  if (c.fecha > ultimoDia) return [];
  const minimo = c.ahora.getTime() + c.reservas.anticipacionMinMin * 60_000;

  const paso = c.reservas.duracionSlotMin;
  const n = cuantasFranjas(c.duracionMin, paso);
  const abiertos = tramosAbiertos(c.fecha, c.horario, c.excepciones);
  const franjas = c.franjas ?? {};
  const resultado: string[] = [];
  for (let inicio = 0; inicio + n * paso <= MINUTOS_DIA; inicio += paso) {
    let cabe = true;
    for (let i = 0; i < n && cabe; i++) {
      const celda = inicio + i * paso;
      cabe = dentro(abiertos, celda, celda + paso) &&
        !ESTADOS_OCUPADOS.has(franjas[formatoHora(celda)] ?? "");
    }
    if (!cabe) continue;
    const hora = formatoHora(inicio);
    const instante = inicioEnBogota(c.fecha, hora);
    if (!instante || instante.getTime() <= c.ahora.getTime() || instante.getTime() < minimo) continue;
    resultado.push(hora);
  }
  return resultado;
}

/** ¿La cita cabe en el horario y las excepciones? (sin ocupación ni anticipación) */
export function cabeEnHorario(
  fecha: string,
  hora: string,
  duracionMin: number,
  horario: HorarioSemanal,
  slotMin: number,
  excepciones: Excepcion[] = [],
): boolean {
  const inicio = minutos(hora);
  return dentro(
    tramosAbiertos(fecha, horario, excepciones),
    inicio,
    inicio + cuantasFranjas(duracionMin, slotMin) * slotMin,
  );
}

/**
 * Horario de una clínica leída de Firestore. Sin `horarioSemanal` (antes de
 * migrar) se usa `horarioBase` para todos los días, igual que la app.
 */
export function horarioDeClinica(clinica: Record<string, unknown>): HorarioSemanal | null {
  if (typeof clinica.horarioSemanal === "object" && clinica.horarioSemanal !== null) {
    return clinica.horarioSemanal as HorarioSemanal;
  }
  const base = clinica.horarioBase as { apertura?: string; cierre?: string } | undefined;
  if (!base?.apertura || !base.cierre) return null;
  return Object.fromEntries(
    DIAS.map((d) => [d, { abierto: true, apertura: base.apertura, cierre: base.cierre }]),
  ) as HorarioSemanal;
}

export function reservasDeClinica(clinica: Record<string, unknown>): ConfigReservas {
  const r = (clinica.reservas ?? {}) as Partial<ConfigReservas>;
  const base = clinica.horarioBase as { duracionSlotMin?: number } | undefined;
  const numero = (v: unknown, def: number) => (typeof v === "number" && v > 0 ? v : def);
  return {
    duracionSlotMin: numero(r.duracionSlotMin, numero(base?.duracionSlotMin, 30)),
    anticipacionMaxDias: numero(r.anticipacionMaxDias, RESERVAS_POR_DEFECTO.anticipacionMaxDias),
    anticipacionMinMin: typeof r.anticipacionMinMin === "number" && r.anticipacionMinMin >= 0
      ? r.anticipacionMinMin
      : RESERVAS_POR_DEFECTO.anticipacionMinMin,
  };
}
