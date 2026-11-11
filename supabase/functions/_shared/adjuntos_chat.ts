import { ErrorFuncion } from "./errores.ts";
import type { UsuarioFirebase } from "./registro.ts";

/**
 * Adjuntos del chat (RF-16) en el bucket privado `chats`. Igual que
 * `registros`: el bucket no tiene políticas para la app (Supabase no puede
 * leer Firestore) y esta lógica verifica en Firestore que quien pide es
 * participante activo del chat antes de entregar un enlace firmado de
 * subida (un solo uso) o de lectura (15 min). El bucket además limita a
 * JPG/PNG/PDF y 10 MB (migración 20261110000000_storage_chats.sql).
 *
 * Ruta: `{chatId}/{uuid}-{nombre}` (firestore.rules exige que el mensaje
 * apunte a la carpeta de su chat).
 */

export const SEGUNDOS_LECTURA = 15 * 60;
export const MAXIMO_BYTES = 10 * 1024 * 1024;
export const MENSAJE_TIPO = "Solo se permiten imágenes JPG o PNG y archivos PDF.";
export const MENSAJE_TAMANO =
  "El archivo supera los 10 MB. Comprime la imagen o selecciona un archivo más liviano.";
const MENSAJE_PERMISO = "No tienes permiso para ver los archivos de este chat.";

const ID_CHAT = /^[A-Za-z0-9]{1,128}_[A-Za-z0-9]{1,128}$/;

const FORMATOS: Record<string, "imagen" | "pdf"> = {
  jpg: "imagen",
  jpeg: "imagen",
  png: "imagen",
  pdf: "pdf",
};

export interface DependenciasAdjuntosChat {
  verificarToken(token: string): Promise<UsuarioFirebase>;
  leer(ruta: string): Promise<Record<string, unknown> | null>;
  /** Enlace de subida de un solo uso para [ruta] en el bucket `chats`. */
  firmarSubida(ruta: string): Promise<{ token: string }>;
  firmarLectura(ruta: string, segundos: number): Promise<string>;
  /** Identificador aleatorio (uuid) para la ruta. */
  nuevoId(): string;
}

export type RespuestaAdjuntoChat =
  | { path: string; token: string; tipo: "imagen" | "pdf"; nombre: string }
  | { url: string; expiraEnSegundos: number };

const texto = (v: unknown): string => (typeof v === "string" ? v : "");

/**
 * Nombre seguro para la ruta: sin carpetas, solo letras, números, punto,
 * guion y guion bajo (los acentos y espacios pasan a "_"), máximo 80.
 */
export function nombreSeguro(nombre: string): string {
  const base = nombre.split(/[\\/]/).pop() ?? "";
  const limpio = base.normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^A-Za-z0-9._-]+/g, "_").replace(/^[._]+/, "");
  if (limpio.length <= 80) return limpio || "archivo";
  const punto = limpio.lastIndexOf(".");
  const ext = punto > 0 ? limpio.slice(punto) : "";
  return limpio.slice(0, 80 - ext.length) + ext;
}

export async function gestionarAdjuntoChat(
  deps: DependenciasAdjuntosChat,
  autorizacion: string | null,
  cuerpo: unknown,
): Promise<RespuestaAdjuntoChat> {
  const token = autorizacion?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) throw new ErrorFuncion("unauthenticated", "Debes iniciar sesión con Google.");
  let usuario: UsuarioFirebase;
  try {
    usuario = await deps.verificarToken(token);
  } catch {
    throw new ErrorFuncion("unauthenticated", "Debes iniciar sesión con Google.");
  }

  const datos = (typeof cuerpo === "object" && cuerpo !== null ? cuerpo : {}) as Record<string, unknown>;
  const chatId = texto(datos.chatId);
  if (!ID_CHAT.test(chatId)) throw new ErrorFuncion("invalid-argument", "Chat inválido.");

  const perfil = await deps.leer(`users/${usuario.uid}`);
  if (!perfil || perfil.estado !== "activo") throw new ErrorFuncion("permission-denied", MENSAJE_PERMISO);
  const chat = await deps.leer(`chats/${chatId}`);
  const participantes = chat?.participantes;
  if (!Array.isArray(participantes) || !participantes.includes(usuario.uid)) {
    throw new ErrorFuncion("permission-denied", MENSAJE_PERMISO);
  }

  if (datos.accion === "subir") {
    const original = texto(datos.nombreArchivo).trim();
    const extension = original.split(".").pop()?.toLowerCase() ?? "";
    const tipo = original.includes(".") ? FORMATOS[extension] : undefined;
    if (!tipo) throw new ErrorFuncion("invalid-argument", MENSAJE_TIPO);
    const tamano = datos.tamanoBytes;
    if (typeof tamano !== "number" || !Number.isInteger(tamano) || tamano <= 0) {
      throw new ErrorFuncion("invalid-argument", "Indica el tamaño del archivo.");
    }
    if (tamano > MAXIMO_BYTES) throw new ErrorFuncion("invalid-argument", MENSAJE_TAMANO);

    const path = `${chatId}/${deps.nuevoId()}-${nombreSeguro(original)}`;
    const { token: tokenSubida } = await deps.firmarSubida(path);
    // `nombre` es el original (lo que se muestra en el chat), ≤ 120 como en las reglas.
    return { path, token: tokenSubida, tipo, nombre: original.slice(0, 120) };
  }

  if (datos.accion === "leer") {
    const path = texto(datos.path);
    if (!path.startsWith(`${chatId}/`) || !/^[^/]+\/[^/]+$/.test(path) || path.includes("..")) {
      throw new ErrorFuncion("invalid-argument", "Archivo inválido.");
    }
    const url = await deps.firmarLectura(path, SEGUNDOS_LECTURA);
    return { url, expiraEnSegundos: SEGUNDOS_LECTURA };
  }

  throw new ErrorFuncion("invalid-argument", "Acción inválida: usa 'subir' o 'leer'.");
}
