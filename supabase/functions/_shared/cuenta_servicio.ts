/** Cuenta de servicio de Firebase (archivo JSON de "Generar nueva clave privada"). */
export interface CuentaServicio {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
}

/**
 * Lee el secreto FIREBASE_SERVICE_ACCOUNT. Acepta el JSON tal cual o
 * codificado en Base64: PowerShell rompe el JSON al pasarlo como argumento
 * (quita las comillas y lo parte en los espacios), así que en Windows se
 * carga en Base64 (ver docs/configuracion-inicial.md, sección C2).
 */
export function leerCuentaServicio(secreto: string | undefined): CuentaServicio {
  const texto = secreto?.trim();
  if (!texto) throw new Error("Falta el secreto FIREBASE_SERVICE_ACCOUNT");

  let json = texto;
  if (!texto.startsWith("{")) {
    try {
      const bytes = Uint8Array.from(atob(texto), (c) => c.charCodeAt(0));
      json = new TextDecoder().decode(bytes);
    } catch {
      throw new Error("FIREBASE_SERVICE_ACCOUNT no es JSON ni Base64 válido");
    }
  }

  let cuenta: CuentaServicio;
  try {
    cuenta = JSON.parse(json) as CuentaServicio;
  } catch {
    throw new Error("FIREBASE_SERVICE_ACCOUNT no es JSON válido");
  }
  if (!cuenta.project_id || !cuenta.client_email || !cuenta.private_key) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT no es una cuenta de servicio válida");
  }
  return cuenta;
}
