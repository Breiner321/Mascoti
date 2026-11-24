import { PDFDocument, rgb, StandardFonts } from "pdf-lib";
import { describe, expect, it } from "vitest";

import {
  AVISO,
  avisoOmitidas,
  type DependenciasCarnet,
  dibujarCarnetPdf,
  fechaCorta,
  fechaHora,
  FILAS_PAGINA_1,
  FILAS_PAGINA_2,
  filasVacunas,
  generarCarnet,
  type LibPdf,
  type ModeloCarnet,
  rutaCarnet,
  SEGUNDOS_CARNET,
  SIN_VACUNAS,
  textoPdf,
} from "../../supabase/functions/_shared/carnet.ts";
import type { BaseDatos, DocumentoLeido, Escritura } from "../../supabase/functions/_shared/cliente_firestore.ts";
import type { Consulta } from "../../supabase/functions/_shared/firestore.ts";
import { ErrorFuncion } from "../../supabase/functions/_shared/errores.ts";

const pdf = { PDFDocument, StandardFonts, rgb } as unknown as LibPdf;

/** 24/11/2026 15:05 en Bogotá = 20:05 UTC. */
const AHORA = new Date("2026-11-24T20:05:00Z");
const dia = (iso: string) => new Date(`${iso}T15:00:00Z`);

const vacuna = (nombre: string, aplicada: string, extra: Record<string, unknown> = {}) => ({
  nombre,
  lote: `L-${nombre}`,
  fechaAplicacion: dia(aplicada),
  ...extra,
});

class BaseFalsa implements BaseDatos {
  readonly proyecto = "demo";
  escrituras: Escritura[] = [];
  consultas: Consulta[] = [];
  constructor(
    private docs: Record<string, Record<string, unknown>>,
    private registros: Record<string, unknown>[] = [],
  ) {}

  async leer(ruta: string): Promise<DocumentoLeido | null> {
    const datos = this.docs[ruta];
    return datos ? { id: ruta.split("/").pop()!, ruta, datos, updateTime: "t" } : null;
  }

  async consultar(consulta: Consulta): Promise<DocumentoLeido[]> {
    this.consultas.push(consulta);
    return this.registros.map((datos, i) => ({ id: `r${i}`, ruta: `r${i}`, datos, updateTime: "t" }));
  }

  async commit(escrituras: Escritura[]): Promise<"ok"> {
    this.escrituras.push(...escrituras);
    return "ok";
  }
}

function preparar(registros: Record<string, unknown>[] = [], mascota: Record<string, unknown> = {}) {
  const db = new BaseFalsa(
    {
      "users/ana": { role: "dueno", estado: "activo" },
      "users/beto": { role: "dueno", estado: "activo" },
      "users/vet": { role: "clinica", estado: "activo", clinicId: "c1" },
      "users/sus": { role: "dueno", estado: "suspendido" },
      "pets/p1": {
        ownerUid: "ana",
        nombre: "Luna",
        especie: "perro",
        raza: "Criolla",
        fechaNacimiento: dia("2022-03-10"),
        codigoPaciente: "MSC-AB12CD",
        ...mascota,
      },
    },
    registros,
  );
  const subidos: { path: string; bytes: Uint8Array }[] = [];
  const deps: DependenciasCarnet = {
    verificarToken: async (token) => {
      if (token === "malo") throw new Error("token inválido");
      return { uid: token };
    },
    db,
    pdf,
    subir: async (path, bytes) => {
      subidos.push({ path, bytes });
    },
    firmarLectura: async (path, segundos) => `https://firmada/${path}?s=${segundos}`,
    ahora: () => AHORA,
  };
  return { db, deps, subidos };
}

async function codigo(promesa: Promise<unknown>): Promise<string> {
  try {
    await promesa;
  } catch (e) {
    if (e instanceof ErrorFuncion) return e.codigo;
    throw e;
  }
  return "ok";
}

describe("generar-carnet: permisos", () => {
  it("sin sesión o con token inválido", async () => {
    const { deps } = preparar();
    expect(await codigo(generarCarnet(deps, null, { petId: "p1" }))).toBe("unauthenticated");
    expect(await codigo(generarCarnet(deps, "Bearer malo", { petId: "p1" }))).toBe("unauthenticated");
  });

  it("mascota inválida o inexistente", async () => {
    const { deps } = preparar();
    expect(await codigo(generarCarnet(deps, "Bearer ana", { petId: "../x" }))).toBe("invalid-argument");
    expect(await codigo(generarCarnet(deps, "Bearer ana", {}))).toBe("invalid-argument");
    expect(await codigo(generarCarnet(deps, "Bearer ana", { petId: "p9" }))).toBe("not-found");
  });

  it("solo el dueño: otro dueño, una clínica o una cuenta suspendida no pueden, y no se guarda nada", async () => {
    const { deps, db, subidos } = preparar([{ vacunas: [vacuna("Rabia", "2026-01-10")] }]);
    for (const uid of ["beto", "vet", "sus", "nadie"]) {
      expect(await codigo(generarCarnet(deps, `Bearer ${uid}`, { petId: "p1" }))).toBe("permission-denied");
    }
    expect(subidos).toHaveLength(0);
    expect(db.escrituras).toHaveLength(0);
    expect(db.consultas).toHaveLength(0);
  });
});

describe("generar-carnet: PDF", () => {
  it("con vacunas: guarda el PDF del día, devuelve la URL de 15 min y el último carnet", async () => {
    const { deps, db, subidos } = preparar([
      { clinicNombre: "Vet Norte", vacunas: [vacuna("Rabia", "2026-01-10", { fechaProximaDosis: dia("2027-01-10") })] },
    ]);
    const r = await generarCarnet(deps, "Bearer ana", { petId: "p1" });

    expect(db.consultas[0]).toMatchObject({ padre: "pets/p1", coleccion: "medicalRecords", filtros: [] });
    expect(r.path).toBe("pets/p1/documentos/carnet-2026-11-24.pdf");
    expect(r.url).toBe(`https://firmada/${r.path}?s=900`);
    expect(r.expiraEnSegundos).toBe(SEGUNDOS_CARNET);
    expect(r.vacunas).toBe(1);
    expect(r.generadoEn).toBe(AHORA.toISOString());

    expect(subidos).toHaveLength(1);
    const cargado = await PDFDocument.load(subidos[0].bytes);
    expect(cargado.getPageCount()).toBe(1);
    expect(cargado.getTitle()).toBe("Carnet de vacunas de Luna");

    const escritura = db.escrituras[0] as { update: { name: string; fields: Record<string, unknown> } };
    expect(escritura.update.name).toContain("pets/p1/documentos/carnet");
    expect(escritura.update.fields).toEqual({
      path: { stringValue: r.path },
      generadoAt: { timestampValue: AHORA.toISOString() },
      vacunas: { integerValue: "1" },
    });
  });

  it("dibuja los datos de la mascota, la tabla, la fecha de emisión y el aviso", async () => {
    const modelo: ModeloCarnet = {
      nombre: "Luna",
      especie: "Perro",
      raza: "Criolla",
      fechaNacimiento: dia("2022-03-10"),
      codigoPaciente: "MSC-AB12CD",
      vacunas: filasVacunas([
        { clinicNombre: "Vet Norte", vacunas: [vacuna("Rabia", "2026-01-10", { fechaProximaDosis: dia("2027-01-10") })] },
      ]),
      emitido: AHORA,
    };
    const { textos, paginas } = await dibujarCarnetPdf(modelo, pdf);
    expect(paginas).toBe(1);
    for (const t of [
      "Mascoti",
      "Carnet de vacunas",
      "Luna",
      "Perro",
      "Criolla",
      "10/03/2022",
      "MSC-AB12CD",
      "Vacuna",
      "Lote",
      "Aplicada",
      "Próxima dosis",
      "Clínica",
      "Rabia",
      "L-Rabia",
      "10/01/2026",
      "10/01/2027",
      "Vet Norte",
      AVISO,
      "Emitido el 24/11/2026, 3:05 p. m. (hora de Colombia)",
      "Página 1 de 1",
    ]) {
      expect(textos).toContain(t);
    }
  });

  it("sin vacunas: un PDF de una página que lo dice", async () => {
    const { deps, subidos } = preparar([{ diagnostico: "Control", vacunas: [] }, { diagnostico: "Otro" }]);
    const r = await generarCarnet(deps, "Bearer ana", { petId: "p1" });
    expect(r.vacunas).toBe(0);
    const cargado = await PDFDocument.load(subidos[0].bytes);
    expect(cargado.getPageCount()).toBe(1);

    const { textos } = await dibujarCarnetPdf(
      { nombre: "Luna", especie: "Perro", raza: "", fechaNacimiento: null, codigoPaciente: "", vacunas: [], emitido: AHORA },
      pdf,
    );
    expect(textos).toContain(SIN_VACUNAS);
    expect(textos).toContain(AVISO);
    expect(textos).toContain("Sin registrar");
    expect(textos).not.toContain("Lote");
  });

  it("muchas vacunas: máximo 2 páginas, con las más recientes y el aviso de las omitidas", async () => {
    const total = FILAS_PAGINA_1 + FILAS_PAGINA_2 + 5;
    const vacunas = Array.from({ length: total }, (_, i) => ({
      nombre: `V${String(i).padStart(3, "0")}`,
      lote: "L",
      fechaAplicacion: new Date(Date.UTC(2020, 0, 1 + i, 15)),
    }));
    const modelo: ModeloCarnet = {
      nombre: "Luna", especie: "Perro", raza: "", fechaNacimiento: null, codigoPaciente: "",
      vacunas: filasVacunas([{ vacunas }]), emitido: AHORA,
    };
    const r = await dibujarCarnetPdf(modelo, pdf);
    expect(r.paginas).toBe(2);
    expect((await PDFDocument.load(r.bytes)).getPageCount()).toBe(2);
    expect(r.vacunasOmitidas).toBe(6);
    expect(r.vacunasIncluidas + r.vacunasOmitidas).toBe(total);
    expect(r.textos).toContain(avisoOmitidas(6));
    expect(r.textos).not.toContain("V000");
    expect(r.textos).toContain(`V${String(total - 1).padStart(3, "0")}`);
    expect(r.textos).toContain("Página 2 de 2");
  });

  it("dos páginas sin omitir cuando caben", async () => {
    const vacunas = Array.from({ length: FILAS_PAGINA_1 + 1 }, (_, i) => vacuna(`V${i}`, "2026-01-01"));
    const r = await dibujarCarnetPdf(
      { nombre: "Luna", especie: "Perro", raza: "", fechaNacimiento: null, codigoPaciente: "",
        vacunas: filasVacunas([{ vacunas }]), emitido: AHORA },
      pdf,
    );
    expect(r.paginas).toBe(2);
    expect(r.vacunasOmitidas).toBe(0);
  });
});

describe("carnet: orden y formato", () => {
  it("todas las vacunas de todos los registros, de la más antigua a la más reciente", () => {
    const filas = filasVacunas([
      { clinicNombre: "Vet Sur", vacunas: [vacuna("Rabia", "2026-06-01"), vacuna("Moquillo", "2025-02-01")] },
      { clinicNombre: "Vet Norte", vacunas: [vacuna("Parvovirus", "2025-09-15"), vacuna("Leptospira", "2026-06-01")] },
      { clinicNombre: "Vet Centro" },
      { vacunas: [{ nombre: "Sin fecha", lote: "X" }, "basura"] },
    ]);
    expect(filas.map((f) => f.vacuna)).toEqual(["Moquillo", "Parvovirus", "Leptospira", "Rabia"]);
    expect(filas.map((f) => f.clinica)).toEqual(["Vet Sur", "Vet Norte", "Vet Norte", "Vet Sur"]);
    expect(filas[0].proximaDosis).toBeNull();
  });

  it("fechas y ruta en hora de Colombia", () => {
    // 23/11 a las 11 p. m. en Bogotá ya es 24/11 en UTC.
    const noche = new Date("2026-11-24T04:00:00Z");
    expect(fechaCorta(noche)).toBe("23/11/2026");
    expect(rutaCarnet("p1", noche)).toBe("pets/p1/documentos/carnet-2026-11-23.pdf");
    expect(fechaHora(noche)).toBe("23/11/2026, 11:00 p. m.");
    expect(fechaHora(new Date("2026-11-24T05:30:00Z"))).toBe("24/11/2026, 12:30 a. m.");
  });

  it("texto que las fuentes del PDF pueden dibujar", () => {
    expect(textoPdf("Ñoño “Max” – 🐶")).toBe('Ñoño "Max" - ?');
    expect(textoPdf("línea\nnueva")).toBe("línea nueva");
  });
});
