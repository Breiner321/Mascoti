import type { BaseDatos, DocumentoLeido, Escritura } from "./cliente_firestore.ts";
import { ErrorFuncion } from "./errores.ts";
import { type EstadoCita, puedeTransicionar } from "./estados_cita.ts";
import { actualizarCampos, agregarAArreglo, crearDocumento, HORA_SERVIDOR } from "./firestore.ts";
import { inicioEnBogota } from "./hora_bogota.ts";
import type { UsuarioFirebase } from "./registro.ts";

/**
 * Citas (RF-14), lógica de la Edge Function `citas`. Solo el servidor crea
 * citas o cambia su estado (firestore.rules no deja escribir appointments).
 *
 * Cada cambio es un commit atómico con precondición `updateTime` sobre lo que
 * se leyó (transacción optimista): si otra petición lo cambió en medio, el
 * commit falla, se vuelve a leer y se decide de nuevo. Así, de dos
 * solicitudes simultáneas al mismo horario solo una gana.
 */

export const MENSAJE_HORARIO_OCUPADO =
  "Este horario ya no está disponible, por favor selecciona otro";
export const MAX_COMENTARIO = 500;
export const MAX_MOTIVO = 300;
/** El dueño puede cancelar hasta 2 h antes de la cita (RF-14). */
export const HORAS_MINIMAS_CANCELACION = 2;
/** Tolerancia antes de marcar una cita confirmada como no_asistio (RF-14). */
export const MINUTOS_TOLERANCIA_NO_ASISTIO = 60;

const MAX_INTENTOS = 5;
const HORA_MS = 60 * 60 * 1000;

export type Actor = "dueno" | "clinica" | "sistema";

/** Un cambio guardado en una cita; RF-13 decide a quién avisar. */
export interface CambioCita {
  appointmentId: string;
  /** null si la cita es nueva. */
  antes: Record<string, unknown> | null;
  despues: Record<string, unknown>;
  actor: Actor;
}

export interface DependenciasCitas {
  db: BaseDatos;
  verificarToken(token: string): Promise<UsuarioFirebase>;
  ahora(): Date;
  /** Id para una cita nueva (igual a los de Firestore). */
  nuevoId(): string;
  /**
   * Se llama después de cada cambio guardado (avisos de RF-13). Si falla,
   * la cita igual queda guardada.
   */
  alCambiar?(cambio: CambioCita): Promise<void>;
  log?(mensaje: string): void;
}

/** Lo que usan los cambios de estado (también la tarea programada). */
export type DependenciasCambio = Pick<DependenciasCitas, "db" | "ahora" | "alCambiar" | "log">;

// ---------------------------------------------------------------------------
// Entrada
// ---------------------------------------------------------------------------

type Cuerpo = Record<string, unknown>;

const texto = (v: unknown): string => (typeof v === "string" ? v : "");

function id(cuerpo: Cuerpo, campo: string): string {
  const valor = cuerpo[campo];
  if (typeof valor !== "string" || valor.length === 0 || valor.length > 128 || valor.includes("/")) {
    throw new ErrorFuncion("invalid-argument", `Falta ${campo}.`);
  }
  return valor;
}

function motivo(cuerpo: Cuerpo, obligatorio: string | null): string | null {
  const valor = typeof cuerpo.motivo === "string" ? cuerpo.motivo.trim() : "";
  if (valor.length === 0) {
    if (obligatorio) throw new ErrorFuncion("invalid-argument", obligatorio);
    return null;
  }
  if (valor.length > MAX_MOTIVO) {
    throw new ErrorFuncion("invalid-argument", `El motivo no puede superar ${MAX_MOTIVO} caracteres.`);
  }
  return valor;
}

async function usuarioActivo(
  deps: DependenciasCitas,
  autorizacion: string | null,
): Promise<{ uid: string; perfil: Record<string, unknown> }> {
  const token = autorizacion?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) throw new ErrorFuncion("unauthenticated", "Debes iniciar sesión con Google.");
  let usuario: UsuarioFirebase;
  try {
    usuario = await deps.verificarToken(token);
  } catch {
    throw new ErrorFuncion("unauthenticated", "Debes iniciar sesión con Google.");
  }
  const perfil = (await deps.db.leer(`users/${usuario.uid}`))?.datos;
  if (!perfil) throw new ErrorFuncion("permission-denied", "Completa tu registro para continuar.");
  if (perfil.estado !== "activo") {
    throw new ErrorFuncion("permission-denied", "Tu cuenta ha sido suspendida. Contacta a soporte");
  }
  return { uid: usuario.uid, perfil };
}

/**
 * Punto de entrada de la Edge Function: `{accion, ...}` con
 * accion ∈ solicitar, responder, cancelar, completar.
 */
export async function ejecutarAccionCita(
  deps: DependenciasCitas,
  autorizacion: string | null,
  cuerpo: unknown,
): Promise<Record<string, unknown>> {
  const datos = (typeof cuerpo === "object" && cuerpo !== null ? cuerpo : {}) as Cuerpo;
  const sesion = await usuarioActivo(deps, autorizacion);
  switch (datos.accion) {
    case "solicitar":
      return { appointmentId: await solicitarCita(deps, sesion.uid, sesion.perfil, datos) };
    case "responder":
      await responderCita(deps, sesion.perfil, datos);
      return { ok: true };
    case "cancelar":
      await cancelarCita(deps, sesion.uid, sesion.perfil, datos);
      return { ok: true };
    case "completar":
      await completarCita(deps, sesion.perfil, datos);
      return { ok: true };
    default:
      throw new ErrorFuncion("invalid-argument", "Acción no válida.");
  }
}

// ---------------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------------

/** Repite [intento] mientras el commit choque con otro cambio. */
async function conReintentos<T>(intento: () => Promise<T | "conflicto">): Promise<T> {
  for (let i = 0; i < MAX_INTENTOS; i++) {
    const resultado = await intento();
    if (resultado !== "conflicto") return resultado;
  }
  throw new ErrorFuncion("aborted", "Hay muchas personas usando este horario. Intenta de nuevo.");
}

async function avisar(deps: DependenciasCambio, cambio: CambioCita): Promise<void> {
  if (!deps.alCambiar) return;
  try {
    await deps.alCambiar(cambio);
  } catch (e) {
    deps.log?.(`No se pudo avisar el cambio de la cita ${cambio.appointmentId}: ${e}`);
  }
}

function rutaSlot(cita: Record<string, unknown>): string {
  return `clinics/${texto(cita.clinicId)}/slots/${texto(cita.slotId)}`;
}

/** Cambia el estado de la franja de la cita, si todavía existe. */
async function escrituraSlot(
  deps: DependenciasCambio,
  cita: Record<string, unknown>,
  estado: "disponible" | "ocupado",
): Promise<Escritura[]> {
  const slot = await deps.db.leer(rutaSlot(cita));
  if (!slot) return [];
  return [
    actualizarCampos(deps.db.proyecto, slot.ruta, { estado }, { updateTime: slot.updateTime }),
  ];
}

/** Clínica del usuario, o error si no es una clínica. */
function clinicaDe(perfil: Record<string, unknown>): string {
  if (perfil.role !== "clinica" || typeof perfil.clinicId !== "string") {
    throw new ErrorFuncion("permission-denied", "Solo la clínica puede hacer esto.");
  }
  return perfil.clinicId;
}

async function leerCita(deps: DependenciasCitas, cuerpo: Cuerpo): Promise<DocumentoLeido> {
  const cita = await deps.db.leer(`appointments/${id(cuerpo, "appointmentId")}`);
  if (!cita) throw new ErrorFuncion("not-found", "No encontramos la cita.");
  return cita;
}

function citaDeLaClinica(cita: DocumentoLeido, clinicId: string): void {
  if (cita.datos.clinicId !== clinicId) {
    throw new ErrorFuncion("permission-denied", "Esta cita no es de tu clínica.");
  }
}

/** Mensaje cuando la cita ya no está en un estado que permita la acción. */
function yaNoSePuede(estado: unknown): ErrorFuncion {
  const mensajes: Record<string, string> = {
    confirmada: "Esta cita ya fue confirmada.",
    rechazada: "Esta solicitud ya fue rechazada.",
    cancelada: "Esta cita ya fue cancelada.",
    expirada: "Esta solicitud expiró porque pasó la hora de la cita.",
    completada: "Esta cita ya fue completada.",
    no_asistio: "Esta cita ya se marcó como no asistida.",
  };
  return new ErrorFuncion(
    "failed-precondition",
    mensajes[texto(estado)] ?? "Esta cita ya no se puede modificar.",
  );
}

/**
 * Guarda el cambio de estado de [cita] (con precondición) más [extra], y
 * avisa. "conflicto" si la cita cambió desde que se leyó.
 */
async function cambiarEstado(
  deps: DependenciasCambio,
  cita: DocumentoLeido,
  estado: EstadoCita,
  campos: Record<string, string | null>,
  extra: Escritura[],
  actor: Actor,
): Promise<"ok" | "conflicto"> {
  if (!puedeTransicionar(cita.datos.estado, estado)) throw yaNoSePuede(cita.datos.estado);
  const cambios: Record<string, string> = { estado };
  for (const [campo, valor] of Object.entries(campos)) {
    if (valor !== null) cambios[campo] = valor;
  }
  const resultado = await deps.db.commit([
    actualizarCampos(
      deps.db.proyecto,
      cita.ruta,
      { ...cambios, updatedAt: HORA_SERVIDOR },
      { updateTime: cita.updateTime },
    ),
    ...extra,
  ]);
  if (resultado === "ok") {
    await avisar(deps, {
      appointmentId: cita.id,
      antes: cita.datos,
      despues: { ...cita.datos, ...cambios, updatedAt: deps.ahora() },
      actor,
    });
  }
  return resultado;
}

// ---------------------------------------------------------------------------
// solicitar
// ---------------------------------------------------------------------------

/**
 * El dueño pide una cita (RF-14 pasos 5-6). Crea la cita 'pendiente', marca
 * la franja 'reservado_temporal' y autoriza a la clínica a ver la mascota y
 * su historial (paso 8), todo en un solo commit.
 */
export async function solicitarCita(
  deps: DependenciasCitas,
  uid: string,
  perfil: Record<string, unknown>,
  cuerpo: Cuerpo,
): Promise<string> {
  if (perfil.role !== "dueno") {
    throw new ErrorFuncion("permission-denied", "Solo los dueños de mascotas pueden solicitar citas.");
  }
  const clinicId = id(cuerpo, "clinicId");
  const serviceId = id(cuerpo, "serviceId");
  const petId = id(cuerpo, "petId");
  const slotId = id(cuerpo, "slotId");
  const comentario = typeof cuerpo.comentario === "string" ? cuerpo.comentario.trim() : "";
  if (comentario.length > MAX_COMENTARIO) {
    throw new ErrorFuncion(
      "invalid-argument",
      `El comentario no puede superar ${MAX_COMENTARIO} caracteres.`,
    );
  }

  const mascota = await deps.db.leer(`pets/${petId}`);
  if (!mascota) throw new ErrorFuncion("not-found", "No encontramos la mascota.");
  if (mascota.datos.ownerUid !== uid) {
    throw new ErrorFuncion("permission-denied", "Solo puedes pedir citas para tus mascotas.");
  }

  const clinica = await deps.db.leer(`clinics/${clinicId}`);
  if (!clinica || clinica.datos.estado !== "activo") {
    throw new ErrorFuncion(
      "failed-precondition",
      "Esta clínica no está recibiendo citas en este momento.",
    );
  }

  const servicio = await deps.db.leer(`clinics/${clinicId}/services/${serviceId}`);
  if (!servicio || servicio.datos.activo !== true) {
    throw new ErrorFuncion("failed-precondition", "Este servicio ya no está disponible.");
  }
  const precio = typeof servicio.datos.precio === "number" ? servicio.datos.precio : 0;
  const duracion = typeof servicio.datos.duracionMin === "number" ? servicio.datos.duracionMin : null;

  const appointmentId = deps.nuevoId();

  return await conReintentos(async () => {
    const slot = await deps.db.leer(`clinics/${clinicId}/slots/${slotId}`);
    if (!slot || slot.datos.estado !== "disponible") {
      throw new ErrorFuncion("aborted", MENSAJE_HORARIO_OCUPADO);
    }
    if (typeof slot.datos.serviceId === "string" && slot.datos.serviceId !== serviceId) {
      throw new ErrorFuncion("invalid-argument", "Este horario no es para el servicio seleccionado.");
    }
    // El inicio se calcula en hora de Bogotá; no se usa el `inicio` que
    // guardó el teléfono de la clínica.
    const inicio = inicioEnBogota(slot.datos.fecha, slot.datos.hora);
    if (!inicio) throw new ErrorFuncion("failed-precondition", "Este horario no es válido.");
    if (inicio.getTime() <= deps.ahora().getTime()) {
      throw new ErrorFuncion("failed-precondition", "Este horario ya pasó, por favor selecciona otro.");
    }

    const cita = {
      clinicId,
      clinicNombre: texto(clinica.datos.nombre),
      clinicOwnerUid: texto(clinica.datos.ownerUid),
      ownerUid: uid,
      ownerNombre: texto(perfil.displayName),
      petId,
      petNombre: texto(mascota.datos.nombre),
      serviceId,
      serviceNombre: texto(servicio.datos.nombre),
      precioAcordado: precio,
      duracionMin: duracion,
      slotId,
      fecha: texto(slot.datos.fecha),
      hora: texto(slot.datos.hora),
      inicio,
      comentario,
      estado: "pendiente",
    };

    const resultado = await deps.db.commit([
      crearDocumento(deps.db.proyecto, `appointments/${appointmentId}`, {
        ...cita,
        createdAt: HORA_SERVIDOR,
        updatedAt: HORA_SERVIDOR,
      }),
      actualizarCampos(
        deps.db.proyecto,
        slot.ruta,
        { estado: "reservado_temporal" },
        { updateTime: slot.updateTime },
      ),
      agregarAArreglo(deps.db.proyecto, `pets/${petId}`, "clinicasAutorizadas", [clinicId]),
    ]);
    if (resultado === "conflicto") return "conflicto";

    await avisar(deps, {
      appointmentId,
      antes: null,
      despues: { ...cita, createdAt: deps.ahora(), updatedAt: deps.ahora() },
      actor: "dueno",
    });
    return appointmentId;
  });
}

// ---------------------------------------------------------------------------
// responder
// ---------------------------------------------------------------------------

/**
 * La clínica aprueba (→ confirmada, franja 'ocupado') o rechaza con motivo
 * (→ rechazada, franja 'disponible'). RF-14 pasos 8-9.
 */
export async function responderCita(
  deps: DependenciasCitas,
  perfil: Record<string, unknown>,
  cuerpo: Cuerpo,
): Promise<void> {
  const clinicId = clinicaDe(perfil);
  if (typeof cuerpo.aprobar !== "boolean") {
    throw new ErrorFuncion("invalid-argument", "Indica si apruebas o rechazas la solicitud.");
  }
  const aprobar = cuerpo.aprobar;
  const razon = aprobar ? null : motivo(cuerpo, "Indica el motivo del rechazo.");

  await conReintentos(async () => {
    const cita = await leerCita(deps, cuerpo);
    citaDeLaClinica(cita, clinicId);
    const estado: EstadoCita = aprobar ? "confirmada" : "rechazada";
    if (!puedeTransicionar(cita.datos.estado, estado)) throw yaNoSePuede(cita.datos.estado);
    const slot = await escrituraSlot(deps, cita.datos, aprobar ? "ocupado" : "disponible");
    return await cambiarEstado(deps, cita, estado, { motivoRechazo: razon }, slot, "clinica");
  });
}

// ---------------------------------------------------------------------------
// cancelar
// ---------------------------------------------------------------------------

/**
 * Cancela una cita pendiente o confirmada y libera la franja. El dueño puede
 * hasta 2 h antes del inicio; la clínica, en cualquier momento, con motivo.
 */
export async function cancelarCita(
  deps: DependenciasCitas,
  uid: string,
  perfil: Record<string, unknown>,
  cuerpo: Cuerpo,
): Promise<void> {
  await conReintentos(async () => {
    const cita = await leerCita(deps, cuerpo);
    let actor: "dueno" | "clinica";
    if (cita.datos.ownerUid === uid) {
      actor = "dueno";
    } else if (perfil.role === "clinica" && perfil.clinicId === cita.datos.clinicId) {
      actor = "clinica";
    } else {
      throw new ErrorFuncion("permission-denied", "No puedes cancelar esta cita.");
    }
    const razon = motivo(cuerpo, actor === "clinica" ? "Indica el motivo de la cancelación." : null);

    if (!puedeTransicionar(cita.datos.estado, "cancelada")) throw yaNoSePuede(cita.datos.estado);
    if (actor === "dueno") {
      const inicio = cita.datos.inicio instanceof Date ? cita.datos.inicio.getTime() : 0;
      if (deps.ahora().getTime() > inicio - HORAS_MINIMAS_CANCELACION * HORA_MS) {
        throw new ErrorFuncion(
          "failed-precondition",
          "Solo puedes cancelar hasta 2 horas antes de la cita. Comunícate con la clínica.",
        );
      }
    }

    const slot = await escrituraSlot(deps, cita.datos, "disponible");
    return await cambiarEstado(
      deps,
      cita,
      "cancelada",
      { canceladoPor: actor, motivoCancelacion: razon },
      slot,
      actor,
    );
  });
}

// ---------------------------------------------------------------------------
// completar
// ---------------------------------------------------------------------------

/** La clínica marca la cita como atendida, solo después de su hora de inicio. */
export async function completarCita(
  deps: DependenciasCitas,
  perfil: Record<string, unknown>,
  cuerpo: Cuerpo,
): Promise<void> {
  const clinicId = clinicaDe(perfil);
  await conReintentos(async () => {
    const cita = await leerCita(deps, cuerpo);
    citaDeLaClinica(cita, clinicId);
    if (!puedeTransicionar(cita.datos.estado, "completada")) throw yaNoSePuede(cita.datos.estado);
    const inicio = cita.datos.inicio instanceof Date ? cita.datos.inicio.getTime() : Infinity;
    if (deps.ahora().getTime() < inicio) {
      throw new ErrorFuncion(
        "failed-precondition",
        "Solo puedes completar la cita después de su hora de inicio.",
      );
    }
    return await cambiarEstado(deps, cita, "completada", {}, [], "clinica");
  });
}

// ---------------------------------------------------------------------------
// Tarea programada (cada 30 min)
// ---------------------------------------------------------------------------

export interface ResultadoVencidas {
  noAsistio: number;
  expiradas: number;
}

/**
 * - Confirmadas con más de 60 min de vencidas → 'no_asistio' (RF-14).
 * - Pendientes cuyo inicio ya pasó → 'expirada' y franja liberada (no lo dice
 *   el RF; evita franjas bloqueadas para siempre si la clínica no responde).
 * Si otra petición cambió la cita en medio, se deja para la próxima vez.
 */
export async function procesarCitasVencidas(
  deps: DependenciasCambio,
  limite = 200,
): Promise<ResultadoVencidas> {
  const ahora = deps.ahora().getTime();
  const resultado: ResultadoVencidas = { noAsistio: 0, expiradas: 0 };

  const confirmadas = await deps.db.consultar({
    coleccion: "appointments",
    filtros: [
      { campo: "estado", op: "EQUAL", valor: "confirmada" },
      {
        campo: "inicio",
        op: "LESS_THAN",
        valor: new Date(ahora - MINUTOS_TOLERANCIA_NO_ASISTIO * 60 * 1000),
      },
    ],
    ordenarPor: "inicio",
    limite,
  });
  for (const cita of confirmadas) {
    if (await cambiarEstado(deps, cita, "no_asistio", {}, [], "sistema") === "ok") {
      resultado.noAsistio++;
    }
  }

  const pendientes = await deps.db.consultar({
    coleccion: "appointments",
    filtros: [
      { campo: "estado", op: "EQUAL", valor: "pendiente" },
      { campo: "inicio", op: "LESS_THAN", valor: new Date(ahora) },
    ],
    ordenarPor: "inicio",
    limite,
  });
  for (const cita of pendientes) {
    const slot = await escrituraSlot(deps, cita.datos, "disponible");
    if (await cambiarEstado(deps, cita, "expirada", {}, slot, "sistema") === "ok") {
      resultado.expiradas++;
    }
  }
  return resultado;
}
