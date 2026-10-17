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
  type RulesTestContext,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
  GeoPoint,
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
      // Mascota de la semana 2: sin código de paciente.
      await setDoc(doc(db, "pets/p1"), { ownerUid: "ana", nombre: "Luna", especie: "perro" });
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
    await assertFails(setDoc(doc(ana, "pets/p3"), { ownerUid: "ana", nombre: "Nueva" })); // sin especie ni código
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
      }));
      // Campos que no se editan desde la app (la ubicación solo junto con
      // la dirección; ver "dirección y coordenadas").
      for (const cambio of [{ nombre: "Otro" }, { lat: 1 }, { geo: null }, { createdAt: new Date() }]) {
        await assertFails(updateDoc(c1, cambio));
      }
    });

    it("dirección y coordenadas cambian juntas y coherentes (semana 3)", async () => {
      const c1 = doc(env.authenticatedContext("vet").firestore(), "clinics/c1");
      const ubicacion = {
        direccion: "Calle 100 # 15-20, Bogotá",
        lat: 4.6867,
        lng: -74.0486,
        geo: { geohash: "d2g6f9yhk", geopoint: new GeoPoint(4.6867, -74.0486) },
      };
      await assertSucceeds(updateDoc(c1, ubicacion));
      // La dirección sola ya no: el mapa quedaría en el lugar anterior.
      await assertFails(updateDoc(c1, { direccion: "Otra dirección 123" }));
      // Coordenadas sin geo, o geo que no coincide.
      await assertFails(updateDoc(c1, { lat: 4.7, lng: -74.05 }));
      for (const malo of [
        { geo: { geohash: "d2g6f9yhk", geopoint: new GeoPoint(4.7, -74.0486) } },
        { geo: { geohash: "XYZ", geopoint: new GeoPoint(4.6867, -74.0486) } },
        { geo: { geohash: "d2g6f9yhk" } },
        { lat: 91, geo: { geohash: "d2g6f9yhk", geopoint: new GeoPoint(90, -74.0486) } },
      ]) {
        await assertFails(updateDoc(c1, { ...ubicacion, lat: 4.6868, ...malo }));
      }
    });

    it("categoriasServicio: solo categorías válidas", async () => {
      const c1 = doc(env.authenticatedContext("vet").firestore(), "clinics/c1");
      await assertSucceeds(updateDoc(c1, { categoriasServicio: ["vacunacion", "peluqueria"] }));
      await assertSucceeds(updateDoc(c1, { categoriasServicio: [] }));
      await assertFails(updateDoc(c1, { categoriasServicio: ["spa"] }));
      await assertFails(updateDoc(c1, { categoriasServicio: "vacunacion" }));
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
      clinicasAutorizadas: [],
      createdAt: new Date(),
    };

    // Como lo hace PetsRepository: mascota + codigosPaciente/{codigo} en un lote.
    function crear(
      db: ReturnType<RulesTestContext["firestore"]>,
      petId: string,
      datos: Record<string, unknown>,
      codigo = "MSC-7K4P",
    ) {
      const lote = writeBatch(db);
      lote.set(doc(db, `pets/${petId}`), { ...datos, codigoPaciente: codigo });
      lote.set(doc(db, `codigosPaciente/${codigo}`), {
        petId,
        ownerUid: datos.ownerUid,
        createdAt: new Date(),
      });
      return lote.commit();
    }

    it("el dueño crea (con código), edita y borra sus mascotas", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      await assertSucceeds(crear(ana, "p3", mascota));
      const p3 = doc(ana, "pets/p3");
      await assertSucceeds(updateDoc(p3, { nombre: "Luna B", alergias: [] }));
      await assertSucceeds(deleteDoc(p3));
    });

    it("solo nombre y especie son obligatorios", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      await assertSucceeds(
        crear(ana, "p3", { ownerUid: "ana", nombre: "Michi", especie: "gato" }),
      );
      await assertFails(crear(ana, "p4", { ownerUid: "ana", nombre: "Sin especie" }, "MSC-2222"));
    });

    it("rechaza datos inválidos", async () => {
      const ana = env.authenticatedContext("ana").firestore();
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
        await assertFails(crear(ana, "p3", { ...mascota, ...malo }));
      }
    });

    it("sexo: indeterminado y otro con detalle (solo con 'otro')", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      await assertSucceeds(crear(ana, "p3", { ...mascota, sexo: "indeterminado" }, "MSC-AAAA"));
      await assertSucceeds(crear(ana, "p4",
        { ...mascota, fotoPath: null, sexo: "otro", sexoDetalle: "Hermafrodita" }, "MSC-BBBB"));
      for (const malo of [
        { sexo: "hembra", sexoDetalle: "x" },
        { sexo: "otro", sexoDetalle: "" },
        { sexo: "otro" }, // falta el detalle
        { sexo: "otro", sexoDetalle: "x".repeat(31) },
      ]) {
        await assertFails(crear(ana, "p5", { ...mascota, fotoPath: null, ...malo }, "MSC-CCCC"));
      }
    });

    it("nadie crea mascotas a nombre de otro ni cambia el dueño", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      const vet = env.authenticatedContext("vet").firestore();
      await assertFails(crear(ana, "p3", { ...mascota, ownerUid: "otro" }));
      await assertFails(crear(vet, "p5", { ...mascota, ownerUid: "vet" })); // rol clínica
      await assertFails(updateDoc(doc(ana, "pets/p1"), { ownerUid: "otro" }));
      await assertFails(updateDoc(doc(ana, "pets/p2"), { nombre: "Robada" }));
      await assertFails(deleteDoc(doc(ana, "pets/p2")));
    });
  });

  // ------------------------------------------------------------------
  // Semana 3: código de paciente y vinculación clínica ↔ mascota
  // ------------------------------------------------------------------

  describe("código de paciente", () => {
    const base = { ownerUid: "ana", nombre: "Kiwi", especie: "ave", clinicasAutorizadas: [] };

    it("una mascota nueva necesita su código registrado en el mismo lote", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      // Sin código.
      await assertFails(setDoc(doc(ana, "pets/p7"), base));
      // Con código pero sin registrarlo en codigosPaciente.
      await assertFails(setDoc(doc(ana, "pets/p7"), { ...base, codigoPaciente: "MSC-7K4P" }));
      // El registro del código solo, sin la mascota.
      await assertFails(setDoc(doc(ana, "codigosPaciente/MSC-7K4P"),
        { petId: "p7", ownerUid: "ana", createdAt: new Date() }));
    });

    it("formato MSC-XXXX sin caracteres ambiguos", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      for (const malo of ["MSC-0K4P", "MSC-OK4P", "MSC-1K4P", "MSC-IK4P", "MSC-LK4P",
                          "MSC-7K4", "MSC-7K4PP", "msc-7k4p", "ABC-7K4P"]) {
        const lote = writeBatch(ana);
        lote.set(doc(ana, "pets/p7"), { ...base, codigoPaciente: malo });
        lote.set(doc(ana, `codigosPaciente/${malo}`), { petId: "p7", ownerUid: "ana" });
        await assertFails(lote.commit());
      }
    });

    it("un código ya usado no se puede reutilizar (unicidad)", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      const lote1 = writeBatch(ana);
      lote1.set(doc(ana, "pets/p7"), { ...base, codigoPaciente: "MSC-7K4P" });
      lote1.set(doc(ana, "codigosPaciente/MSC-7K4P"), { petId: "p7", ownerUid: "ana" });
      await assertSucceeds(lote1.commit());

      const lote2 = writeBatch(ana);
      lote2.set(doc(ana, "pets/p8"), { ...base, codigoPaciente: "MSC-7K4P" });
      lote2.set(doc(ana, "codigosPaciente/MSC-7K4P"), { petId: "p8", ownerUid: "ana" });
      await assertFails(lote2.commit());
    });

    it("no se puede apuntar un código a la mascota de otro", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      await assertFails(setDoc(doc(ana, "codigosPaciente/MSC-9999"),
        { petId: "p2", ownerUid: "ana" }));
    });

    it("nadie lee codigosPaciente desde la app", async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "codigosPaciente/MSC-7K4P"), { petId: "p1", ownerUid: "ana" });
      });
      for (const uid of ["ana", "vet", "vet2"]) {
        const db = env.authenticatedContext(uid).firestore();
        await assertFails(getDoc(doc(db, "codigosPaciente/MSC-7K4P")));
      }
    });

    it("el código no cambia; a una mascota antigua se le asigna una sola vez", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      // p1 es de la semana 2 (sin código): se le asigna con su registro.
      const lote = writeBatch(ana);
      lote.update(doc(ana, "pets/p1"), { codigoPaciente: "MSC-7K4P" });
      lote.set(doc(ana, "codigosPaciente/MSC-7K4P"), { petId: "p1", ownerUid: "ana" });
      await assertSucceeds(lote.commit());
      // Luego ya no se puede cambiar.
      const otro = writeBatch(ana);
      otro.update(doc(ana, "pets/p1"), { codigoPaciente: "MSC-2222" });
      otro.set(doc(ana, "codigosPaciente/MSC-2222"), { petId: "p1", ownerUid: "ana" });
      await assertFails(otro.commit());
    });
  });

  describe("clinicasAutorizadas", () => {
    beforeEach(async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "pets/p6"), {
          ownerUid: "ana",
          nombre: "Toby",
          especie: "perro",
          codigoPaciente: "MSC-TOBY",
          clinicasAutorizadas: ["c2"],
        });
      });
    });

    it("una mascota nueva empieza sin clínicas autorizadas", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      const lote = writeBatch(ana);
      lote.set(doc(ana, "pets/p7"),
        { ownerUid: "ana", nombre: "X", especie: "gato", codigoPaciente: "MSC-7K4P",
          clinicasAutorizadas: ["c2"] });
      lote.set(doc(ana, "codigosPaciente/MSC-7K4P"), { petId: "p7", ownerUid: "ana" });
      await assertFails(lote.commit());
    });

    it("el dueño puede quitar clínicas (revocar) pero no agregarlas", async () => {
      const p6 = doc(env.authenticatedContext("ana").firestore(), "pets/p6");
      await assertFails(updateDoc(p6, { clinicasAutorizadas: ["c2", "c1"] }));
      await assertFails(updateDoc(p6, { clinicasAutorizadas: ["c1"] }));
      await assertSucceeds(updateDoc(p6, { clinicasAutorizadas: [] }));
    });

    it("una clínica autorizada (activa) lee la mascota; las demás no", async () => {
      const vet2 = env.authenticatedContext("vet2").firestore(); // clínica c2, activa
      const vet = env.authenticatedContext("vet").firestore(); // clínica c1, no autorizada
      await assertSucceeds(getDoc(doc(vet2, "pets/p6")));
      await assertSucceeds(getDocs(query(collection(vet2, "pets"),
        where("clinicasAutorizadas", "array-contains", "c2"))));
      await assertFails(getDoc(doc(vet, "pets/p6")));
      await assertFails(getDocs(query(collection(vet, "pets"),
        where("clinicasAutorizadas", "array-contains", "c2"))));
      // Ni la clínica autorizada puede editarla.
      await assertFails(updateDoc(doc(vet2, "pets/p6"), { nombre: "Otro" }));
    });

    it("al revocar, la clínica deja de leerla", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      const vet2 = env.authenticatedContext("vet2").firestore();
      await assertSucceeds(updateDoc(doc(ana, "pets/p6"), { clinicasAutorizadas: [] }));
      await assertFails(getDoc(doc(vet2, "pets/p6")));
    });
  });

  // ------------------------------------------------------------------
  // Semana 3: historial médico (RF-08) y próximas dosis
  // ------------------------------------------------------------------

  describe("medicalRecords y vacunasProgramadas", () => {
    // p6 de ana, autorizada para c2 (vet2, activa). vet (c1) no está autorizada.
    beforeEach(async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "pets/p6"), {
          ownerUid: "ana",
          nombre: "Toby",
          especie: "perro",
          codigoPaciente: "MSC-TOBY",
          clinicasAutorizadas: ["c2"],
        });
      });
    });

    const aplicada = new Date("2026-10-10T15:00:00Z");
    const refuerzo = new Date("2027-10-10T15:00:00Z");
    const registro = () => ({
      clinicId: "c2",
      clinicNombre: "Vet 2",
      fecha: new Date("2026-10-10T15:00:00Z"),
      diagnostico: "Control anual, sano",
      tratamiento: "Ninguno",
      vacunas: [{ nombre: "Rabia", lote: "L-123", fechaAplicacion: aplicada, fechaProximaDosis: refuerzo }],
      adjuntos: [{ path: "p6/r1/radiografia.jpg", tipo: "imagen", nombre: "Radiografía.jpg" }],
      createdAt: serverTimestamp(),
    });

    const dosis = () => ({
      petId: "p6",
      ownerUid: "ana",
      clinicId: "c2",
      recordId: "r1",
      vacuna: "Rabia",
      fechaProximaDosis: refuerzo,
      notificado: false,
      createdAt: serverTimestamp(),
    });

    async function sembrarRegistro(creado: Date, extra: Record<string, unknown> = {}) {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "pets/p6/medicalRecords/r1"),
          { ...registro(), createdAt: creado, ...extra });
      });
    }

    it("la clínica autorizada crea el registro con sus próximas dosis en un lote", async () => {
      const vet2 = env.authenticatedContext("vet2").firestore();
      const lote = writeBatch(vet2);
      lote.set(doc(vet2, "pets/p6/medicalRecords/r1"), registro());
      lote.set(doc(vet2, "vacunasProgramadas/r1_0"), dosis());
      await assertSucceeds(lote.commit());
    });

    it("una clínica no autorizada, o a nombre de otra, no crea registros", async () => {
      const vet = env.authenticatedContext("vet").firestore(); // c1, no autorizada
      const vet2 = env.authenticatedContext("vet2").firestore();
      await assertFails(setDoc(doc(vet, "pets/p6/medicalRecords/r1"), { ...registro(), clinicId: "c1" }));
      await assertFails(setDoc(doc(vet2, "pets/p6/medicalRecords/r1"), { ...registro(), clinicId: "c1" }));
      // El dueño tampoco escribe su historial.
      const ana = env.authenticatedContext("ana").firestore();
      await assertFails(setDoc(doc(ana, "pets/p6/medicalRecords/r1"), registro()));
    });

    it("valida los campos del registro", async () => {
      const r1 = doc(env.authenticatedContext("vet2").firestore(), "pets/p6/medicalRecords/r1");
      const vacuna = registro().vacunas[0];
      const adjunto = registro().adjuntos[0];
      for (const malo of [
        { diagnostico: "" },
        { diagnostico: "x".repeat(2001) },
        { fecha: "2026-10-10" },
        { fecha: new Date("2999-01-01T00:00:00Z") },
        { tratamiento: 5 },
        { createdAt: new Date("2026-01-01T00:00:00Z") }, // debe ser la hora del servidor
        { extra: true },
        { vacunas: [{ ...vacuna, lote: "" }] },
        { vacunas: [{ lote: vacuna.lote, fechaAplicacion: vacuna.fechaAplicacion }] }, // sin nombre
        { vacunas: [{ ...vacuna, fechaProximaDosis: new Date("2026-01-01T00:00:00Z") }] },
        { vacunas: [vacuna, { ...vacuna, fechaAplicacion: "ayer" }] },
        { vacunas: Array(11).fill(vacuna) },
        { adjuntos: [{ ...adjunto, tipo: "video" }] },
        { adjuntos: [{ ...adjunto, path: "p6/otro/radiografia.jpg" }] },
        { adjuntos: [{ ...adjunto, path: "p9/r1/radiografia.jpg" }] },
        { adjuntos: Array(11).fill(adjunto) },
      ]) {
        await assertFails(setDoc(r1, { ...registro(), ...malo }));
      }
      // Sin vacunas ni adjuntos ni tratamiento también es válido.
      await assertSucceeds(setDoc(r1, {
        clinicId: "c2", fecha: new Date("2026-10-10T15:00:00Z"),
        diagnostico: "Consulta", createdAt: serverTimestamp(),
      }));
    });

    it("leen el dueño y las clínicas autorizadas; los demás no", async () => {
      await sembrarRegistro(new Date());
      const ana = env.authenticatedContext("ana").firestore();
      const vet2 = env.authenticatedContext("vet2").firestore();
      const vet = env.authenticatedContext("vet").firestore();
      const otro = env.authenticatedContext("vet2").firestore();
      await assertSucceeds(getDoc(doc(ana, "pets/p6/medicalRecords/r1")));
      await assertSucceeds(getDocs(query(collection(ana, "pets/p6/medicalRecords"), orderBy("fecha", "desc"))));
      await assertSucceeds(getDocs(collection(otro, "pets/p6/medicalRecords")));
      await assertFails(getDoc(doc(vet, "pets/p6/medicalRecords/r1")));
      // Al revocar el acceso, la clínica deja de leer el historial.
      await assertSucceeds(updateDoc(doc(ana, "pets/p6"), { clinicasAutorizadas: [] }));
      await assertFails(getDoc(doc(vet2, "pets/p6/medicalRecords/r1")));
    });

    it("la clínica autora corrige dentro de 24 h; después no; nunca se borra", async () => {
      const r1 = doc(env.authenticatedContext("vet2").firestore(), "pets/p6/medicalRecords/r1");
      await sembrarRegistro(new Date(Date.now() - 60 * 60 * 1000)); // hace 1 h
      await assertSucceeds(updateDoc(r1, { diagnostico: "Corregido", updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(r1, { diagnostico: "Sin updatedAt" }));
      await assertFails(updateDoc(r1, { clinicId: "c1", updatedAt: serverTimestamp() }));
      await assertFails(deleteDoc(r1));

      await sembrarRegistro(new Date(Date.now() - 25 * 60 * 60 * 1000)); // hace 25 h
      await assertFails(updateDoc(r1, { diagnostico: "Tarde", updatedAt: serverTimestamp() }));
    });

    it("solo la clínica autora edita, aunque otra también esté autorizada", async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await updateDoc(doc(ctx.firestore(), "pets/p6"), { clinicasAutorizadas: ["c2", "c1"] });
        await updateDoc(doc(ctx.firestore(), "clinics/c1"), { estado: "activo" });
      });
      await sembrarRegistro(new Date());
      const vet = env.authenticatedContext("vet").firestore(); // c1, autorizada pero no autora
      await assertSucceeds(getDoc(doc(vet, "pets/p6/medicalRecords/r1")));
      await assertFails(updateDoc(doc(vet, "pets/p6/medicalRecords/r1"),
        { diagnostico: "Ajeno", updatedAt: serverTimestamp() }));
    });

    it("la próxima dosis debe coincidir con la vacuna del registro", async () => {
      const vet2 = env.authenticatedContext("vet2").firestore();
      for (const [id, malo] of [
        ["r1_0", { vacuna: "Moquillo" }],
        ["r1_0", { fechaProximaDosis: new Date("2028-01-01T00:00:00Z") }],
        ["r1_1", {}], // el registro solo tiene una vacuna
        ["r1_0", { ownerUid: "otro" }],
        ["r1_0", { notificado: true }],
        ["r2_0", {}], // otro registro
      ] as [string, Record<string, unknown>][]) {
        const lote = writeBatch(vet2);
        lote.set(doc(vet2, "pets/p6/medicalRecords/r1"), registro());
        lote.set(doc(vet2, `vacunasProgramadas/${id}`), { ...dosis(), ...malo });
        await assertFails(lote.commit());
      }
      // Sin el registro en el mismo lote (o ya existente) tampoco.
      await assertFails(setDoc(doc(vet2, "vacunasProgramadas/r1_0"), dosis()));
    });

    it("las próximas dosis las leen el dueño y la clínica autora", async () => {
      await sembrarRegistro(new Date());
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "vacunasProgramadas/r1_0"), { ...dosis(), createdAt: new Date() });
      });
      const ana = env.authenticatedContext("ana").firestore();
      await assertSucceeds(getDoc(doc(ana, "vacunasProgramadas/r1_0")));
      await assertSucceeds(getDocs(query(collection(ana, "vacunasProgramadas"),
        where("ownerUid", "==", "ana"))));
      await assertSucceeds(getDoc(doc(env.authenticatedContext("vet2").firestore(), "vacunasProgramadas/r1_0")));
      await assertFails(getDoc(doc(env.authenticatedContext("vet").firestore(), "vacunasProgramadas/r1_0")));
      // El dueño no puede marcarla como notificada ni borrarla.
      await assertFails(updateDoc(doc(ana, "vacunasProgramadas/r1_0"), { notificado: true }));
      await assertFails(deleteDoc(doc(ana, "vacunasProgramadas/r1_0")));
    });
  });
});
