import { describe, expect, it } from "vitest";

import {
  enmascararTelefono,
  FORMATO_QR_ID,
  formatearTelefono,
  hashIp,
  ipDelCliente,
} from "../../supabase/functions/_shared/placa.ts";

describe("placa QR: utilidades", () => {
  it("enmascara el teléfono como 300 *** **67", () => {
    expect(enmascararTelefono("3001234567")).toBe("300 *** **67");
    expect(enmascararTelefono("300 123 4567")).toBe("300 *** **67");
    expect(enmascararTelefono("6041234567890")).toBe("604 ********90");
    expect(enmascararTelefono("123")).toBe("***");
  });

  it("formatea el teléfono revelado", () => {
    expect(formatearTelefono("3001234567")).toBe("300 123 4567");
  });

  it("toma la IP del cliente de x-forwarded-for", () => {
    expect(ipDelCliente("190.1.2.3, 10.0.0.1")).toBe("190.1.2.3");
    expect(ipDelCliente(null)).toBe("desconocida");
    expect(ipDelCliente("x".repeat(100))).toBe("desconocida");
  });

  it("no guarda la IP: solo su hash", async () => {
    const h = await hashIp("190.1.2.3");
    expect(h).toMatch(/^[0-9a-f]{64}$/);
    expect(h).not.toContain("190");
    expect(await hashIp("190.1.2.3")).toBe(h);
    expect(await hashIp("190.1.2.4")).not.toBe(h);
  });

  it("formato del id de la placa", () => {
    expect(FORMATO_QR_ID.test("abcDEF1234")).toBe(true);
    expect(FORMATO_QR_ID.test("corto")).toBe(false);
    expect(FORMATO_QR_ID.test("abc/def/1234")).toBe(false);
  });
});
