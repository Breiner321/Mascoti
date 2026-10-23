import { describe, expect, it } from "vitest";

import type { CambioCita } from "../../supabase/functions/_shared/citas.ts";
import {
  avisosPorCambio,
  esTokenInvalido,
  fechaLegible,
  horaLegible,
  mensajeFcm,
} from "../../supabase/functions/_shared/notificaciones.ts";

const cita = {
  clinicId: "c1",
  clinicNombre: "Vet Norte",
  clinicOwnerUid: "vet",
  ownerUid: "ana",
  ownerNombre: "Ana Pérez",
  petNombre: "Luna",
  serviceNombre: "Consulta general",
  fecha: "2026-11-05",
  hora: "14:30",
  estado: "pendiente",
};

function cambio(
  de: string | null,
  a: string,
  actor: CambioCita["actor"],
  extra: Record<string, unknown> = {},
): CambioCita {
  return {
    appointmentId: "a1",
    antes: de === null ? null : { ...cita, estado: de },
    despues: { ...cita, ...extra, estado: a },
    actor,
  };
}

describe("avisosPorCambio: qué notificar y a quién", () => {
  it("nueva solicitud → la clínica", () => {
    expect(avisosPorCambio(cambio(null, "pendiente", "dueno"))).toEqual([{
      uid: "vet",
      tipo: "cita_nueva",
      titulo: "Nueva solicitud de cita",
      cuerpo: "Ana Pérez pidió Consulta general para Luna el jueves 5 de noviembre a las 2:30 p. m.",
      referenciaId: "a1",
    }]);
  });

  it("confirmada → el dueño", () => {
    const [aviso] = avisosPorCambio(cambio("pendiente", "confirmada", "clinica"));
    expect(aviso).toMatchObject({ uid: "ana", tipo: "cita_aprobada", titulo: "¡Cita confirmada!" });
    expect(aviso.cuerpo).toBe("Vet Norte confirmó la cita de Luna el jueves 5 de noviembre a las 2:30 p. m.");
    expect(aviso.prioridadAlta).toBeUndefined();
  });

  it("rechazada → el dueño, con el motivo", () => {
    const [aviso] = avisosPorCambio(
      cambio("pendiente", "rechazada", "clinica", { motivoRechazo: "No hay veterinario" }),
    );
    expect(aviso).toMatchObject({ uid: "ana", tipo: "cita_rechazada" });
    expect(aviso.cuerpo).toContain("Motivo: No hay veterinario");
  });

  it("cancelada por la clínica → el dueño, prioridad alta y sugiere reagendar", () => {
    const [aviso] = avisosPorCambio(
      cambio("confirmada", "cancelada", "clinica", { motivoCancelacion: "Imprevisto" }),
    );
    expect(aviso).toMatchObject({ uid: "ana", tipo: "cita_cancelada", prioridadAlta: true });
    expect(aviso.cuerpo).toBe(
      "Vet Norte canceló la cita de Luna del jueves 5 de noviembre. Motivo: Imprevisto. Te sugerimos reagendar.",
    );
  });

  it("cancelada por el dueño → la clínica", () => {
    const [aviso] = avisosPorCambio(cambio("confirmada", "cancelada", "dueno"));
    expect(aviso).toMatchObject({ uid: "vet", tipo: "cita_cancelada", titulo: "Cita cancelada por el dueño" });
    expect(aviso.prioridadAlta).toBeUndefined();
  });

  it("sin aviso: cambios del sistema, completada o sin cambio de estado", () => {
    expect(avisosPorCambio(cambio("confirmada", "no_asistio", "sistema"))).toEqual([]);
    expect(avisosPorCambio(cambio("pendiente", "expirada", "sistema"))).toEqual([]);
    expect(avisosPorCambio(cambio("confirmada", "completada", "clinica"))).toEqual([]);
    expect(avisosPorCambio(cambio("pendiente", "pendiente", "clinica"))).toEqual([]);
  });
});

describe("textos y FCM", () => {
  it("fecha y hora legibles (iguales a la app)", () => {
    expect(fechaLegible("2026-11-01")).toBe("domingo 1 de noviembre");
    expect(fechaLegible("raro")).toBe("raro");
    expect(horaLegible("00:15")).toBe("12:15 a. m.");
    expect(horaLegible("09:05")).toBe("9:05 a. m.");
    expect(horaLegible("12:00")).toBe("12:00 p. m.");
    expect(horaLegible("23:59")).toBe("11:59 p. m.");
  });

  it("tokens inválidos según la respuesta de FCM", () => {
    expect(esTokenInvalido(404, '{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}'))
      .toBe(true);
    expect(esTokenInvalido(400, "The registration token is not a valid FCM registration token")).toBe(true);
    expect(esTokenInvalido(403, '{"details":[{"errorCode":"SENDER_ID_MISMATCH"}]}')).toBe(true);
    // Errores temporales o de formato del mensaje: el token sigue siendo válido.
    expect(esTokenInvalido(429, "QUOTA_EXCEEDED")).toBe(false);
    expect(esTokenInvalido(503, "UNAVAILABLE")).toBe(false);
    expect(esTokenInvalido(400, "Invalid JSON payload")).toBe(false);
  });

  it("mensaje FCM con datos para navegar y canal según la prioridad", () => {
    const normal = mensajeFcm("tok", {
      titulo: "T", cuerpo: "C", datos: { tipo: "cita_aprobada", referenciaId: "a1" }, prioridadAlta: false,
    });
    expect(normal).toEqual({
      message: {
        token: "tok",
        notification: { title: "T", body: "C" },
        data: { tipo: "cita_aprobada", referenciaId: "a1" },
        android: { priority: "NORMAL", notification: { channel_id: "mascoti_general" } },
      },
    });
    const alta = mensajeFcm("tok", { titulo: "T", cuerpo: "C", datos: {}, prioridadAlta: true });
    expect(alta).toMatchObject({
      message: { android: { priority: "HIGH", notification: { channel_id: "mascoti_urgente" } } },
    });
  });
});
