import { describe, expect, it } from "vitest";

import {
  nombrePasarela,
  pasarelaDelPedido,
  pasarelaSimulada,
  pasarelaWompi,
} from "../../supabase/functions/_shared/pasarela.ts";

const datos = {
  orderId: "o1",
  referencia: "MSC-o1",
  total: 45000,
  expiraEn: new Date("2026-11-18T15:15:00Z"),
  contacto: { correo: "ana@example.com" },
};

describe("pasarela de pago", () => {
  it("PASARELA_PAGO vacía usa la simulada; un valor desconocido es un error", () => {
    expect(nombrePasarela(undefined)).toBe("simulada");
    expect(nombrePasarela("  ")).toBe("simulada");
    expect(nombrePasarela("Wompi")).toBe("wompi");
    expect(nombrePasarela("simulada")).toBe("simulada");
    expect(() => nombrePasarela("paypal")).toThrow("PASARELA_PAGO desconocida");
  });

  it("los pedidos sin el campo `pasarela` son de Wompi", () => {
    expect(pasarelaDelPedido(undefined)).toBe("wompi");
    expect(pasarelaDelPedido("wompi")).toBe("wompi");
    expect(pasarelaDelPedido("simulada")).toBe("simulada");
  });

  it("la simulada no devuelve página de pago", async () => {
    expect(pasarelaSimulada.nombre).toBe("simulada");
    expect(await pasarelaSimulada.iniciarPago(datos)).toEqual({ checkoutUrl: null, redirectUrl: null });
  });

  it("Wompi devuelve el Web Checkout firmado y la URL de regreso del pedido", async () => {
    const wompi = pasarelaWompi({
      llavePublica: "pub_test_123",
      secretoIntegridad: "test_integrity_secreto",
      urlRegreso: "https://x.supabase.co/functions/v1/webhook-wompi/retorno/",
    });
    const r = await wompi.iniciarPago(datos);
    expect(r.redirectUrl).toBe("https://x.supabase.co/functions/v1/webhook-wompi/retorno/o1");
    const url = new URL(r.checkoutUrl!);
    expect(url.origin + url.pathname).toBe("https://checkout.wompi.co/p/");
    expect(url.searchParams.get("amount-in-cents")).toBe("4500000");
    expect(url.searchParams.get("reference")).toBe("MSC-o1");
    expect(url.searchParams.get("signature:integrity")).toMatch(/^[0-9a-f]{64}$/);
  });
});
