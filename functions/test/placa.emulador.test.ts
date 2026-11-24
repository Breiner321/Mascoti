/**
 * Placa QR (RF-17): Edge Function placa-publica y reglas de qrTags contra el
 * emulador. Requieren el emulador:
 *   cd functions && npm run test:rules
 * Con `npm test` (sin emulador) se omiten.
 */
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { ClienteFirestore } from "../../supabase/functions/_shared/cliente_firestore.ts";
import { ErrorFuncion } from "../../supabase/functions/_shared/errores.ts";
import { camposFirestore, rutaDocumento, type ValorCampo } from "../../supabase/functions/_shared/firestore.ts";
import {
  consultarPlaca,
  type DependenciasPlaca,
  MENSAJE_INACTIVA,
} from "../../supabase/functions/_shared/placa.ts";

const host = process.env.FIRESTORE_EMULATOR_HOST;

const mostrarTodo = { nombreDueno: true, telefono: true, alergias: true, mensaje: "Recompensa" };

describe.skipIf(!host)("placa-publica (emulador)", () => {
  const PROYECTO = "demo-mascoti-placa";
  const db = new ClienteFirestore(PROYECTO, `http://${host}/v1`, async () => "owner");
  let intentos: Map<string, number>;
  let deps: DependenciasPlaca;

  async function poner(ruta: string, campos: { [campo: string]: ValorCampo }) {
    await db.commit([{ update: { name: rutaDocumento(PROYECTO, ruta), fields: camposFirestore(campos) } }]);
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

  beforeEach(async () => {
    await fetch(`http://${host}/emulator/v1/projects/${PROYECTO}/databases/(default)/documents`, {
      method: "DELETE",
    });
    intentos = new Map();
    deps = {
      db,
      firmarFoto: async (path) => `https://firmada.example/${path}?token=t`,
      // Límite de prueba: 2 por IP.
      registrarRevelacion: async (ipHash) => {
        const n = (intentos.get(ipHash) ?? 0) + 1;
        intentos.set(ipHash, n);
        return n <= 2 ? { permitido: true, reintentarEnSegundos: 0 } : { permitido: false, reintentarEnSegundos: 1500 };
      },
    };
    await poner("users/ana", { role: "dueno", estado: "activo", nombre: "Ana Pérez", telefono: "3001234567", email: "ana@x.co" });
    await poner("users/susp", { role: "dueno", estado: "suspendido", nombre: "Susp", telefono: "3009998877" });
    await poner("pets/p1", {
      ownerUid: "ana", nombre: "Luna", especie: "perro", fotoPath: "ana/p1/foto.jpg",
      alergias: ["Pollo", "Penicilina"], raza: "Criolla", codigoPaciente: "MSC-ABCD",
    });
    await poner("pets/p2", { ownerUid: "susp", nombre: "Max", especie: "gato" });
    await poner("qrTags/qrActiva0001", { petId: "p1", ownerUid: "ana", activo: true, mostrar: mostrarTodo });
    await poner("qrTags/qrMinima0001", {
      petId: "p1", ownerUid: "ana", activo: true,
      mostrar: { nombreDueno: false, telefono: false, alergias: false },
    });
    await poner("qrTags/qrApagada001", { petId: "p1", ownerUid: "ana", activo: false, mostrar: mostrarTodo });
    await poner("qrTags/qrSuspend001", { petId: "p2", ownerUid: "susp", activo: true, mostrar: mostrarTodo });
  });

  it("devuelve solo lo elegido, con el teléfono enmascarado", async () => {
    const ficha = await consultarPlaca(deps, { qrId: "qrActiva0001" }, "190.1.2.3");
    expect(ficha).toEqual({
      nombre: "Luna",
      especie: "Perro",
      fotoUrl: "https://firmada.example/ana/p1/foto.jpg?token=t",
      alergias: ["Pollo", "Penicilina"],
      mensaje: "Recompensa",
      nombreDueno: "Ana Pérez",
      telefonoEnmascarado: "300 *** **67",
    });
    // Nunca otros datos de la mascota o del dueño.
    const texto = JSON.stringify(ficha);
    for (const privado of ["3001234567", "MSC-ABCD", "ana@x.co", "Criolla", "ana/p1/foto.jpg\""]) {
      expect(texto).not.toContain(privado);
    }
  });

  it("sin nada elegido muestra solo nombre, especie y foto", async () => {
    expect(await consultarPlaca(deps, { qrId: "qrMinima0001" }, "1.1.1.1")).toEqual({
      nombre: "Luna", especie: "Perro", fotoUrl: "https://firmada.example/ana/p1/foto.jpg?token=t",
    });
  });

  it("revelar devuelve el teléfono completo, con límite por IP", async () => {
    const cuerpo = { qrId: "qrActiva0001", revelar: true };
    expect((await consultarPlaca(deps, cuerpo, "190.1.2.3")).telefono).toBe("3001234567");
    await consultarPlaca(deps, cuerpo, "190.1.2.3");
    const e = await error(consultarPlaca(deps, cuerpo, "190.1.2.3"));
    expect(e.codigo).toBe("resource-exhausted");
    expect(e.estadoHttp).toBe(429);
    expect(e.message).toBe("Ya viste varios teléfonos. Intenta de nuevo en 25 minutos.");
    // Otra IP sí puede; ver la ficha sin revelar no cuenta.
    expect((await consultarPlaca(deps, cuerpo, "200.1.1.1")).telefono).toBe("3001234567");
    expect((await consultarPlaca(deps, { qrId: "qrActiva0001" }, "190.1.2.3")).telefono).toBeUndefined();
  });

  it("no revela un teléfono que el dueño no comparte (ni cuenta el intento)", async () => {
    const e = await error(consultarPlaca(deps, { qrId: "qrMinima0001", revelar: true }, "190.1.2.3"));
    expect(e.codigo).toBe("failed-precondition");
    expect(intentos.size).toBe(0);
  });

  it("inactiva, inexistente, inválida o de una cuenta suspendida: no está activa", async () => {
    for (const qrId of ["qrApagada001", "noExiste0001", "qrSuspend001", "corto", "../users/ana1", 42, undefined]) {
      const e = await error(consultarPlaca(deps, { qrId }, "1.1.1.1"));
      expect(e.message).toBe(MENSAJE_INACTIVA);
      expect(e.estadoHttp).toBe(404);
    }
  });

  it("sin foto o si falla la firma, sigue sin foto", async () => {
    deps.firmarFoto = async () => {
      throw new Error("Storage caído");
    };
    expect((await consultarPlaca(deps, { qrId: "qrActiva0001" }, "1.1.1.1")).fotoUrl).toBeNull();
  });
});

describe.skipIf(!host)("firestore.rules: qrTags (RF-17)", () => {
  let env: RulesTestEnvironment;

  beforeAll(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-mascoti-qr-reglas",
      firestore: { rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8") },
    });
  });

  afterAll(async () => {
    await env?.cleanup();
  });

  const placa = (extra: Record<string, unknown> = {}) => ({
    petId: "p1",
    ownerUid: "ana",
    activo: true,
    mostrar: { nombreDueno: true, telefono: true, alergias: false, mensaje: "Llámame" },
    createdAt: serverTimestamp(),
    ...extra,
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "users/ana"), { role: "dueno", estado: "activo" });
      await setDoc(doc(db, "users/beto"), { role: "dueno", estado: "activo" });
      await setDoc(doc(db, "users/vet"), { role: "clinica", estado: "activo", clinicId: "c1" });
      await setDoc(doc(db, "pets/p1"), { ownerUid: "ana", nombre: "Luna" });
      await setDoc(doc(db, "pets/p2"), { ownerUid: "beto", nombre: "Max" });
      await setDoc(doc(db, "qrTags/existente01"), { ...placa(), createdAt: new Date() });
    });
  });

  it("solo el dueño de la mascota crea su placa", async () => {
    const ana = env.authenticatedContext("ana").firestore();
    const beto = env.authenticatedContext("beto").firestore();
    const vet = env.authenticatedContext("vet").firestore();
    await assertSucceeds(setDoc(doc(ana, "qrTags/nuevaPlaca01"), placa()));
    // Mascota ajena, otro ownerUid, clínica.
    await assertFails(setDoc(doc(beto, "qrTags/nuevaPlaca02"), placa({ ownerUid: "beto" })));
    await assertFails(setDoc(doc(ana, "qrTags/nuevaPlaca03"), placa({ petId: "p2" })));
    await assertFails(setDoc(doc(vet, "qrTags/nuevaPlaca04"), placa({ ownerUid: "vet" })));
  });

  it("valida id, campos y mostrar", async () => {
    const ana = env.authenticatedContext("ana").firestore();
    await assertFails(setDoc(doc(ana, "qrTags/corto"), placa()));
    await assertFails(setDoc(doc(ana, "qrTags/con-guion-1"), placa()));
    await assertFails(setDoc(doc(ana, "qrTags/nuevaPlaca05"), placa({ activo: false })));
    await assertFails(setDoc(doc(ana, "qrTags/nuevaPlaca06"), placa({ telefono: "3001234567" })));
    await assertFails(setDoc(doc(ana, "qrTags/nuevaPlaca07"), placa({ createdAt: new Date("2020-01-01") })));
    await assertFails(setDoc(doc(ana, "qrTags/nuevaPlaca08"), placa({
      mostrar: { nombreDueno: true, telefono: true, alergias: true, mensaje: "x".repeat(201) },
    })));
    await assertFails(setDoc(doc(ana, "qrTags/nuevaPlaca09"), placa({
      mostrar: { nombreDueno: "sí", telefono: true, alergias: true },
    })));
    await assertFails(setDoc(doc(ana, "qrTags/nuevaPlaca10"), placa({
      mostrar: { nombreDueno: true, telefono: true, alergias: true, email: true },
    })));
    await assertSucceeds(setDoc(doc(ana, "qrTags/nuevaPlaca11"), placa({
      mostrar: { nombreDueno: false, telefono: false, alergias: true },
    })));
  });

  it("solo el dueño la lee; nadie más", async () => {
    const ana = env.authenticatedContext("ana").firestore();
    const beto = env.authenticatedContext("beto").firestore();
    const anon = env.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(ana, "qrTags/existente01")));
    await assertSucceeds(getDocs(query(
      collection(ana, "qrTags"), where("ownerUid", "==", "ana"), where("petId", "==", "p1"),
    )));
    await assertFails(getDoc(doc(beto, "qrTags/existente01")));
    await assertFails(getDoc(doc(anon, "qrTags/existente01")));
    await assertFails(getDocs(query(collection(beto, "qrTags"), where("petId", "==", "p1"))));
  });

  it("el dueño activa, desactiva y cambia qué mostrar; nada más", async () => {
    const ana = env.authenticatedContext("ana").firestore();
    const beto = env.authenticatedContext("beto").firestore();
    const ref = doc(ana, "qrTags/existente01");
    await assertSucceeds(updateDoc(ref, { activo: false }));
    await assertSucceeds(updateDoc(ref, { activo: true }));
    await assertSucceeds(updateDoc(ref, { mostrar: { nombreDueno: false, telefono: true, alergias: true } }));
    await assertFails(updateDoc(ref, { petId: "p2" }));
    await assertFails(updateDoc(ref, { ownerUid: "beto" }));
    await assertFails(updateDoc(ref, { activo: "no" }));
    await assertFails(updateDoc(doc(beto, "qrTags/existente01"), { activo: false }));
    await assertFails(deleteDoc(ref));
  });
});
