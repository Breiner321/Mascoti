import { getAuth } from "firebase-admin/auth";
import { logger } from "firebase-functions/v2";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";

import { REGION } from "../config";

export type AccionSuspension = "deshabilitar" | "habilitar" | null;

/** Decide qué hacer en Firebase Auth cuando cambia users/{uid}.estado. */
export function accionSuspension(antes: unknown, despues: unknown): AccionSuspension {
  if (antes === despues) return null;
  if (despues === "suspendido") return "deshabilitar";
  if (antes === "suspendido" && despues === "activo") return "habilitar";
  return null;
}

/**
 * RF-02 (Adaptación a Firebase): al suspender una cuenta se deshabilita en
 * Firebase Auth y se revocan sus tokens, para bloquearla del todo (el siguiente
 * login falla con `user-disabled`). Al reactivarla se vuelve a habilitar.
 */
export const sincronizarSuspension = onDocumentUpdated(
  { document: "users/{uid}", region: REGION },
  async (event) => {
    const uid = event.params.uid;
    const accion = accionSuspension(
      event.data?.before.get("estado"),
      event.data?.after.get("estado"),
    );
    if (accion === null) return;

    const auth = getAuth();
    if (accion === "deshabilitar") {
      await auth.updateUser(uid, { disabled: true });
      await auth.revokeRefreshTokens(uid);
    } else {
      await auth.updateUser(uid, { disabled: false });
    }
    logger.info(`Cuenta ${uid}: ${accion}`);
  },
);
