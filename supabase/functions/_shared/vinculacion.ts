import { ErrorFuncion } from "./errores.ts";
import type { UsuarioFirebase } from "./registro.ts";

/** Igual que PatientCode en lib/core/domain/patient_code.dart. */
const ALFABETO = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
const CODIGO = new RegExp(`^MSC-[${ALFABETO}]{4}$`);

/** Límite de intentos para que no se puedan adivinar códigos. */
export const MAX_INTENTOS = 10;
export const VENTANA_MINUTOS = 60;

/** Lo que escribe la clínica → `MSC-XXXX`, o null si no tiene el formato. */
export function normalizarCodigo(entrada: unknown): string | null {
  if (typeof entrada !== "string") return null;
  let texto = entrada.toUpperCase().replace(/[\s\-_]/g, "");
  if (texto.startsWith("MSC")) texto = texto.slice(3);
  const codigo = `MSC-${texto}`;
  return CODIGO.test(codigo) ? codigo : null;
}

export interface ResultadoIntento {
  permitido: boolean;
  /** Segundos hasta poder intentar de nuevo (si no está permitido). */
  reintentarEnSegundos: number;
}

/**
 * Dependencias externas, inyectadas para probar sin red
 * (functions/test/vinculacion.test.ts). index.ts pasa las reales.
 */
export interface DependenciasVinculacion {
  verificarToken(token: string): Promise<UsuarioFirebase>;
  /** Documento de Firestore como objeto plano, o null si no existe. */
  leer(ruta: string): Promise<Record<string, unknown> | null>;
  /** Cuenta un intento de la clínica (atómico). */
  registrarIntento(clinicId: string): Promise<ResultadoIntento>;
  /** Agrega clinicId a pets/{petId}.clinicasAutorizadas sin duplicarlo. */
  autorizarClinica(petId: string, clinicId: string): Promise<void>;
}

export interface MascotaVinculada {
  petId: string;
  codigoPaciente: string;
  nombre: string;
  especie: string;
  /** Ruta en el bucket `mascotas` (la clínica pide un enlace firmado). */
  fotoPath: string | null;
  duenoNombre: string;
  /** false si la clínica ya estaba autorizada antes. */
  nueva: boolean;
}

const texto = (v: unknown): string => (typeof v === "string" ? v : "");

/**
 * Semana 3: la clínica escribe el código que le da el dueño y queda
 * autorizada para ver la mascota y su historial (RF-08).
 *
 * Errores (ErrorFuncion): unauthenticated, permission-denied (no es clínica
 * o está suspendida), failed-precondition (clínica no activa),
 * invalid-argument (formato), resource-exhausted (demasiados intentos),
 * not-found (código inexistente).
 */
export async function vincularMascota(
  deps: DependenciasVinculacion,
  autorizacion: string | null,
  cuerpo: unknown,
): Promise<MascotaVinculada> {
  const token = autorizacion?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) throw new ErrorFuncion("unauthenticated", "Debes iniciar sesión con Google.");

  let usuario: UsuarioFirebase;
  try {
    usuario = await deps.verificarToken(token);
  } catch {
    throw new ErrorFuncion("unauthenticated", "Debes iniciar sesión con Google.");
  }

  const perfil = await deps.leer(`users/${usuario.uid}`);
  if (!perfil || perfil.role !== "clinica" || typeof perfil.clinicId !== "string") {
    throw new ErrorFuncion("permission-denied", "Solo las clínicas pueden vincular mascotas.");
  }
  if (perfil.estado !== "activo") {
    throw new ErrorFuncion("permission-denied", "Tu cuenta ha sido suspendida. Contacta a soporte");
  }
  const clinicId = perfil.clinicId;

  const clinica = await deps.leer(`clinics/${clinicId}`);
  if (!clinica || clinica.estado !== "activo") {
    throw new ErrorFuncion(
      "failed-precondition",
      "Tu clínica debe estar activa para vincular mascotas. Completa tu perfil de atención.",
    );
  }

  const datos = (typeof cuerpo === "object" && cuerpo !== null ? cuerpo : {}) as Record<string, unknown>;
  const codigo = normalizarCodigo(datos.codigo);
  if (!codigo) {
    throw new ErrorFuncion("invalid-argument", "El código debe tener el formato MSC-XXXX.");
  }

  // Cada búsqueda cuenta, exista o no el código.
  const intento = await deps.registrarIntento(clinicId);
  if (!intento.permitido) {
    const minutos = Math.max(1, Math.ceil(intento.reintentarEnSegundos / 60));
    throw new ErrorFuncion(
      "resource-exhausted",
      `Demasiados intentos. Intenta de nuevo en ${minutos} ${minutos === 1 ? "minuto" : "minutos"}.`,
    );
  }

  const registro = await deps.leer(`codigosPaciente/${codigo}`);
  const petId = registro ? texto(registro.petId) : "";
  const mascota = petId ? await deps.leer(`pets/${petId}`) : null;
  if (!mascota) {
    throw new ErrorFuncion("not-found", "No existe una mascota con ese código.");
  }

  const yaAutorizada = Array.isArray(mascota.clinicasAutorizadas) &&
    mascota.clinicasAutorizadas.includes(clinicId);
  if (!yaAutorizada) await deps.autorizarClinica(petId, clinicId);

  const dueno = await deps.leer(`users/${texto(mascota.ownerUid)}`);

  return {
    petId,
    codigoPaciente: codigo,
    nombre: texto(mascota.nombre),
    especie: texto(mascota.especie),
    fotoPath: typeof mascota.fotoPath === "string" ? mascota.fotoPath : null,
    duenoNombre: texto(dueno?.displayName),
    nueva: !yaAutorizada,
  };
}
