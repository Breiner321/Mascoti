// RF-02: suspender o reactivar una cuenta (solo administradores).
//
// Reemplaza a la Cloud Function sincronizarSuspension, que no se puede
// desplegar en el plan gratuito de Firebase. Hace los dos pasos juntos:
//   1. users/{uid}.estado = 'suspendido' | 'activo'  (las reglas bloquean al suspendido)
//   2. deshabilita/habilita la cuenta en Firebase Auth y revoca sus sesiones
//
// Uso (desde functions/), con la cuenta de servicio de Firebase FUERA del repo:
//   PowerShell:  $env:GOOGLE_APPLICATION_CREDENTIALS="C:\ruta\cuenta-servicio.json"
//   npm run suspender -- <uid>              → suspende
//   npm run suspender -- <uid> --reactivar  → reactiva
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const [uid, opcion] = process.argv.slice(2);
if (!uid || (opcion && opcion !== "--reactivar")) {
  console.error("Uso: npm run suspender -- <uid> [--reactivar]");
  process.exit(1);
}
if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error("Define GOOGLE_APPLICATION_CREDENTIALS con la ruta de la cuenta de servicio.");
  process.exit(1);
}

const reactivar = opcion === "--reactivar";
initializeApp();
const db = getFirestore();
const auth = getAuth();

const ref = db.collection("users").doc(uid);
const doc = await ref.get();
if (!doc.exists) {
  console.error(`No existe users/${uid}.`);
  process.exit(1);
}

await ref.update({
  estado: reactivar ? "activo" : "suspendido",
  estadoActualizadoEn: FieldValue.serverTimestamp(),
});
await auth.updateUser(uid, { disabled: !reactivar });
if (!reactivar) await auth.revokeRefreshTokens(uid);

console.log(`${doc.get("email") ?? uid}: cuenta ${reactivar ? "reactivada" : "suspendida"}.`);
