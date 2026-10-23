import { describe, expect, it } from "vitest";

import {
  ESTADOS_CITA,
  type EstadoCita,
  esFinal,
  puedeTransicionar,
} from "../../supabase/functions/_shared/estados_cita.ts";
import {
  fechaBogota,
  inicioDelDia,
  inicioEnBogota,
  sumarDias,
} from "../../supabase/functions/_shared/hora_bogota.ts";
import {
  actualizarCampos,
  consultaEstructurada,
  HORA_SERVIDOR,
} from "../../supabase/functions/_shared/firestore.ts";

/** Las únicas transiciones válidas (RF-14). Igual que en appointment_test.dart. */
const VALIDAS: [EstadoCita, EstadoCita][] = [
  ["pendiente", "confirmada"],
  ["pendiente", "rechazada"],
  ["pendiente", "cancelada"],
  ["pendiente", "expirada"],
  ["confirmada", "completada"],
  ["confirmada", "cancelada"],
  ["confirmada", "no_asistio"],
];

describe("máquina de estados de la cita", () => {
  it("son 7 estados, iguales a AppointmentStatus en Dart", () => {
    expect([...ESTADOS_CITA]).toEqual([
      "pendiente", "confirmada", "rechazada", "cancelada", "expirada", "completada", "no_asistio",
    ]);
  });

  it("recorre las 49 combinaciones: solo las válidas se permiten", () => {
    for (const de of ESTADOS_CITA) {
      for (const a of ESTADOS_CITA) {
        const esperada = VALIDAS.some(([x, y]) => x === de && y === a);
        expect(puedeTransicionar(de, a), `${de} → ${a}`).toBe(esperada);
      }
    }
  });

  it("estados finales y valores desconocidos", () => {
    expect(ESTADOS_CITA.filter(esFinal)).toEqual([
      "rechazada", "cancelada", "expirada", "completada", "no_asistio",
    ]);
    expect(puedeTransicionar(undefined, "confirmada")).toBe(false);
    expect(puedeTransicionar("aprobada", "confirmada")).toBe(false);
  });
});

describe("hora de Bogotá (UTC−5)", () => {
  it("fecha y hora → instante", () => {
    expect(inicioEnBogota("2026-11-05", "09:30")?.toISOString()).toBe("2026-11-05T14:30:00.000Z");
    // 21:00 en Bogotá ya es el día siguiente en UTC.
    expect(inicioEnBogota("2026-12-31", "21:00")?.toISOString()).toBe("2027-01-01T02:00:00.000Z");
  });

  it("rechaza formatos y fechas inexistentes", () => {
    for (const [f, h] of [["2026-02-30", "09:00"], ["2026-11-05", "24:00"], ["5/11/2026", "09:00"],
                          ["2026-11-05", "9:00"], [null, "09:00"]]) {
      expect(inicioEnBogota(f, h)).toBeNull();
    }
  });

  it("día en Bogotá de un instante", () => {
    expect(fechaBogota(new Date("2026-11-06T04:59:00Z"))).toBe("2026-11-05");
    expect(fechaBogota(new Date("2026-11-06T05:00:00Z"))).toBe("2026-11-06");
    expect(inicioDelDia("2026-11-06").toISOString()).toBe("2026-11-06T05:00:00.000Z");
    expect(sumarDias(new Date("2026-11-06T04:00:00Z"), 1)).toBe("2026-11-06");
  });
});

describe("escrituras parciales y consultas REST", () => {
  it("actualizarCampos: máscara, hora del servidor, borrado y precondición", () => {
    const e = actualizarCampos("p", "appointments/a1",
      { estado: "confirmada", motivo: undefined, updatedAt: HORA_SERVIDOR },
      { updateTime: "2026-11-01T00:00:00Z" });
    expect(e.update.name).toBe("projects/p/databases/(default)/documents/appointments/a1");
    expect(e.update.fields).toEqual({ estado: { stringValue: "confirmada" } });
    expect(e.updateMask?.fieldPaths).toEqual(["estado", "motivo"]);
    expect(e.updateTransforms).toEqual([{ fieldPath: "updatedAt", setToServerValue: "REQUEST_TIME" }]);
    expect(e.currentDocument).toEqual({ updateTime: "2026-11-01T00:00:00Z" });
  });

  it("consultaEstructurada con varios filtros y fechas", () => {
    const q = consultaEstructurada({
      coleccion: "appointments",
      filtros: [
        { campo: "estado", op: "EQUAL", valor: "pendiente" },
        { campo: "inicio", op: "LESS_THAN", valor: new Date("2026-11-01T00:00:00Z") },
      ],
      ordenarPor: "inicio",
      limite: 10,
    });
    expect(q).toMatchObject({
      from: [{ collectionId: "appointments" }],
      where: { compositeFilter: { op: "AND" } },
      orderBy: [{ field: { fieldPath: "inicio" } }],
      limit: 10,
    });
    const filtros = (q.where as { compositeFilter: { filters: unknown[] } }).compositeFilter.filters;
    expect(filtros[1]).toEqual({
      fieldFilter: {
        field: { fieldPath: "inicio" },
        op: "LESS_THAN",
        value: { timestampValue: "2026-11-01T00:00:00.000Z" },
      },
    });
  });
});
