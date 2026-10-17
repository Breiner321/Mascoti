import { beforeEach, describe, expect, it } from "vitest";

import { ErrorFuncion } from "../../supabase/functions/_shared/errores.ts";
import {
  agregarAArreglo,
  decodificarCampos,
  PuntoGeo,
} from "../../supabase/functions/_shared/firestore.ts";
import {
  type DependenciasVinculacion,
  normalizarCodigo,
  vincularMascota,
} from "../../supabase/functions/_shared/vinculacion.ts";

describe("normalizarCodigo", () => {
  it("acepta lo que escribe la clínica y devuelve MSC-XXXX", () => {
    expect(normalizarCodigo("MSC-7K4P")).toBe("MSC-7K4P");
    expect(normalizarCodigo(" msc 7k4p ")).toBe("MSC-7K4P");
    expect(normalizarCodigo("7k4p")).toBe("MSC-7K4P");
    expect(normalizarCodigo("MSC7K4P")).toBe("MSC-7K4P");
  });

  it("rechaza formatos inválidos y caracteres ambiguos", () => {
    for (const malo of ["", "MSC-7K4", "MSC-7K4PP", "MSC-0K4P", "MSC-OK4P", "MSC-1K4P",
                        "MSC-IK4P", "MSC-LK4P", "ABC-7K4P", 1234, null, undefined]) {
      expect(normalizarCodigo(malo)).toBeNull();
    }
  });
});

describe("vincularMascota (Edge Function vincular-mascota)", () => {
  let docs: Record<string, Record<string, unknown>>;
  let intentos: string[];
  let permitido: boolean;
  let autorizadas: [string, string][];
  let deps: DependenciasVinculacion;

  beforeEach(() => {
    docs = {
      "users/vet": { role: "clinica", estado: "activo", clinicId: "c1" },
      "clinics/c1": { estado: "activo", nombre: "Vet Norte" },
      "codigosPaciente/MSC-7K4P": { petId: "p1", ownerUid: "ana" },
      "pets/p1": {
        ownerUid: "ana",
        nombre: "Luna",
        especie: "perro",
        fotoPath: "ana/p1/foto.jpg",
        clinicasAutorizadas: [],
      },
      "users/ana": { role: "dueno", estado: "activo", displayName: "Ana Pérez" },
    };
    intentos = [];
    permitido = true;
    autorizadas = [];
    deps = {
      verificarToken: async (token) => {
        if (!token.startsWith("token-")) throw new Error("firma inválida");
        return { uid: token.slice("token-".length) };
      },
      leer: async (ruta) => docs[ruta] ?? null,
      registrarIntento: async (clinicId) => {
        intentos.push(clinicId);
        return { permitido, reintentarEnSegundos: permitido ? 0 : 1500 };
      },
      autorizarClinica: async (petId, clinicId) => {
        autorizadas.push([petId, clinicId]);
      },
    };
  });

  const vincular = (codigo: unknown, uid = "vet") =>
    vincularMascota(deps, `Bearer token-${uid}`, { codigo });

  async function esperarError(promesa: Promise<unknown>, codigo: string, mensaje?: string) {
    const error = await promesa.then(() => null, (e) => e);
    expect(error).toBeInstanceOf(ErrorFuncion);
    expect(error.codigo).toBe(codigo);
    if (mensaje) expect(error.message).toBe(mensaje);
  }

  it("autoriza la clínica y devuelve los datos básicos de la mascota", async () => {
    const resultado = await vincular("msc 7k4p");

    expect(resultado).toEqual({
      petId: "p1",
      codigoPaciente: "MSC-7K4P",
      nombre: "Luna",
      especie: "perro",
      fotoPath: "ana/p1/foto.jpg",
      duenoNombre: "Ana Pérez",
      nueva: true,
    });
    expect(autorizadas).toEqual([["p1", "c1"]]);
    expect(intentos).toEqual(["c1"]);
  });

  it("si ya estaba autorizada no escribe de nuevo", async () => {
    docs["pets/p1"].clinicasAutorizadas = ["c1"];
    const resultado = await vincular("MSC-7K4P");
    expect(resultado.nueva).toBe(false);
    expect(autorizadas).toHaveLength(0);
  });

  it("sin sesión o con token inválido → unauthenticated", async () => {
    await esperarError(vincularMascota(deps, null, { codigo: "MSC-7K4P" }), "unauthenticated");
    await esperarError(vincularMascota(deps, "Bearer falso", { codigo: "MSC-7K4P" }),
      "unauthenticated");
  });

  it("solo clínicas activas pueden vincular", async () => {
    await esperarError(vincular("MSC-7K4P", "ana"), "permission-denied",
      "Solo las clínicas pueden vincular mascotas.");

    docs["users/vet"].estado = "suspendido";
    await esperarError(vincular("MSC-7K4P"), "permission-denied");

    docs["users/vet"].estado = "activo";
    docs["clinics/c1"].estado = "incompleto";
    await esperarError(vincular("MSC-7K4P"), "failed-precondition",
      "Tu clínica debe estar activa para vincular mascotas. Completa tu perfil de atención.");

    expect(intentos).toHaveLength(0);
    expect(autorizadas).toHaveLength(0);
  });

  it("formato inválido → invalid-argument, sin gastar un intento", async () => {
    await esperarError(vincular("MSC-0OO1"), "invalid-argument",
      "El código debe tener el formato MSC-XXXX.");
    expect(intentos).toHaveLength(0);
  });

  it("código inexistente → not-found, y sí cuenta como intento", async () => {
    await esperarError(vincular("MSC-2222"), "not-found", "No existe una mascota con ese código.");
    expect(intentos).toEqual(["c1"]);
  });

  it("código de una mascota borrada → not-found", async () => {
    delete docs["pets/p1"];
    await esperarError(vincular("MSC-7K4P"), "not-found");
  });

  it("superado el límite → resource-exhausted con los minutos de espera", async () => {
    permitido = false;
    await esperarError(vincular("MSC-7K4P"), "resource-exhausted",
      "Demasiados intentos. Intenta de nuevo en 25 minutos.");
    expect(autorizadas).toHaveLength(0);
  });
});

describe("utilidades REST de Firestore (lectura y arrayUnion)", () => {
  it("decodifica un documento con todos los tipos", () => {
    const fecha = "2026-10-16T12:00:00Z";
    expect(decodificarCampos({
      nombre: { stringValue: "Luna" },
      edad: { integerValue: "3" },
      peso: { doubleValue: 12.5 },
      activo: { booleanValue: true },
      nada: { nullValue: null },
      creada: { timestampValue: fecha },
      lugar: { geoPointValue: { latitude: 4.7, longitude: -74 } },
      clinicas: { arrayValue: { values: [{ stringValue: "c1" }] } },
      vacio: { arrayValue: {} },
      contacto: { mapValue: { fields: { telefono: { stringValue: "300" } } } },
    })).toEqual({
      nombre: "Luna",
      edad: 3,
      peso: 12.5,
      activo: true,
      nada: null,
      creada: new Date(fecha),
      lugar: new PuntoGeo(4.7, -74),
      clinicas: ["c1"],
      vacio: [],
      contacto: { telefono: "300" },
    });
  });

  it("agregarAArreglo arma un appendMissingElements que exige el documento", () => {
    expect(agregarAArreglo("mascoti-b27cf", "pets/p1", "clinicasAutorizadas", ["c1"])).toEqual({
      transform: {
        document: "projects/mascoti-b27cf/databases/(default)/documents/pets/p1",
        fieldTransforms: [{
          fieldPath: "clinicasAutorizadas",
          appendMissingElements: { values: [{ stringValue: "c1" }] },
        }],
      },
      currentDocument: { exists: true },
    });
  });
});
