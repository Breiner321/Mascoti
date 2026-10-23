/**
 * Máquina de estados de una cita (RF-14). Igual a AppointmentStatus en
 * lib/core/domain/appointment.dart: si cambias una, cambia la otra (las
 * pruebas de ambos lados recorren todas las combinaciones).
 */
export const ESTADOS_CITA = [
  "pendiente",
  "confirmada",
  "rechazada",
  "cancelada",
  "expirada",
  "completada",
  "no_asistio",
] as const;

export type EstadoCita = typeof ESTADOS_CITA[number];

const TRANSICIONES: Record<EstadoCita, readonly EstadoCita[]> = {
  pendiente: ["confirmada", "rechazada", "cancelada", "expirada"],
  confirmada: ["completada", "cancelada", "no_asistio"],
  rechazada: [],
  cancelada: [],
  expirada: [],
  completada: [],
  no_asistio: [],
};

export function esEstadoCita(valor: unknown): valor is EstadoCita {
  return typeof valor === "string" && (ESTADOS_CITA as readonly string[]).includes(valor);
}

/** true si una cita en [de] puede pasar a [a]. */
export function puedeTransicionar(de: unknown, a: EstadoCita): boolean {
  return esEstadoCita(de) && TRANSICIONES[de].includes(a);
}

/** Estados en los que la cita ya no cambia. */
export function esFinal(estado: EstadoCita): boolean {
  return TRANSICIONES[estado].length === 0;
}
