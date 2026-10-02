/**
 * Pruebas de firestore.rules. Requieren el emulador:
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
import { doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

const conEmulador = Boolean(process.env.FIRESTORE_EMULATOR_HOST);

describe.skipIf(!conEmulador)("firestore.rules", () => {
  let env: RulesTestEnvironment;

  beforeAll(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-mascoti",
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
      await setDoc(doc(db, "users/ana"), { uid: "ana", role: "dueno", estado: "activo" });
      await setDoc(doc(db, "users/vet"), { uid: "vet", role: "clinica", estado: "activo", clinicId: "c1" });
      await setDoc(doc(db, "clinics/c1"), { ownerUid: "vet", nombre: "Vet", estado: "incompleto" });
    });
  });

  it("un usuario lee solo su propio perfil", async () => {
    const ana = env.authenticatedContext("ana").firestore();
    await assertSucceeds(getDoc(doc(ana, "users/ana")));
    await assertFails(getDoc(doc(ana, "users/vet")));
  });

  it("nadie crea su perfil desde la app (solo la Function)", async () => {
    const nuevo = env.authenticatedContext("nuevo").firestore();
    await assertFails(setDoc(doc(nuevo, "users/nuevo"), { role: "clinica" }));
  });

  it("el rol no se puede cambiar desde la app", async () => {
    const ana = env.authenticatedContext("ana").firestore();
    await assertFails(updateDoc(doc(ana, "users/ana"), { role: "clinica" }));
    await assertSucceeds(updateDoc(doc(ana, "users/ana"), { lastLoginAt: new Date() }));
  });

  it("solo la clínica dueña edita su perfil (RF-04)", async () => {
    const vet = env.authenticatedContext("vet").firestore();
    const ana = env.authenticatedContext("ana").firestore();
    await assertSucceeds(updateDoc(doc(vet, "clinics/c1"), { tiposAnimales: ["perros"] }));
    await assertFails(updateDoc(doc(ana, "clinics/c1"), { tiposAnimales: ["gatos"] }));
    await assertFails(updateDoc(doc(vet, "clinics/c1"), { ownerUid: "ana" }));
  });

  it("sin sesión no se lee nada", async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, "clinics/c1")));
  });
});
