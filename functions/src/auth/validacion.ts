import { HttpsError } from "firebase-functions/v2/https";

export type Rol = "dueno" | "clinica";

export interface DatosClinica {
  nombre: string;
  telefono: string;
  direccion: string;
  lat: number | null;
  lng: number | null;
}

export interface DatosRegistro {
  role: Rol;
  clinica?: DatosClinica;
}

const TELEFONO = /^\d{10}$/;

function invalido(mensaje: string): never {
  throw new HttpsError("invalid-argument", mensaje);
}

function numeroONulo(valor: unknown, campo: string): number | null {
  if (valor === null || valor === undefined) return null;
  if (typeof valor !== "number" || !Number.isFinite(valor)) invalido(`${campo} inválido`);
  return valor;
}

/** Valida el payload de completarRegistro con las reglas de RF-01 (paso 9-10). */
export function validarRegistro(data: unknown): DatosRegistro {
  if (typeof data !== "object" || data === null) invalido("Datos de registro vacíos");
  const { role, clinica } = data as Record<string, unknown>;

  if (role === "dueno") return { role: "dueno" };
  if (role !== "clinica") invalido("Selecciona un rol válido");

  if (typeof clinica !== "object" || clinica === null) {
    invalido("Faltan los datos de la clínica");
  }
  const c = clinica as Record<string, unknown>;
  const nombre = typeof c.nombre === "string" ? c.nombre.trim() : "";
  const telefono = typeof c.telefono === "string" ? c.telefono.trim() : "";
  const direccion = typeof c.direccion === "string" ? c.direccion.trim() : "";

  if (nombre.length < 3) invalido("El nombre comercial debe tener mínimo 3 caracteres");
  if (!TELEFONO.test(telefono)) invalido("El teléfono debe tener 10 dígitos numéricos");
  if (direccion.length === 0) invalido("Selecciona una dirección válida de la lista");

  // TODO(RF-01): exigir lat/lng cuando la app use Google Places.
  const lat = numeroONulo(c.lat, "lat");
  const lng = numeroONulo(c.lng, "lng");

  return { role: "clinica", clinica: { nombre, telefono, direccion, lat, lng } };
}
