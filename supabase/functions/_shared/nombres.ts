/**
 * Nombre visible de una persona (Cambio 1). Igual a AppUser.nombreVisible en
 * lib/core/auth/domain/app_user.dart: `nombre` que escribió el dueño → nombre
 * de la cuenta de Google → "Usuario". Nunca el correo.
 * Para una clínica se usa siempre `clinics/{id}.nombre`.
 */
export const NOMBRE_POR_DEFECTO = "Usuario";

export function nombreVisible(perfil: Record<string, unknown> | null | undefined): string {
  for (const campo of ["nombre", "displayName"]) {
    const valor = perfil?.[campo];
    if (typeof valor === "string" && valor.trim().length > 0) return valor.trim();
  }
  return NOMBRE_POR_DEFECTO;
}
