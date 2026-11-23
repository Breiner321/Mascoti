/**
 * Edge Functions de la tienda (RF-12) contra el emulador de Firestore, con
 * la misma API REST que en producción. Requieren el emulador:
 *   cd functions && npm run test:rules
 * Con `npm test` (sin emulador) se omiten.
 *
 * Proyecto propio (demo-mascoti-pedidos) para no chocar con las demás pruebas.
 */
import { createHash } from "node:crypto";

import { beforeEach, describe, expect, it } from "vitest";

import { ClienteFirestore } from "../../supabase/functions/_shared/cliente_firestore.ts";
import { ErrorFuncion } from "../../supabase/functions/_shared/errores.ts";
import {
  camposFirestore,
  rutaDocumento,
  type ValorCampo,
} from "../../supabase/functions/_shared/firestore.ts";
import type { Aviso } from "../../supabase/functions/_shared/notificaciones.ts";
import { pasarelaSimulada, pasarelaWompi } from "../../supabase/functions/_shared/pasarela.ts";
import {
  actualizarPedido,
  crearPedido,
  type DependenciasCrearPedido,
  expirarPedidos,
  pagarPedidoSimulado,
  procesarEventoWompi,
} from "../../supabase/functions/_shared/pedidos.ts";

const host = process.env.FIRESTORE_EMULATOR_HOST;
const PROYECTO = "demo-mascoti-pedidos";
const SECRETO_EVENTOS = "test_events_secreto";
const AHORA = new Date("2026-11-18T15:00:00Z");
const MINUTO = 60 * 1000;

const sha256 = (texto: string) => createHash("sha256").update(texto).digest("hex");

function evento(orderId: string, status: string, montoEnCentavos: number, txId = `tx-${orderId}`) {
  const transaction = {
    id: txId,
    status,
    amount_in_cents: montoEnCentavos,
    reference: `MSC-${orderId}`,
    currency: "COP",
  };
  const timestamp = 1763478000;
  return {
    event: "transaction.updated",
    data: { transaction },
    environment: "test",
    signature: {
      properties: ["transaction.id", "transaction.status", "transaction.amount_in_cents"],
      checksum: sha256(`${txId}${status}${montoEnCentavos}${timestamp}${SECRETO_EVENTOS}`),
    },
    timestamp,
  };
}

describe.skipIf(!host)("Edge Functions de pedidos (emulador)", () => {
  const db = new ClienteFirestore(PROYECTO, `http://${host}/v1`, async () => "owner");
  let ahora: Date;
  let avisos: Aviso[];
  let ids: number;
  let deps: DependenciasCrearPedido;

  async function poner(ruta: string, campos: { [campo: string]: ValorCampo }) {
    await db.commit([{ update: { name: rutaDocumento(PROYECTO, ruta), fields: camposFirestore(campos) } }]);
  }

  async function leer(ruta: string) {
    return (await db.leer(ruta))?.datos;
  }

  const entrega = { tipo: "recoger", telefono: "3001234567" };

  function comprar(uid: string, cuerpo: Record<string, unknown> = { clinicId: "c1", entrega }) {
    return crearPedido(deps, `Bearer ${uid}`, cuerpo);
  }

  const webhookDeps = () => ({ ...deps, secretoEventos: SECRETO_EVENTOS });

  function webhook(cuerpo: unknown, encabezado?: string) {
    return procesarEventoWompi(webhookDeps(), cuerpo, encabezado);
  }

  function actualizar(uid: string, cuerpo: Record<string, unknown>) {
    return actualizarPedido(deps, `Bearer ${uid}`, cuerpo);
  }

  async function error(promesa: Promise<unknown>): Promise<ErrorFuncion> {
    try {
      await promesa;
    } catch (e) {
      if (e instanceof ErrorFuncion) return e;
      throw e;
    }
    throw new Error("Se esperaba ErrorFuncion");
  }

  async function producto(id: string) {
    return (await leer(`clinics/c1/products/${id}`))!;
  }

  beforeEach(async () => {
    await fetch(`http://${host}/emulator/v1/projects/${PROYECTO}/databases/(default)/documents`, {
      method: "DELETE",
    });
    ahora = AHORA;
    avisos = [];
    ids = 0;
    deps = {
      db,
      verificarToken: async (token) => ({ uid: token, email: `${token}@example.com` }),
      ahora: () => ahora,
      nuevoId: () => `pedido${++ids}`,
      notificar: async (aviso) => {
        avisos.push(aviso);
      },
      pasarela: pasarelaWompi({
        llavePublica: "pub_test_123",
        secretoIntegridad: "test_integrity_secreto",
        urlRegreso: "https://x.supabase.co/functions/v1/webhook-wompi/retorno",
      }),
    };

    await poner("users/ana", { role: "dueno", estado: "activo", nombre: "Ana Pérez" });
    await poner("users/beto", { role: "dueno", estado: "activo", nombre: "Beto Gil" });
    await poner("users/susp", { role: "dueno", estado: "suspendido" });
    await poner("users/vet", { role: "clinica", estado: "activo", clinicId: "c1" });
    await poner("users/vet2", { role: "clinica", estado: "activo", clinicId: "c2" });
    await poner("clinics/c1", { ownerUid: "vet", nombre: "Vet Norte", estado: "activo" });
    await poner("clinics/c2", { ownerUid: "vet2", nombre: "Vet Sur", estado: "activo" });
    await poner("clinics/c3", { ownerUid: "vet3", nombre: "Incompleta", estado: "incompleto" });
    const base = { clinicId: "c1", categoria: "alimento", fotoPath: "vet/x.jpg", stockReservado: 0 };
    await poner("clinics/c1/products/p1", { ...base, nombre: "Concentrado", precio: 45000, stock: 5, estado: "activo" });
    await poner("clinics/c1/products/p2", { ...base, nombre: "Collar", precio: 12500, stock: 1, estado: "activo" });
    await poner("clinics/c1/products/p3", { ...base, nombre: "Retirado", precio: 9000, stock: 3, estado: "inactivo" });
    await poner("clinics/c2/products/q1", { ...base, clinicId: "c2", nombre: "Pelota", precio: 8000, stock: 9, estado: "activo" });
    // La app manda un precio de referencia viejo: el servidor no lo usa.
    await poner("users/ana/cart/p1", { clinicId: "c1", nombre: "Concentrado", precio: 1, cantidad: 2 });
    await poner("users/ana/cart/p2", { clinicId: "c1", nombre: "Collar", precio: 1, cantidad: 1 });
  });

  describe("crear-pedido", () => {
    it("calcula el total con los precios del servidor, aparta el stock y firma el checkout", async () => {
      const r = await comprar("ana");
      expect(r.orderId).toBe("pedido1");
      expect(r.total).toBe(2 * 45000 + 12500);
      expect(r.reutilizado).toBe(false);

      const pedido = (await leer("orders/pedido1"))!;
      expect(pedido).toMatchObject({
        ownerUid: "ana",
        ownerNombre: "Ana Pérez",
        clinicId: "c1",
        clinicNombre: "Vet Norte",
        clinicOwnerUid: "vet",
        total: 102500,
        estado: "pendiente_pago",
        referenciaPago: "MSC-pedido1",
        entrega: { tipo: "recoger", telefono: "3001234567" },
      });
      expect(pedido.items).toEqual(expect.arrayContaining([
        { productId: "p1", nombre: "Concentrado", precio: 45000, cantidad: 2 },
        { productId: "p2", nombre: "Collar", precio: 12500, cantidad: 1 },
      ]));
      expect((pedido.expiraEn as Date).getTime()).toBe(AHORA.getTime() + 15 * MINUTO);

      // Reserva, no descuento: el stock físico no cambia.
      expect(await producto("p1")).toMatchObject({ stock: 5, stockReservado: 2, estado: "activo" });
      expect(await producto("p2")).toMatchObject({ stock: 1, stockReservado: 1, estado: "activo" });

      const url = new URL(r.checkoutUrl!);
      const expiracion = new Date(AHORA.getTime() + 15 * MINUTO).toISOString();
      expect(url.searchParams.get("amount-in-cents")).toBe("10250000");
      expect(url.searchParams.get("reference")).toBe("MSC-pedido1");
      expect(url.searchParams.get("expiration-time")).toBe(expiracion);
      expect(url.searchParams.get("signature:integrity"))
        .toBe(sha256(`MSC-pedido110250000COP${expiracion}test_integrity_secreto`));
      expect(r.redirectUrl).toBe("https://x.supabase.co/functions/v1/webhook-wompi/retorno/pedido1");
      expect(url.searchParams.get("redirect-url")).toBe(r.redirectUrl);
    });

    it("valida usuario, clínica, carrito y entrega", async () => {
      expect((await error(comprar("vet"))).codigo).toBe("permission-denied");
      expect((await error(comprar("susp"))).codigo).toBe("permission-denied");
      expect((await error(crearPedido(deps, null, { clinicId: "c1", entrega }))).codigo).toBe("unauthenticated");
      expect((await error(comprar("ana", { clinicId: "c3", entrega }))).message)
        .toBe("Esta clínica no está vendiendo en este momento.");
      expect((await error(comprar("ana", { clinicId: "c1", entrega: { tipo: "domicilio", telefono: "3001234567" } })))
        .codigo).toBe("invalid-argument");
      expect((await error(comprar("beto"))).message).toBe("Tu carrito está vacío.");
      await poner("users/ana/cart/q1", { clinicId: "c2", nombre: "Pelota", precio: 8000, cantidad: 1 });
      expect((await error(comprar("ana"))).message)
        .toBe("Tu carrito tiene productos de otra clínica. Vacíalo antes de pagar.");
      expect(await leer("orders/pedido1")).toBeUndefined();
    });

    it("sin stock suficiente devuelve la lista de problemas y no aparta nada", async () => {
      await poner("users/ana/cart/p1", { clinicId: "c1", nombre: "Concentrado", precio: 1, cantidad: 6 });
      await poner("users/ana/cart/p2", { clinicId: "c1", nombre: "Collar", precio: 1, cantidad: 2 });
      await poner("users/ana/cart/p3", { clinicId: "c1", nombre: "Retirado", precio: 1, cantidad: 1 });
      const e = await error(comprar("ana"));
      expect(e.codigo).toBe("failed-precondition");
      expect(e.message.split("\n").sort()).toEqual([
        "Retirado ya no está disponible",
        "Solo queda 1 unidad de Collar",
        "Solo quedan 5 unidades de Concentrado",
      ]);
      expect((await producto("p1")).stockReservado).toBe(0);
    });

    it("lo reservado por otro no está disponible", async () => {
      await poner("users/beto/cart/p2", { clinicId: "c1", nombre: "Collar", precio: 12500, cantidad: 1 });
      await comprar("beto");
      expect((await error(comprar("ana"))).message).toBe("Collar ya no tiene unidades disponibles");
    });

    it("carrera por la última unidad: de dos compras simultáneas solo una gana", async () => {
      await db.commit([{ delete: rutaDocumento(PROYECTO, "users/ana/cart/p1") }]);
      await poner("users/beto/cart/p2", { clinicId: "c1", nombre: "Collar", precio: 12500, cantidad: 1 });
      deps.nuevoId = () => `carrera${++ids}`;

      const resultados = await Promise.allSettled([comprar("ana"), comprar("beto")]);
      const ganadores = resultados.filter((r) => r.status === "fulfilled");
      const perdedores = resultados.filter((r) => r.status === "rejected") as PromiseRejectedResult[];
      expect(ganadores).toHaveLength(1);
      expect(perdedores).toHaveLength(1);
      expect(perdedores[0].reason).toBeInstanceOf(ErrorFuncion);
      expect(perdedores[0].reason.message).toBe("Collar ya no tiene unidades disponibles");
      expect(await producto("p2")).toMatchObject({ stock: 1, stockReservado: 1 });
    });

    it("reutiliza un pedido pendiente idéntico y reemplaza uno distinto", async () => {
      const primero = await comprar("ana");
      const otra = await comprar("ana");
      expect(otra.orderId).toBe(primero.orderId);
      expect(otra.reutilizado).toBe(true);
      expect((await producto("p1")).stockReservado).toBe(2);

      // Cambió la entrega: el anterior expira y su reserva pasa al nuevo.
      const domicilio = { tipo: "domicilio", telefono: "3001234567", direccion: "Calle 10 # 5-20" };
      const nuevo = await comprar("ana", { clinicId: "c1", entrega: domicilio });
      expect(nuevo.orderId).toBe("pedido2");
      expect((await leer(`orders/${primero.orderId}`))!.estado).toBe("expirado");
      expect(await producto("p1")).toMatchObject({ stockReservado: 2 });
      expect(await producto("p2")).toMatchObject({ stockReservado: 1 });
    });

    it("límite de pedidos pendientes por usuario", async () => {
      for (const id of ["v1", "v2", "v3"]) {
        await poner(`orders/${id}`, {
          ownerUid: "ana", clinicId: "c2", estado: "pendiente_pago", total: 8000,
          items: [], expiraEn: new Date(AHORA.getTime() + 10 * MINUTO),
        });
      }
      const e = await error(comprar("ana"));
      expect(e.codigo).toBe("resource-exhausted");
      expect(e.message).toBe("Tienes 3 pagos pendientes. Termínalos o espera 15 minutos.");
    });
  });

  describe("webhook-wompi", () => {
    it("APPROVED: pagado, stock descontado, agotado en 0, carrito vaciado y avisos", async () => {
      const { orderId } = await comprar("ana");
      await poner("users/ana/cart/q9", { clinicId: "c1", nombre: "Otro", precio: 1, cantidad: 1 });
      const r = await webhook(evento(orderId, "APPROVED", 10250000));
      expect(r).toEqual({ resultado: "pagado", orderId });

      expect(await leer(`orders/${orderId}`)).toMatchObject({
        estado: "pagado", wompiTransactionId: `tx-${orderId}`, wompiEstado: "APPROVED",
      });
      expect(await producto("p1")).toMatchObject({ stock: 3, stockReservado: 0, estado: "activo" });
      expect(await producto("p2")).toMatchObject({ stock: 0, stockReservado: 0, estado: "agotado" });
      expect(await leer("users/ana/cart/p1")).toBeUndefined();
      expect(await leer("users/ana/cart/p2")).toBeUndefined();
      // Solo se quita lo comprado.
      expect(await leer("users/ana/cart/q9")).toBeDefined();
      expect(avisos.map((a) => [a.uid, a.tipo, a.titulo])).toEqual([
        ["ana", "pedido", "Pago aprobado"],
        ["vet", "pedido_nuevo", "Nuevo pedido"],
      ]);
    });

    it("es idempotente: el mismo evento dos veces no descuenta dos veces", async () => {
      const { orderId } = await comprar("ana");
      const cuerpo = evento(orderId, "APPROVED", 10250000);
      await webhook(cuerpo);
      const segunda = await webhook(cuerpo);
      expect(segunda).toEqual({ resultado: "duplicado", orderId });
      expect(await producto("p1")).toMatchObject({ stock: 3, stockReservado: 0 });
      expect(avisos).toHaveLength(2);
    });

    it("eventos simultáneos repetidos: solo uno aplica", async () => {
      const { orderId } = await comprar("ana");
      const cuerpo = evento(orderId, "APPROVED", 10250000);
      const r = await Promise.all([webhook(cuerpo), webhook(cuerpo), webhook(cuerpo)]);
      expect(r.filter((x) => x.resultado === "pagado")).toHaveLength(1);
      expect(await producto("p1")).toMatchObject({ stock: 3, stockReservado: 0 });
    });

    it("DECLINED, VOIDED o ERROR: pago_rechazado y se libera la reserva", async () => {
      for (const estado of ["DECLINED", "VOIDED", "ERROR"]) {
        const { orderId } = await comprar("ana");
        expect((await producto("p1")).stockReservado).toBe(2);
        expect(await webhook(evento(orderId, estado, 10250000)))
          .toEqual({ resultado: "pago_rechazado", orderId });
        expect((await leer(`orders/${orderId}`))!.estado).toBe("pago_rechazado");
        expect(await producto("p1")).toMatchObject({ stock: 5, stockReservado: 0 });
        // El carrito sigue para intentarlo de nuevo.
        expect(await leer("users/ana/cart/p1")).toBeDefined();
      }
      expect(avisos.every((a) => a.uid === "ana" && a.titulo === "Tu pago no pudo ser procesado")).toBe(true);
    });

    it("rechaza un evento con firma inválida sin tocar nada", async () => {
      const { orderId } = await comprar("ana");
      const alterado = evento(orderId, "APPROVED", 10250000);
      alterado.signature.checksum = sha256("otra cosa");
      const e = await error(webhook(alterado));
      expect(e.codigo).toBe("unauthenticated");
      expect(e.estadoHttp).toBe(401);
      expect((await leer(`orders/${orderId}`))!.estado).toBe("pendiente_pago");
    });

    it("ignora un monto o una referencia que no coinciden con el pedido", async () => {
      const { orderId } = await comprar("ana");
      expect(await webhook(evento(orderId, "APPROVED", 100)))
        .toMatchObject({ resultado: "ignorado", motivo: "monto o referencia no coinciden" });
      expect(await webhook(evento("noexiste", "APPROVED", 10250000)))
        .toMatchObject({ resultado: "ignorado" });
      expect((await leer(`orders/${orderId}`))!.estado).toBe("pendiente_pago");
      // PENDING no cambia nada.
      expect(await webhook(evento(orderId, "PENDING", 10250000))).toMatchObject({ resultado: "ignorado" });
    });

    it("pago aprobado de un pedido ya expirado: no revive ni descuenta; avisa al dueño", async () => {
      const { orderId } = await comprar("ana");
      ahora = new Date(AHORA.getTime() + 16 * MINUTO);
      expect(await expirarPedidos(deps)).toEqual({ expirados: 1 });
      const r = await webhook(evento(orderId, "APPROVED", 10250000));
      expect(r).toEqual({ resultado: "pago_tardio", orderId });
      expect(await leer(`orders/${orderId}`)).toMatchObject({ estado: "expirado", pagoTardio: true });
      expect(await producto("p1")).toMatchObject({ stock: 5, stockReservado: 0 });
      expect(avisos.map((a) => a.titulo)).toEqual(["Recibimos un pago de un pedido no activo"]);
      expect((await webhook(evento(orderId, "APPROVED", 10250000))).resultado).toBe("duplicado");
    });

    it("un intento rechazado y luego uno aprobado con la misma referencia: pago no activo", async () => {
      const { orderId } = await comprar("ana");
      await webhook(evento(orderId, "DECLINED", 10250000, "tx-1"));
      const r = await webhook(evento(orderId, "APPROVED", 10250000, "tx-2"));
      expect(r).toEqual({ resultado: "pago_tardio", orderId });
      expect(await leer(`orders/${orderId}`)).toMatchObject({
        estado: "pago_rechazado", pagoTardio: true, wompiTransactionId: "tx-2",
      });
      expect(await producto("p1")).toMatchObject({ stock: 5, stockReservado: 0 });
    });
  });

  describe("actualizar-pedido", () => {
    async function pagado(tipo: "recoger" | "domicilio" = "recoger") {
      const cuerpo = tipo === "recoger"
        ? { clinicId: "c1", entrega }
        : { clinicId: "c1", entrega: { tipo, telefono: "3001234567", direccion: "Calle 10" } };
      const { orderId } = await comprar("ana", cuerpo);
      await webhook(evento(orderId, "APPROVED", 10250000));
      avisos = [];
      return orderId;
    }

    it("recorre pagado → preparando → listo → entregado con push al dueño", async () => {
      const orderId = await pagado();
      for (const estado of ["preparando", "listo", "entregado"]) {
        expect(await actualizar("vet", { orderId, estado })).toEqual({ ok: true, estado });
        expect((await leer(`orders/${orderId}`))!.estado).toBe(estado);
      }
      expect(avisos.map((a) => a.titulo)).toEqual([
        "Tu pedido está en preparación", "Tu pedido está listo", "Pedido entregado",
      ]);
      expect(avisos.every((a) => a.uid === "ana" && a.referenciaId === orderId)).toBe(true);
    });

    it("respeta la máquina de estados y el tipo de entrega", async () => {
      const orderId = await pagado();
      expect((await error(actualizar("vet", { orderId, estado: "entregado" }))).codigo).toBe("failed-precondition");
      await actualizar("vet", { orderId, estado: "preparando" });
      expect((await error(actualizar("vet", { orderId, estado: "enviado" }))).message)
        .toBe("Este pedido es para recoger: márcalo como listo.");
      expect((await error(actualizar("vet", { orderId, estado: "pagado" }))).message).toBe("Estado no válido.");
    });

    it("solo la clínica del pedido", async () => {
      const orderId = await pagado();
      expect((await error(actualizar("vet2", { orderId, estado: "preparando" }))).codigo).toBe("permission-denied");
      expect((await error(actualizar("ana", { orderId, estado: "preparando" }))).codigo).toBe("permission-denied");
      expect((await error(actualizar("vet", { orderId: "nada", estado: "preparando" }))).codigo).toBe("not-found");
    });

    it("cancelar un pedido pagado exige motivo, devuelve el stock y avisa del reembolso", async () => {
      const orderId = await pagado("domicilio");
      expect(await producto("p2")).toMatchObject({ stock: 0, estado: "agotado" });
      expect((await error(actualizar("vet", { orderId, estado: "cancelado" }))).message)
        .toBe("Indica el motivo de la cancelación.");
      await actualizar("vet", { orderId, estado: "cancelado", motivo: " Sin repartidor " });

      expect(await leer(`orders/${orderId}`)).toMatchObject({ estado: "cancelado", motivoCancelacion: "Sin repartidor" });
      expect(await producto("p1")).toMatchObject({ stock: 5, stockReservado: 0, estado: "activo" });
      expect(await producto("p2")).toMatchObject({ stock: 1, estado: "activo" });
      expect(avisos[0].cuerpo).toBe(
        "Tu pedido fue cancelado: Sin repartidor. La clínica se comunicará contigo para el reembolso",
      );
    });

    it("no se cancela un pedido enviado", async () => {
      const orderId = await pagado("domicilio");
      await actualizar("vet", { orderId, estado: "preparando" });
      await actualizar("vet", { orderId, estado: "enviado" });
      expect((await error(actualizar("vet", { orderId, estado: "cancelado", motivo: "x" }))).message)
        .toBe("Solo puedes cancelar un pedido pagado o en preparación.");
    });
  });

  describe("tarea de pedidos vencidos", () => {
    it("expira los pendientes de más de 15 min y libera su stock", async () => {
      const { orderId } = await comprar("ana");
      ahora = new Date(AHORA.getTime() + 14 * MINUTO);
      expect(await expirarPedidos(deps)).toEqual({ expirados: 0 });
      ahora = new Date(AHORA.getTime() + 16 * MINUTO);
      expect(await expirarPedidos(deps)).toEqual({ expirados: 1 });
      expect((await leer(`orders/${orderId}`))!.estado).toBe("expirado");
      expect(await producto("p1")).toMatchObject({ stock: 5, stockReservado: 0 });
      // Dos veces no libera dos veces.
      expect(await expirarPedidos(deps)).toEqual({ expirados: 0 });
      expect((await producto("p1")).stockReservado).toBe(0);
    });
  });

  describe("pago simulado (sin pasarela)", () => {
    const simulado = () => ({ ...deps, pasarela: pasarelaSimulada });

    function pagar(uid: string, cuerpo: Record<string, unknown>, pasarelaActiva: "simulada" | "wompi" = "simulada") {
      return pagarPedidoSimulado({ ...deps, pasarelaActiva }, `Bearer ${uid}`, cuerpo);
    }

    it("crear-pedido no devuelve enlace de pago y marca el pedido como simulado", async () => {
      const r = await crearPedido(simulado(), "Bearer ana", { clinicId: "c1", entrega });
      expect(r).toMatchObject({ pasarela: "simulada", checkoutUrl: null, redirectUrl: null, total: 102500 });
      expect(await leer(`orders/${r.orderId}`)).toMatchObject({
        estado: "pendiente_pago",
        pasarela: "simulada",
      });
      expect(await producto("p1")).toMatchObject({ stock: 5, stockReservado: 2 });
    });

    it("aprobado: pagado, stock descontado, agotado en 0, carrito vaciado y avisos", async () => {
      const { orderId } = await crearPedido(simulado(), "Bearer ana", { clinicId: "c1", entrega });
      avisos = [];
      expect(await pagar("ana", { orderId, resultado: "aprobado" })).toEqual({ resultado: "pagado", orderId });

      expect(await leer(`orders/${orderId}`)).toMatchObject({
        estado: "pagado",
        transaccionId: `SIM-${orderId}`,
        estadoPasarela: "APPROVED",
      });
      expect(await producto("p1")).toMatchObject({ stock: 3, stockReservado: 0, estado: "activo" });
      expect(await producto("p2")).toMatchObject({ stock: 0, stockReservado: 0, estado: "agotado" });
      expect(await leer("users/ana/cart/p1")).toBeUndefined();
      expect(avisos.map((a) => [a.uid, a.tipo])).toEqual([
        ["ana", "pedido"],
        ["vet", "pedido_nuevo"],
      ]);

      // Repetir no descuenta dos veces.
      expect(await pagar("ana", { orderId, resultado: "aprobado" })).toEqual({ resultado: "duplicado", orderId });
      expect((await producto("p1")).stock).toBe(3);
    });

    it("rechazado: pago_rechazado, libera la reserva y deja el carrito", async () => {
      const { orderId } = await crearPedido(simulado(), "Bearer ana", { clinicId: "c1", entrega });
      expect(await pagar("ana", { orderId, resultado: "rechazado" }))
        .toEqual({ resultado: "pago_rechazado", orderId });
      expect(await leer(`orders/${orderId}`)).toMatchObject({
        estado: "pago_rechazado",
        estadoPasarela: "DECLINED",
      });
      expect(await producto("p1")).toMatchObject({ stock: 5, stockReservado: 0 });
      expect(await leer("users/ana/cart/p1")).toBeDefined();
      expect((await error(pagar("ana", { orderId, resultado: "aprobado" }))).message)
        .toBe("Este pedido ya no se puede pagar.");
    });

    it("solo el dueño, con datos válidos, a tiempo y con la pasarela simulada activa", async () => {
      const { orderId } = await crearPedido(simulado(), "Bearer ana", { clinicId: "c1", entrega });

      expect((await error(pagar("beto", { orderId, resultado: "aprobado" }))).codigo).toBe("not-found");
      expect((await error(pagar("ana", { orderId, resultado: "quizas" }))).codigo).toBe("invalid-argument");
      expect((await error(pagar("ana", { resultado: "aprobado" }))).codigo).toBe("invalid-argument");
      expect((await error(pagar("ana", { orderId, resultado: "aprobado" }, "wompi"))).message)
        .toBe("Los pagos de prueba están desactivados.");

      ahora = new Date(AHORA.getTime() + 16 * MINUTO);
      expect((await error(pagar("ana", { orderId, resultado: "aprobado" }))).message)
        .toBe("El tiempo para pagar este pedido terminó. Vuelve a confirmar la compra.");
      expect((await leer(`orders/${orderId}`))!.estado).toBe("pendiente_pago");
    });

    it("un pedido de Wompi no se puede pagar como simulado", async () => {
      const { orderId } = await comprar("ana");
      expect((await error(pagar("ana", { orderId, resultado: "aprobado" }))).message)
        .toBe("Este pedido no admite pagos de prueba.");
    });
  });
});
