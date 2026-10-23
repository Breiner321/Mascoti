/**
 * Cliente mínimo de la API REST de Firestore, sin dependencias: funciona en
 * Deno (Edge Functions, contra Google) y en Node (pruebas, contra el
 * emulador). Ver functions/test/citas.emulador.test.ts.
 */
import {
  type Consulta,
  consultaEstructurada,
  decodificarCampos,
  type EscrituraFirestore,
  type TransformacionFirestore,
  type ValorFirestore,
} from "./firestore.ts";

/** Documento leído, con su `updateTime` para usarlo como precondición. */
export interface DocumentoLeido {
  id: string;
  ruta: string;
  datos: Record<string, unknown>;
  updateTime: string;
}

export type Escritura = EscrituraFirestore | TransformacionFirestore;

/**
 * Lo que necesitan las Edge Functions de la base de datos. Las pruebas
 * pueden dar otra implementación.
 */
export interface BaseDatos {
  readonly proyecto: string;
  leer(ruta: string): Promise<DocumentoLeido | null>;
  consultar(consulta: Consulta): Promise<DocumentoLeido[]>;
  /**
   * Commit atómico. "conflicto" si falla una precondición (el documento
   * cambió, ya existe o ya no existe): quien llama vuelve a leer y decide.
   */
  commit(escrituras: Escritura[]): Promise<"ok" | "conflicto">;
}

interface DocumentoRest {
  name: string;
  fields?: Record<string, ValorFirestore>;
  updateTime: string;
}

export class ClienteFirestore implements BaseDatos {
  /**
   * @param base `https://firestore.googleapis.com/v1` o, con el emulador,
   *   `http://127.0.0.1:8080/v1`.
   * @param token token OAuth de la cuenta de servicio (con el emulador,
   *   `"owner"` salta las reglas).
   */
  constructor(
    readonly proyecto: string,
    private readonly base: string,
    private readonly token: () => Promise<string>,
  ) {}

  private get documentos(): string {
    return `${this.base}/projects/${this.proyecto}/databases/(default)/documents`;
  }

  private async encabezados(): Promise<Record<string, string>> {
    return {
      "Authorization": `Bearer ${await this.token()}`,
      "Content-Type": "application/json",
    };
  }

  private static leido(doc: DocumentoRest): DocumentoLeido {
    const ruta = doc.name.split("/documents/")[1] ?? "";
    return {
      id: ruta.split("/").pop() ?? "",
      ruta,
      datos: decodificarCampos(doc.fields),
      updateTime: doc.updateTime,
    };
  }

  async leer(ruta: string): Promise<DocumentoLeido | null> {
    const respuesta = await fetch(`${this.documentos}/${ruta}`, {
      headers: await this.encabezados(),
    });
    if (respuesta.status === 404) return null;
    if (!respuesta.ok) throw new Error(`Firestore ${respuesta.status}: ${await respuesta.text()}`);
    return ClienteFirestore.leido(await respuesta.json() as DocumentoRest);
  }

  async consultar(consulta: Consulta): Promise<DocumentoLeido[]> {
    const padre = consulta.padre ? `/${consulta.padre}` : "";
    const respuesta = await fetch(`${this.documentos}${padre}:runQuery`, {
      method: "POST",
      headers: await this.encabezados(),
      body: JSON.stringify({ structuredQuery: consultaEstructurada(consulta) }),
    });
    if (!respuesta.ok) throw new Error(`Firestore ${respuesta.status}: ${await respuesta.text()}`);
    const filas = await respuesta.json() as { document?: DocumentoRest }[];
    return filas.filter((f) => f.document).map((f) => ClienteFirestore.leido(f.document!));
  }

  async commit(escrituras: Escritura[]): Promise<"ok" | "conflicto"> {
    const respuesta = await fetch(`${this.documentos}:commit`, {
      method: "POST",
      headers: await this.encabezados(),
      body: JSON.stringify({ writes: escrituras }),
    });
    if (respuesta.ok) return "ok";
    const texto = await respuesta.text();
    if (esConflicto(respuesta.status, texto)) return "conflicto";
    throw new Error(`Firestore ${respuesta.status}: ${texto}`);
  }
}

/** Respuesta de error de un commit que se debe a una precondición. */
export function esConflicto(estado: number, texto: string): boolean {
  return estado === 409 ||
    /FAILED_PRECONDITION|ALREADY_EXISTS|ABORTED|NOT_FOUND/.test(texto);
}
