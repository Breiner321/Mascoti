import { beforeEach, describe, expect, it } from "vitest";

import { ErrorFuncion } from "../../supabase/functions/_shared/errores.ts";
import {
  crearDocumento,
  type EscrituraFirestore,
  HORA_SERVIDOR,
  nuevoIdFirestore,
  PuntoGeo,
  valorFirestore,
} from "../../supabase/functions/_shared/firestore.ts";
import {
  completarRegistro,
  type DependenciasRegistro,
} from "../../supabase/functions/_shared/registro.ts";

const clinica = {
  nombre: "Vet Norte",
  telefono: "3001234567",
  direccion: "Calle 100, Bogotá",
  lat: 4.711,
  lng: -74.0721,
};

/** Cambio 1: el dueño envía su nombre completo y teléfono. */
const DUENO = { role: "dueno", dueno: { nombre: " Ana   Pérez ", telefono: "3001234567" } };

describe("completarRegistro (Edge Function, RF-01)", () => {
  let escrituras: EscrituraFirestore[][];
  let habilitados: string[];
  let resultadoCommit: "ok" | "ya-existe";
  let deps: DependenciasRegistro;

  beforeEach(() => {
    escrituras = [];
    habilitados = [];
    resultadoCommit = "ok";
    deps = {
      proyecto: "mascoti-b27cf",
      verificarToken: async (token) => {
        if (token !== "token-valido") throw new Error("firma inválida");
        return { uid: "u1", email: "ana@correo.co", name: "Ana", picture: "https://foto" };
      },
      commit: async (e) => {
        escrituras.push(e);
        return resultadoCommit;
      },
      habilitarEnSupabase: async (uid) => {
        habilitados.push(uid);
      },
      nuevoId: () => "clinica123",
    };
  });

  async function esperarError(promesa: Promise<unknown>, codigo: string, mensaje?: string) {
    const error = await promesa.then(() => null, (e) => e);
    expect(error).toBeInstanceOf(ErrorFuncion);
    expect(error.codigo).toBe(codigo);
    if (mensaje) expect(error.message).toBe(mensaje);
  }

  it("sin token o con token inválido → unauthenticated", async () => {
    await esperarError(completarRegistro(deps, null, DUENO), "unauthenticated");
    await esperarError(
      completarRegistro(deps, "Bearer token-falso", DUENO),
      "unauthenticated",
    );
    expect(escrituras).toHaveLength(0);
  });

  it("datos inválidos → invalid-argument sin escribir nada", async () => {
    await esperarError(
      completarRegistro(deps, "Bearer token-valido", {
        role: "clinica",
        clinica: { ...clinica, lat: undefined },
      }),
      "invalid-argument",
      "Selecciona una dirección válida de la lista",
    );
    expect(escrituras).toHaveLength(0);
  });

  it("dueño: crea solo users/{uid} con su nombre, teléfono y los datos de Google", async () => {
    const resultado = await completarRegistro(deps, "Bearer token-valido", DUENO);

    expect(resultado).toEqual({ role: "dueno", clinicId: null });
    expect(escrituras).toHaveLength(1);
    const [usuario] = escrituras[0];
    expect(usuario.update.name).toBe(
      "projects/mascoti-b27cf/databases/(default)/documents/users/u1",
    );
    expect(usuario.currentDocument).toEqual({ exists: false });
    expect(usuario.update.fields).toMatchObject({
      email: { stringValue: "ana@correo.co" },
      role: { stringValue: "dueno" },
      estado: { stringValue: "activo" },
      clinicId: { nullValue: null },
      onboardingVisto: { booleanValue: false },
      // Cambio 1: nombre normalizado y teléfono; el de Google se conserva aparte.
      nombre: { stringValue: "Ana Pérez" },
      telefono: { stringValue: "3001234567" },
      displayName: { stringValue: "Ana" },
    });
    expect(usuario.updateTransforms?.map((t) => t.fieldPath)).toEqual([
      "createdAt",
      "lastLoginAt",
    ]);
    expect(habilitados).toEqual(["u1"]);
  });

  it("clínica: users y clinics en el MISMO commit, con geohash", async () => {
    const resultado = await completarRegistro(deps, "Bearer token-valido", {
      role: "clinica",
      clinica,
    });

    expect(resultado).toEqual({ role: "clinica", clinicId: "clinica123" });
    expect(escrituras).toHaveLength(1);
    const [usuario, clinicaDoc] = escrituras[0];
    expect(usuario.update.fields.clinicId).toEqual({ stringValue: "clinica123" });
    expect(clinicaDoc.update.name).toMatch(/documents\/clinics\/clinica123$/);
    expect(clinicaDoc.currentDocument).toEqual({ exists: false });
    expect(clinicaDoc.update.fields).toMatchObject({
      ownerUid: { stringValue: "u1" },
      estado: { stringValue: "incompleto" },
      tiposAnimales: { arrayValue: { values: [] } },
      geo: {
        mapValue: {
          fields: {
            geohash: { stringValue: "d2g6f3w7df" },
            geopoint: { geoPointValue: { latitude: 4.711, longitude: -74.0721 } },
          },
        },
      },
    });
  });

  it("cuenta ya registrada → already-exists con el mensaje del RF", async () => {
    resultadoCommit = "ya-existe";
    await esperarError(
      completarRegistro(deps, "Bearer token-valido", DUENO),
      "already-exists",
      "Esta cuenta ya está registrada. Iniciando sesión...",
    );
    expect(habilitados).toHaveLength(0);
  });

  it("si falla habilitar en Supabase, el registro igual termina", async () => {
    deps.habilitarEnSupabase = async () => {
      throw new Error("Identity Toolkit 500");
    };
    const avisos: string[] = [];
    deps.log = (m) => avisos.push(m);

    await expect(
      completarRegistro(deps, "Bearer token-valido", DUENO),
    ).resolves.toEqual({ role: "dueno", clinicId: null });
    expect(avisos).toHaveLength(1);
  });
  it("Cambio 1: un dueño sin nombre (app vieja) o con datos inválidos no se registra", async () => {
    await esperarError(
      completarRegistro(deps, "Bearer token-valido", { role: "dueno" }),
      "invalid-argument",
      "Actualiza la app para completar tu registro",
    );
    await esperarError(
      completarRegistro(deps, "Bearer token-valido", { role: "dueno", dueno: { nombre: "Al", telefono: "3001234567" } }),
      "invalid-argument",
      "El nombre completo debe tener entre 3 y 60 caracteres",
    );
    expect(escrituras).toHaveLength(0);
  });

  it("Cambio 1: la clínica no guarda nombre de persona en users", async () => {
    await completarRegistro(deps, "Bearer token-valido", { role: "clinica", clinica });
    const usuario = escrituras[0].find((e) => e.update.name.endsWith("/users/u1"))!;
    expect(usuario.update.fields.nombre).toBeUndefined();
  });
});

describe("utilidades de Firestore REST", () => {
  it("convierte cada tipo de valor", () => {
    expect(valorFirestore("a")).toEqual({ stringValue: "a" });
    expect(valorFirestore(3)).toEqual({ integerValue: "3" });
    expect(valorFirestore(3.5)).toEqual({ doubleValue: 3.5 });
    expect(valorFirestore(true)).toEqual({ booleanValue: true });
    expect(valorFirestore(null)).toEqual({ nullValue: null });
    expect(valorFirestore(new PuntoGeo(1, 2))).toEqual({
      geoPointValue: { latitude: 1, longitude: 2 },
    });
    expect(valorFirestore(["x"])).toEqual({
      arrayValue: { values: [{ stringValue: "x" }] },
    });
  });

  it("HORA_SERVIDOR se vuelve transformación y no campo", () => {
    const escritura = crearDocumento("p", "users/u1", { a: "x", createdAt: HORA_SERVIDOR });
    expect(Object.keys(escritura.update.fields)).toEqual(["a"]);
    expect(escritura.updateTransforms).toEqual([
      { fieldPath: "createdAt", setToServerValue: "REQUEST_TIME" },
    ]);
  });

  it("los ids nuevos tienen 20 caracteres alfanuméricos", () => {
    const id = nuevoIdFirestore((n) => Uint8Array.from({ length: n }, (_, i) => i * 13));
    expect(id).toMatch(/^[A-Za-z0-9]{20}$/);
  });

});
