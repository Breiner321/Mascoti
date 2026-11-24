import type { BaseDatos } from "./cliente_firestore.ts";
import { ErrorFuncion } from "./errores.ts";
import { camposFirestore, rutaDocumento } from "./firestore.ts";
import { DESFASE_BOGOTA_MS, fechaBogota } from "./hora_bogota.ts";
import { ESPECIES } from "./placa.ts";
import type { UsuarioFirebase } from "./registro.ts";

/**
 * Carnet de vacunas en PDF (RF-18). Solo el dueño de la mascota lo genera:
 * se leen la mascota y TODAS las vacunas de sus medicalRecords, se dibuja el
 * PDF con pdf-lib (inyectada: este archivo no tiene dependencias), se guarda
 * en el bucket privado `documentos` y se devuelve un enlace firmado de 15 min.
 * El certificado de viaje quedó fuera de alcance (docs/cambios-alcance.md).
 */

export const BUCKET_DOCUMENTOS = "documentos";
export const SEGUNDOS_CARNET = 15 * 60;
export const MAX_PAGINAS = 2;
export const AVISO = "Documento informativo generado por Mascoti";
export const SIN_VACUNAS = "Esta mascota aún no tiene vacunas registradas en Mascoti.";

const ID = /^[A-Za-z0-9]{1,40}$/;

// ---------------------------------------------------------------------------
// Lo mínimo de pdf-lib que se usa (la Edge Function pasa "npm:pdf-lib" y las
// pruebas el paquete de node_modules).
// ---------------------------------------------------------------------------

export interface FuentePdf {
  widthOfTextAtSize(texto: string, tamano: number): number;
}

interface OpcionesTexto {
  x: number;
  y: number;
  size: number;
  font: FuentePdf;
  color: unknown;
}

export interface PaginaPdf {
  drawText(texto: string, opciones: OpcionesTexto): void;
  drawRectangle(opciones: { x: number; y: number; width: number; height: number; color: unknown }): void;
  drawLine(opciones: {
    start: { x: number; y: number };
    end: { x: number; y: number };
    thickness: number;
    color: unknown;
  }): void;
}

export interface DocumentoPdf {
  addPage(tamano: [number, number]): PaginaPdf;
  embedFont(nombre: string): Promise<FuentePdf>;
  setTitle(titulo: string): void;
  setAuthor(autor: string): void;
  setCreator(creador: string): void;
  setProducer(productor: string): void;
  setLanguage(idioma: string): void;
  setCreationDate(fecha: Date): void;
  save(): Promise<Uint8Array>;
}

export interface LibPdf {
  PDFDocument: { create(): Promise<DocumentoPdf> };
  StandardFonts: { Helvetica: string; HelveticaBold: string };
  rgb(r: number, g: number, b: number): unknown;
}

// ---------------------------------------------------------------------------
// Modelo
// ---------------------------------------------------------------------------

export interface FilaVacuna {
  vacuna: string;
  lote: string;
  aplicada: Date;
  proximaDosis: Date | null;
  clinica: string;
}

export interface ModeloCarnet {
  nombre: string;
  especie: string;
  raza: string;
  fechaNacimiento: Date | null;
  codigoPaciente: string;
  vacunas: FilaVacuna[];
  emitido: Date;
}

const texto = (v: unknown): string => (typeof v === "string" ? v.trim() : "");
const fecha = (v: unknown): Date | null =>
  v instanceof Date && !Number.isNaN(v.getTime()) ? v : null;

/** Todas las vacunas de los registros, de la más antigua a la más reciente. */
export function filasVacunas(registros: Record<string, unknown>[]): FilaVacuna[] {
  const filas: FilaVacuna[] = [];
  for (const registro of registros) {
    const vacunas = Array.isArray(registro.vacunas) ? registro.vacunas : [];
    for (const v of vacunas) {
      if (typeof v !== "object" || v === null) continue;
      const datos = v as Record<string, unknown>;
      const aplicada = fecha(datos.fechaAplicacion);
      if (!aplicada) continue;
      filas.push({
        vacuna: texto(datos.nombre) || "Vacuna",
        lote: texto(datos.lote) || "—",
        aplicada,
        proximaDosis: fecha(datos.fechaProximaDosis),
        clinica: texto(registro.clinicNombre) || "Clínica veterinaria",
      });
    }
  }
  return filas.sort((a, b) =>
    a.aplicada.getTime() - b.aplicada.getTime() || a.vacuna.localeCompare(b.vacuna, "es")
  );
}

/** dd/mm/aaaa en hora de Colombia. */
export function fechaCorta(instante: Date): string {
  const [a, m, d] = fechaBogota(instante).split("-");
  return `${d}/${m}/${a}`;
}

/** "24/11/2026, 3:05 p. m." en hora de Colombia. */
export function fechaHora(instante: Date): string {
  const local = new Date(instante.getTime() + DESFASE_BOGOTA_MS);
  const h = local.getUTCHours();
  const min = String(local.getUTCMinutes()).padStart(2, "0");
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${fechaCorta(instante)}, ${h12}:${min} ${h < 12 ? "a. m." : "p. m."}`;
}

/** Ruta del PDF en el bucket: un carnet por día (el del mismo día se reemplaza). */
export function rutaCarnet(petId: string, instante: Date): string {
  return `pets/${petId}/documentos/carnet-${fechaBogota(instante)}.pdf`;
}

/**
 * Las fuentes estándar de PDF usan WinAnsi: se cambian las comillas tipográficas
 * y se reemplaza lo que no se puede dibujar (emojis, otros alfabetos).
 */
export function textoPdf(valor: string): string {
  return valor
    .replace(/[\r\n\t]+/g, " ")
    .replace(/[“”]/g, '"')
    .replace(/[‘’]/g, "'")
    .replace(/[–—]/g, "-")
    .replace(/…/g, "...")
    .replace(/[^\x20-\x7E\xA0-\xFF]/gu, "?");
}

// ---------------------------------------------------------------------------
// Dibujo
// ---------------------------------------------------------------------------

const A4: [number, number] = [595.28, 841.89];
const MARGEN = 40;
const ANCHO = A4[0] - 2 * MARGEN;
const ALTO_FILA = 18;
const PIE = 70; // Espacio reservado abajo para el aviso y el número de página.

/** Columnas de la tabla (suman ANCHO). */
const COLUMNAS: { titulo: string; ancho: number }[] = [
  { titulo: "Vacuna", ancho: 130 },
  { titulo: "Lote", ancho: 75 },
  { titulo: "Aplicada", ancho: 70 },
  { titulo: "Próxima dosis", ancho: 80 },
  { titulo: "Clínica", ancho: ANCHO - 355 },
];

/** Dónde empieza la tabla en cada página (la primera lleva los datos). */
const INICIO_TABLA_1 = A4[1] - 300;
const INICIO_TABLA_2 = A4[1] - 110;

/** Filas que caben debajo del encabezado de la tabla. */
const capacidad = (inicio: number) => Math.floor((inicio - ALTO_FILA - (MARGEN + PIE)) / ALTO_FILA);
export const FILAS_PAGINA_1 = capacidad(INICIO_TABLA_1);
export const FILAS_PAGINA_2 = capacidad(INICIO_TABLA_2);

export interface PdfCarnet {
  bytes: Uint8Array;
  paginas: number;
  /** Vacunas dibujadas y las que no cupieron (las más antiguas). */
  vacunasIncluidas: number;
  vacunasOmitidas: number;
  /** Todo el texto dibujado, en orden (para las pruebas). */
  textos: string[];
}

/** Reparte las filas: 1 página si caben; si no, 2 con las más recientes. */
export function repartirFilas(total: number): { paginas: number; omitidas: number } {
  if (total <= FILAS_PAGINA_1) return { paginas: 1, omitidas: 0 };
  const maximo = FILAS_PAGINA_1 + FILAS_PAGINA_2;
  if (total <= maximo) return { paginas: 2, omitidas: 0 };
  // Una fila se usa para el aviso "y N vacunas anteriores…".
  return { paginas: 2, omitidas: total - (maximo - 1) };
}

/** Primera fila cuando no caben todas: las más antiguas se omiten. */
export function avisoOmitidas(n: number): string {
  return n === 1
    ? "y 1 vacuna anterior más en el historial de Mascoti"
    : `y ${n} vacunas anteriores más en el historial de Mascoti`;
}

export async function dibujarCarnetPdf(modelo: ModeloCarnet, pdf: LibPdf): Promise<PdfCarnet> {
  const doc = await pdf.PDFDocument.create();
  const normal = await doc.embedFont(pdf.StandardFonts.Helvetica);
  const negrita = await doc.embedFont(pdf.StandardFonts.HelveticaBold);
  const morado = pdf.rgb(0x7e / 255, 0x22 / 255, 0xce / 255);
  const moradoSuave = pdf.rgb(0xf3 / 255, 0xe8 / 255, 0xff / 255);
  const tinta = pdf.rgb(0x1e / 255, 0x15 / 255, 0x30 / 255);
  const tenue = pdf.rgb(0x67 / 255, 0x5f / 255, 0x73 / 255);
  const borde = pdf.rgb(0xed / 255, 0xe4 / 255, 0xf7 / 255);
  const blanco = pdf.rgb(1, 1, 1);

  const nombre = modelo.nombre || "Mascota";
  doc.setTitle(`Carnet de vacunas de ${nombre}`);
  doc.setAuthor("Mascoti");
  doc.setCreator("Mascoti");
  doc.setProducer("Mascoti");
  doc.setLanguage("es-CO");
  doc.setCreationDate(modelo.emitido);

  const textos: string[] = [];
  const escribir = (
    pagina: PaginaPdf,
    valor: string,
    x: number,
    y: number,
    tamano: number,
    opciones: { fuente?: FuentePdf; color?: unknown; ancho?: number } = {},
  ) => {
    const fuente = opciones.fuente ?? normal;
    let limpio = textoPdf(valor);
    // Recorta con "..." lo que no cabe en la columna.
    if (opciones.ancho !== undefined && fuente.widthOfTextAtSize(limpio, tamano) > opciones.ancho) {
      while (limpio.length > 1 && fuente.widthOfTextAtSize(`${limpio}...`, tamano) > opciones.ancho) {
        limpio = limpio.slice(0, -1);
      }
      limpio = `${limpio.trimEnd()}...`;
    }
    pagina.drawText(limpio, { x, y, size: tamano, font: fuente, color: opciones.color ?? tinta });
    textos.push(limpio);
  };

  const filas = modelo.vacunas;
  const { paginas, omitidas } = filas.length === 0
    ? { paginas: 1, omitidas: 0 }
    : repartirFilas(filas.length);
  const visibles = filas.slice(omitidas);

  const encabezadoTabla = (pagina: PaginaPdf, y: number) => {
    pagina.drawRectangle({ x: MARGEN, y: y - 5, width: ANCHO, height: ALTO_FILA, color: morado });
    let x = MARGEN + 6;
    for (const c of COLUMNAS) {
      escribir(pagina, c.titulo, x, y, 9, { fuente: negrita, color: blanco, ancho: c.ancho - 10 });
      x += c.ancho;
    }
  };

  const fila = (pagina: PaginaPdf, v: FilaVacuna, y: number, par: boolean) => {
    if (par) pagina.drawRectangle({ x: MARGEN, y: y - 5, width: ANCHO, height: ALTO_FILA, color: moradoSuave });
    const celdas = [
      v.vacuna,
      v.lote,
      fechaCorta(v.aplicada),
      v.proximaDosis ? fechaCorta(v.proximaDosis) : "—",
      v.clinica,
    ];
    let x = MARGEN + 6;
    celdas.forEach((celda, i) => {
      escribir(pagina, celda, x, y, 9, { ancho: COLUMNAS[i].ancho - 10 });
      x += COLUMNAS[i].ancho;
    });
  };

  const pie = (pagina: PaginaPdf, numero: number) => {
    const y = MARGEN + 34;
    pagina.drawLine({
      start: { x: MARGEN, y: y + 14 },
      end: { x: A4[0] - MARGEN, y: y + 14 },
      thickness: 1,
      color: borde,
    });
    escribir(pagina, AVISO, MARGEN, y, 9, { fuente: negrita, color: tenue });
    escribir(pagina, `Emitido el ${fechaHora(modelo.emitido)} (hora de Colombia)`, MARGEN, y - 14, 8, {
      color: tenue,
    });
    escribir(pagina, `Página ${numero} de ${paginas}`, A4[0] - MARGEN - 60, y - 14, 8, { color: tenue });
  };

  // ---- Página 1: encabezado y datos de la mascota ----
  const p1 = doc.addPage(A4);
  let y = A4[1] - MARGEN - 26;
  escribir(p1, "Mascoti", MARGEN, y, 28, { fuente: negrita, color: morado });
  escribir(p1, "Carnet de vacunas", MARGEN, y - 24, 14, { fuente: negrita });
  p1.drawLine({
    start: { x: MARGEN, y: y - 36 },
    end: { x: A4[0] - MARGEN, y: y - 36 },
    thickness: 2,
    color: morado,
  });

  y -= 64;
  const datos: [string, string][] = [
    ["Nombre", nombre],
    ["Especie", modelo.especie],
    ["Raza", modelo.raza || "Sin raza registrada"],
    ["Fecha de nacimiento", modelo.fechaNacimiento ? fechaCorta(modelo.fechaNacimiento) : "Sin registrar"],
    ["Código de paciente", modelo.codigoPaciente || "Sin código"],
  ];
  for (const [etiqueta, valor] of datos) {
    escribir(p1, etiqueta, MARGEN, y, 10, { fuente: negrita, color: tenue });
    escribir(p1, valor, MARGEN + 130, y, 11, { ancho: ANCHO - 130 });
    y -= 20;
  }

  y = INICIO_TABLA_1 + 30;
  escribir(p1, "Vacunas aplicadas", MARGEN, y, 13, { fuente: negrita, color: morado });

  if (filas.length === 0) {
    escribir(p1, SIN_VACUNAS, MARGEN, INICIO_TABLA_1, 11);
    escribir(
      p1,
      "Cuando una clínica registre una vacuna en el historial médico, aparecerá aquí.",
      MARGEN,
      INICIO_TABLA_1 - 18,
      10,
      { color: tenue },
    );
    pie(p1, 1);
  } else {
    let restantes = [...visibles];
    let pagina = p1;
    let numero = 1;
    let inicio = INICIO_TABLA_1;
    let cupo = FILAS_PAGINA_1;
    while (true) {
      encabezadoTabla(pagina, inicio);
      let yFila = inicio - ALTO_FILA;
      let usadas = 0;
      if (numero === 1 && omitidas > 0) {
        escribir(pagina, avisoOmitidas(omitidas), MARGEN + 6, yFila, 9, { color: tenue });
        yFila -= ALTO_FILA;
        usadas = 1;
      }
      const tanda = restantes.slice(0, cupo - usadas);
      tanda.forEach((v, i) => fila(pagina, v, yFila - i * ALTO_FILA, i % 2 === 1));
      restantes = restantes.slice(tanda.length);
      pie(pagina, numero);
      if (restantes.length === 0 || numero === MAX_PAGINAS) break;
      numero += 1;
      pagina = doc.addPage(A4);
      const yTitulo = A4[1] - MARGEN - 20;
      escribir(pagina, "Mascoti", MARGEN, yTitulo, 18, { fuente: negrita, color: morado });
      escribir(pagina, `Carnet de vacunas de ${nombre} (continuación)`, MARGEN, yTitulo - 22, 11, {
        fuente: negrita,
        ancho: ANCHO,
      });
      inicio = INICIO_TABLA_2;
      cupo = FILAS_PAGINA_2;
    }
  }

  return {
    bytes: await doc.save(),
    paginas,
    vacunasIncluidas: visibles.length,
    vacunasOmitidas: omitidas,
    textos,
  };
}

// ---------------------------------------------------------------------------
// Función
// ---------------------------------------------------------------------------

export interface DependenciasCarnet {
  verificarToken(token: string): Promise<UsuarioFirebase>;
  db: BaseDatos;
  pdf: LibPdf;
  /** Sube (o reemplaza) el PDF en el bucket `documentos`. */
  subir(path: string, bytes: Uint8Array): Promise<void>;
  firmarLectura(path: string, segundos: number): Promise<string>;
  ahora(): Date;
}

export interface RespuestaCarnet {
  url: string;
  expiraEnSegundos: number;
  path: string;
  generadoEn: string;
  vacunas: number;
}

export async function generarCarnet(
  deps: DependenciasCarnet,
  autorizacion: string | null,
  cuerpo: unknown,
): Promise<RespuestaCarnet> {
  const token = autorizacion?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) throw new ErrorFuncion("unauthenticated", "Debes iniciar sesión con Google.");
  let usuario: UsuarioFirebase;
  try {
    usuario = await deps.verificarToken(token);
  } catch {
    throw new ErrorFuncion("unauthenticated", "Debes iniciar sesión con Google.");
  }

  const datos = (typeof cuerpo === "object" && cuerpo !== null ? cuerpo : {}) as Record<string, unknown>;
  const petId = texto(datos.petId);
  if (!ID.test(petId)) throw new ErrorFuncion("invalid-argument", "Mascota inválida.");

  const perfil = (await deps.db.leer(`users/${usuario.uid}`))?.datos;
  if (!perfil || perfil.role !== "dueno" || perfil.estado !== "activo") {
    throw new ErrorFuncion("permission-denied", "Solo el dueño de la mascota puede generar su carnet.");
  }
  const mascota = (await deps.db.leer(`pets/${petId}`))?.datos;
  if (!mascota) throw new ErrorFuncion("not-found", "La mascota no existe.");
  if (mascota.ownerUid !== usuario.uid) {
    throw new ErrorFuncion("permission-denied", "Solo el dueño de la mascota puede generar su carnet.");
  }

  const registros = await deps.db.consultar({ padre: `pets/${petId}`, coleccion: "medicalRecords", filtros: [] });
  const ahora = deps.ahora();
  const modelo: ModeloCarnet = {
    nombre: texto(mascota.nombre),
    especie: ESPECIES[texto(mascota.especie)] ?? "Mascota",
    raza: texto(mascota.raza),
    fechaNacimiento: fecha(mascota.fechaNacimiento),
    codigoPaciente: texto(mascota.codigoPaciente),
    vacunas: filasVacunas(registros.map((r) => r.datos)),
    emitido: ahora,
  };

  let pdf: PdfCarnet;
  try {
    pdf = await dibujarCarnetPdf(modelo, deps.pdf);
  } catch (e) {
    console.error(e);
    throw new ErrorFuncion("internal", "No pudimos generar el carnet. Intenta de nuevo.");
  }

  const path = rutaCarnet(petId, ahora);
  await deps.subir(path, pdf.bytes);
  const url = await deps.firmarLectura(path, SEGUNDOS_CARNET);

  // Último carnet, para que la app muestre "Último carnet: …".
  await deps.db.commit([{
    update: {
      name: rutaDocumento(deps.db.proyecto, `pets/${petId}/documentos/carnet`),
      fields: camposFirestore({ path, generadoAt: ahora, vacunas: modelo.vacunas.length }),
    },
  }]);

  return {
    url,
    expiraEnSegundos: SEGUNDOS_CARNET,
    path,
    generadoEn: ahora.toISOString(),
    vacunas: modelo.vacunas.length,
  };
}
