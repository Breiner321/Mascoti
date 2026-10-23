// Solo para Deno (Edge Functions). Habla con Google usando la cuenta de
// servicio de Firebase guardada en el secreto FIREBASE_SERVICE_ACCOUNT.
import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT } from "npm:jose@5.9.6";

import { ClienteFirestore } from "./cliente_firestore.ts";
import type { CuentaServicio } from "./cuenta_servicio.ts";
import {
  type DependenciasNotificaciones,
  esTokenInvalido,
  type MensajePush,
  mensajeFcm,
  type ResultadoPush,
} from "./notificaciones.ts";
import {
  decodificarCampos,
  nuevoIdFirestore,
  type EscrituraFirestore,
  type TransformacionFirestore,
  type ValorFirestore,
} from "./firestore.ts";
import type { UsuarioFirebase } from "./registro.ts";

const JWKS_FIREBASE = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"),
);

/** Verifica un ID token de Firebase Auth del proyecto (firma, emisor, audiencia, vigencia). */
export async function verificarTokenFirebase(
  token: string,
  proyecto: string,
): Promise<UsuarioFirebase> {
  const { payload } = await jwtVerify(token, JWKS_FIREBASE, {
    issuer: `https://securetoken.google.com/${proyecto}`,
    audience: proyecto,
    algorithms: ["RS256"],
  });
  if (typeof payload.sub !== "string" || payload.sub.length === 0) {
    throw new Error("Token sin uid");
  }
  return {
    uid: payload.sub,
    email: payload.email as string | undefined,
    name: payload.name as string | undefined,
    picture: payload.picture as string | undefined,
  };
}

let tokenEnCache: { valor: string; vence: number } | null = null;

/** Token OAuth de la cuenta de servicio (se reutiliza mientras esté vigente). */
async function tokenDeAcceso(cuenta: CuentaServicio): Promise<string> {
  const ahora = Math.floor(Date.now() / 1000);
  if (tokenEnCache && tokenEnCache.vence - 60 > ahora) return tokenEnCache.valor;

  const tokenUri = cuenta.token_uri ?? "https://oauth2.googleapis.com/token";
  const llave = await importPKCS8(cuenta.private_key, "RS256");
  const asercion = await new SignJWT({ scope: "https://www.googleapis.com/auth/cloud-platform" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(cuenta.client_email)
    .setAudience(tokenUri)
    .setIssuedAt(ahora)
    .setExpirationTime(ahora + 3600)
    .sign(llave);

  const respuesta = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: asercion,
    }),
  });
  if (!respuesta.ok) throw new Error(`OAuth ${respuesta.status}: ${await respuesta.text()}`);
  const { access_token, expires_in } = await respuesta.json();
  tokenEnCache = { valor: access_token, vence: ahora + Number(expires_in ?? 3600) };
  return access_token;
}

/** Cliente REST de Firestore autenticado con la cuenta de servicio. */
export function clienteFirestore(cuenta: CuentaServicio): ClienteFirestore {
  return new ClienteFirestore(
    cuenta.project_id,
    "https://firestore.googleapis.com/v1",
    () => tokenDeAcceso(cuenta),
  );
}

/** Dependencias reales de las notificaciones (RF-13). */
export function dependenciasNotificaciones(cuenta: CuentaServicio): DependenciasNotificaciones {
  return {
    db: clienteFirestore(cuenta),
    enviarPush: (token, mensaje) => enviarPushFcm(cuenta, token, mensaje),
    ahora: () => new Date(),
    nuevoId: () => nuevoIdFirestore((n) => crypto.getRandomValues(new Uint8Array(n))),
    log: console.warn,
  };
}

/** Push a un dispositivo con FCM HTTP v1 (gratis en el plan Spark). */
export async function enviarPushFcm(
  cuenta: CuentaServicio,
  token: string,
  mensaje: MensajePush,
): Promise<ResultadoPush> {
  const respuesta = await fetch(
    `https://fcm.googleapis.com/v1/projects/${cuenta.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${await tokenDeAcceso(cuenta)}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(mensajeFcm(token, mensaje)),
    },
  );
  if (respuesta.ok) return "ok";
  const texto = await respuesta.text();
  if (esTokenInvalido(respuesta.status, texto)) return "token-invalido";
  throw new Error(`FCM ${respuesta.status}: ${texto}`);
}

/** Commit atómico de Firestore. "ya-existe" si falla una precondición exists:false. */
export async function commitFirestore(
  cuenta: CuentaServicio,
  escrituras: (EscrituraFirestore | TransformacionFirestore)[],
): Promise<"ok" | "ya-existe"> {
  const url =
    `https://firestore.googleapis.com/v1/projects/${cuenta.project_id}/databases/(default)/documents:commit`;
  const respuesta = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${await tokenDeAcceso(cuenta)}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ writes: escrituras }),
  });
  if (respuesta.ok) return "ok";

  const texto = await respuesta.text();
  if (respuesta.status === 409 || /ALREADY_EXISTS|FAILED_PRECONDITION/.test(texto)) {
    return "ya-existe";
  }
  throw new Error(`Firestore ${respuesta.status}: ${texto}`);
}

/**
 * Supabase solo acepta tokens de Firebase que traigan `role: "authenticated"`
 * (Third-party Auth). Es un dato técnico de Supabase: el rol de la app
 * (dueño/clínica) se sigue leyendo de users/{uid}.role.
 */
export async function habilitarEnSupabase(cuenta: CuentaServicio, uid: string): Promise<void> {
  const url =
    `https://identitytoolkit.googleapis.com/v1/projects/${cuenta.project_id}/accounts:update`;
  const respuesta = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${await tokenDeAcceso(cuenta)}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      localId: uid,
      customAttributes: JSON.stringify({ role: "authenticated" }),
    }),
  });
  if (!respuesta.ok) throw new Error(`Identity Toolkit ${respuesta.status}: ${await respuesta.text()}`);
}

/** Documento de Firestore como objeto plano, o null si no existe. */
export async function leerDocumentoFirestore(
  cuenta: CuentaServicio,
  ruta: string,
): Promise<Record<string, unknown> | null> {
  const url =
    `https://firestore.googleapis.com/v1/projects/${cuenta.project_id}/databases/(default)/documents/${ruta}`;
  const respuesta = await fetch(url, {
    headers: { "Authorization": `Bearer ${await tokenDeAcceso(cuenta)}` },
  });
  if (respuesta.status === 404) return null;
  if (!respuesta.ok) throw new Error(`Firestore ${respuesta.status}: ${await respuesta.text()}`);
  const documento = await respuesta.json() as { fields?: Record<string, ValorFirestore> };
  return decodificarCampos(documento.fields);
}
