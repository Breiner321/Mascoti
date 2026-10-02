import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { geoClinica } from "../clinicas/geo";
import { REGION } from "../config";
import { validarRegistro } from "./validacion";

/**
 * RF-01: crea de forma atómica users/{uid} y, si el rol es Clínica,
 * clinics/{clinicId} en estado 'incompleto'.
 * La app la llama después de iniciar sesión con Google (Firebase Auth).
 */
export const completarRegistro = onCall({ region: REGION }, async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión con Google.");
  }

  const datos = validarRegistro(request.data);
  const db = getFirestore();
  const userRef = db.collection("users").doc(auth.uid);
  const token = auth.token;

  const clinicId = await db.runTransaction(async (tx) => {
    const existente = await tx.get(userRef);
    if (existente.exists) {
      throw new HttpsError(
        "already-exists",
        "Esta cuenta ya está registrada. Iniciando sesión...",
      );
    }

    let nuevoClinicId: string | null = null;
    if (datos.role === "clinica" && datos.clinica) {
      const clinicRef = db.collection("clinics").doc();
      nuevoClinicId = clinicRef.id;
      tx.set(clinicRef, {
        ownerUid: auth.uid,
        nombre: datos.clinica.nombre,
        direccion: datos.clinica.direccion,
        lat: datos.clinica.lat,
        lng: datos.clinica.lng,
        geo: geoClinica(datos.clinica.lat, datos.clinica.lng),
        telefono: datos.clinica.telefono,
        tiposAnimales: [],
        atencionEmergencias: false,
        estado: "incompleto",
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    tx.set(userRef, {
      uid: auth.uid,
      email: token.email ?? "",
      displayName: token.name ?? "",
      photoURL: token.picture ?? null,
      role: datos.role,
      estado: "activo",
      clinicId: nuevoClinicId,
      createdAt: FieldValue.serverTimestamp(),
      lastLoginAt: FieldValue.serverTimestamp(),
    });

    return nuevoClinicId;
  });

  return { role: datos.role, clinicId };
});
