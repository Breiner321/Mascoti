/** Códigos de error que entiende la app (ver RegistrationFailure en Dart). */
export type CodigoError =
  | "unauthenticated"
  | "invalid-argument"
  | "already-exists"
  | "internal";

const ESTADO_HTTP: Record<CodigoError, number> = {
  "unauthenticated": 401,
  "invalid-argument": 400,
  "already-exists": 409,
  "internal": 500,
};

/** Error con el mensaje literal del RF que la app puede mostrar. */
export class ErrorRegistro extends Error {
  constructor(readonly codigo: CodigoError, mensaje: string) {
    super(mensaje);
    this.name = "ErrorRegistro";
  }

  get estadoHttp(): number {
    return ESTADO_HTTP[this.codigo];
  }
}
