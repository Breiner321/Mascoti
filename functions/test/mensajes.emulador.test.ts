/**
 * Edge Function notificar-mensaje (RF-15) contra el emulador de Firestore:
 * verifica emisor y participantes, no avisa lo ya leído, agrupa ráfagas y
 * arma el push con el nombre visible del emisor. FCM es un falso.
 *   cd functions && npm run test:rules
 */
import { beforeEach, describe, expect, it } from "vitest";

import { ClienteFirestore } from "../../supabase/functions/_shared/cliente_firestore.ts";
import { ErrorFuncion } from "../../supabase/functions/_shared/errores.ts";
import {
  camposFirestore,
  rutaDocumento,
  type ValorCampo,
} from "../../supabase/functions/_shared/firestore.ts";
import {
  CUERPO_ADJUNTO,
  type DependenciasMensajes,
  notificarMensaje,
} from "../../supabase/functions/_shared/mensajes.ts";
import type { MensajePush } from "../../supabase/functions/_shared/notificaciones.ts";

const host = process.env.FIRESTORE_EMULATOR_HOST;
const PROYECTO = "demo-mascoti-mensajes";
const CHAT = "ana_c1";

describe.skipIf(!host)("notificar-mensaje (emulador)", () => {
  const db = new ClienteFirestore(PROYECTO, `http://${host}/v1`, async () => "owner");
  let pushes: { token: string; mensaje: MensajePush }[];
  let ahora: Date;
  let deps: DependenciasMensajes;

  async function poner(ruta: string, campos: { [campo: string]: ValorCampo }) {
    await db.commit([{ update: { name: rutaDocumento(PROYECTO, ruta), fields: camposFirestore(campos) } }]);
  }

  const llamar = (uid: string, cuerpo: unknown = { chatId: CHAT, messageId: "m1" }) =>
    notificarMensaje(deps, `Bearer token-${uid}`, cuerpo);

  beforeEach(async () => {
    await fetch(`http://${host}/emulator/v1/projects/${PROYECTO}/databases/(default)/documents`, {
      method: "DELETE",
    });
    pushes = [];
    ahora = new Date("2026-11-10T15:00:00Z");
    deps = {
      db,
      verificarToken: async (token) => {
        if (!token.startsWith("token-")) throw new Error("firma inválida");
        return { uid: token.slice("token-".length) };
      },
      enviarPush: async (token, mensaje) => {
        pushes.push({ token, mensaje });
        return "ok";
      },
      ahora: () => ahora,
    };
    await poner("users/ana", { role: "dueno", estado: "activo", nombre: "Ana Pérez", displayName: "ana.g" });
    await poner("users/vet", { role: "clinica", estado: "activo", clinicId: "c1" });
    await poner("users/beto", { role: "dueno", estado: "activo" });
    await poner("clinics/c1", { ownerUid: "vet", nombre: "Vet Norte", estado: "activo" });
    await poner("users/vet/devices/d1", { fcmToken: "tok-vet", plataforma: "android", valido: true });
    await poner("users/ana/devices/d1", { fcmToken: "tok-ana", plataforma: "android", valido: true });
    await poner(`chats/${CHAT}`, {
      participantes: ["ana", "vet"], ownerUid: "ana", clinicId: "c1", clinicOwnerUid: "vet",
      ownerNombre: "Ana Pérez", clinicNombre: "Vet Norte (copia)", noLeidos: { ana: 0, vet: 1 },
      typing: {},
    });
    await poner(`chats/${CHAT}/messages/m1`, {
      senderUid: "ana", tipo: "texto", texto: "  Hola,\n¿Luna puede comer antes de la cirugía?  ",
      leido: false,
    });
  });

  it("push al receptor con el nombre del dueño y la vista previa; guarda ultimoPush", async () => {
    expect(await llamar("ana")).toEqual({ enviado: true, dispositivos: 1 });
    expect(pushes).toEqual([{
      token: "tok-vet",
      mensaje: {
        titulo: "Ana Pérez",
        cuerpo: "Hola, ¿Luna puede comer antes de la cirugía?",
        datos: { tipo: "mensaje", referenciaId: CHAT },
        prioridadAlta: false,
        etiqueta: CHAT,
      },
    }]);
    const chat = (await db.leer(`chats/${CHAT}`))!.datos;
    expect(chat.ultimoPush).toEqual({ vet: ahora });
    // No toca el resto del chat ni crea notificaciones.
    expect(chat.noLeidos).toEqual({ ana: 0, vet: 1 });
    expect(chat.clinicNombre).toBe("Vet Norte (copia)");
    expect(await db.consultar({ coleccion: "notifications", filtros: [] })).toEqual([]);
  });

  it("de la clínica: el nombre comercial; adjunto y varios sin leer", async () => {
    await poner(`chats/${CHAT}`, {
      participantes: ["ana", "vet"], ownerUid: "ana", clinicId: "c1", clinicOwnerUid: "vet",
      clinicNombre: "Copia vieja", noLeidos: { ana: 3, vet: 0 },
    });
    await poner(`chats/${CHAT}/messages/m2`, {
      senderUid: "vet", tipo: "adjunto", adjunto: { path: `${CHAT}/x-rx.png`, nombre: "rx.png" }, leido: false,
    });
    await llamar("vet", { chatId: CHAT, messageId: "m2" });
    expect(pushes).toHaveLength(1);
    expect(pushes[0].token).toBe("tok-ana");
    expect(pushes[0].mensaje.titulo).toBe("Vet Norte");
    expect(pushes[0].mensaje.cuerpo).toBe(`3 mensajes nuevos · ${CUERPO_ADJUNTO}`);
  });

  it("agrupa ráfagas: un push cada 30 s por conversación y receptor", async () => {
    await llamar("ana");
    await poner(`chats/${CHAT}/messages/m2`, { senderUid: "ana", tipo: "texto", texto: "¿?", leido: false });
    ahora = new Date(ahora.getTime() + 10_000);
    expect(await llamar("ana", { chatId: CHAT, messageId: "m2" })).toEqual({ enviado: false, motivo: "agrupado" });
    // Repetir la llamada del mismo mensaje tampoco envía otro.
    expect(await llamar("ana")).toEqual({ enviado: false, motivo: "agrupado" });
    ahora = new Date(ahora.getTime() + 25_000);
    expect(await llamar("ana", { chatId: CHAT, messageId: "m2" })).toEqual({ enviado: true, dispositivos: 1 });
    expect(pushes).toHaveLength(2);
  });

  it("no avisa si el receptor ya lo leyó (tenía la conversación abierta)", async () => {
    await poner(`chats/${CHAT}/messages/m1`, { senderUid: "ana", tipo: "texto", texto: "Hola", leido: true });
    expect(await llamar("ana")).toEqual({ enviado: false, motivo: "leido" });
    await poner(`chats/${CHAT}/messages/m1`, { senderUid: "ana", tipo: "texto", texto: "Hola", leido: false });
    await poner(`chats/${CHAT}`, {
      participantes: ["ana", "vet"], ownerUid: "ana", clinicId: "c1", clinicOwnerUid: "vet",
      noLeidos: { ana: 0, vet: 0 },
    });
    expect(await llamar("ana")).toEqual({ enviado: false, motivo: "leido" });
    expect(pushes).toEqual([]);
  });

  it("solo el emisor, participante y con sesión", async () => {
    const error = (p: Promise<unknown>) => p.then(() => null, (e) => e as ErrorFuncion);
    expect((await error(llamar("vet")))?.codigo).toBe("permission-denied");
    expect((await error(llamar("beto")))?.codigo).toBe("permission-denied");
    expect((await error(notificarMensaje(deps, null, { chatId: CHAT, messageId: "m1" })))?.codigo)
      .toBe("unauthenticated");
    expect((await error(notificarMensaje(deps, "Bearer falso", { chatId: CHAT, messageId: "m1" })))?.codigo)
      .toBe("unauthenticated");
    expect((await error(llamar("ana", { chatId: CHAT, messageId: "nada" })))?.codigo).toBe("not-found");
    expect((await error(llamar("ana", { chatId: "../users", messageId: "m1" })))?.codigo)
      .toBe("invalid-argument");
    expect((await error(llamar("ana", { chatId: "otro_c9", messageId: "m1" })))?.codigo)
      .toBe("permission-denied");
    expect(pushes).toEqual([]);
  });
});
