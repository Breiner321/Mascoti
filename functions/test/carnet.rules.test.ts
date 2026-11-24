/**
 * Reglas del último carnet de vacunas (RF-18): pets/{petId}/documentos.
 * Requieren el emulador:
 *   cd functions && npm run test:rules
 * Con `npm test` (sin emulador) se omiten automáticamente.
 */
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, Timestamp } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

const conEmulador = Boolean(process.env.FIRESTORE_EMULATOR_HOST);

describe.skipIf(!conEmulador)("firestore.rules: documentos (RF-18)", () => {
  let env: RulesTestEnvironment;

  beforeAll(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-mascoti-carnet",
      firestore: { rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8") },
    });
  });

  afterAll(async () => {
    await env?.cleanup();
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "users/ana"), { role: "dueno", estado: "activo" });
      await setDoc(doc(db, "users/beto"), { role: "dueno", estado: "activo" });
      await setDoc(doc(db, "users/sus"), { role: "dueno", estado: "suspendido" });
      await setDoc(doc(db, "pets/p1"), { ownerUid: "ana", nombre: "Luna", especie: "perro" });
      await setDoc(doc(db, "pets/p1/documentos/carnet"), {
        path: "pets/p1/documentos/carnet-2026-11-24.pdf",
        generadoAt: Timestamp.now(),
        vacunas: 2,
      });
    });
  });

  it("el dueño activo lee su último carnet", async () => {
    await assertSucceeds(getDoc(doc(env.authenticatedContext("ana").firestore(), "pets/p1/documentos/carnet")));
  });

  it("otro dueño, una cuenta suspendida o sin sesión no lo leen", async () => {
    await assertFails(getDoc(doc(env.authenticatedContext("beto").firestore(), "pets/p1/documentos/carnet")));
    await assertFails(getDoc(doc(env.authenticatedContext("sus").firestore(), "pets/p1/documentos/carnet")));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "pets/p1/documentos/carnet")));
  });

  it("nadie lo escribe desde la app (solo la Edge Function)", async () => {
    await assertFails(setDoc(doc(env.authenticatedContext("ana").firestore(), "pets/p1/documentos/carnet"), {
      path: "otro.pdf",
      generadoAt: Timestamp.now(),
      vacunas: 0,
    }));
  });
});
