import { beforeEach, describe, expect, it } from "vitest";

import {
  type DependenciasAdjuntosChat,
  gestionarAdjuntoChat,
  MENSAJE_TAMANO,
  MENSAJE_TIPO,
  nombreSeguro,
  SEGUNDOS_LECTURA,
} from "../../supabase/functions/_shared/adjuntos_chat.ts";
import { ErrorFuncion } from "../../supabase/functions/_shared/errores.ts";

describe("gestionarAdjuntoChat (Edge Function adjuntos-chat, RF-16)", () => {
  let docs: Record<string, Record<string, unknown>>;
  let subidas: string[];
  let deps: DependenciasAdjuntosChat;

  beforeEach(() => {
    docs = {
      "users/ana": { role: "dueno", estado: "activo" },
      "users/vet": { role: "clinica", estado: "activo", clinicId: "c1" },
      "users/beto": { role: "dueno", estado: "activo" },
      "users/susp": { role: "dueno", estado: "suspendido" },
      "chats/ana_c1": { participantes: ["ana", "vet"] },
      "chats/susp_c1": { participantes: ["susp", "vet"] },
    };
    subidas = [];
    deps = {
      verificarToken: async (token) => {
        if (!token.startsWith("token-")) throw new Error("firma");
        return { uid: token.slice("token-".length) };
      },
      leer: async (ruta) => docs[ruta] ?? null,
      firmarSubida: async (ruta) => {
        subidas.push(ruta);
        return { token: "tok-subida" };
      },
      firmarLectura: async (ruta, segundos) => `https://firmado/${ruta}?s=${segundos}`,
      nuevoId: () => "6f1c2d3e-uuid",
    };
  });

  const pedir = (uid: string, cuerpo: Record<string, unknown>) =>
    gestionarAdjuntoChat(deps, `Bearer token-${uid}`, { chatId: "ana_c1", ...cuerpo });

  const falla = async (p: Promise<unknown>) => {
    const e = await p.then(() => null, (x) => x);
    expect(e).toBeInstanceOf(ErrorFuncion);
    return e as ErrorFuncion;
  };

  it("subir: ruta en la carpeta del chat con uuid y nombre seguro", async () => {
    const r = await pedir("ana", { accion: "subir", nombreArchivo: "Exámen de sangre.PDF", tamanoBytes: 2048 });
    expect(r).toEqual({
      path: "ana_c1/6f1c2d3e-uuid-Examen_de_sangre.PDF",
      token: "tok-subida",
      tipo: "pdf",
      nombre: "Exámen de sangre.PDF",
    });
    const foto = await pedir("vet", { accion: "subir", nombreArchivo: "rx.jpeg", tamanoBytes: 10 * 1024 * 1024 });
    expect(foto).toMatchObject({ tipo: "imagen", path: "ana_c1/6f1c2d3e-uuid-rx.jpeg" });
    expect(subidas).toHaveLength(2);
  });

  it("subir: solo JPG, PNG o PDF de máximo 10 MB", async () => {
    for (const nombreArchivo of ["video.mp4", "documento.docx", "sin_extension", "pdf"]) {
      const e = await falla(pedir("ana", { accion: "subir", nombreArchivo, tamanoBytes: 10 }));
      expect(e.codigo).toBe("invalid-argument");
      expect(e.message).toBe(MENSAJE_TIPO);
    }
    const grande = await falla(pedir("ana", {
      accion: "subir", nombreArchivo: "rx.png", tamanoBytes: 10 * 1024 * 1024 + 1,
    }));
    expect(grande.message).toBe(MENSAJE_TAMANO);
    expect((await falla(pedir("ana", { accion: "subir", nombreArchivo: "rx.png" }))).codigo)
      .toBe("invalid-argument");
    expect((await falla(pedir("ana", { accion: "subir", nombreArchivo: "rx.png", tamanoBytes: 0 }))).codigo)
      .toBe("invalid-argument");
    expect(subidas).toEqual([]);
  });

  it("leer: enlace de 15 min, solo de la carpeta del chat", async () => {
    const r = await pedir("vet", { accion: "leer", path: "ana_c1/6f1c-rx.png" });
    expect(r).toEqual({ url: `https://firmado/ana_c1/6f1c-rx.png?s=${15 * 60}`, expiraEnSegundos: SEGUNDOS_LECTURA });
    for (const path of ["otro_c2/x.png", "ana_c1/sub/x.png", "ana_c1/../otro_c2/x.png", "ana_c1/", ""]) {
      expect((await falla(pedir("ana", { accion: "leer", path }))).codigo).toBe("invalid-argument");
    }
  });

  it("solo participantes activos con sesión", async () => {
    expect((await falla(pedir("beto", { accion: "leer", path: "ana_c1/x.png" }))).codigo)
      .toBe("permission-denied");
    expect((await falla(pedir("beto", { accion: "subir", nombreArchivo: "x.png", tamanoBytes: 1 }))).codigo)
      .toBe("permission-denied");
    expect((await falla(gestionarAdjuntoChat(deps, "Bearer token-susp",
      { chatId: "susp_c1", accion: "leer", path: "susp_c1/x.png" }))).codigo).toBe("permission-denied");
    expect((await falla(pedir("ana", { chatId: "nadie_c9", accion: "leer", path: "nadie_c9/x.png" }))).codigo)
      .toBe("permission-denied");
    expect((await falla(gestionarAdjuntoChat(deps, null, { chatId: "ana_c1" }))).codigo).toBe("unauthenticated");
    expect((await falla(gestionarAdjuntoChat(deps, "Bearer malo", { chatId: "ana_c1" }))).codigo)
      .toBe("unauthenticated");
    expect((await falla(pedir("ana", { chatId: "../x" }))).codigo).toBe("invalid-argument");
    expect((await falla(pedir("ana", { accion: "borrar" }))).codigo).toBe("invalid-argument");
  });

  it("nombre seguro: sin carpetas ni caracteres raros, máximo 80 con la extensión", () => {
    expect(nombreSeguro("../../etc/passwd")).toBe("passwd");
    expect(nombreSeguro("C:\\fotos\\Luña 1.jpg")).toBe("Luna_1.jpg");
    expect(nombreSeguro(".oculto.png")).toBe("oculto.png");
    expect(nombreSeguro("###")).toBe("archivo");
    const largo = nombreSeguro(`${"a".repeat(200)}.pdf`);
    expect(largo).toHaveLength(80);
    expect(largo.endsWith(".pdf")).toBe(true);
  });
});
