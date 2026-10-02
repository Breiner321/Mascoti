import { describe, expect, it } from "vitest";

import { validarRegistro } from "../src/auth/validacion";

describe("validarRegistro (RF-01)", () => {
  it("acepta un dueño", () => {
    expect(validarRegistro({ role: "dueno" })).toEqual({ role: "dueno" });
  });

  it("rechaza un rol desconocido", () => {
    expect(() => validarRegistro({ role: "admin" })).toThrow();
    expect(() => validarRegistro(null)).toThrow();
  });

  it("valida los datos de la clínica", () => {
    const base = { nombre: "Vet Norte", telefono: "3001234567", direccion: "Calle 1" };
    expect(validarRegistro({ role: "clinica", clinica: base })).toEqual({
      role: "clinica",
      clinica: { ...base, lat: null, lng: null },
    });
    expect(() => validarRegistro({ role: "clinica", clinica: { ...base, nombre: "ab" } })).toThrow();
    expect(() => validarRegistro({ role: "clinica", clinica: { ...base, telefono: "123" } })).toThrow();
    expect(() => validarRegistro({ role: "clinica", clinica: { ...base, direccion: " " } })).toThrow();
    expect(() => validarRegistro({ role: "clinica" })).toThrow();
  });
});
