import type { BaseDatos, DocumentoLeido } from "./cliente_firestore.ts";
import { ErrorFuncion } from "./errores.ts";
import { camposFirestore, type EscrituraFirestore, rutaDocumento } from "./firestore.ts";
import { nombreVisible } from "./nombres.ts";
import { enviarPushAUsuario, type MensajePush, type ResultadoPush } from "./notificaciones.ts";
import type { UsuarioFirebase } from "./registro.ts";

/**
 * Push de un mensaje del chat (RF-15). La app llama a la Edge Function
 * `notificar-mensaje` después de enviar; si falla, el mensaje igual quedó
 * enviado (lo escribe la app en Firestore, con el contador `noLeidos` del
 * receptor en el mismo lote validado por las reglas).
 *
 * - Verifica que quien llama es participante y emisor del mensaje.
 * - No envía si el receptor ya lo leyó (tenía la conversación abierta).
 * - Agrupa ráfagas: máximo un push por conversación y receptor cada
 *   [SEGUNDOS_AGRUPAR] (`chats.ultimoPush.{uid}`); con la etiqueta de Android
 *   = chatId cada push reemplaza al anterior en la bandeja.
 * - No crea documento en `notifications`: el chat tiene su propio contador.
 */

export const SEGUNDOS_AGRUPAR = 30;
export const LARGO_VISTA_PREVIA = 100;
export const CUERPO_ADJUNTO = "📎 Archivo adjunto";

const ID_CHAT = /^[A-Za-z0-9]{1,128}_[A-Za-z0-9]{1,128}$/;
const ID_MENSAJE = /^[A-Za-z0-9]{1,40}$/;

export interface DependenciasMensajes {
  db: BaseDatos;
  verificarToken(token: string): Promise<UsuarioFirebase>;
  enviarPush(token: string, mensaje: MensajePush): Promise<ResultadoPush>;
  ahora(): Date;
  log?(mensaje: string): void;
}

export type ResultadoMensaje =
  | { enviado: true; dispositivos: number }
  | { enviado: false; motivo: "leido" | "agrupado" };

const texto = (v: unknown): string => (typeof v === "string" ? v : "");

/** Vista previa en una línea (igual a ChatLimits.preview en Dart). */
export function vistaPrevia(valor: string): string {
  const linea = valor.trim().replace(/\s+/g, " ");
  return linea.length <= LARGO_VISTA_PREVIA ? linea : `${linea.slice(0, LARGO_VISTA_PREVIA - 1)}…`;
}

/** Cuerpo del push: la vista previa y, si hay varios sin leer, cuántos. */
export function cuerpoPush(mensaje: Record<string, unknown>, noLeidos: number): string {
  const previa = mensaje.tipo === "adjunto" ? CUERPO_ADJUNTO : vistaPrevia(texto(mensaje.texto));
  return noLeidos > 1 ? `${noLeidos} mensajes nuevos · ${previa}` : previa;
}

export async function notificarMensaje(
  deps: DependenciasMensajes,
  autorizacion: string | null,
  cuerpo: unknown,
): Promise<ResultadoMensaje> {
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
  const messageId = texto(datos.messageId);
  if (!ID_CHAT.test(chatId) || !ID_MENSAJE.test(messageId)) {
    throw new ErrorFuncion("invalid-argument", "Mensaje inválido.");
  }

  const perfil = await deps.db.leer(`users/${usuario.uid}`);
  if (!perfil || perfil.datos.estado !== "activo") {
    throw new ErrorFuncion("permission-denied", "No tienes permiso para escribir en este chat.");
  }
  let chat = await deps.db.leer(`chats/${chatId}`);
  const participantes = chat?.datos.participantes;
  if (!chat || !Array.isArray(participantes) || !participantes.includes(usuario.uid)) {
    throw new ErrorFuncion("permission-denied", "No tienes permiso para escribir en este chat.");
  }
  const mensaje = await deps.db.leer(`chats/${chatId}/messages/${messageId}`);
  if (!mensaje) throw new ErrorFuncion("not-found", "El mensaje no existe.");
  if (mensaje.datos.senderUid !== usuario.uid) {
    throw new ErrorFuncion("permission-denied", "Solo quien envió el mensaje puede notificarlo.");
  }

  const receptor = texto(participantes[0] === usuario.uid ? participantes[1] : participantes[0]);
  if (mensaje.datos.leido === true) return { enviado: false, motivo: "leido" };

  // Reserva el turno de push con precondición: si el chat cambió (otro
  // mensaje, "escribiendo…"), se vuelve a leer y se decide de nuevo.
  for (let intento = 0; ; intento++) {
    const estado = turnoDePush(chat, receptor, deps.ahora());
    if (estado !== "libre") return { enviado: false, motivo: estado };
    const reserva = await deps.db.commit([
      reservarPush(deps.db.proyecto, chatId, receptor, deps.ahora(), chat.updateTime),
    ]);
    if (reserva === "ok") break;
    if (intento >= 2) return { enviado: false, motivo: "agrupado" };
    chat = await deps.db.leer(`chats/${chatId}`);
    if (!chat) throw new ErrorFuncion("not-found", "El chat no existe.");
  }

  const noLeidos = numero(mapa(chat.datos.noLeidos)[receptor]) ?? 1;
  const titulo = await nombreEmisor(deps.db, chat, usuario.uid, perfil.datos);
  const { enviados } = await enviarPushAUsuario(deps, receptor, {
    titulo,
    cuerpo: cuerpoPush(mensaje.datos, noLeidos),
    datos: { tipo: "mensaje", referenciaId: chatId },
    prioridadAlta: false,
    etiqueta: chatId,
  });
  return { enviado: true, dispositivos: enviados };
}

/** `ultimoPush.{receptor}` = [hora], solo si el chat no cambió desde [updateTime]. */
export function reservarPush(
  proyecto: string,
  chatId: string,
  receptor: string,
  hora: Date,
  updateTime: string,
): EscrituraFirestore {
  return {
    update: {
      name: rutaDocumento(proyecto, `chats/${chatId}`),
      fields: camposFirestore({ ultimoPush: { [receptor]: hora } }),
    },
    // Solo esa clave del mapa: no toca los demás campos ni el otro participante.
    updateMask: { fieldPaths: [`ultimoPush.${receptor}`] },
    currentDocument: { updateTime },
  };
}

function mapa(v: unknown): Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v) ? v as Record<string, unknown> : {};
}

function numero(v: unknown): number | undefined {
  return typeof v === "number" ? v : undefined;
}

/** "leido" si el receptor ya no tiene pendientes; "agrupado" si hubo push hace poco. */
function turnoDePush(chat: DocumentoLeido, receptor: string, ahora: Date): "libre" | "leido" | "agrupado" {
  if (numero(mapa(chat.datos.noLeidos)[receptor]) === 0) return "leido";
  const ultimo = mapa(chat.datos.ultimoPush)[receptor];
  if (ultimo instanceof Date && ahora.getTime() - ultimo.getTime() < SEGUNDOS_AGRUPAR * 1000) {
    return "agrupado";
  }
  return "libre";
}

/** Nombre visible del emisor (Cambio 1): el comercial si es la clínica. */
async function nombreEmisor(
  db: BaseDatos,
  chat: DocumentoLeido,
  uid: string,
  perfil: Record<string, unknown>,
): Promise<string> {
  if (uid === chat.datos.clinicOwnerUid) {
    const clinica = await db.leer(`clinics/${texto(chat.datos.clinicId)}`);
    return texto(clinica?.datos.nombre) || texto(chat.datos.clinicNombre) || "Tu veterinaria";
  }
  return nombreVisible(perfil);
}
