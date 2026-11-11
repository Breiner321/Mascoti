import { describe, expect, it } from "vitest";

import {
  cuerpoPush,
  reservarPush,
  vistaPrevia,
} from "../../supabase/functions/_shared/mensajes.ts";
import { mensajeFcm } from "../../supabase/functions/_shared/notificaciones.ts";

describe("notificar-mensaje: textos y escrituras", () => {
  it("vista previa en una línea y de máximo 100 caracteres (igual a ChatLimits.preview)", () => {
    expect(vistaPrevia("  Hola\n  doctor ")).toBe("Hola doctor");
    const larga = vistaPrevia("a".repeat(300));
    expect(larga).toHaveLength(100);
    expect(larga.endsWith("…")).toBe(true);
  });

  it("cuerpo: vista previa, adjunto y cuántos sin leer", () => {
    expect(cuerpoPush({ tipo: "texto", texto: "Hola" }, 1)).toBe("Hola");
    expect(cuerpoPush({ tipo: "adjunto" }, 1)).toBe("📎 Archivo adjunto");
    expect(cuerpoPush({ tipo: "texto", texto: "Hola" }, 4)).toBe("4 mensajes nuevos · Hola");
  });

  it("ultimoPush solo cambia la clave del receptor, con precondición", () => {
    const hora = new Date("2026-11-10T15:00:00Z");
    expect(reservarPush("p", "ana_c1", "vet", hora, "2026-11-10T14:59:59.000001Z")).toEqual({
      update: {
        name: "projects/p/databases/(default)/documents/chats/ana_c1",
        fields: {
          ultimoPush: { mapValue: { fields: { vet: { timestampValue: "2026-11-10T15:00:00.000Z" } } } },
        },
      },
      updateMask: { fieldPaths: ["ultimoPush.vet"] },
      currentDocument: { updateTime: "2026-11-10T14:59:59.000001Z" },
    });
  });

  it("FCM: la etiqueta reemplaza la notificación anterior de la conversación", () => {
    const cuerpo = mensajeFcm("tok", {
      titulo: "Ana", cuerpo: "Hola", datos: { tipo: "mensaje", referenciaId: "ana_c1" },
      prioridadAlta: false, etiqueta: "ana_c1",
    }) as { message: { android: { notification: Record<string, unknown> } } };
    expect(cuerpo.message.android.notification).toEqual({ channel_id: "mascoti_general", tag: "ana_c1" });
    const sinEtiqueta = mensajeFcm("tok", {
      titulo: "T", cuerpo: "C", datos: {}, prioridadAlta: false,
    }) as { message: { android: { notification: Record<string, unknown> } } };
    expect(sinEtiqueta.message.android.notification).toEqual({ channel_id: "mascoti_general" });
  });
});
