"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sincronizarSuspension = void 0;
exports.accionSuspension = accionSuspension;
const auth_1 = require("firebase-admin/auth");
const v2_1 = require("firebase-functions/v2");
const firestore_1 = require("firebase-functions/v2/firestore");
const config_1 = require("../config");
/** Decide qué hacer en Firebase Auth cuando cambia users/{uid}.estado. */
function accionSuspension(antes, despues) {
    if (antes === despues)
        return null;
    if (despues === "suspendido")
        return "deshabilitar";
    if (antes === "suspendido" && despues === "activo")
        return "habilitar";
    return null;
}
/**
 * RF-02 (Adaptación a Firebase): al suspender una cuenta se deshabilita en
 * Firebase Auth y se revocan sus tokens, para bloquearla del todo (el siguiente
 * login falla con `user-disabled`). Al reactivarla se vuelve a habilitar.
 */
exports.sincronizarSuspension = (0, firestore_1.onDocumentUpdated)({ document: "users/{uid}", region: config_1.REGION }, async (event) => {
    const uid = event.params.uid;
    const accion = accionSuspension(event.data?.before.get("estado"), event.data?.after.get("estado"));
    if (accion === null)
        return;
    const auth = (0, auth_1.getAuth)();
    if (accion === "deshabilitar") {
        await auth.updateUser(uid, { disabled: true });
        await auth.revokeRefreshTokens(uid);
    }
    else {
        await auth.updateUser(uid, { disabled: false });
    }
    v2_1.logger.info(`Cuenta ${uid}: ${accion}`);
});
//# sourceMappingURL=sincronizarSuspension.js.map