/**
 * Fechas en hora de Colombia (America/Bogota): UTC−5 todo el año, sin horario
 * de verano. Igual a BogotaTime en lib/core/format/bogota_time.dart.
 */
export const DESFASE_BOGOTA_MS = -5 * 60 * 60 * 1000;

const FECHA = /^(\d{4})-(\d{2})-(\d{2})$/;
const HORA = /^([01]\d|2[0-3]):([0-5]\d)$/;

/** 'YYYY-MM-DD' + 'HH:mm' en Bogotá → instante. null si el formato no sirve. */
export function inicioEnBogota(fecha: unknown, hora: unknown): Date | null {
  const f = typeof fecha === "string" ? FECHA.exec(fecha) : null;
  const h = typeof hora === "string" ? HORA.exec(hora) : null;
  if (!f || !h) return null;
  const utc = Date.UTC(Number(f[1]), Number(f[2]) - 1, Number(f[3]), Number(h[1]), Number(h[2]));
  const instante = new Date(utc - DESFASE_BOGOTA_MS);
  // Rechaza fechas que no existen (2026-02-30).
  return fechaBogota(instante) === fecha ? instante : null;
}

/** 'YYYY-MM-DD' del día en Bogotá al que pertenece [instante]. */
export function fechaBogota(instante: Date): string {
  return new Date(instante.getTime() + DESFASE_BOGOTA_MS).toISOString().slice(0, 10);
}

/** Inicio (00:00 en Bogotá) del día 'YYYY-MM-DD'. */
export function inicioDelDia(fecha: string): Date {
  return inicioEnBogota(fecha, "00:00")!;
}

/** 'YYYY-MM-DD' de [dias] días después del día de [instante] en Bogotá. */
export function sumarDias(instante: Date, dias: number): string {
  return fechaBogota(new Date(instante.getTime() + dias * 24 * 60 * 60 * 1000));
}
