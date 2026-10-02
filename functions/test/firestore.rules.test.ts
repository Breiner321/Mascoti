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
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
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
      await setDoc(doc(db, "users/vet2"), { uid: "vet2", role: "clinica", estado: "activo", clinicId: "c2" });
      await setDoc(doc(db, "clinics/c2"), { ownerUid: "vet2", nombre: "Vet 2", estado: "activo" });
      await setDoc(doc(db, "users/susp"), { uid: "susp", role: "clinica", estado: "suspendido", clinicId: "c3" });
      await setDoc(doc(db, "clinics/c3"), { ownerUid: "susp", nombre: "Suspendida", estado: "activo" });
      await setDoc(doc(db, "users/susp/devices/d1"), { fcmToken: "t" });
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

  it("una cuenta suspendida solo lee su perfil (RF-02)", async () => {
    const susp = env.authenticatedContext("susp").firestore();
    await assertSucceeds(getDoc(doc(susp, "users/susp")));
    await assertFails(updateDoc(doc(susp, "users/susp"), { lastLoginAt: new Date() }));
    await assertFails(updateDoc(doc(susp, "users/susp"), { displayName: "Otra" }));
    await assertFails(updateDoc(doc(susp, "clinics/c3"), { tiposAnimales: ["perros"] }));
    await assertFails(setDoc(doc(susp, "clinics/c3/services/s1"), { nombre: "Consulta" }));
    await assertFails(setDoc(doc(susp, "users/susp/devices/d2"), { fcmToken: "t2" }));
    // Al cerrar sesión puede borrar su token FCM.
    await assertSucceeds(deleteDoc(doc(susp, "users/susp/devices/d1")));
  });

  it("una clínica no edita otra clínica ni sus servicios", async () => {
    const vet2 = env.authenticatedContext("vet2").firestore();
    await assertFails(updateDoc(doc(vet2, "clinics/c1"), { nombre: "Robada" }));
    await assertFails(setDoc(doc(vet2, "clinics/c1/services/s1"), { nombre: "Consulta" }));
    await assertSucceeds(updateDoc(doc(vet2, "clinics/c2"), { nombre: "Vet 2 Norte" }));
    await assertSucceeds(setDoc(doc(vet2, "clinics/c2/services/s1"), { nombre: "Consulta" }));
  });

  it("nadie cambia role, estado ni clinicId", async () => {
    const ana = env.authenticatedContext("ana").firestore();
    const vet = env.authenticatedContext("vet").firestore();
    for (const cambio of [{ role: "clinica" }, { estado: "suspendido" }, { clinicId: "c1" }]) {
      await assertFails(updateDoc(doc(ana, "users/ana"), cambio));
    }
    await assertFails(updateDoc(doc(vet, "users/vet"), { clinicId: "c2" }));
    await assertFails(updateDoc(doc(vet, "users/vet"), { estado: "activo", role: "dueno" }));
    // Tampoco sobre el perfil de otra persona.
    await assertFails(updateDoc(doc(vet, "users/ana"), { estado: "suspendido" }));
  });

  it("la clínica solo usa estados válidos y no cambia su dueño", async () => {
    const vet = env.authenticatedContext("vet").firestore();
    await assertSucceeds(updateDoc(doc(vet, "clinics/c1"), { estado: "activo" }));
    await assertFails(updateDoc(doc(vet, "clinics/c1"), { estado: "verificada" }));
    await assertFails(updateDoc(doc(vet, "clinics/c1"), { createdAt: new Date() }));
  });

  it("sin sesión no se lee nada", async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, "clinics/c1")));
  });
});
