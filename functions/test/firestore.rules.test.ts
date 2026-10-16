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
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} from "firebase/firestore";
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
      await setDoc(doc(db, "pets/p1"), { ownerUid: "ana", nombre: "Luna" });
      await setDoc(doc(db, "pets/p2"), { ownerUid: "otro", nombre: "Max" });
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
    await assertSucceeds(updateDoc(doc(vet2, "clinics/c2"), { telefono: "3009998877" }));
    await assertSucceeds(setDoc(doc(vet2, "clinics/c2/services/s1"), {
      nombre: "Consulta", categoria: "consulta_general", precio: 40000, duracionMin: 30, activo: true,
    }));
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
    await assertSucceeds(updateDoc(doc(vet, "clinics/c1"), { estado: "activo", tiposAnimales: ["perros"] }));
    await assertFails(updateDoc(doc(vet, "clinics/c1"), { estado: "verificada" }));
    await assertFails(updateDoc(doc(vet, "clinics/c1"), { createdAt: new Date() }));
  });

  it("el dueño marca el onboarding como visto (RF-01 paso 14)", async () => {
    const ana = env.authenticatedContext("ana").firestore();
    const vet = env.authenticatedContext("vet").firestore();
    await assertSucceeds(updateDoc(doc(ana, "users/ana"), { onboardingVisto: true }));
    await assertFails(updateDoc(doc(ana, "users/ana"), { onboardingVisto: "si" }));
    await assertFails(updateDoc(doc(vet, "users/ana"), { onboardingVisto: true }));
  });

  it("un dueño lee solo sus mascotas", async () => {
    const ana = env.authenticatedContext("ana").firestore();
    await assertSucceeds(getDoc(doc(ana, "pets/p1")));
    await assertFails(getDoc(doc(ana, "pets/p2")));
    await assertSucceeds(getDocs(query(collection(ana, "pets"), where("ownerUid", "==", "ana"))));
    await assertFails(getDocs(collection(ana, "pets")));
    await assertFails(setDoc(doc(ana, "pets/p3"), { ownerUid: "ana", nombre: "Nueva" }));
  });

  it("sin sesión no se lee nada", async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, "clinics/c1")));
  });

  // ------------------------------------------------------------------
  // Semana 2: validación de campos (RF-04, RF-05, RF-06, mascotas)
  // ------------------------------------------------------------------

  describe("clinics: perfil de atención (RF-04)", () => {
    it("la dueña cambia solo los campos permitidos y con valores válidos", async () => {
      const vet = env.authenticatedContext("vet").firestore();
      const c1 = doc(vet, "clinics/c1");
      await assertSucceeds(updateDoc(c1, {
        tiposAnimales: ["perros", "gatos"],
        atencionEmergencias: true,
        horarioBase: { apertura: "08:00", cierre: "18:00", duracionSlotMin: 30 },
        telefono: "3009998877",
        direccion: "Calle 100 # 15-20, Bogotá",
      }));
      // Campos que no se editan desde la app.
      for (const cambio of [{ nombre: "Otro" }, { lat: 1 }, { geo: null }, { createdAt: new Date() }]) {
        await assertFails(updateDoc(c1, cambio));
      }
    });

    it("tiposAnimales: lista no vacía y solo valores válidos", async () => {
      const c1 = doc(env.authenticatedContext("vet").firestore(), "clinics/c1");
      await assertFails(updateDoc(c1, { tiposAnimales: [] }));
      await assertFails(updateDoc(c1, { tiposAnimales: ["perros", "dinosaurios"] }));
      await assertFails(updateDoc(c1, { tiposAnimales: "perros" }));
      await assertSucceeds(updateDoc(c1, { tiposAnimales: ["exoticos", "granja"] }));
    });

    it("horarioBase, teléfono, dirección y emergencias con formato válido", async () => {
      const c1 = doc(env.authenticatedContext("vet").firestore(), "clinics/c1");
      const horario = { apertura: "08:00", cierre: "18:00", duracionSlotMin: 30 };
      await assertFails(updateDoc(c1, { horarioBase: { ...horario, apertura: "8:00" } }));
      await assertFails(updateDoc(c1, { horarioBase: { ...horario, apertura: "19:00" } }));
      await assertFails(updateDoc(c1, { horarioBase: { ...horario, duracionSlotMin: 2 } }));
      await assertFails(updateDoc(c1, { horarioBase: { ...horario, duracionSlotMin: 30.5 } }));
      await assertFails(updateDoc(c1, { horarioBase: { ...horario, extra: 1 } }));
      await assertFails(updateDoc(c1, { telefono: "300123" }));
      await assertFails(updateDoc(c1, { direccion: "" }));
      await assertFails(updateDoc(c1, { atencionEmergencias: "si" }));
    });

    it("estado: solo 'incompleto' → 'activo' y con tipos de animales", async () => {
      const c1 = doc(env.authenticatedContext("vet").firestore(), "clinics/c1");
      await assertFails(updateDoc(c1, { estado: "activo" })); // sin tiposAnimales
      await assertFails(updateDoc(c1, { estado: "verificada", tiposAnimales: ["perros"] }));
      await assertSucceeds(updateDoc(c1, { estado: "activo", tiposAnimales: ["perros"] }));
      // Una vez activa no vuelve a incompleta desde la app.
      await assertFails(updateDoc(c1, { estado: "incompleto" }));
    });
  });

  describe("services (RF-05)", () => {
    const servicio = {
      nombre: "Consulta general",
      categoria: "consulta_general",
      descripcion: "",
      precio: 45000.5,
      duracionMin: 30,
      activo: true,
    };

    it("la clínica dueña crea y actualiza servicios válidos", async () => {
      const s1 = doc(env.authenticatedContext("vet").firestore(), "clinics/c1/services/s1");
      await assertSucceeds(setDoc(s1, servicio));
      await assertSucceeds(updateDoc(s1, { precio: 50000, updatedAt: new Date() }));
    });

    it("rechaza datos inválidos", async () => {
      const s1 = doc(env.authenticatedContext("vet").firestore(), "clinics/c1/services/s1");
      for (const malo of [
        { nombre: "ab" },
        { nombre: "x".repeat(61) },
        { precio: 0 },
        { precio: -100 },
        { precio: "45000" },
        { duracionMin: 4 },
        { duracionMin: 481 },
        { duracionMin: 30.5 },
        { categoria: "spa" },
        { activo: "si" },
        { extra: true },
      ]) {
        await assertFails(setDoc(s1, { ...servicio, ...malo }));
      }
    });

    it("no se borra: soft delete con activo = false", async () => {
      const vet = env.authenticatedContext("vet").firestore();
      const s1 = doc(vet, "clinics/c1/services/s1");
      await assertSucceeds(setDoc(s1, servicio));
      await assertFails(deleteDoc(s1));
      await assertSucceeds(updateDoc(s1, { activo: false }));
    });

    it("otra clínica o un dueño no escriben servicios; todos con sesión leen", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      const vet2 = env.authenticatedContext("vet2").firestore();
      await assertFails(setDoc(doc(ana, "clinics/c1/services/s9"), servicio));
      await assertFails(setDoc(doc(vet2, "clinics/c1/services/s9"), servicio));
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "clinics/c1/services/s1"), servicio);
      });
      await assertSucceeds(getDoc(doc(ana, "clinics/c1/services/s1")));
    });
  });

  describe("slots (RF-06)", () => {
    const franja = {
      fecha: "2026-10-15",
      hora: "09:30",
      inicio: new Date("2026-10-15T09:30:00-05:00"),
      serviceId: "s1",
      precio: 45000,
      estado: "disponible",
    };
    const id = "clinics/c1/slots/2026-10-15_09:30";

    async function sembrar(estado: string) {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), id), { ...franja, estado });
      });
    }

    it("la clínica dueña publica franjas disponibles y bloquea horarios", async () => {
      const vet = env.authenticatedContext("vet").firestore();
      await assertSucceeds(setDoc(doc(vet, id), franja));
      await assertSucceeds(setDoc(doc(vet, "clinics/c1/slots/2026-10-15_12:00"), {
        fecha: "2026-10-15",
        hora: "12:00",
        inicio: new Date("2026-10-15T12:00:00-05:00"),
        estado: "no_disponible",
      }));
    });

    it("rechaza franjas inválidas", async () => {
      const slot = doc(env.authenticatedContext("vet").firestore(), id);
      for (const malo of [
        { estado: "libre" },
        { estado: "ocupado" }, // lo pone el agendamiento, no la clínica
        { estado: "reservado_temporal" },
        { serviceId: null }, // 'disponible' exige servicio
        { hora: "9:30" },
        { fecha: "15/10/2026" },
        { hora: "10:00" }, // el id debe ser {fecha}_{hora}
        { precio: 0 },
        { inicio: "2026-10-15" },
        { extra: 1 },
      ]) {
        await assertFails(setDoc(slot, { ...franja, ...malo }));
      }
    });

    it("no se modifica ni borra una franja ocupada o reservada (flujo alterno)", async () => {
      const slot = doc(env.authenticatedContext("vet").firestore(), id);
      for (const estado of ["ocupado", "reservado_temporal"]) {
        await sembrar(estado);
        await assertFails(updateDoc(slot, { estado: "no_disponible", serviceId: null }));
        await assertFails(deleteDoc(slot));
      }
      await sembrar("disponible");
      await assertSucceeds(updateDoc(slot, { estado: "no_disponible", serviceId: null }));
      await assertSucceeds(deleteDoc(slot));
    });

    it("solo la dueña escribe; cualquier usuario con sesión lee", async () => {
      await sembrar("disponible");
      const ana = env.authenticatedContext("ana").firestore();
      const vet2 = env.authenticatedContext("vet2").firestore();
      await assertFails(setDoc(doc(ana, id), franja));
      await assertFails(setDoc(doc(vet2, id), franja));
      await assertSucceeds(getDoc(doc(ana, id)));
      await assertSucceeds(getDocs(query(collection(ana, "clinics/c1/slots"),
        where("fecha", "==", "2026-10-15"), where("estado", "==", "disponible"))));
      await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), id)));
    });
  });

  describe("pets (registro de mascotas)", () => {
    const mascota = {
      ownerUid: "ana",
      nombre: "Luna",
      especie: "perro",
      raza: "Criolla",
      sexo: "hembra",
      fechaNacimiento: new Date("2023-09-01T00:00:00Z"),
      fotoPath: "ana/p3/foto.jpg",
      alergias: ["pollo"],
      condiciones: [],
      contactoEmergencia: { nombre: "Ana", telefono: "3001234567" },
      createdAt: new Date(),
    };

    it("el dueño crea, edita y borra sus mascotas", async () => {
      const p3 = doc(env.authenticatedContext("ana").firestore(), "pets/p3");
      await assertSucceeds(setDoc(p3, mascota));
      await assertSucceeds(updateDoc(p3, { nombre: "Luna B", alergias: [] }));
      await assertSucceeds(deleteDoc(p3));
    });

    it("solo nombre y especie son obligatorios", async () => {
      const p3 = doc(env.authenticatedContext("ana").firestore(), "pets/p3");
      await assertSucceeds(setDoc(p3, { ownerUid: "ana", nombre: "Michi", especie: "gato" }));
      await assertFails(setDoc(doc(env.authenticatedContext("ana").firestore(), "pets/p4"),
        { ownerUid: "ana", nombre: "Sin especie" }));
    });

    it("rechaza datos inválidos", async () => {
      const p3 = doc(env.authenticatedContext("ana").firestore(), "pets/p3");
      for (const malo of [
        { nombre: "" },
        { especie: "dragon" },
        { sexo: "otro" },
        { fechaNacimiento: new Date("2999-01-01T00:00:00Z") },
        { fotoPath: "otro/p3/foto.jpg" }, // carpeta de otra persona
        { fotoPath: "ana/p9/foto.jpg" }, // otra mascota
        { fotoPath: "ana/p3/foto.gif" },
        { alergias: "pollo" },
        { contactoEmergencia: { nombre: "Ana", telefono: "abc" } },
        { extra: true },
      ]) {
        await assertFails(setDoc(p3, { ...mascota, ...malo }));
      }
    });

    it("nadie crea mascotas a nombre de otro ni cambia el dueño", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      const vet = env.authenticatedContext("vet").firestore();
      await assertFails(setDoc(doc(ana, "pets/p3"), { ...mascota, ownerUid: "otro" }));
      await assertFails(setDoc(doc(vet, "pets/p5"), { ...mascota, ownerUid: "vet" })); // rol clínica
      await assertFails(updateDoc(doc(ana, "pets/p1"), { ownerUid: "otro" }));
      await assertFails(updateDoc(doc(ana, "pets/p2"), { nombre: "Robada" }));
      await assertFails(deleteDoc(doc(ana, "pets/p2")));
    });
  });
});
