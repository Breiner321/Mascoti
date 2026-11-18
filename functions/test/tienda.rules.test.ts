/**
 * Reglas de la tienda (RF-07, RF-12): productos, carrito y pedidos.
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
  collection,
  collectionGroup,
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
} from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

const conEmulador = Boolean(process.env.FIRESTORE_EMULATOR_HOST);

describe.skipIf(!conEmulador)("firestore.rules: tienda", () => {
  let env: RulesTestEnvironment;

  beforeAll(async () => {
    env = await initializeTestEnvironment({
      projectId: "demo-mascoti-tienda",
      firestore: { rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8") },
    });
  });

  afterAll(async () => {
    await env?.cleanup();
  });

  const producto = (extra: Record<string, unknown> = {}) => ({
    clinicId: "c1",
    nombre: "Concentrado 2 kg",
    categoria: "alimento",
    descripcion: "Para perros adultos",
    precio: 45000,
    stock: 5,
    stockReservado: 0,
    fotoPath: "vet/p1.jpg",
    estado: "activo",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...extra,
  });

  const pedido = (extra: Record<string, unknown> = {}) => ({
    ownerUid: "ana",
    ownerNombre: "Ana",
    clinicId: "c1",
    clinicNombre: "Vet",
    items: [{ productId: "p1", nombre: "Concentrado", precio: 45000, cantidad: 1 }],
    total: 45000,
    entrega: { tipo: "recoger", telefono: "3001234567" },
    estado: "pagado",
    referenciaPago: "MSC-o1",
    createdAt: new Date("2026-11-18T15:00:00Z"),
    ...extra,
  });

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "users/ana"), { uid: "ana", role: "dueno", estado: "activo" });
      await setDoc(doc(db, "users/beto"), { uid: "beto", role: "dueno", estado: "activo" });
      await setDoc(doc(db, "users/vet"), { uid: "vet", role: "clinica", estado: "activo", clinicId: "c1" });
      await setDoc(doc(db, "users/vet2"), { uid: "vet2", role: "clinica", estado: "activo", clinicId: "c2" });
      await setDoc(doc(db, "users/susp"), { uid: "susp", role: "dueno", estado: "suspendido" });
      await setDoc(doc(db, "clinics/c1"), { ownerUid: "vet", nombre: "Vet", estado: "activo" });
      await setDoc(doc(db, "clinics/c2"), { ownerUid: "vet2", nombre: "Vet 2", estado: "activo" });
      await setDoc(doc(db, "clinics/c1/products/p1"), producto({ createdAt: new Date(), updatedAt: new Date() }));
      await setDoc(doc(db, "clinics/c1/products/p2"), producto({
        nombre: "Collar", categoria: "accesorio", stock: 0, estado: "agotado",
        fotoPath: "vet/p2.jpg", createdAt: new Date(), updatedAt: new Date(),
      }));
      await setDoc(doc(db, "clinics/c1/products/p3"), producto({
        nombre: "Retirado", estado: "inactivo", fotoPath: "vet/p3.jpg",
        createdAt: new Date(), updatedAt: new Date(),
      }));
      await setDoc(doc(db, "clinics/c2/products/q1"), producto({
        clinicId: "c2", nombre: "Pelota", categoria: "juguete", fotoPath: "vet2/q1.png",
        createdAt: new Date(), updatedAt: new Date(),
      }));
      await setDoc(doc(db, "orders/o1"), pedido());
      await setDoc(doc(db, "orders/o2"), pedido({ estado: "pendiente_pago" }));
      await setDoc(doc(db, "orders/o3"), pedido({ ownerUid: "beto", clinicId: "c2", estado: "preparando" }));
    });
  });

  describe("products (RF-07)", () => {
    it("la clínica dueña crea un producto válido", async () => {
      const vet = env.authenticatedContext("vet").firestore();
      await assertSucceeds(setDoc(doc(vet, "clinics/c1/products/nuevo"), producto({ fotoPath: "vet/nuevo.jpg" })));
      // Stock inicial 0 → agotado.
      await assertSucceeds(setDoc(doc(vet, "clinics/c1/products/n2"), producto({
        stock: 0, estado: "agotado", fotoPath: "vet/n2.png",
      })));
    });

    it("otra clínica o un dueño no escriben productos ajenos", async () => {
      const vet2 = env.authenticatedContext("vet2").firestore();
      const ana = env.authenticatedContext("ana").firestore();
      await assertFails(setDoc(doc(vet2, "clinics/c1/products/x"), producto({ fotoPath: "vet2/x.jpg" })));
      await assertFails(updateDoc(doc(vet2, "clinics/c1/products/p1"), { stock: 99, updatedAt: serverTimestamp() }));
      await assertFails(setDoc(doc(ana, "clinics/c1/products/x"), producto({ fotoPath: "ana/x.jpg" })));
    });

    it("valida nombre 3-60, precio entero > 0, stock entero ≥ 0 y categoría", async () => {
      const vet = env.authenticatedContext("vet").firestore();
      const ruta = doc(vet, "clinics/c1/products/nuevo");
      const foto = { fotoPath: "vet/nuevo.jpg" };
      await assertFails(setDoc(ruta, producto({ ...foto, nombre: "Ab" })));
      await assertFails(setDoc(ruta, producto({ ...foto, nombre: "x".repeat(61) })));
      await assertFails(setDoc(ruta, producto({ ...foto, nombre: " Collar" })));
      await assertFails(setDoc(ruta, producto({ ...foto, precio: 0 })));
      await assertFails(setDoc(ruta, producto({ ...foto, precio: 45000.5 })));
      await assertFails(setDoc(ruta, producto({ ...foto, stock: -1 })));
      await assertFails(setDoc(ruta, producto({ ...foto, stock: 1.5 })));
      await assertFails(setDoc(ruta, producto({ ...foto, categoria: "ropa" })));
      await assertFails(setDoc(ruta, producto({ ...foto, clinicId: "c2" })));
      await assertFails(setDoc(ruta, producto({ ...foto, extra: true })));
      await assertSucceeds(setDoc(ruta, producto({ ...foto, nombre: "x".repeat(60) })));
    });

    it("la foto va en la carpeta de la clínica (bucket productos)", async () => {
      const vet = env.authenticatedContext("vet").firestore();
      const ruta = doc(vet, "clinics/c1/products/nuevo");
      await assertFails(setDoc(ruta, producto({ fotoPath: "vet2/nuevo.jpg" })));
      await assertFails(setDoc(ruta, producto({ fotoPath: "vet/../x.jpg" })));
      await assertFails(setDoc(ruta, producto({ fotoPath: "vet/nuevo.gif" })));
      await assertFails(setDoc(ruta, producto({ fotoPath: "" })));
    });

    it("agotado si y solo si stock == 0 (salvo inactivo)", async () => {
      const vet = env.authenticatedContext("vet").firestore();
      const p1 = doc(vet, "clinics/c1/products/p1");
      const ahora = { updatedAt: serverTimestamp() };
      await assertFails(updateDoc(p1, { stock: 0, ...ahora }));
      await assertFails(updateDoc(p1, { estado: "agotado", ...ahora }));
      await assertSucceeds(updateDoc(p1, { stock: 0, estado: "agotado", ...ahora }));
      await assertFails(updateDoc(p1, { stock: 3, ...ahora }));
      await assertSucceeds(updateDoc(p1, { stock: 3, estado: "activo", ...ahora }));
      // Inactivo con cualquier stock.
      await assertSucceeds(updateDoc(p1, { estado: "inactivo", ...ahora }));
      await assertSucceeds(updateDoc(p1, { stock: 0, ...ahora }));
    });

    it("stockReservado y createdAt solo los cambia el servidor; sin borrado", async () => {
      const vet = env.authenticatedContext("vet").firestore();
      const p1 = doc(vet, "clinics/c1/products/p1");
      await assertFails(updateDoc(p1, { stockReservado: 2, updatedAt: serverTimestamp() }));
      await assertFails(updateDoc(p1, { createdAt: new Date(), updatedAt: serverTimestamp() }));
      await assertFails(setDoc(doc(vet, "clinics/c1/products/n"), producto({ fotoPath: "vet/n.jpg", stockReservado: 1 })));
      await assertFails(updateDoc(p1, { precio: 50000 })); // sin updatedAt
      await assertSucceeds(updateDoc(p1, { precio: 50000, updatedAt: serverTimestamp() }));
      await assertFails(deleteDoc(p1));
    });

    it("los dueños leen activos y agotados, no inactivos; la clínica lee todo", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      const vet = env.authenticatedContext("vet").firestore();
      const anon = env.unauthenticatedContext().firestore();
      await assertSucceeds(getDoc(doc(ana, "clinics/c1/products/p1")));
      await assertSucceeds(getDoc(doc(ana, "clinics/c1/products/p2")));
      await assertFails(getDoc(doc(ana, "clinics/c1/products/p3")));
      await assertFails(getDoc(doc(anon, "clinics/c1/products/p1")));
      await assertSucceeds(getDoc(doc(vet, "clinics/c1/products/p3")));

      const visibles = where("estado", "in", ["activo", "agotado"]);
      await assertSucceeds(getDocs(query(collection(ana, "clinics/c1/products"), visibles)));
      await assertFails(getDocs(collection(ana, "clinics/c1/products")));
      await assertSucceeds(getDocs(collection(vet, "clinics/c1/products")));
      // Catálogo general (consulta de grupo).
      await assertSucceeds(getDocs(query(collectionGroup(ana, "products"), visibles)));
      await assertFails(getDocs(collectionGroup(ana, "products")));
    });
  });

  describe("users/{uid}/cart (RF-12)", () => {
    const item = (extra: Record<string, unknown> = {}) => ({
      clinicId: "c1", nombre: "Concentrado 2 kg", precio: 45000, cantidad: 2, addedAt: serverTimestamp(), ...extra,
    });

    it("solo el dueño lee y escribe su carrito", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      const beto = env.authenticatedContext("beto").firestore();
      await assertSucceeds(setDoc(doc(ana, "users/ana/cart/p1"), item()));
      await assertSucceeds(getDocs(collection(ana, "users/ana/cart")));
      await assertFails(getDocs(collection(beto, "users/ana/cart")));
      await assertFails(setDoc(doc(beto, "users/ana/cart/p1"), item()));
      await assertFails(deleteDoc(doc(beto, "users/ana/cart/p1")));
      await assertSucceeds(deleteDoc(doc(ana, "users/ana/cart/p1")));
    });

    it("valida cantidad 1-99, precio entero y que el producto exista en esa clínica", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      const ruta = doc(ana, "users/ana/cart/p1");
      await assertFails(setDoc(ruta, item({ cantidad: 0 })));
      await assertFails(setDoc(ruta, item({ cantidad: 100 })));
      await assertFails(setDoc(ruta, item({ cantidad: 1.5 })));
      await assertFails(setDoc(ruta, item({ precio: 0 })));
      await assertFails(setDoc(ruta, item({ clinicId: "c2" })));
      await assertFails(setDoc(doc(ana, "users/ana/cart/noexiste"), item()));
      await assertFails(setDoc(ruta, item({ addedAt: new Date("2020-01-01") })));
      await assertSucceeds(setDoc(ruta, item({ cantidad: 99 })));
      // Cambiar la cantidad conserva addedAt.
      await assertSucceeds(updateDoc(ruta, { cantidad: 3 }));
      await assertFails(updateDoc(ruta, { addedAt: new Date() }));
    });

    it("una clínica o una cuenta suspendida no usan carrito", async () => {
      const vet = env.authenticatedContext("vet").firestore();
      const susp = env.authenticatedContext("susp").firestore();
      await assertFails(setDoc(doc(vet, "users/vet/cart/p1"), item()));
      await assertFails(setDoc(doc(susp, "users/susp/cart/p1"), item()));
    });
  });

  describe("orders (RF-12)", () => {
    it("nadie escribe pedidos desde la app", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      const vet = env.authenticatedContext("vet").firestore();
      await assertFails(setDoc(doc(ana, "orders/nuevo"), pedido({ estado: "pagado" })));
      await assertFails(updateDoc(doc(ana, "orders/o2"), { estado: "pagado" }));
      await assertFails(updateDoc(doc(vet, "orders/o1"), { estado: "preparando" }));
      await assertFails(deleteDoc(doc(ana, "orders/o1")));
    });

    it("el dueño lee sus pedidos en cualquier estado", async () => {
      const ana = env.authenticatedContext("ana").firestore();
      await assertSucceeds(getDoc(doc(ana, "orders/o1")));
      await assertSucceeds(getDoc(doc(ana, "orders/o2")));
      await assertFails(getDoc(doc(ana, "orders/o3")));
      await assertSucceeds(getDocs(query(
        collection(ana, "orders"), where("ownerUid", "==", "ana"), orderBy("createdAt", "desc"),
      )));
      await assertFails(getDocs(collection(ana, "orders")));
    });

    it("la clínica lee solo sus pedidos ya pagados", async () => {
      const vet = env.authenticatedContext("vet").firestore();
      const vet2 = env.authenticatedContext("vet2").firestore();
      await assertSucceeds(getDoc(doc(vet, "orders/o1")));
      await assertFails(getDoc(doc(vet, "orders/o2"))); // pendiente_pago
      await assertFails(getDoc(doc(vet2, "orders/o1")));
      const pagados = ["pagado", "preparando", "listo", "enviado", "entregado", "cancelado"];
      await assertSucceeds(getDocs(query(
        collection(vet, "orders"),
        where("clinicId", "==", "c1"),
        where("estado", "in", pagados),
        orderBy("createdAt", "desc"),
      )));
      await assertFails(getDocs(query(collection(vet, "orders"), where("clinicId", "==", "c1"))));
    });

    it("una cuenta suspendida no lee pedidos", async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "orders/o9"), pedido({ ownerUid: "susp" }));
      });
      const susp = env.authenticatedContext("susp").firestore();
      await assertFails(getDoc(doc(susp, "orders/o9")));
    });
  });
});
