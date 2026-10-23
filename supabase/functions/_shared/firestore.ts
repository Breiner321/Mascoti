/**
 * Utilidades para escribir en Firestore con su API REST (las Edge Functions
 * corren en Deno, donde el SDK de Firebase Admin no funciona bien).
 * Formato: https://firebase.google.com/docs/firestore/reference/rest/v1/Value
 */

/** Marca un campo para que Firestore le ponga la hora del servidor. */
export const HORA_SERVIDOR = Symbol("HORA_SERVIDOR");

/** Punto geográfico de Firestore (GeoPoint). */
export class PuntoGeo {
  constructor(readonly lat: number, readonly lng: number) {}
}

export type ValorCampo =
  | string
  | number
  | boolean
  | null
  | PuntoGeo
  | Date
  | typeof HORA_SERVIDOR
  | ValorCampo[]
  | { [campo: string]: ValorCampo };

export type ValorFirestore = Record<string, unknown>;

/** Precondición de una escritura: que exista (o no), o que no haya cambiado. */
export type Precondicion = { exists: boolean } | { updateTime: string };

export interface EscrituraFirestore {
  update: { name: string; fields: Record<string, ValorFirestore> };
  updateMask?: { fieldPaths: string[] };
  updateTransforms?: { fieldPath: string; setToServerValue: "REQUEST_TIME" }[];
  currentDocument?: Precondicion;
}

export function valorFirestore(valor: ValorCampo): ValorFirestore {
  if (valor === null) return { nullValue: null };
  if (typeof valor === "string") return { stringValue: valor };
  if (typeof valor === "boolean") return { booleanValue: valor };
  if (typeof valor === "number") {
    return Number.isInteger(valor)
      ? { integerValue: String(valor) }
      : { doubleValue: valor };
  }
  if (valor instanceof Date) return { timestampValue: valor.toISOString() };
  if (valor instanceof PuntoGeo) {
    return { geoPointValue: { latitude: valor.lat, longitude: valor.lng } };
  }
  if (Array.isArray(valor)) {
    return { arrayValue: { values: valor.map(valorFirestore) } };
  }
  if (typeof valor === "object") {
    return { mapValue: { fields: camposFirestore(valor) } };
  }
  throw new Error("HORA_SERVIDOR solo se permite como campo de primer nivel");
}

export function camposFirestore(campos: { [campo: string]: ValorCampo }) {
  const resultado: Record<string, ValorFirestore> = {};
  for (const [campo, valor] of Object.entries(campos)) {
    if (valor !== HORA_SERVIDOR) resultado[campo] = valorFirestore(valor);
  }
  return resultado;
}

/**
 * Escritura que CREA el documento: falla si ya existe (`exists: false`).
 * Los campos con [HORA_SERVIDOR] se convierten en transformaciones.
 */
export function crearDocumento(
  proyecto: string,
  ruta: string,
  campos: { [campo: string]: ValorCampo },
): EscrituraFirestore {
  const horas = Object.entries(campos)
    .filter(([, valor]) => valor === HORA_SERVIDOR)
    .map(([campo]) => ({ fieldPath: campo, setToServerValue: "REQUEST_TIME" as const }));
  return {
    update: {
      name: `projects/${proyecto}/databases/(default)/documents/${ruta}`,
      fields: camposFirestore(campos),
    },
    ...(horas.length > 0 ? { updateTransforms: horas } : {}),
    currentDocument: { exists: false },
  };
}

const ALFABETO_ID = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

/** Id aleatorio de 20 caracteres, igual a los que genera Firestore. */
export function nuevoIdFirestore(aleatorio: (n: number) => Uint8Array): string {
  return Array.from(aleatorio(20), (b) => ALFABETO_ID[b % ALFABETO_ID.length]).join("");
}

// ---------------------------------------------------------------------------
// Lectura y escrituras parciales (semana 3)
// ---------------------------------------------------------------------------

/** Escritura con transformaciones de campos (p. ej. agregar a un arreglo). */
export interface TransformacionFirestore {
  transform: {
    document: string;
    fieldTransforms: {
      fieldPath: string;
      appendMissingElements?: { values: ValorFirestore[] };
    }[];
  };
  currentDocument?: { exists: boolean };
}

export function rutaDocumento(proyecto: string, ruta: string): string {
  return `projects/${proyecto}/databases/(default)/documents/${ruta}`;
}

/**
 * Agrega [valores] a un arreglo sin duplicarlos (como arrayUnion). Falla si
 * el documento no existe.
 */
export function agregarAArreglo(
  proyecto: string,
  ruta: string,
  campo: string,
  valores: string[],
): TransformacionFirestore {
  return {
    transform: {
      document: rutaDocumento(proyecto, ruta),
      fieldTransforms: [{
        fieldPath: campo,
        appendMissingElements: { values: valores.map((v) => ({ stringValue: v })) },
      }],
    },
    currentDocument: { exists: true },
  };
}

/** Valor de la API REST → valor de JavaScript (Timestamp → Date). */
export function decodificarValor(valor: ValorFirestore): unknown {
  if ("nullValue" in valor) return null;
  if ("stringValue" in valor) return valor.stringValue;
  if ("booleanValue" in valor) return valor.booleanValue;
  if ("integerValue" in valor) return Number(valor.integerValue);
  if ("doubleValue" in valor) return valor.doubleValue;
  if ("timestampValue" in valor) return new Date(String(valor.timestampValue));
  if ("geoPointValue" in valor) {
    const g = valor.geoPointValue as { latitude?: number; longitude?: number };
    return new PuntoGeo(g.latitude ?? 0, g.longitude ?? 0);
  }
  if ("arrayValue" in valor) {
    const valores = (valor.arrayValue as { values?: ValorFirestore[] }).values ?? [];
    return valores.map(decodificarValor);
  }
  if ("mapValue" in valor) {
    const campos = (valor.mapValue as { fields?: Record<string, ValorFirestore> }).fields ?? {};
    return decodificarCampos(campos);
  }
  return undefined;
}

/** `fields` de un documento REST → objeto plano. */
export function decodificarCampos(
  campos: Record<string, ValorFirestore> | undefined,
): Record<string, unknown> {
  const resultado: Record<string, unknown> = {};
  for (const [campo, valor] of Object.entries(campos ?? {})) {
    resultado[campo] = decodificarValor(valor);
  }
  return resultado;
}

// ---------------------------------------------------------------------------
// Actualizaciones parciales y consultas (semana 4: citas)
// ---------------------------------------------------------------------------

/**
 * Escritura que cambia SOLO [campos] de un documento existente. Con
 * `{updateTime}` falla si alguien lo modificó después de leerlo (transacción
 * optimista). Un campo con valor `undefined` se borra del documento.
 */
export function actualizarCampos(
  proyecto: string,
  ruta: string,
  campos: { [campo: string]: ValorCampo | undefined },
  precondicion: Precondicion = { exists: true },
): EscrituraFirestore {
  const horas = Object.entries(campos)
    .filter(([, valor]) => valor === HORA_SERVIDOR)
    .map(([campo]) => ({ fieldPath: campo, setToServerValue: "REQUEST_TIME" as const }));
  const presentes: { [campo: string]: ValorCampo } = {};
  for (const [campo, valor] of Object.entries(campos)) {
    if (valor !== undefined) presentes[campo] = valor;
  }
  return {
    update: { name: rutaDocumento(proyecto, ruta), fields: camposFirestore(presentes) },
    updateMask: {
      fieldPaths: Object.entries(campos)
        .filter(([, valor]) => valor !== HORA_SERVIDOR)
        .map(([campo]) => campo),
    },
    ...(horas.length > 0 ? { updateTransforms: horas } : {}),
    currentDocument: precondicion,
  };
}

export type OperadorFiltro =
  | "EQUAL"
  | "LESS_THAN"
  | "LESS_THAN_OR_EQUAL"
  | "GREATER_THAN"
  | "GREATER_THAN_OR_EQUAL";

/** Filtro `campo operador valor` de una consulta. */
export interface Filtro {
  campo: string;
  op: OperadorFiltro;
  valor: ValorCampo;
}

/** Consulta simple sobre una colección (filtros AND). */
export interface Consulta {
  /** Para una subcolección, el documento padre (p. ej. `users/ana`). */
  padre?: string;
  coleccion: string;
  filtros: Filtro[];
  ordenarPor?: string;
  limite?: number;
}

/** Consulta → `structuredQuery` de la API REST (`documents:runQuery`). */
export function consultaEstructurada(consulta: Consulta): Record<string, unknown> {
  const filtros = consulta.filtros.map((f) => ({
    fieldFilter: { field: { fieldPath: f.campo }, op: f.op, value: valorFirestore(f.valor) },
  }));
  return {
    from: [{ collectionId: consulta.coleccion }],
    ...(filtros.length === 1 ? { where: filtros[0] } : {}),
    ...(filtros.length > 1 ? { where: { compositeFilter: { op: "AND", filters: filtros } } } : {}),
    ...(consulta.ordenarPor
      ? { orderBy: [{ field: { fieldPath: consulta.ordenarPor }, direction: "ASCENDING" }] }
      : {}),
    ...(consulta.limite ? { limit: consulta.limite } : {}),
  };
}
