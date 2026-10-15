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
  | typeof HORA_SERVIDOR
  | ValorCampo[]
  | { [campo: string]: ValorCampo };

export type ValorFirestore = Record<string, unknown>;

export interface EscrituraFirestore {
  update: { name: string; fields: Record<string, ValorFirestore> };
  updateTransforms?: { fieldPath: string; setToServerValue: "REQUEST_TIME" }[];
  currentDocument?: { exists: boolean };
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

function camposFirestore(campos: { [campo: string]: ValorCampo }) {
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
