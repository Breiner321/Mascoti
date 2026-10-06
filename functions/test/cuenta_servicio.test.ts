import { describe, expect, it } from "vitest";

import { leerCuentaServicio } from "../../supabase/functions/_shared/cuenta_servicio.ts";

// Cuenta FALSA, solo para la prueba (la llave no es real).
const cuenta = {
  type: "service_account",
  project_id: "mascoti-b27cf",
  client_email: "firebase-adminsdk@mascoti-b27cf.iam.gserviceaccount.com",
  private_key: "-----BEGIN PRIVATE KEY-----\nFALSA\n-----END PRIVATE KEY-----\n",
};

describe("leerCuentaServicio", () => {
  it("acepta el JSON tal cual", () => {
    expect(leerCuentaServicio(JSON.stringify(cuenta)).project_id).toBe("mascoti-b27cf");
  });

  it("acepta el JSON en Base64 (como se carga desde PowerShell)", () => {
    const base64 = Buffer.from(JSON.stringify(cuenta, null, 2), "utf8").toString("base64");
    const leida = leerCuentaServicio(base64);
    expect(leida.client_email).toBe(cuenta.client_email);
    expect(leida.private_key).toBe(cuenta.private_key);
  });

  it("rechaza un secreto vacío, roto o incompleto con un mensaje claro", () => {
    expect(() => leerCuentaServicio(undefined)).toThrow("Falta el secreto");
    expect(() => leerCuentaServicio("")).toThrow("Falta el secreto");
    expect(() => leerCuentaServicio("{no es json")).toThrow("no es JSON válido");
    expect(() => leerCuentaServicio("%%%")).toThrow("ni Base64");
    expect(() => leerCuentaServicio(JSON.stringify({ project_id: "x" }))).toThrow(
      "no es una cuenta de servicio válida",
    );
  });
});
