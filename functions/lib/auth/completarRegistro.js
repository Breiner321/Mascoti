"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.completarRegistro = void 0;
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const geo_1 = require("../clinicas/geo");
const config_1 = require("../config");
const validacion_1 = require("./validacion");
/**
 * RF-01: crea de forma atómica users/{uid} y, si el rol es Clínica,
 * clinics/{clinicId} en estado 'incompleto'.
 * La app la llama después de iniciar sesión con Google (Firebase Auth).
 */
exports.completarRegistro = (0, https_1.onCall)({ region: config_1.REGION }, async (request) => {
    const auth = request.auth;
    if (!auth) {
        throw new https_1.HttpsError("unauthenticated", "Debes iniciar sesión con Google.");
    }
    const datos = (0, validacion_1.validarRegistro)(request.data);
    const db = (0, firestore_1.getFirestore)();
    const userRef = db.collection("users").doc(auth.uid);
    const token = auth.token;
    const clinicId = await db.runTransaction(async (tx) => {
        const existente = await tx.get(userRef);
        if (existente.exists) {
            throw new https_1.HttpsError("already-exists", "Esta cuenta ya está registrada. Iniciando sesión...");
        }
        let nuevoClinicId = null;
        if (datos.role === "clinica" && datos.clinica) {
            const clinicRef = db.collection("clinics").doc();
            nuevoClinicId = clinicRef.id;
            tx.set(clinicRef, {
                ownerUid: auth.uid,
                nombre: datos.clinica.nombre,
                direccion: datos.clinica.direccion,
                lat: datos.clinica.lat,
                lng: datos.clinica.lng,
                geo: (0, geo_1.geoClinica)(datos.clinica.lat, datos.clinica.lng),
                telefono: datos.clinica.telefono,
                tiposAnimales: [],
                atencionEmergencias: false,
                estado: "incompleto",
                createdAt: firestore_1.FieldValue.serverTimestamp(),
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
            createdAt: firestore_1.FieldValue.serverTimestamp(),
            lastLoginAt: firestore_1.FieldValue.serverTimestamp(),
        });
        return nuevoClinicId;
    });
    return { role: datos.role, clinicId };
});
//# sourceMappingURL=completarRegistro.js.map