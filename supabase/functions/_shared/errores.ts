/**
 * Códigos de error que entiende la app (RegistrationFailure, PetLinkFailure
 * en Dart). El cuerpo de la respuesta es `{error: {code, message}}`.
 */
export type CodigoError =
  | "unauthenticated"
  | "permission-denied"
  | "invalid-argument"
  | "not-found"
  | "already-exists"
  | "failed-precondition"
  | "resource-exhausted"
  | "internal";

const ESTADO_HTTP: Record<CodigoError, number> = {
  "unauthenticated": 401,
  "permission-denied": 403,
  "invalid-argument": 400,
  "not-found": 404,
  "already-exists": 409,
  "failed-precondition": 412,
  "resource-exhausted": 429,
  "internal": 500,
};

/** Error de una Edge Function con el mensaje que la app puede mostrar tal cual. */
export class ErrorFuncion extends Error {
  constructor(readonly codigo: CodigoError, mensaje: string) {
    super(mensaje);
    this.name = "ErrorFuncion";
  }

  get estadoHttp(): number {
    return ESTADO_HTTP[this.codigo];
  }
}
