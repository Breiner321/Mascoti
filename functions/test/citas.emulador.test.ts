/**
 * Edge Function `citas` (RF-14) contra el emulador de Firestore, con la misma
 * API REST que usa en producción. Requieren el emulador:
 *   cd functions && npm run test:rules
 * Con `npm test` (sin emulador) se omiten.
 *
 * Usan su propio proyecto (demo-mascoti-citas) para no chocar con las pruebas
 * de reglas, que borran demo-mascoti antes de cada caso.
 */
import { beforeEach, describe, expect, it } from "vitest";

import {
  type CambioCita,
  type DependenciasCitas,
  ejecutarAccionCita,
  MENSAJE_HORARIO_OCUPADO,
  procesarCitasVencidas,
} from "../../supabase/functions/_shared/citas.ts";
import { ClienteFirestore } from "../../supabase/functions/_shared/cliente_firestore.ts";
import { ErrorFuncion } from "../../supabase/functions/_shared/errores.ts";
import {
  camposFirestore,
  rutaDocumento,
  type ValorCampo,
} from "../../supabase/functions/_shared/firestore.ts";

const host = process.env.FIRESTORE_EMULATOR_HOST;
const PROYECTO = "demo-mascoti-citas";

/** 1 de noviembre de 2026, 10:00 a. m. en Bogotá. */
const AHORA = new Date("2026-11-01T15:00:00Z");
const MINUTO = 60 * 1000;

describe.skipIf(!host)("Edge Function citas (emulador)", () => {
  const db = new ClienteFirestore(PROYECTO, `http://${host}/v1`, async () => "owner");
  let ahora: Date;
  let cambios: CambioCita[];
  let ids: number;
  let deps: DependenciasCitas;

  async function poner(ruta: string, campos: { [campo: string]: ValorCampo }) {
    await db.commit([{ update: { name: rutaDocumento(PROYECTO, ruta), fields: camposFirestore(campos) } }]);
  }

  async function leer(ruta: string) {
    return (await db.leer(ruta))?.datos;
  }

  /** Ejecuta una acción como [uid] (el "token" de prueba es el uid). */
  function como(uid: string, cuerpo: Record<string, unknown>) {
    return ejecutarAccionCita(deps, `Bearer ${uid}`, cuerpo);
  }

  const solicitud = {
    accion: "solicitar",
    clinicId: "c1",
    serviceId: "s1",
    petId: "p1",
    slotId: "2026-11-05_09:30",
    comentario: " Vómito desde ayer ",
  };

  async function error(promesa: Promise<unknown>): Promise<ErrorFuncion> {
    try {
      await promesa;
    } catch (e) {
      if (e instanceof ErrorFuncion) return e;
      throw e;
    }
    throw new Error("Se esperaba ErrorFuncion");
  }

  async function slotEstado(slotId = solicitud.slotId) {
    return (await leer(`clinics/c1/slots/${slotId}`))?.estado;
  }

  /** Crea una cita en [estado] por el flujo real. */
  async function citaEn(estado: "pendiente" | "confirmada"): Promise<string> {
    const { appointmentId } = await como("ana", solicitud) as { appointmentId: string };
    if (estado === "confirmada") {
      await como("vet", { accion: "responder", appointmentId, aprobar: true });
    }
    return appointmentId;
  }

  beforeEach(async () => {
    await fetch(`http://${host}/emulator/v1/projects/${PROYECTO}/databases/(default)/documents`, {
      method: "DELETE",
    });
    ahora = AHORA;
    cambios = [];
    ids = 0;
    deps = {
      db,
      verificarToken: async (token) => ({ uid: token }),
      ahora: () => ahora,
      nuevoId: () => `cita${++ids}`,
      alCambiar: async (cambio) => {
        cambios.push(cambio);
      },
    };

    // Cambio 1: la cita copia `nombre`, no el nombre de Google ni el correo.
    await poner("users/ana", {
      role: "dueno", estado: "activo", nombre: "Ana Pérez", displayName: "ana.p", email: "ana@gmail.com",
    });
    // Registrado antes del Cambio 1 (sin nombre): se usa el de Google.
    await poner("users/beto", { role: "dueno", estado: "activo", displayName: "Beto", email: "beto@gmail.com" });
    await poner("users/susp", { role: "dueno", estado: "suspendido" });
    await poner("users/vet", { role: "clinica", estado: "activo", clinicId: "c1" });
    await poner("users/vet2", { role: "clinica", estado: "activo", clinicId: "c2" });
    // Cambio 2: lunes a sábado de 8:00 a 12:00 con descanso de 10:00 a 10:30.
    const dia = { abierto: true, apertura: "08:00", cierre: "12:00", descansoInicio: "10:00", descansoFin: "10:30" };
    await poner("clinics/c1", {
      ownerUid: "vet", nombre: "Vet Norte", estado: "activo",
      horarioSemanal: { lun: dia, mar: dia, mie: dia, jue: dia, vie: dia, sab: dia, dom: { abierto: false } },
      reservas: { duracionSlotMin: 30, anticipacionMaxDias: 30, anticipacionMinMin: 120 },
    });
    await poner("clinics/c2", { ownerUid: "vet2", nombre: "Vet Sur", estado: "activo" });
    await poner("clinics/c1/services/s1", {
      nombre: "Consulta general", precio: 45000, duracionMin: 30, activo: true,
    });
    await poner("clinics/c1/services/s2", { nombre: "Baño", precio: 30000, activo: false });
    await poner("clinics/c1/services/s60", { nombre: "Cirugía menor", precio: 90000, duracionMin: 60, activo: true });
    // Franja de antes del Cambio 2 (creada por la clínica): sigue sirviendo.
    await poner("clinics/c1/slots/2026-11-05_09:30", {
      fecha: "2026-11-05", hora: "09:30", serviceId: "s1", estado: "disponible",
      // Un teléfono en otra zona horaria pudo guardar mal el inicio: no se usa.
      inicio: new Date("2026-11-05T09:30:00Z"),
    });
    await poner("pets/p1", { ownerUid: "ana", nombre: "Luna", especie: "perro", clinicasAutorizadas: [] });
    await poner("pets/p2", { ownerUid: "beto", nombre: "Max", especie: "gato", clinicasAutorizadas: [] });
  });

  describe("solicitar", () => {
    it("crea la cita pendiente, aparta la franja y autoriza a la clínica", async () => {
      const r = await como("ana", solicitud);
      expect(r).toEqual({ appointmentId: "cita1" });

      const cita = (await leer("appointments/cita1"))!;
      expect(cita).toMatchObject({
        estado: "pendiente",
        clinicId: "c1",
        clinicNombre: "Vet Norte",
        clinicOwnerUid: "vet",
        ownerUid: "ana",
        ownerNombre: "Ana Pérez",
        petId: "p1",
        petNombre: "Luna",
        serviceId: "s1",
        serviceNombre: "Consulta general",
        precioAcordado: 45000,
        duracionMin: 30,
        slotId: "2026-11-05_09:30",
        fecha: "2026-11-05",
        hora: "09:30",
        comentario: "Vómito desde ayer",
      });
      // 9:30 a. m. en Bogotá = 14:30 UTC.
      expect((cita.inicio as Date).toISOString()).toBe("2026-11-05T14:30:00.000Z");
      expect(cita.createdAt).toBeInstanceOf(Date);
      expect(await slotEstado()).toBe("reservado_temporal");
      expect((await leer("pets/p1"))!.clinicasAutorizadas).toEqual(["c1"]);
      expect(cambios).toHaveLength(1);
      expect(cambios[0]).toMatchObject({ appointmentId: "cita1", antes: null, actor: "dueno" });
    });

    it("carrera: dos solicitudes simultáneas al mismo horario → solo una gana", async () => {
      const resultados = await Promise.allSettled([
        como("ana", solicitud),
        como("beto", { ...solicitud, petId: "p2" }),
      ]);

      const ganadas = resultados.filter((r) => r.status === "fulfilled");
      const perdidas = resultados.filter((r) => r.status === "rejected") as PromiseRejectedResult[];
      expect(ganadas).toHaveLength(1);
      expect(perdidas).toHaveLength(1);
      expect(perdidas[0].reason).toBeInstanceOf(ErrorFuncion);
      expect(perdidas[0].reason.codigo).toBe("aborted");
      expect(perdidas[0].reason.message).toBe(MENSAJE_HORARIO_OCUPADO);

      const citas = await db.consultar({ coleccion: "appointments", filtros: [] });
      expect(citas).toHaveLength(1);
      expect(await slotEstado()).toBe("reservado_temporal");
      // Solo la mascota del ganador quedó autorizada.
      const autorizadas = [
        ...((await leer("pets/p1"))!.clinicasAutorizadas as string[]),
        ...((await leer("pets/p2"))!.clinicasAutorizadas as string[]),
      ];
      expect(autorizadas).toEqual(["c1"]);
    });

    it("Cambio 1: sin nombre propio usa el de Google, nunca el correo", async () => {
      const { appointmentId } = await como("beto", { ...solicitud, petId: "p2" }) as { appointmentId: string };
      expect((await leer(`appointments/${appointmentId}`))!.ownerNombre).toBe("Beto");
    });

    it("horario ya apartado → mensaje del RF", async () => {
      await como("ana", solicitud);
      const e = await error(como("beto", { ...solicitud, petId: "p2" }));
      expect(e.codigo).toBe("aborted");
      expect(e.message).toBe("Este horario ya no está disponible, por favor selecciona otro");
    });

    it("validaciones de dueño, mascota, clínica, servicio y franja", async () => {
      expect((await error(como("beto", solicitud))).codigo).toBe("permission-denied"); // mascota ajena
      expect((await error(como("vet", solicitud))).codigo).toBe("permission-denied"); // una clínica
      expect((await error(como("susp", solicitud))).message).toContain("suspendida");
      expect((await error(ejecutarAccionCita(deps, null, solicitud))).codigo).toBe("unauthenticated");
      expect((await error(como("ana", { ...solicitud, petId: "nada" }))).codigo).toBe("not-found");
      expect((await error(como("ana", { ...solicitud, serviceId: "s2" }))).message)
        .toBe("Este servicio ya no está disponible.");
      expect((await error(como("ana", { ...solicitud, clinicId: "c2" }))).codigo)
        .toBe("failed-precondition"); // c2 no tiene ese servicio
      // Cambio 2: en el descanso o fuera del horario no se puede.
      expect((await error(como("ana", { ...solicitud, slotId: "2026-11-05_10:00" }))).codigo)
        .toBe("aborted");
      expect((await error(como("ana", { ...solicitud, slotId: "2026-11-05_15:00" }))).message)
        .toBe(MENSAJE_HORARIO_OCUPADO);
      expect((await error(como("ana", { ...solicitud, slotId: "2026-11-08_09:00" }))).codigo)
        .toBe("aborted"); // domingo, cerrado
      expect((await error(como("ana", { ...solicitud, comentario: "x".repeat(501) }))).codigo)
        .toBe("invalid-argument");
      expect((await error(como("ana", { ...solicitud, petId: "../x" }))).codigo).toBe("invalid-argument");
      expect((await error(como("ana", { accion: "borrar" }))).codigo).toBe("invalid-argument");

      ahora = new Date("2026-11-05T14:30:00Z");
      expect((await error(como("ana", solicitud))).message)
        .toBe("Este horario ya pasó, por favor selecciona otro.");

      expect(await slotEstado()).toBe("disponible");
      expect(cambios).toHaveLength(0);
    });
  });

  describe("Cambio 2: disponibilidad según el horario", () => {
    it("sin franja creada: se reserva dentro del horario y se crea el candado", async () => {
      const { appointmentId } = await como("ana", {
        ...solicitud, slotId: undefined, fecha: "2026-11-05", hora: "08:00",
      }) as { appointmentId: string };
      const cita = (await leer(`appointments/${appointmentId}`))!;
      expect(cita).toMatchObject({ slotId: "2026-11-05_08:00", slotIds: ["2026-11-05_08:00"], hora: "08:00" });
      expect(await leer("clinics/c1/slots/2026-11-05_08:00")).toMatchObject({
        fecha: "2026-11-05", hora: "08:00", estado: "reservado_temporal", appointmentId,
      });
    });

    it("un servicio de 60 min aparta 2 franjas y las libera al cancelar", async () => {
      const { appointmentId } = await como("ana", {
        ...solicitud, serviceId: "s60", slotId: "2026-11-05_08:30",
      }) as { appointmentId: string };
      expect((await leer(`appointments/${appointmentId}`))!.slotIds)
        .toEqual(["2026-11-05_08:30", "2026-11-05_09:00"]);
      expect(await slotEstado("2026-11-05_08:30")).toBe("reservado_temporal");
      expect(await slotEstado("2026-11-05_09:00")).toBe("reservado_temporal");

      // Ya no cabe un servicio de 30 min a las 9:00.
      const e = await error(como("beto", { ...solicitud, petId: "p2", slotId: "2026-11-05_09:00" }));
      expect(e.message).toBe(MENSAJE_HORARIO_OCUPADO);

      await como("vet", { accion: "responder", appointmentId, aprobar: true });
      expect(await slotEstado("2026-11-05_09:00")).toBe("ocupado");

      await como("ana", { accion: "cancelar", appointmentId });
      expect(await slotEstado("2026-11-05_08:30")).toBe("disponible");
      expect((await leer("clinics/c1/slots/2026-11-05_09:00"))!.appointmentId).toBeUndefined();
      // Y se puede volver a reservar.
      await como("beto", { ...solicitud, petId: "p2", slotId: "2026-11-05_09:00" });
    });

    it("carrera entre servicios que se solapan (60 min a las 8:30 y 30 min a las 9:00): solo uno gana", async () => {
      const resultados = await Promise.allSettled([
        como("ana", { ...solicitud, serviceId: "s60", slotId: "2026-11-05_08:30" }),
        como("beto", { ...solicitud, petId: "p2", slotId: "2026-11-05_09:00" }),
      ]);
      expect(resultados.filter((r) => r.status === "fulfilled")).toHaveLength(1);
      const [perdida] = resultados.filter((r) => r.status === "rejected") as PromiseRejectedResult[];
      expect(perdida.reason.message).toBe(MENSAJE_HORARIO_OCUPADO);
      expect(await db.consultar({ coleccion: "appointments", filtros: [] })).toHaveLength(1);
    });

    it("un servicio de 60 min no cruza el descanso", async () => {
      const e = await error(como("ana", { ...solicitud, serviceId: "s60", slotId: "2026-11-05_09:30" }));
      expect(e.codigo).toBe("aborted");
    });

    it("respeta los bloqueos de la clínica", async () => {
      await poner("clinics/c1/excepciones/x1", {
        tipo: "bloqueo", fechaInicio: "2026-11-05", fechaFin: "2026-11-06", motivo: "Festivo",
      });
      expect((await error(como("ana", solicitud))).codigo).toBe("aborted");
      // Una apertura extra el domingo sí se puede reservar.
      await poner("clinics/c1/excepciones/x2", {
        tipo: "apertura", fechaInicio: "2026-11-08", fechaFin: "2026-11-08", desde: "09:00", hasta: "10:00",
      });
      await como("ana", { ...solicitud, slotId: "2026-11-08_09:00" });
    });

    it("anticipación mínima y máxima", async () => {
      ahora = new Date("2026-11-05T13:00:00Z"); // 8:00 a. m.; la cita es a las 9:30
      expect((await error(como("ana", solicitud))).message)
        .toBe("Debes reservar con al menos 2 horas de anticipación.");
      ahora = AHORA;
      expect((await error(como("ana", { ...solicitud, slotId: "2026-12-05_09:30" }))).message)
        .toBe("Solo puedes reservar con hasta 30 días de anticipación.");
    });

    it("una clínica sin migrar (solo horarioBase) sigue recibiendo citas", async () => {
      await poner("clinics/c1", {
        ownerUid: "vet", nombre: "Vet Norte", estado: "activo",
        horarioBase: { apertura: "08:00", cierre: "18:00", duracionSlotMin: 30 },
      });
      await como("ana", { ...solicitud, slotId: "2026-11-08_15:00" }); // domingo: todos los días abiertos
      await poner("clinics/c2/services/s1", { nombre: "Consulta", precio: 1, activo: true });
      expect((await error(como("ana", { ...solicitud, clinicId: "c2" }))).message)
        .toBe("Esta clínica aún no tiene horario de atención.");
    });
  });

  describe("responder", () => {
    it("aprobar → confirmada y franja ocupada", async () => {
      const appointmentId = await citaEn("pendiente");
      await como("vet", { accion: "responder", appointmentId, aprobar: true });

      expect((await leer(`appointments/${appointmentId}`))!.estado).toBe("confirmada");
      expect(await slotEstado()).toBe("ocupado");
      expect(cambios[1]).toMatchObject({ actor: "clinica" });
      expect(cambios[1].antes!.estado).toBe("pendiente");
      expect(cambios[1].despues.estado).toBe("confirmada");
    });

    it("rechazar exige motivo y libera la franja", async () => {
      const appointmentId = await citaEn("pendiente");
      const e = await error(como("vet", { accion: "responder", appointmentId, aprobar: false, motivo: "  " }));
      expect(e.message).toBe("Indica el motivo del rechazo.");

      await como("vet", { accion: "responder", appointmentId, aprobar: false, motivo: "No hay veterinario" });
      const cita = (await leer(`appointments/${appointmentId}`))!;
      expect(cita.estado).toBe("rechazada");
      expect(cita.motivoRechazo).toBe("No hay veterinario");
      expect(await slotEstado()).toBe("disponible");
    });

    it("solo la clínica dueña, y solo una vez", async () => {
      const appointmentId = await citaEn("pendiente");
      expect((await error(como("vet2", { accion: "responder", appointmentId, aprobar: true }))).codigo)
        .toBe("permission-denied");
      expect((await error(como("ana", { accion: "responder", appointmentId, aprobar: true }))).codigo)
        .toBe("permission-denied");
      expect((await error(como("vet", { accion: "responder", appointmentId }))).codigo)
        .toBe("invalid-argument");
      expect((await error(como("vet", { accion: "responder", appointmentId: "nada", aprobar: true }))).codigo)
        .toBe("not-found");

      await como("vet", { accion: "responder", appointmentId, aprobar: true });
      const e = await error(como("vet", { accion: "responder", appointmentId, aprobar: false, motivo: "x" }));
      expect(e.codigo).toBe("failed-precondition");
      expect(e.message).toBe("Esta cita ya fue confirmada.");
    });
  });

  describe("cancelar", () => {
    it("el dueño cancela con más de 2 h de anticipación y se libera la franja", async () => {
      const appointmentId = await citaEn("confirmada");
      await como("ana", { accion: "cancelar", appointmentId });

      const cita = (await leer(`appointments/${appointmentId}`))!;
      expect(cita.estado).toBe("cancelada");
      expect(cita.canceladoPor).toBe("dueno");
      expect(cita.motivoCancelacion).toBeUndefined();
      expect(await slotEstado()).toBe("disponible");
      expect(cambios.at(-1)).toMatchObject({ actor: "dueno" });
    });

    it("el dueño no puede a menos de 2 h", async () => {
      const appointmentId = await citaEn("pendiente");
      ahora = new Date("2026-11-05T12:31:00Z"); // 7:31 a. m.; la cita es a las 9:30
      const e = await error(como("ana", { accion: "cancelar", appointmentId }));
      expect(e.message).toBe("Solo puedes cancelar hasta 2 horas antes de la cita. Comunícate con la clínica.");

      ahora = new Date("2026-11-05T12:30:00Z"); // justo 2 h antes: todavía puede
      await como("ana", { accion: "cancelar", appointmentId });
    });

    it("la clínica cancela con motivo obligatorio", async () => {
      const appointmentId = await citaEn("confirmada");
      ahora = new Date("2026-11-05T14:00:00Z"); // 30 min antes: la clínica sí puede
      expect((await error(como("vet", { accion: "cancelar", appointmentId }))).message)
        .toBe("Indica el motivo de la cancelación.");

      await como("vet", { accion: "cancelar", appointmentId, motivo: "Imprevisto del veterinario" });
      const cita = (await leer(`appointments/${appointmentId}`))!;
      expect(cita).toMatchObject({
        estado: "cancelada", canceladoPor: "clinica", motivoCancelacion: "Imprevisto del veterinario",
      });
      expect(await slotEstado()).toBe("disponible");
    });

    it("nadie más puede cancelar, ni una cita terminada", async () => {
      const appointmentId = await citaEn("pendiente");
      expect((await error(como("beto", { accion: "cancelar", appointmentId }))).codigo).toBe("permission-denied");
      expect((await error(como("vet2", { accion: "cancelar", appointmentId, motivo: "x" }))).codigo)
        .toBe("permission-denied");
      await como("ana", { accion: "cancelar", appointmentId });
      expect((await error(como("ana", { accion: "cancelar", appointmentId }))).message)
        .toBe("Esta cita ya fue cancelada.");
    });
  });

  describe("completar", () => {
    it("solo la clínica y solo después de la hora de inicio", async () => {
      const appointmentId = await citaEn("confirmada");
      expect((await error(como("vet", { accion: "completar", appointmentId }))).message)
        .toBe("Solo puedes completar la cita después de su hora de inicio.");
      ahora = new Date("2026-11-05T14:30:00Z");
      expect((await error(como("ana", { accion: "completar", appointmentId }))).codigo)
        .toBe("permission-denied");

      await como("vet", { accion: "completar", appointmentId });
      expect((await leer(`appointments/${appointmentId}`))!.estado).toBe("completada");
    });

    it("una solicitud pendiente no se puede completar", async () => {
      const appointmentId = await citaEn("pendiente");
      ahora = new Date("2026-11-05T15:00:00Z");
      expect((await error(como("vet", { accion: "completar", appointmentId }))).codigo)
        .toBe("failed-precondition");
    });
  });

  describe("tarea cada 30 min", () => {
    it("no_asistio tras 60 min de tolerancia y expirada si nadie respondió", async () => {
      const confirmada = await citaEn("confirmada");
      await poner("clinics/c1/slots/2026-11-05_11:00", {
        fecha: "2026-11-05", hora: "11:00", serviceId: "s1", estado: "disponible",
      });
      const { appointmentId: pendiente } = await como("beto", {
        ...solicitud, petId: "p2", slotId: "2026-11-05_11:00",
      }) as { appointmentId: string };
      cambios = [];

      // 10:29 a. m.: la confirmada (9:30) lleva 59 min; la pendiente (11:00) no ha empezado.
      ahora = new Date(Date.parse("2026-11-05T14:30:00Z") + 59 * MINUTO);
      expect(await procesarCitasVencidas(deps)).toEqual({ noAsistio: 0, expiradas: 0 });

      // 11:01 a. m.
      ahora = new Date("2026-11-05T16:01:00Z");
      expect(await procesarCitasVencidas(deps)).toEqual({ noAsistio: 1, expiradas: 1 });
      expect((await leer(`appointments/${confirmada}`))!.estado).toBe("no_asistio");
      expect((await leer(`appointments/${pendiente}`))!.estado).toBe("expirada");
      expect(await slotEstado("2026-11-05_11:00")).toBe("disponible");
      expect(cambios.map((c) => c.actor)).toEqual(["sistema", "sistema"]);

      // Otra ejecución no vuelve a tocarlas.
      expect(await procesarCitasVencidas(deps)).toEqual({ noAsistio: 0, expiradas: 0 });
    });
  });
});
