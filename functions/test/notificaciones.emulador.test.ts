/**
 * Envío de notificaciones (RF-13) contra el emulador de Firestore: documento
 * en `notifications`, push a cada dispositivo, tokens inválidos, recordatorios
 * diarios sin duplicados y avisos de las citas. FCM es un falso.
 *   cd functions && npm run test:rules
 */
import { beforeEach, describe, expect, it } from "vitest";

import { ejecutarAccionCita } from "../../supabase/functions/_shared/citas.ts";
import { ClienteFirestore } from "../../supabase/functions/_shared/cliente_firestore.ts";
import {
  camposFirestore,
  rutaDocumento,
  type ValorCampo,
} from "../../supabase/functions/_shared/firestore.ts";
import {
  type DependenciasNotificaciones,
  enviarNotificacion,
  enviarRecordatoriosDiarios,
  type MensajePush,
  notificarCambioCita,
} from "../../supabase/functions/_shared/notificaciones.ts";

const host = process.env.FIRESTORE_EMULATOR_HOST;
const PROYECTO = "demo-mascoti-notificaciones";

/** Lunes 2 de noviembre de 2026, 8:00 a. m. en Bogotá. */
const AHORA = new Date("2026-11-02T13:00:00Z");

describe.skipIf(!host)("notificaciones (emulador)", () => {
  const db = new ClienteFirestore(PROYECTO, `http://${host}/v1`, async () => "owner");
  let pushes: { token: string; mensaje: MensajePush }[];
  let invalidos: Set<string>;
  let ids: number;
  let deps: DependenciasNotificaciones;

  async function poner(ruta: string, campos: { [campo: string]: ValorCampo }) {
    await db.commit([{ update: { name: rutaDocumento(PROYECTO, ruta), fields: camposFirestore(campos) } }]);
  }

  async function notificaciones(uid?: string) {
    const todas = await db.consultar({ coleccion: "notifications", filtros: [] });
    return todas.filter((n) => uid === undefined || n.datos.uid === uid);
  }

  beforeEach(async () => {
    await fetch(`http://${host}/emulator/v1/projects/${PROYECTO}/databases/(default)/documents`, {
      method: "DELETE",
    });
    pushes = [];
    invalidos = new Set(["tok-viejo"]);
    ids = 0;
    deps = {
      db,
      ahora: () => AHORA,
      nuevoId: () => `n${++ids}`,
      enviarPush: async (token, mensaje) => {
        pushes.push({ token, mensaje });
        return invalidos.has(token) ? "token-invalido" : "ok";
      },
    };
    await poner("users/ana/devices/d1", { fcmToken: "tok-ana", plataforma: "android", valido: true });
    await poner("users/ana/devices/d2", { fcmToken: "tok-viejo", plataforma: "android", valido: true });
    await poner("users/ana/devices/d3", { fcmToken: "tok-apagado", plataforma: "android", valido: false });
  });

  const aviso = {
    uid: "ana",
    tipo: "cita_aprobada" as const,
    titulo: "¡Cita confirmada!",
    cuerpo: "Vet Norte confirmó la cita de Luna.",
    referenciaId: "a1",
  };

  describe("enviarNotificacion", () => {
    it("crea el documento y envía el push a los dispositivos válidos", async () => {
      const r = await enviarNotificacion(deps, aviso);

      expect(r).toEqual({ notificationId: "n1", creada: true, enviados: 1, invalidos: 1 });
      const [doc] = await notificaciones();
      expect(doc.id).toBe("n1");
      expect(doc.datos).toMatchObject({
        uid: "ana", tipo: "cita_aprobada", titulo: "¡Cita confirmada!", referenciaId: "a1", leido: false,
      });
      expect(doc.datos.createdAt).toBeInstanceOf(Date);
      // d3 ya estaba marcado como inválido: no se intenta.
      expect(pushes.map((p) => p.token).sort()).toEqual(["tok-ana", "tok-viejo"]);
      expect(pushes[0].mensaje.datos).toEqual({ tipo: "cita_aprobada", referenciaId: "a1", notificationId: "n1" });
    });

    it("un token inválido queda marcado valido=false y no se vuelve a usar", async () => {
      await enviarNotificacion(deps, aviso);
      expect((await db.leer("users/ana/devices/d2"))!.datos.valido).toBe(false);
      expect((await db.leer("users/ana/devices/d1"))!.datos.valido).toBe(true);

      pushes = [];
      await enviarNotificacion(deps, aviso);
      expect(pushes.map((p) => p.token)).toEqual(["tok-ana"]);
    });

    it("sin dispositivos (o sin permiso de push) igual queda en el centro de notificaciones", async () => {
      const r = await enviarNotificacion(deps, { ...aviso, uid: "beto" });
      expect(r.enviados).toBe(0);
      expect(await notificaciones("beto")).toHaveLength(1);
    });

    it("un error temporal de FCM no invalida el token ni frena a los demás", async () => {
      deps.enviarPush = async (token) => {
        if (token === "tok-ana") throw new Error("FCM 503");
        return "ok";
      };
      const r = await enviarNotificacion(deps, aviso);
      expect(r).toMatchObject({ enviados: 1, invalidos: 0 });
      expect((await db.leer("users/ana/devices/d1"))!.datos.valido).toBe(true);
    });

    it("con id fijo no duplica ni reenvía", async () => {
      await enviarNotificacion(deps, { ...aviso, id: "recordatorio_a1" });
      pushes = [];
      const r = await enviarNotificacion(deps, { ...aviso, id: "recordatorio_a1" });
      expect(r.creada).toBe(false);
      expect(pushes).toHaveLength(0);
      expect(await notificaciones()).toHaveLength(1);
    });
  });

  describe("recordatorios diarios (8:00 a. m.)", () => {
    beforeEach(async () => {
      const cita = {
        clinicId: "c1", clinicNombre: "Vet Norte", ownerUid: "ana", petNombre: "Luna",
        serviceNombre: "Consulta general",
      };
      // Mañana = martes 3 de noviembre (en Bogotá).
      await poner("appointments/manana", {
        ...cita, estado: "confirmada", hora: "09:30", inicio: new Date("2026-11-03T14:30:00Z"),
      });
      await poner("appointments/mananaNoche", {
        ...cita, estado: "confirmada", hora: "23:30", inicio: new Date("2026-11-04T04:30:00Z"),
      });
      await poner("appointments/cancelada", {
        ...cita, estado: "cancelada", hora: "10:00", inicio: new Date("2026-11-03T15:00:00Z"),
      });
      await poner("appointments/pendiente", {
        ...cita, estado: "pendiente", hora: "11:00", inicio: new Date("2026-11-03T16:00:00Z"),
      });
      await poner("appointments/pasado", {
        ...cita, estado: "confirmada", hora: "09:00", inicio: new Date("2026-11-04T14:00:00Z"),
      });

      await poner("pets/p1", { ownerUid: "ana", nombre: "Luna" });
      const dosis = { petId: "p1", ownerUid: "ana", clinicId: "c1", vacuna: "Rabia", notificado: false };
      await poner("vacunasProgramadas/r1_0", { ...dosis, fechaProximaDosis: new Date("2026-11-05T15:00:00Z") });
      await poner("vacunasProgramadas/r2_0", { ...dosis, vacuna: "Moquillo",
        fechaProximaDosis: new Date("2026-11-06T15:00:00Z") }); // en 4 días: todavía no
      await poner("vacunasProgramadas/r3_0", { ...dosis, notificado: true,
        fechaProximaDosis: new Date("2026-11-03T15:00:00Z") }); // ya avisada
      await poner("vacunasProgramadas/r4_0", { ...dosis,
        fechaProximaDosis: new Date("2026-10-30T15:00:00Z") }); // ya pasó
    });

    it("citas confirmadas de mañana y vacunas de los próximos 3 días", async () => {
      expect(await enviarRecordatoriosDiarios(deps)).toEqual({ citas: 2, vacunas: 1 });

      const docs = await notificaciones("ana");
      expect(docs.map((d) => d.id).sort()).toEqual([
        "recordatorio_manana", "recordatorio_mananaNoche", "vacuna_r1_0",
      ]);
      const cita = docs.find((d) => d.id === "recordatorio_manana")!.datos;
      expect(cita).toMatchObject({ tipo: "recordatorio_cita", referenciaId: "manana", titulo: "Tu cita es mañana" });
      expect(cita.cuerpo).toBe("Luna tiene Consulta general en Vet Norte mañana a las 9:30 a. m.");
      const vacuna = docs.find((d) => d.id === "vacuna_r1_0")!.datos;
      expect(vacuna).toMatchObject({ tipo: "vacuna", referenciaId: "p1" });
      expect(vacuna.cuerpo).toBe("A Luna le toca la próxima dosis de Rabia el jueves 5 de noviembre.");
      expect((await db.leer("vacunasProgramadas/r1_0"))!.datos.notificado).toBe(true);
      expect((await db.leer("vacunasProgramadas/r2_0"))!.datos.notificado).toBe(false);
    });

    it("si se ejecuta dos veces no hay duplicados", async () => {
      await enviarRecordatoriosDiarios(deps);
      pushes = [];
      expect(await enviarRecordatoriosDiarios(deps)).toEqual({ citas: 0, vacunas: 0 });
      expect(pushes).toHaveLength(0);
      expect(await notificaciones("ana")).toHaveLength(3);
    });
  });

  it("de punta a punta: solicitar y responder una cita avisa a la clínica y al dueño", async () => {
    await poner("users/ana", {
      role: "dueno", estado: "activo", nombre: "Ana Pérez", displayName: "ana.g", email: "ana@gmail.com",
    });
    await poner("users/vet", { role: "clinica", estado: "activo", clinicId: "c1" });
    await poner("users/vet/devices/dv", { fcmToken: "tok-vet", valido: true });
    await poner("clinics/c1", { ownerUid: "vet", nombre: "Vet Norte", estado: "activo" });
    await poner("clinics/c1/services/s1", { nombre: "Consulta", precio: 1000, activo: true });
    await poner("clinics/c1/slots/2026-11-05_09:30", { fecha: "2026-11-05", hora: "09:30", estado: "disponible" });
    await poner("pets/p1", { ownerUid: "ana", nombre: "Luna" });

    const citas = {
      db,
      verificarToken: async (token: string) => ({ uid: token }),
      ahora: () => AHORA,
      nuevoId: () => "a1",
      alCambiar: (c: Parameters<typeof notificarCambioCita>[1]) => notificarCambioCita(deps, c),
    };
    await ejecutarAccionCita(citas, "Bearer ana", {
      accion: "solicitar", clinicId: "c1", serviceId: "s1", petId: "p1", slotId: "2026-11-05_09:30",
    });
    const [nueva] = await notificaciones("vet");
    expect(nueva.datos.tipo).toBe("cita_nueva");
    // Cambio 1: la clínica ve el nombre real del dueño, no su correo ni su cuenta de Google.
    expect(nueva.datos.cuerpo).toMatch(/^Ana Pérez pidió Consulta para Luna/);
    expect(nueva.datos.cuerpo).not.toContain("ana@gmail.com");
    expect(nueva.datos.cuerpo).not.toContain("ana.g");
    expect(pushes.map((p) => p.token)).toEqual(["tok-vet"]);

    await ejecutarAccionCita(citas, "Bearer vet", {
      accion: "responder", appointmentId: "a1", aprobar: false, motivo: "Sin cupo",
    });
    const [rechazo] = await notificaciones("ana");
    expect(rechazo.datos).toMatchObject({ tipo: "cita_rechazada", referenciaId: "a1" });
    expect(rechazo.datos.cuerpo).toContain("Motivo: Sin cupo");
  });
});
