import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

import {
  ESTADOS_DE_LA_CLINICA,
  ESTADOS_PEDIDO,
  ESTADOS_VISIBLES_CLINICA,
  esFinalPedido,
  puedeTransicionarPedido,
  TIPOS_ENTREGA,
} from "../../supabase/functions/_shared/estados_pedido.ts";

/** Mismos casos que test/core/domain/order_test.dart. */
const fixture = JSON.parse(
  readFileSync(resolve(__dirname, "../../test/fixtures/estados_pedido.json"), "utf8"),
) as {
  estados: string[];
  entregas: string[];
  validas: [string, string, string][];
  porLaClinica: string[];
  finales: string[];
};

describe("máquina de estados del pedido (test/fixtures/estados_pedido.json)", () => {
  const validas = new Set(fixture.validas.map((t) => t.join("|")));

  it("los estados coinciden con la app", () => {
    expect([...ESTADOS_PEDIDO]).toEqual(fixture.estados);
    expect([...TIPOS_ENTREGA]).toEqual(fixture.entregas);
  });

  it("todas las combinaciones (de, a, entrega)", () => {
    let revisadas = 0;
    for (const de of ESTADOS_PEDIDO) {
      for (const a of ESTADOS_PEDIDO) {
        for (const entrega of TIPOS_ENTREGA) {
          const clave = `${de}|${a}|${entrega}`;
          expect(puedeTransicionarPedido(de, a, entrega), clave).toBe(validas.has(clave));
          revisadas++;
        }
      }
    }
    expect(revisadas).toBe(9 * 9 * 2);
  });

  it("finales, estados de la clínica y visibles para la clínica", () => {
    expect(ESTADOS_PEDIDO.filter(esFinalPedido).sort()).toEqual([...fixture.finales].sort());
    expect([...ESTADOS_DE_LA_CLINICA].sort()).toEqual([...fixture.porLaClinica].sort());
    expect(ESTADOS_VISIBLES_CLINICA).not.toContain("pendiente_pago");
    expect(ESTADOS_VISIBLES_CLINICA).not.toContain("expirado");
  });

  it("valores desconocidos no transicionan", () => {
    expect(puedeTransicionarPedido("raro", "pagado", "recoger")).toBe(false);
    expect(puedeTransicionarPedido("pendiente_pago", "pagado", "dron")).toBe(false);
    expect(puedeTransicionarPedido(undefined, "pagado", "recoger")).toBe(false);
  });
});
