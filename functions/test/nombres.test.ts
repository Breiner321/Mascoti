import { describe, expect, it } from "vitest";

import { nombreVisible } from "../../supabase/functions/_shared/nombres.ts";

describe("nombreVisible (Cambio 1)", () => {
  it("nombre del dueño → nombre de Google → Usuario, nunca el correo", () => {
    expect(nombreVisible({ nombre: " Ana Pérez ", displayName: "ana.g", email: "a@b.co" })).toBe("Ana Pérez");
    expect(nombreVisible({ nombre: "", displayName: "Ana G", email: "a@b.co" })).toBe("Ana G");
    expect(nombreVisible({ displayName: "  ", email: "a@b.co" })).toBe("Usuario");
    expect(nombreVisible(null)).toBe("Usuario");
    expect(nombreVisible({ nombre: 3 })).toBe("Usuario");
  });
});
