import type { BaseDatos } from "./cliente_firestore.ts";
import type { CambioCita } from "./citas.ts";
import { actualizarCampos, crearDocumento, HORA_SERVIDOR } from "./firestore.ts";
import { fechaBogota, inicioDelDia, sumarDias } from "./hora_bogota.ts";

/**
 * Notificaciones (RF-13). Toda notificación se guarda en `notifications`
 * (centro de notificaciones de la app, con badge) y además se envía como
 * push a los dispositivos válidos del usuario. Sin permiso de push o sin
 * dispositivos, el documento igual queda.
 */

/** Igual a NotificationType en lib/core/notificaciones. */
export type TipoNotificacion =
  | "cita_nueva"
  | "cita_aprobada"
  | "cita_rechazada"
  | "cita_cancelada"
  | "recordatorio_cita"
  | "vacuna";

export interface Aviso {
  uid: string;
  tipo: TipoNotificacion;
  titulo: string;
  cuerpo: string;
  /** Cita (appointmentId) o, para vacunas, la mascota (petId). */
  referenciaId: string;
  /** Push con prioridad alta (cancelación de la clínica). */
  prioridadAlta?: boolean;
  /**
   * Id del documento en `notifications`. Si se repite, no se crea otro ni se
   * envía otro push (evita duplicados si una tarea se ejecuta dos veces).
   */
  id?: string;
}

export interface MensajePush {
  titulo: string;
  cuerpo: string;
  datos: Record<string, string>;
  prioridadAlta: boolean;
}

export type ResultadoPush = "ok" | "token-invalido";

export interface DependenciasNotificaciones {
  db: BaseDatos;
  /** Envía un push a un token (FCM HTTP v1). */
  enviarPush(token: string, mensaje: MensajePush): Promise<ResultadoPush>;
  ahora(): Date;
  /** Id para notificaciones sin id fijo. */
  nuevoId(): string;
  log?(mensaje: string): void;
}

// ---------------------------------------------------------------------------
// Textos
// ---------------------------------------------------------------------------

const DIAS = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"];
const MESES = [
  "enero", "febrero", "marzo", "abril", "mayo", "junio",
  "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
];

/** '2026-11-05' → 'jueves 5 de noviembre'. */
export function fechaLegible(fecha: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(fecha);
  if (!m) return fecha;
  const dia = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
  return `${DIAS[dia.getUTCDay()]} ${dia.getUTCDate()} de ${MESES[dia.getUTCMonth()]}`;
}

/** '13:50' → '1:50 p. m.' (igual a TimeFormat.hour en Dart). */
export function horaLegible(hora: string): string {
  const m = /^(\d{1,2}):(\d{2})$/.exec(hora);
  if (!m) return hora;
  const h = Number(m[1]);
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${m[2]} ${h < 12 ? "a. m." : "p. m."}`;
}

const t = (v: unknown): string => (typeof v === "string" ? v : "");

/** Cierra la frase con punto, sin duplicarlo después de "a. m." / "p. m.". */
function frase(texto: string): string {
  return texto.endsWith(".") ? texto : `${texto}.`;
}

function cuando(cita: Record<string, unknown>): string {
  return `el ${fechaLegible(t(cita.fecha))} a las ${horaLegible(t(cita.hora))}`;
}

// ---------------------------------------------------------------------------
// Qué avisar cuando cambia una cita (reemplaza al trigger onDocumentUpdated)
// ---------------------------------------------------------------------------

/**
 * Avisos que produce un cambio de una cita (RF-14 paso 11 y flujos
 * alternos). Función pura: se prueba sin red.
 *
 * - Nueva solicitud → la clínica.
 * - Confirmada / rechazada (con motivo) → el dueño.
 * - Cancelada por la clínica → el dueño, prioridad alta, sugiere reagendar.
 * - Cancelada por el dueño → la clínica.
 * - Cambios del sistema (no asistió, expirada) → nadie.
 */
export function avisosPorCambio(cambio: CambioCita): Aviso[] {
  const { antes, despues, appointmentId: referenciaId } = cambio;
  const mascota = t(despues.petNombre);
  const clinica = t(despues.clinicNombre);
  const dueno = t(despues.ownerNombre) || "Un cliente";
  const uidDueno = t(despues.ownerUid);
  const uidClinica = t(despues.clinicOwnerUid);

  if (antes === null) {
    if (despues.estado !== "pendiente" || !uidClinica) return [];
    return [{
      uid: uidClinica,
      tipo: "cita_nueva",
      titulo: "Nueva solicitud de cita",
      cuerpo: frase(`${dueno} pidió ${t(despues.serviceNombre)} para ${mascota} ${cuando(despues)}`),
      referenciaId,
    }];
  }

  if (antes.estado === despues.estado || cambio.actor === "sistema") return [];

  switch (despues.estado) {
    case "confirmada":
      return [{
        uid: uidDueno,
        tipo: "cita_aprobada",
        titulo: "¡Cita confirmada!",
        cuerpo: frase(`${clinica} confirmó la cita de ${mascota} ${cuando(despues)}`),
        referenciaId,
      }];
    case "rechazada":
      return [{
        uid: uidDueno,
        tipo: "cita_rechazada",
        titulo: "Solicitud de cita rechazada",
        cuerpo: `${clinica} no pudo aceptar la cita de ${mascota}. Motivo: ${t(despues.motivoRechazo)}`,
        referenciaId,
      }];
    case "cancelada":
      if (cambio.actor === "clinica") {
        return [{
          uid: uidDueno,
          tipo: "cita_cancelada",
          titulo: "La clínica canceló tu cita",
          cuerpo: `${clinica} canceló la cita de ${mascota} del ${fechaLegible(t(despues.fecha))}. ` +
            `Motivo: ${t(despues.motivoCancelacion)}. Te sugerimos reagendar.`,
          referenciaId,
          prioridadAlta: true,
        }];
      }
      if (!uidClinica) return [];
      return [{
        uid: uidClinica,
        tipo: "cita_cancelada",
        titulo: "Cita cancelada por el dueño",
        cuerpo: `${frase(`${dueno} canceló la cita de ${mascota} ${cuando(despues)}`)} El horario quedó libre.`,
        referenciaId,
      }];
    default:
      return [];
  }
}

// ---------------------------------------------------------------------------
// Envío
// ---------------------------------------------------------------------------

export interface ResultadoEnvio {
  notificationId: string;
  /** false si ya existía (no se envió de nuevo). */
  creada: boolean;
  enviados: number;
  invalidos: number;
}

/**
 * Crea SIEMPRE el documento en `notifications` y luego envía el push a cada
 * dispositivo válido del usuario. Un token que FCM rechaza como inválido se
 * marca `valido: false` (la app lo vuelve a registrar al iniciar sesión).
 */
export async function enviarNotificacion(
  deps: DependenciasNotificaciones,
  aviso: Aviso,
): Promise<ResultadoEnvio> {
  const notificationId = aviso.id ?? deps.nuevoId();
  const creada = await deps.db.commit([
    crearDocumento(deps.db.proyecto, `notifications/${notificationId}`, {
      uid: aviso.uid,
      tipo: aviso.tipo,
      titulo: aviso.titulo,
      cuerpo: aviso.cuerpo,
      referenciaId: aviso.referenciaId,
      leido: false,
      createdAt: HORA_SERVIDOR,
    }),
  ]);
  if (creada === "conflicto") {
    return { notificationId, creada: false, enviados: 0, invalidos: 0 };
  }

  const dispositivos = await deps.db.consultar({
    padre: `users/${aviso.uid}`,
    coleccion: "devices",
    filtros: [],
  });
  const mensaje: MensajePush = {
    titulo: aviso.titulo,
    cuerpo: aviso.cuerpo,
    datos: { tipo: aviso.tipo, referenciaId: aviso.referenciaId, notificationId },
    prioridadAlta: aviso.prioridadAlta ?? false,
  };

  let enviados = 0;
  let invalidos = 0;
  for (const dispositivo of dispositivos) {
    const token = dispositivo.datos.fcmToken;
    if (typeof token !== "string" || token.length === 0 || dispositivo.datos.valido === false) continue;
    try {
      if (await deps.enviarPush(token, mensaje) === "ok") {
        enviados++;
        continue;
      }
      invalidos++;
      await deps.db.commit([
        actualizarCampos(deps.db.proyecto, dispositivo.ruta, { valido: false, updatedAt: HORA_SERVIDOR }),
      ]);
    } catch (e) {
      // Un error temporal de FCM no invalida el token ni detiene a los demás.
      deps.log?.(`Push a ${dispositivo.ruta} falló: ${e}`);
    }
  }
  return { notificationId, creada: true, enviados, invalidos };
}

/** Envía todos los avisos de un cambio de cita; los errores solo se registran. */
export async function notificarCambioCita(
  deps: DependenciasNotificaciones,
  cambio: CambioCita,
): Promise<void> {
  for (const aviso of avisosPorCambio(cambio)) {
    if (!aviso.uid) continue;
    try {
      await enviarNotificacion(deps, aviso);
    } catch (e) {
      deps.log?.(`No se pudo notificar ${aviso.tipo} a ${aviso.uid}: ${e}`);
    }
  }
}

/** Canales de Android (los crea la app en PushMessaging). */
export const CANAL_GENERAL = "mascoti_general";
export const CANAL_URGENTE = "mascoti_urgente";

/**
 * Respuesta de error de FCM HTTP v1 → ¿el token ya no sirve? UNREGISTERED
 * (app desinstalada o token borrado), SENDER_ID_MISMATCH (token de otro
 * proyecto) o un token mal formado. Otros errores (cuota, servidor) no
 * invalidan el token.
 */
export function esTokenInvalido(estado: number, texto: string): boolean {
  if (/UNREGISTERED|SENDER_ID_MISMATCH/.test(texto)) return true;
  if (estado === 404) return true;
  return estado === 400 && /registration token/i.test(texto);
}

/** Cuerpo de `messages:send` de FCM HTTP v1. */
export function mensajeFcm(token: string, mensaje: MensajePush): Record<string, unknown> {
  return {
    message: {
      token,
      notification: { title: mensaje.titulo, body: mensaje.cuerpo },
      data: mensaje.datos,
      android: {
        priority: mensaje.prioridadAlta ? "HIGH" : "NORMAL",
        notification: {
          channel_id: mensaje.prioridadAlta ? CANAL_URGENTE : CANAL_GENERAL,
          ...(mensaje.prioridadAlta ? { notification_priority: "PRIORITY_MAX" } : {}),
        },
      },
    },
  };
}

// ---------------------------------------------------------------------------
// Tarea diaria de las 8:00 a. m. (hora de Colombia)
// ---------------------------------------------------------------------------

export interface ResultadoRecordatorios {
  citas: number;
  vacunas: number;
}

/** Días hacia adelante para avisar una próxima dosis (RF-13 paso 2). */
export const DIAS_AVISO_VACUNA = 3;

/**
 * RF-13: recordatorio de las citas confirmadas de mañana y de las vacunas
 * con próxima dosis entre hoy y dentro de 3 días. Si se ejecuta dos veces el
 * mismo día no duplica: el id de la notificación es fijo
 * (`recordatorio_{citaId}`, `vacuna_{id}`) y la vacuna queda `notificado`.
 * Las citas canceladas no salen porque solo se buscan las 'confirmada'.
 */
export async function enviarRecordatoriosDiarios(
  deps: DependenciasNotificaciones,
  limite = 500,
): Promise<ResultadoRecordatorios> {
  const ahora = deps.ahora();
  const resultado: ResultadoRecordatorios = { citas: 0, vacunas: 0 };

  const desde = inicioDelDia(sumarDias(ahora, 1));
  const hasta = inicioDelDia(sumarDias(ahora, 2));
  const citas = await deps.db.consultar({
    coleccion: "appointments",
    filtros: [
      { campo: "estado", op: "EQUAL", valor: "confirmada" },
      { campo: "inicio", op: "GREATER_THAN_OR_EQUAL", valor: desde },
      { campo: "inicio", op: "LESS_THAN", valor: hasta },
    ],
    ordenarPor: "inicio",
    limite,
  });
  for (const cita of citas) {
    const c = cita.datos;
    const envio = await enviarNotificacion(deps, {
      id: `recordatorio_${cita.id}`,
      uid: t(c.ownerUid),
      tipo: "recordatorio_cita",
      titulo: "Tu cita es mañana",
      cuerpo: frase(`${t(c.petNombre)} tiene ${t(c.serviceNombre)} en ${t(c.clinicNombre)} ` +
        `mañana a las ${horaLegible(t(c.hora))}`),
      referenciaId: cita.id,
    });
    if (envio.creada) resultado.citas++;
  }

  const hoy = inicioDelDia(fechaBogota(ahora));
  const limiteVacunas = inicioDelDia(sumarDias(ahora, DIAS_AVISO_VACUNA + 1));
  const vacunas = await deps.db.consultar({
    coleccion: "vacunasProgramadas",
    filtros: [
      { campo: "notificado", op: "EQUAL", valor: false },
      { campo: "fechaProximaDosis", op: "GREATER_THAN_OR_EQUAL", valor: hoy },
      { campo: "fechaProximaDosis", op: "LESS_THAN", valor: limiteVacunas },
    ],
    ordenarPor: "fechaProximaDosis",
    limite,
  });
  const nombres = new Map<string, string>();
  for (const dosis of vacunas) {
    const v = dosis.datos;
    const petId = t(v.petId);
    if (!nombres.has(petId)) {
      nombres.set(petId, t((await deps.db.leer(`pets/${petId}`))?.datos.nombre) || "Tu mascota");
    }
    const fecha = v.fechaProximaDosis instanceof Date ? fechaBogota(v.fechaProximaDosis) : "";
    const envio = await enviarNotificacion(deps, {
      id: `vacuna_${dosis.id}`,
      uid: t(v.ownerUid),
      tipo: "vacuna",
      titulo: "Se acerca una vacuna",
      cuerpo: `A ${nombres.get(petId)} le toca la próxima dosis de ${t(v.vacuna)} ` +
        `el ${fechaLegible(fecha)}.`,
      referenciaId: petId,
    });
    await deps.db.commit([
      actualizarCampos(deps.db.proyecto, dosis.ruta, { notificado: true }),
    ]);
    if (envio.creada) resultado.vacunas++;
  }
  return resultado;
}
