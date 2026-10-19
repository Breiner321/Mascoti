import { ErrorFuncion } from "./errores.ts";
import type { UsuarioFirebase } from "./registro.ts";

/**
 * Adjuntos del historial médico (RF-08) en el bucket privado `registros`.
 * Supabase no puede leer Firestore en sus políticas, así que el bucket NO
 * tiene políticas: nadie sube ni lee directamente. Esta lógica verifica en
 * Firestore quién puede hacerlo y entrega enlaces firmados de un solo uso
 * (subida) o temporales (lectura). Es el equivalente de firestore.get() en
 * reglas de Storage.
 */

const ID = /^[A-Za-z0-9]{1,40}$/;
const VENTANA_EDICION_MS = 24 * 60 * 60 * 1000;
export const SEGUNDOS_LECTURA = 60 * 60;

const EXTENSIONES: Record<string, { ext: string; tipo: "imagen" | "pdf" }> = {
  jpg: { ext: "jpg", tipo: "imagen" },
  jpeg: { ext: "jpg", tipo: "imagen" },
  png: { ext: "png", tipo: "imagen" },
  pdf: { ext: "pdf", tipo: "pdf" },
};

export interface DependenciasAdjuntos {
  verificarToken(token: string): Promise<UsuarioFirebase>;
  leer(ruta: string): Promise<Record<string, unknown> | null>;
  /** Enlace de subida de un solo uso para [ruta] en el bucket `registros`. */
  firmarSubida(ruta: string): Promise<{ token: string }>;
  /** Enlace de lectura temporal. */
  firmarLectura(ruta: string, segundos: number): Promise<string>;
  nuevoId(): string;
  ahora(): Date;
}

export type SolicitudAdjunto =
  | { accion: "subir"; petId: string; recordId: string; nombreArchivo: string }
  | { accion: "leer"; petId: string; path: string };

export type RespuestaAdjunto =
  | { path: string; token: string; tipo: "imagen" | "pdf" }
  | { url: string; expiraEnSegundos: number };

const texto = (v: unknown): string => (typeof v === "string" ? v : "");

export async function gestionarAdjunto(
  deps: DependenciasAdjuntos,
  autorizacion: string | null,
  cuerpo: unknown,
): Promise<RespuestaAdjunto> {
  const token = autorizacion?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) throw new ErrorFuncion("unauthenticated", "Debes iniciar sesión con Google.");
  let usuario: UsuarioFirebase;
  try {
    usuario = await deps.verificarToken(token);
  } catch {
    throw new ErrorFuncion("unauthenticated", "Debes iniciar sesión con Google.");
  }

  const datos = (typeof cuerpo === "object" && cuerpo !== null ? cuerpo : {}) as Record<string, unknown>;
  const petId = texto(datos.petId);
  if (!ID.test(petId)) throw new ErrorFuncion("invalid-argument", "Mascota inválida.");

  const perfil = await deps.leer(`users/${usuario.uid}`);
  if (!perfil || perfil.estado !== "activo") {
    throw new ErrorFuncion("permission-denied", "No tienes permiso para ver este archivo.");
  }
  const mascota = await deps.leer(`pets/${petId}`);
  if (!mascota) throw new ErrorFuncion("not-found", "La mascota no existe.");

  const clinicId = perfil.role === "clinica" ? texto(perfil.clinicId) : "";
  const autorizadas = Array.isArray(mascota.clinicasAutorizadas) ? mascota.clinicasAutorizadas : [];
  const esClinicaAutorizada = clinicId !== "" && autorizadas.includes(clinicId);
  const esDueno = perfil.role === "dueno" && mascota.ownerUid === usuario.uid;

  if (datos.accion === "subir") {
    if (!esClinicaAutorizada) {
      throw new ErrorFuncion("permission-denied",
        "Solo una clínica autorizada puede adjuntar archivos al historial.");
    }
    const recordId = texto(datos.recordId);
    if (!ID.test(recordId)) throw new ErrorFuncion("invalid-argument", "Registro inválido.");

    const extension = texto(datos.nombreArchivo).split(".").pop()?.toLowerCase() ?? "";
    const formato = EXTENSIONES[extension];
    if (!formato) {
      throw new ErrorFuncion("invalid-argument", "Solo se permiten imágenes JPG o PNG y archivos PDF.");
    }

    // Si el registro ya existe, solo su clínica autora y dentro de 24 h.
    const registro = await deps.leer(`pets/${petId}/medicalRecords/${recordId}`);
    if (registro) {
      const creado = registro.createdAt instanceof Date ? registro.createdAt.getTime() : 0;
      if (registro.clinicId !== clinicId || deps.ahora().getTime() - creado > VENTANA_EDICION_MS) {
        throw new ErrorFuncion("permission-denied",
          "Este registro ya no se puede modificar (pasaron más de 24 horas).");
      }
    }

    const path = `${petId}/${recordId}/${deps.nuevoId()}.${formato.ext}`;
    const { token: tokenSubida } = await deps.firmarSubida(path);
    return { path, token: tokenSubida, tipo: formato.tipo };
  }

  if (datos.accion === "leer") {
    if (!esDueno && !esClinicaAutorizada) {
      throw new ErrorFuncion("permission-denied", "No tienes permiso para ver este archivo.");
    }
    const path = texto(datos.path);
    if (!new RegExp(`^${petId}/[A-Za-z0-9]{1,40}/[^/]+$`).test(path)) {
      throw new ErrorFuncion("invalid-argument", "Archivo inválido.");
    }
    const url = await deps.firmarLectura(path, SEGUNDOS_LECTURA);
    return { url, expiraEnSegundos: SEGUNDOS_LECTURA };
  }

  throw new ErrorFuncion("invalid-argument", "Acción inválida: usa 'subir' o 'leer'.");
}
