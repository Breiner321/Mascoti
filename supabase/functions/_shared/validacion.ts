import { ErrorFuncion } from "./errores.ts";

export type Rol = "dueno" | "clinica";

export interface DatosClinica {
  nombre: string;
  telefono: string;
  direccion: string;
  lat: number;
  lng: number;
}

export interface DatosRegistro {
  role: Rol;
  clinica?: DatosClinica;
}

const TELEFONO = /^\d{10}$/;

function invalido(mensaje: string): never {
  throw new ErrorFuncion("invalid-argument", mensaje);
}

/** lat/lng vienen del buscador de direcciones: obligatorios, finitos y en rango. */
function coordenada(valor: unknown, limite: number): number {
  if (typeof valor !== "number" || !Number.isFinite(valor) || Math.abs(valor) > limite) {
    invalido("Selecciona una dirección válida de la lista");
  }
  return valor;
}

/** Valida el payload de completar-registro con las reglas de RF-01 (pasos 9-10). */
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

  const lat = coordenada(c.lat, 90);
  const lng = coordenada(c.lng, 180);

  return { role: "clinica", clinica: { nombre, telefono, direccion, lat, lng } };
}
