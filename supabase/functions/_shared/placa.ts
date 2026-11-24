import type { BaseDatos } from "./cliente_firestore.ts";
import { ErrorFuncion } from "./errores.ts";
import { nombreVisible } from "./nombres.ts";
import type { ResultadoIntento } from "./vinculacion.ts";

/**
 * Placa QR (RF-17): lógica de la Edge Function `placa-publica`, que usa la
 * página pública `/q/{qrId}` de Firebase Hosting. Sin sesión: cualquiera que
 * escanee la placa. Devuelve SOLO lo que el dueño eligió mostrar en
 * `qrTags/{qrId}.mostrar`; el teléfono va enmascarado y se revela completo
 * solo con `revelar: true`, con límite de intentos por IP.
 *
 * El nombre y el teléfono del dueño se leen de `users/{ownerUid}` en cada
 * consulta (no se copian en la placa): si el dueño los cambia, la placa
 * muestra los nuevos.
 */

export const MENSAJE_INACTIVA = "Esta placa no está activa";
/** "Ver teléfono": máximo por IP en la ventana. */
export const MAX_REVELAR = 5;
export const VENTANA_REVELAR_MINUTOS = 60;
/** Vida del enlace firmado de la foto. */
export const SEGUNDOS_FOTO = 300;
export const BUCKET_FOTOS = "mascotas";

/** Id de una placa: 10 a 40 letras o dígitos (igual que firestore.rules). */
export const FORMATO_QR_ID = /^[A-Za-z0-9]{10,40}$/;

/** Igual a PetSpecies.label en lib/core/domain/pet.dart. */
const ESPECIES: Record<string, string> = {
  perro: "Perro",
  gato: "Gato",
  ave: "Ave",
  roedor: "Roedor",
  reptil: "Reptil",
  granja: "Animal de granja",
  exotico: "Exótico",
};

export interface FichaPublica {
  nombre: string;
  especie: string;
  /** Enlace firmado de 5 min, o null si no hay foto. */
  fotoUrl: string | null;
  alergias?: string[];
  mensaje?: string;
  nombreDueno?: string;
  /** "300 *** **67". */
  telefonoEnmascarado?: string;
  /** Solo con `revelar: true`. */
  telefono?: string;
}

export interface DependenciasPlaca {
  db: BaseDatos;
  firmarFoto(path: string): Promise<string>;
  /** Cuenta un "Ver teléfono" de [ipHash]. */
  registrarRevelacion(ipHash: string): Promise<ResultadoIntento>;
  log?(mensaje: string): void;
}

const texto = (v: unknown): string => (typeof v === "string" ? v.trim() : "");

/** "3001234567" → "300 *** **67". Otros largos: primeros 3 y últimos 2. */
export function enmascararTelefono(telefono: string): string {
  const d = telefono.replace(/\D/g, "");
  if (d.length < 6) return "*".repeat(Math.max(d.length, 3));
  if (d.length === 10) return `${d.slice(0, 3)} *** **${d.slice(8)}`;
  return `${d.slice(0, 3)} ${"*".repeat(d.length - 5)}${d.slice(-2)}`;
}

/** "3001234567" → "300 123 4567" (para mostrar el número revelado). */
export function formatearTelefono(telefono: string): string {
  const d = telefono.replace(/\D/g, "");
  return d.length === 10 ? `${d.slice(0, 3)} ${d.slice(3, 6)} ${d.slice(6)}` : d;
}

/** SHA-256 en hex de la IP: el límite no guarda la IP. */
export async function hashIp(ip: string): Promise<string> {
  const bytes = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`placa:${ip}`)),
  );
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Primera IP de `x-forwarded-for` (la del cliente), o "desconocida". */
export function ipDelCliente(encabezado: string | null): string {
  const ip = encabezado?.split(",")[0]?.trim();
  return ip && ip.length <= 64 ? ip : "desconocida";
}

function minutos(segundos: number): string {
  const m = Math.max(1, Math.ceil(segundos / 60));
  return `${m} ${m === 1 ? "minuto" : "minutos"}`;
}

/**
 * Ficha pública de la placa [cuerpo.qrId]. Placa inexistente, desactivada,
 * de una mascota que ya no existe o de una cuenta suspendida → "Esta placa
 * no está activa" (no se distingue el motivo).
 */
export async function consultarPlaca(
  deps: DependenciasPlaca,
  cuerpo: unknown,
  ip: string,
): Promise<FichaPublica> {
  const datos = (typeof cuerpo === "object" && cuerpo !== null ? cuerpo : {}) as Record<string, unknown>;
  const qrId = datos.qrId;
  const inactiva = new ErrorFuncion("not-found", MENSAJE_INACTIVA);
  if (typeof qrId !== "string" || !FORMATO_QR_ID.test(qrId)) throw inactiva;

  const placa = (await deps.db.leer(`qrTags/${qrId}`))?.datos;
  if (!placa || placa.activo !== true) throw inactiva;
  const petId = texto(placa.petId);
  const ownerUid = texto(placa.ownerUid);
  if (!petId || !ownerUid || petId.includes("/") || ownerUid.includes("/")) throw inactiva;

  const [mascota, dueno] = await Promise.all([
    deps.db.leer(`pets/${petId}`),
    deps.db.leer(`users/${ownerUid}`),
  ]);
  if (!mascota || mascota.datos.ownerUid !== ownerUid) throw inactiva;
  if (!dueno || dueno.datos.estado !== "activo") throw inactiva;

  const mostrar = (typeof placa.mostrar === "object" && placa.mostrar !== null
    ? placa.mostrar
    : {}) as Record<string, unknown>;
  const m = mascota.datos;

  let fotoUrl: string | null = null;
  const fotoPath = texto(m.fotoPath);
  if (fotoPath) {
    try {
      fotoUrl = await deps.firmarFoto(fotoPath);
    } catch (e) {
      deps.log?.(`No se pudo firmar la foto de ${petId}: ${e}`);
    }
  }

  const ficha: FichaPublica = {
    nombre: texto(m.nombre) || "Mascota",
    especie: ESPECIES[texto(m.especie)] ?? "Mascota",
    fotoUrl,
  };
  if (mostrar.alergias === true) {
    ficha.alergias = Array.isArray(m.alergias)
      ? m.alergias.filter((a): a is string => typeof a === "string" && a.trim().length > 0)
      : [];
  }
  const mensaje = texto(mostrar.mensaje);
  if (mensaje) ficha.mensaje = mensaje;
  if (mostrar.nombreDueno === true) ficha.nombreDueno = nombreVisible(dueno.datos);

  const telefono = texto(dueno.datos.telefono);
  const compartePhone = mostrar.telefono === true && telefono.length > 0;
  if (compartePhone) ficha.telefonoEnmascarado = enmascararTelefono(telefono);

  if (datos.revelar === true) {
    if (!compartePhone) {
      throw new ErrorFuncion("failed-precondition", "El dueño no comparte su teléfono en esta placa.");
    }
    const intento = await deps.registrarRevelacion(await hashIp(ip));
    if (!intento.permitido) {
      throw new ErrorFuncion(
        "resource-exhausted",
        `Ya viste varios teléfonos. Intenta de nuevo en ${minutos(intento.reintentarEnSegundos)}.`,
      );
    }
    ficha.telefono = telefono.replace(/\D/g, "");
  }
  return ficha;
}
