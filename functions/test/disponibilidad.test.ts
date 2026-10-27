import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

import {
  cabeEnHorario,
  type ConfigReservas,
  type Excepcion,
  franjasDe,
  horarioDeClinica,
  type HorarioSemanal,
  horasDisponibles,
  reservasDeClinica,
} from "../../supabase/functions/_shared/disponibilidad.ts";

/** Casos compartidos con test/core/domain/availability_test.dart. */
const fixture = JSON.parse(
  readFileSync(resolve(__dirname, "../../test/fixtures/disponibilidad.json"), "utf8"),
) as { base: Record<string, unknown>; casos: Record<string, unknown>[] };

describe("disponibilidad: casos compartidos (TypeScript = Dart)", () => {
  for (const crudo of fixture.casos) {
    const c = { ...fixture.base, ...crudo };
    it(c.nombre as string, () => {
      expect(horasDisponibles({
        fecha: c.fecha as string,
        duracionMin: c.duracionMin as number,
        horario: c.horario as HorarioSemanal,
        reservas: c.reservas as ConfigReservas,
        ahora: new Date(c.ahora as string),
        excepciones: c.excepciones as Excepcion[],
        franjas: c.franjas as Record<string, string>,
      })).toEqual(c.esperado);
    });
  }
});

describe("disponibilidad: utilidades del servidor", () => {
  const horario = fixture.base.horario as HorarioSemanal;

  it("franjasDe: las franjas que aparta la reserva", () => {
    expect(franjasDe("09:00", 60, 30)).toEqual(["09:00", "09:30"]);
    expect(franjasDe("09:00", 45, 30)).toEqual(["09:00", "09:30"]);
    expect(franjasDe("09:00", 30, 15)).toEqual(["09:00", "09:15"]);
  });

  it("cabeEnHorario", () => {
    expect(cabeEnHorario("2026-11-02", "09:00", 60, horario, 30)).toBe(true);
    expect(cabeEnHorario("2026-11-02", "09:30", 60, horario, 30)).toBe(false);
    expect(cabeEnHorario("2026-11-01", "09:00", 30, horario, 30)).toBe(false);
  });

  it("una clínica sin migrar usa horarioBase todos los días", () => {
    const vieja = { horarioBase: { apertura: "07:00", cierre: "19:00", duracionSlotMin: 20 } };
    expect(horarioDeClinica(vieja)?.dom).toEqual({ abierto: true, apertura: "07:00", cierre: "19:00" });
    expect(reservasDeClinica(vieja)).toEqual({
      duracionSlotMin: 20, anticipacionMaxDias: 30, anticipacionMinMin: 120,
    });
    expect(horarioDeClinica({})).toBeNull();
    expect(reservasDeClinica({ reservas: { duracionSlotMin: 60, anticipacionMaxDias: 7, anticipacionMinMin: 0 } }))
      .toEqual({ duracionSlotMin: 60, anticipacionMaxDias: 7, anticipacionMinMin: 0 });
  });
});
