import { createHash } from "node:crypto";

import { describe, expect, it } from "vitest";

import { ErrorFuncion } from "../../supabase/functions/_shared/errores.ts";
import {
  avisosPedido,
  calcularTotal,
  mensajeStock,
  pedidoDeReferencia,
  pesos,
  validarEntrega,
} from "../../supabase/functions/_shared/pedidos.ts";
import {
  centavos,
  checksumEvento,
  firmaIntegridad,
  type TransaccionWompi,
  urlCheckout,
  verificarEvento,
} from "../../supabase/functions/_shared/wompi.ts";

const sha256 = (texto: string) => createHash("sha256").update(texto).digest("hex");
const SECRETO_EVENTOS = "test_events_secreto";

/** Evento `transaction.updated` firmado como lo firma Wompi. */
function eventoFirmado(
  transaccion: TransaccionWompi,
  secreto = SECRETO_EVENTOS,
  timestamp = 1763478000,
) {
  const propiedades = ["transaction.id", "transaction.status", "transaction.amount_in_cents"];
  const concatenado = `${transaccion.id}${transaccion.status}${transaccion.amount_in_cents}${timestamp}${secreto}`;
  return {
    event: "transaction.updated",
    data: { transaction: transaccion },
    environment: "test",
    signature: { properties: propiedades, checksum: sha256(concatenado).toUpperCase() },
    timestamp,
    sent_at: "2026-11-18T15:00:00.000Z",
  };
}

describe("cálculo del total", () => {
  it("suma precio × cantidad con enteros en pesos", () => {
    expect(calcularTotal([
      { precio: 45000, cantidad: 2 },
      { precio: 12500, cantidad: 1 },
    ])).toBe(102500);
  });

  it("rechaza precios o cantidades que no son enteros positivos", () => {
    expect(() => calcularTotal([{ precio: 45000.5, cantidad: 1 }])).toThrow();
    expect(() => calcularTotal([{ precio: 0, cantidad: 1 }])).toThrow();
    expect(() => calcularTotal([{ precio: 1000, cantidad: 0 }])).toThrow();
    expect(() => calcularTotal([{ precio: 1000, cantidad: 1.5 }])).toThrow();
  });

  it("a Wompi se envía amount_in_cents = pesos × 100", () => {
    expect(centavos(102500)).toBe(10250000);
    expect(() => centavos(10.5)).toThrow();
    expect(() => centavos(0)).toThrow();
  });

  it("pesos colombianos para los avisos", () => {
    expect(pesos(102500)).toBe("$102.500");
    expect(pesos(1500000)).toBe("$1.500.000");
    expect(pesos(900)).toBe("$900");
  });
});

describe("entrega y mensajes", () => {
  it("valida la entrega como la app", () => {
    expect(validarEntrega({ tipo: "recoger", telefono: " 3001234567 " }))
      .toEqual({ tipo: "recoger", telefono: "3001234567" });
    expect(validarEntrega({ tipo: "domicilio", telefono: "3001234567", direccion: " Calle 10 # 5-20 " }))
      .toEqual({ tipo: "domicilio", telefono: "3001234567", direccion: "Calle 10 # 5-20" });
    // A recoger se ignora la dirección.
    expect(validarEntrega({ tipo: "recoger", telefono: "3001234567", direccion: "x" }))
      .toEqual({ tipo: "recoger", telefono: "3001234567" });
    for (const malo of [
      null,
      { tipo: "dron", telefono: "3001234567" },
      { tipo: "recoger", telefono: "300" },
      { tipo: "domicilio", telefono: "3001234567" },
      { tipo: "domicilio", telefono: "3001234567", direccion: "x".repeat(201) },
    ]) {
      expect(() => validarEntrega(malo)).toThrow(ErrorFuncion);
    }
  });

  it("mensaje de stock con la cantidad que queda", () => {
    expect(mensajeStock("Concentrado", 2)).toBe("Solo quedan 2 unidades de Concentrado");
    expect(mensajeStock("Collar", 1)).toBe("Solo queda 1 unidad de Collar");
    expect(mensajeStock("Collar", 0)).toBe("Collar ya no tiene unidades disponibles");
  });

  it("la referencia MSC-{orderId} identifica el pedido", () => {
    expect(pedidoDeReferencia("MSC-abc123XYZ")).toBe("abc123XYZ");
    expect(pedidoDeReferencia("OTRA-abc")).toBeNull();
    expect(pedidoDeReferencia("MSC-../users")).toBeNull();
    expect(pedidoDeReferencia("MSC-")).toBeNull();
    expect(pedidoDeReferencia(42)).toBeNull();
  });
});

describe("firma de integridad (Web Checkout)", () => {
  it("coincide con el ejemplo de la documentación de Wompi", async () => {
    // https://docs.wompi.co/docs/colombia/widget-checkout-web/ (sin expiración).
    expect(await firmaIntegridad({
      referencia: "sk8-438k4-xmxm392-sn2m",
      montoEnCentavos: 2490000,
      moneda: "COP",
      secretoIntegridad: "prod_integrity_Z5mMke9x0k8gpErbDqwrJXMqsI6SFli6",
    })).toBe("37c8407747e595535433ef8f6a811d853cd943046624a0ec04662b17bbf33bf5");
  });

  it("con expiración concatena la fecha antes del secreto", async () => {
    const expiracion = "2023-06-09T20:28:50.000Z";
    expect(await firmaIntegridad({
      referencia: "sk8-438k4-xmxm392-sn2m",
      montoEnCentavos: 2490000,
      expiracion,
      secretoIntegridad: "prod_integrity_Z5mMke9x0k8gpErbDqwrJXMqsI6SFli6",
    })).toBe(sha256(`sk8-438k4-xmxm392-sn2m2490000COP${expiracion}prod_integrity_Z5mMke9x0k8gpErbDqwrJXMqsI6SFli6`));
  });

  it("arma la URL del Web Checkout con todos los parámetros", () => {
    const url = new URL(urlCheckout({
      llavePublica: "pub_test_123",
      referencia: "MSC-o1",
      montoEnCentavos: 9000000,
      firma: "abc",
      redirectUrl: "https://x.supabase.co/functions/v1/webhook-wompi/retorno/o1",
      expiracion: "2026-11-18T15:15:00.000Z",
      correo: "ana@example.com",
    }));
    expect(url.origin + url.pathname).toBe("https://checkout.wompi.co/p/");
    expect(url.searchParams.get("public-key")).toBe("pub_test_123");
    expect(url.searchParams.get("currency")).toBe("COP");
    expect(url.searchParams.get("amount-in-cents")).toBe("9000000");
    expect(url.searchParams.get("reference")).toBe("MSC-o1");
    expect(url.searchParams.get("signature:integrity")).toBe("abc");
    expect(url.searchParams.get("redirect-url")).toBe("https://x.supabase.co/functions/v1/webhook-wompi/retorno/o1");
    expect(url.searchParams.get("expiration-time")).toBe("2026-11-18T15:15:00.000Z");
    expect(url.searchParams.get("customer-data:email")).toBe("ana@example.com");
  });
});

describe("firma de los eventos del webhook", () => {
  const tx = {
    id: "1234-1610641025-49201",
    status: "APPROVED",
    amount_in_cents: 4490000,
    reference: "MSC-o1",
    currency: "COP",
  };

  it("acepta un evento con la firma válida (como el ejemplo de la documentación)", async () => {
    const evento = eventoFirmado(tx);
    // Concatenación del ejemplo de Wompi: id + status + monto + timestamp + secreto.
    expect(await checksumEvento(evento, SECRETO_EVENTOS))
      .toBe(sha256(`1234-1610641025-49201APPROVED44900001763478000${SECRETO_EVENTOS}`));
    expect(await verificarEvento(evento, SECRETO_EVENTOS)).not.toBeNull();
    // También con el encabezado X-Event-Checksum.
    expect(await verificarEvento(evento, SECRETO_EVENTOS, evento.signature.checksum)).not.toBeNull();
  });

  it("rechaza un evento alterado", async () => {
    const evento = eventoFirmado(tx);
    const alterados = [
      { ...evento, data: { transaction: { ...tx, status: "DECLINED" } } },
      { ...evento, data: { transaction: { ...tx, amount_in_cents: 100 } } },
      { ...evento, timestamp: evento.timestamp + 1 },
      { ...evento, signature: { ...evento.signature, checksum: "0".repeat(64) } },
    ];
    for (const malo of alterados) {
      expect(await verificarEvento(malo, SECRETO_EVENTOS)).toBeNull();
    }
    // Firmado con otro secreto.
    expect(await verificarEvento(eventoFirmado(tx, "otro"), SECRETO_EVENTOS)).toBeNull();
    // El encabezado no coincide con la firma.
    expect(await verificarEvento(evento, SECRETO_EVENTOS, "f".repeat(64))).toBeNull();
  });

  it("rechaza cuerpos sin la forma de un evento o sin secreto configurado", async () => {
    for (const malo of [null, "texto", {}, { event: "transaction.updated", data: {} }]) {
      expect(await verificarEvento(malo, SECRETO_EVENTOS)).toBeNull();
    }
    expect(await verificarEvento(eventoFirmado(tx, ""), "")).toBeNull();
  });
});

describe("avisos de pedidos (RF-13)", () => {
  const pedido = {
    ownerUid: "ana",
    ownerNombre: "Ana Pérez",
    clinicNombre: "Vet Norte",
    clinicOwnerUid: "vet",
    total: 102500,
    items: [{ productId: "p1", nombre: "Concentrado", precio: 45000, cantidad: 2 }],
    entrega: { tipo: "domicilio", telefono: "3001234567", direccion: "Calle 10" },
  };

  it("pago aprobado: al dueño y 'Nuevo pedido' a la clínica, con ids fijos", () => {
    const avisos = avisosPedido("o1", pedido, "pagado");
    expect(avisos.map((a) => [a.uid, a.tipo, a.titulo, a.id])).toEqual([
      ["ana", "pedido", "Pago aprobado", "pedido_o1_pagado"],
      ["vet", "pedido_nuevo", "Nuevo pedido", "pedido_nuevo_o1"],
    ]);
    expect(avisos[1].cuerpo).toBe("Ana Pérez compró 2 productos ($102.500). Envío a domicilio.");
    expect(avisos.every((a) => a.referenciaId === "o1")).toBe(true);
  });

  it("pago rechazado y cancelación con el texto acordado", () => {
    expect(avisosPedido("o1", pedido, "pago_rechazado")[0].titulo).toBe("Tu pago no pudo ser procesado");
    const cancelado = avisosPedido("o1", { ...pedido, motivoCancelacion: "Sin repartidor" }, "cancelado")[0];
    expect(cancelado.cuerpo).toBe(
      "Tu pedido fue cancelado: Sin repartidor. La clínica se comunicará contigo para el reembolso",
    );
    expect(cancelado.prioridadAlta).toBe(true);
  });

  it("cada cambio de la clínica avisa al dueño", () => {
    for (const estado of ["preparando", "listo", "enviado", "entregado"] as const) {
      const [aviso] = avisosPedido("o1", pedido, estado);
      expect(aviso.uid).toBe("ana");
      expect(aviso.tipo).toBe("pedido");
      expect(aviso.id).toBe(`pedido_o1_${estado}`);
    }
    expect(avisosPedido("o1", pedido, "expirado")).toEqual([]);
  });
});
