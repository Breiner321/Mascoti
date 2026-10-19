import { beforeEach, describe, expect, it } from "vitest";

import {
  type DependenciasAdjuntos,
  gestionarAdjunto,
} from "../../supabase/functions/_shared/adjuntos.ts";
import { ErrorFuncion } from "../../supabase/functions/_shared/errores.ts";

describe("gestionarAdjunto (Edge Function adjuntos-historial)", () => {
  const ahora = new Date("2026-10-16T12:00:00Z");
  let docs: Record<string, Record<string, unknown>>;
  let subidas: string[];
  let lecturas: string[];
  let deps: DependenciasAdjuntos;

  beforeEach(() => {
    docs = {
      "users/ana": { role: "dueno", estado: "activo" },
      "users/vet2": { role: "clinica", estado: "activo", clinicId: "c2" },
      "users/vet": { role: "clinica", estado: "activo", clinicId: "c1" },
      "users/otro": { role: "dueno", estado: "activo" },
      "pets/p6": { ownerUid: "ana", clinicasAutorizadas: ["c2"] },
    };
    subidas = [];
    lecturas = [];
    deps = {
      verificarToken: async (token) => ({ uid: token.replace("token-", "") }),
      leer: async (ruta) => docs[ruta] ?? null,
      firmarSubida: async (ruta) => {
        subidas.push(ruta);
        return { token: "tok-subida" };
      },
      firmarLectura: async (ruta, segundos) => {
        lecturas.push(ruta);
        return `https://firmado/${ruta}?s=${segundos}`;
      },
      nuevoId: () => "ARCH1",
      ahora: () => ahora,
    };
  });

  const pedir = (uid: string, cuerpo: Record<string, unknown>) =>
    gestionarAdjunto(deps, `Bearer token-${uid}`, cuerpo);

  async function esperarError(promesa: Promise<unknown>, codigo: string) {
    const error = await promesa.then(() => null, (e) => e);
    expect(error).toBeInstanceOf(ErrorFuncion);
    expect(error.codigo).toBe(codigo);
  }

  const subir = (extra: Record<string, unknown> = {}) => ({
    accion: "subir",
    petId: "p6",
    recordId: "r1",
    nombreArchivo: "Radiografía.JPEG",
    ...extra,
  });

  it("la clínica autorizada obtiene un enlace de subida en {petId}/{recordId}/", async () => {
    expect(await pedir("vet2", subir())).toEqual({
      path: "p6/r1/ARCH1.jpg",
      token: "tok-subida",
      tipo: "imagen",
    });
    expect(await pedir("vet2", subir({ nombreArchivo: "examen.pdf" }))).toMatchObject({
      path: "p6/r1/ARCH1.pdf",
      tipo: "pdf",
    });
  });

  it("nadie más puede subir: dueño, clínica no autorizada, sin sesión", async () => {
    await esperarError(pedir("ana", subir()), "permission-denied");
    await esperarError(pedir("vet", subir()), "permission-denied");
    await esperarError(gestionarAdjunto(deps, null, subir()), "unauthenticated");
    docs["users/vet2"].estado = "suspendido";
    await esperarError(pedir("vet2", subir()), "permission-denied");
    expect(subidas).toHaveLength(0);
  });

  it("solo JPG, PNG o PDF", async () => {
    for (const nombre of ["video.mp4", "documento.docx", "sin-extension"]) {
      await esperarError(pedir("vet2", subir({ nombreArchivo: nombre })), "invalid-argument");
    }
  });

  it("un registro existente solo lo amplía su autora y dentro de 24 h", async () => {
    docs["pets/p6/medicalRecords/r1"] = {
      clinicId: "c2",
      createdAt: new Date(ahora.getTime() - 60 * 60 * 1000),
    };
    await expect(pedir("vet2", subir())).resolves.toMatchObject({ path: "p6/r1/ARCH1.jpg" });

    docs["pets/p6/medicalRecords/r1"].createdAt = new Date(ahora.getTime() - 25 * 60 * 60 * 1000);
    await esperarError(pedir("vet2", subir()), "permission-denied");

    docs["pets/p6/medicalRecords/r1"] = { clinicId: "c1", createdAt: ahora };
    await esperarError(pedir("vet2", subir()), "permission-denied");
  });

  it("leen el dueño y las clínicas autorizadas", async () => {
    const leer = { accion: "leer", petId: "p6", path: "p6/r1/ARCH1.jpg" };
    expect(await pedir("ana", leer)).toEqual({
      url: "https://firmado/p6/r1/ARCH1.jpg?s=3600",
      expiraEnSegundos: 3600,
    });
    await expect(pedir("vet2", leer)).resolves.toHaveProperty("url");
    await esperarError(pedir("vet", leer), "permission-denied");
    await esperarError(pedir("otro", leer), "permission-denied");
  });

  it("no deja leer archivos de otra mascota cambiando la ruta", async () => {
    await esperarError(
      pedir("ana", { accion: "leer", petId: "p6", path: "p9/r1/ARCH1.jpg" }),
      "invalid-argument",
    );
    await esperarError(
      pedir("ana", { accion: "leer", petId: "p6", path: "p6/../p9/x.jpg" }),
      "invalid-argument",
    );
    expect(lecturas).toHaveLength(0);
  });

  it("mascota inexistente, id inválido o acción desconocida", async () => {
    await esperarError(pedir("vet2", subir({ petId: "p404" })), "not-found");
    await esperarError(pedir("vet2", subir({ petId: "../p6" })), "invalid-argument");
    await esperarError(pedir("vet2", { accion: "borrar", petId: "p6" }), "invalid-argument");
  });
});
