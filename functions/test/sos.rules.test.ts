/**
 * Reglas del SOS (RF-10): eventos de auditoría `auditEvents`.
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
import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

const conEmulador = Boolean(process.env.FIRESTORE_EMULATOR_HOST);

describe.skipIf(!conEmulador)("firestore.rules: auditEvents (RF-10)", () => {
  let env: RulesTestEnvironment;

  beforeAll(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-mascoti-sos",
      firestore: { rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8") },
    });
  });

  afterAll(async () => {
    await env?.cleanup();
  });

  const evento = (extra: Record<string, unknown> = {}) => ({
    tipo: "emergencyTriggered",
    uid: "ana",
    lat: 6.21,
    lng: -75.57,
    createdAt: serverTimestamp(),
    ...extra,
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "users/ana"), { uid: "ana", role: "dueno", estado: "activo" });
      await setDoc(doc(db, "users/vet"), { uid: "vet", role: "clinica", estado: "activo", clinicId: "c1" });
      await setDoc(doc(db, "users/susp"), { uid: "susp", role: "dueno", estado: "suspendido" });
      await setDoc(doc(db, "auditEvents/e1"), { tipo: "emergencyTriggered", uid: "ana", createdAt: new Date() });
    });
  });

  it("el dueño crea su propio evento, con o sin ubicación", async () => {
    const ana = env.authenticatedContext("ana").firestore();
    await assertSucceeds(addDoc(collection(ana, "auditEvents"), evento()));
    const { lat: _lat, lng: _lng, ...sinUbicacion } = evento();
    await assertSucceeds(addDoc(collection(ana, "auditEvents"), sinUbicacion));
  });

  it("nadie crea eventos a nombre de otro usuario", async () => {
    const ana = env.authenticatedContext("ana").firestore();
    await assertFails(addDoc(collection(ana, "auditEvents"), evento({ uid: "beto" })));
    const anonimo = env.unauthenticatedContext().firestore();
    await assertFails(addDoc(collection(anonimo, "auditEvents"), evento()));
  });

  it("solo dueños activos: ni clínicas ni cuentas suspendidas", async () => {
    const vet = env.authenticatedContext("vet").firestore();
    await assertFails(addDoc(collection(vet, "auditEvents"), evento({ uid: "vet" })));
    const susp = env.authenticatedContext("susp").firestore();
    await assertFails(addDoc(collection(susp, "auditEvents"), evento({ uid: "susp" })));
  });

  it("rechaza otro tipo, campos extra, hora del cliente o ubicación incompleta", async () => {
    const ana = env.authenticatedContext("ana").firestore();
    const col = collection(ana, "auditEvents");
    await assertFails(addDoc(col, evento({ tipo: "otro" })));
    await assertFails(addDoc(col, evento({ telefono: "3001234567" })));
    await assertFails(addDoc(col, evento({ createdAt: new Date("2026-01-01T00:00:00Z") })));
    const { lng: _lng, ...soloLat } = evento();
    await assertFails(addDoc(col, soloLat));
    await assertFails(addDoc(col, evento({ lat: "6.21" })));
    await assertFails(addDoc(col, evento({ lat: 200 })));
  });

  it("nadie los lee, cambia ni borra desde la app", async () => {
    const ana = env.authenticatedContext("ana").firestore();
    await assertFails(getDoc(doc(ana, "auditEvents/e1")));
    await assertFails(getDocs(collection(ana, "auditEvents")));
    await assertFails(updateDoc(doc(ana, "auditEvents/e1"), { lat: 1 }));
    await assertFails(deleteDoc(doc(ana, "auditEvents/e1")));
  });
});
