import { describe, expect, it } from "vitest";

import { accionSuspension } from "../src/auth/sincronizarSuspension";

describe("accionSuspension (RF-02)", () => {
  it("deshabilita al suspender", () => {
    expect(accionSuspension("activo", "suspendido")).toBe("deshabilitar");
  });

  it("habilita al reactivar", () => {
    expect(accionSuspension("suspendido", "activo")).toBe("habilitar");
  });

  it("no hace nada si el estado no cambia o es otro campo", () => {
    expect(accionSuspension("activo", "activo")).toBeNull();
    expect(accionSuspension("suspendido", "suspendido")).toBeNull();
    expect(accionSuspension(undefined, "activo")).toBeNull();
  });
});
