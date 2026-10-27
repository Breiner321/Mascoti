import { ErrorFuncion } from "./errores.ts";
import { crearDocumento, type EscrituraFirestore, HORA_SERVIDOR, PuntoGeo } from "./firestore.ts";
import { geohash } from "./geohash.ts";
import { validarRegistro, type Rol } from "./validacion.ts";

/** Datos del usuario que vienen en su token de Firebase. */
export interface UsuarioFirebase {
  uid: string;
  email?: string;
  name?: string;
  picture?: string;
}

/**
 * Dependencias externas, inyectadas para poder probar la lógica sin red
 * (ver functions/test/registro.test.ts). index.ts pasa las reales.
 */
export interface DependenciasRegistro {
  proyecto: string;
  /** Verifica el ID token de Firebase. Lanza si no es válido. */
  verificarToken(token: string): Promise<UsuarioFirebase>;
  /** Aplica todas las escrituras en un solo commit atómico. */
  commit(escrituras: EscrituraFirestore[]): Promise<"ok" | "ya-existe">;
  /** Marca el usuario para que Supabase acepte su token (Third-party Auth). */
  habilitarEnSupabase(uid: string): Promise<void>;
  nuevoId(): string;
  log?(mensaje: string): void;
}

export interface ResultadoRegistro {
  role: Rol;
  clinicId: string | null;
}

/**
 * RF-01: crea de forma atómica users/{uid} y, si el rol es Clínica,
 * clinics/{clinicId} en estado 'incompleto'. Reemplaza a la Cloud Function
 * completarRegistro con el mismo contrato y los mismos mensajes.
 */
export async function completarRegistro(
  deps: DependenciasRegistro,
  autorizacion: string | null,
  cuerpo: unknown,
): Promise<ResultadoRegistro> {
  const token = autorizacion?.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!token) {
    throw new ErrorFuncion("unauthenticated", "Debes iniciar sesión con Google.");
  }

  let usuario: UsuarioFirebase;
  try {
    usuario = await deps.verificarToken(token);
  } catch {
    throw new ErrorFuncion("unauthenticated", "Debes iniciar sesión con Google.");
  }

  const datos = validarRegistro(cuerpo);
  const escrituras: EscrituraFirestore[] = [];

  let clinicId: string | null = null;
  if (datos.role === "clinica" && datos.clinica) {
    const c = datos.clinica;
    clinicId = deps.nuevoId();
    escrituras.push(
      crearDocumento(deps.proyecto, `clinics/${clinicId}`, {
        ownerUid: usuario.uid,
        nombre: c.nombre,
        direccion: c.direccion,
        lat: c.lat,
        lng: c.lng,
        geo: { geohash: geohash(c.lat, c.lng), geopoint: new PuntoGeo(c.lat, c.lng) },
        telefono: c.telefono,
        tiposAnimales: [],
        atencionEmergencias: false,
        estado: "incompleto",
        createdAt: HORA_SERVIDOR,
      }),
    );
  }

  // users/{uid} con `exists: false`: si ya estaba registrado, el commit
  // completo falla y no queda ninguna clínica huérfana.
  escrituras.unshift(
    crearDocumento(deps.proyecto, `users/${usuario.uid}`, {
      uid: usuario.uid,
      email: usuario.email ?? "",
      displayName: usuario.name ?? "",
      photoURL: usuario.picture ?? null,
      role: datos.role,
      estado: "activo",
      clinicId,
      onboardingVisto: false,
      // Cambio 1: nombre real y teléfono del dueño (la clínica usa el de clinics).
      ...(datos.dueno ? { nombre: datos.dueno.nombre, telefono: datos.dueno.telefono } : {}),
      createdAt: HORA_SERVIDOR,
      lastLoginAt: HORA_SERVIDOR,
    }),
  );

  const resultado = await deps.commit(escrituras);
  if (resultado === "ya-existe") {
    throw new ErrorFuncion("already-exists", "Esta cuenta ya está registrada. Iniciando sesión...");
  }

  try {
    await deps.habilitarEnSupabase(usuario.uid);
  } catch (e) {
    // El registro ya quedó hecho; sin esto solo falla Storage hasta reintentar.
    deps.log?.(`No se pudo habilitar ${usuario.uid} en Supabase: ${e}`);
  }

  return { role: datos.role, clinicId };
}
