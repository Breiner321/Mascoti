import { beforeEach, describe, expect, it } from "vitest";

import { ErrorFuncion } from "../../supabase/functions/_shared/errores.ts";
import {
  areaDeCuadro,
  CIUDADES,
  consultaOverpass,
  cuadrosAlrededor,
  cuadrosDe,
  type DependenciasOsm,
  type DependenciasPrecarga,
  type EntradaCache,
  leerOverpass,
  MENSAJE_ACERCA,
  MENSAJE_NO_DISPONIBLE,
  normalizarTelefono,
  precargarVeterinarias,
  validarArea,
  type VeterinariaOsm,
  veterinariasEnArea,
} from "../../supabase/functions/_shared/veterinarias_osm.ts";

/** Respuesta de Overpass con un nodo, un edificio (con centro) y datos raros. */
const RESPUESTA = {
  elements: [
    {
      type: "node", id: 1, lat: 4.651, lon: -74.061,
      tags: {
        amenity: "veterinary", name: "Veterinaria Patitas", "addr:street": "Calle 72",
        "addr:housenumber": "10-20", "addr:city": "Bogotá", phone: "+57 300 123 4567; 601 555 0000",
        opening_hours: "Mo-Fr 08:00-18:00", website: "https://patitas.co",
      },
    },
    {
      type: "way", id: 2, center: { lat: 4.652, lon: -74.062 },
      tags: { amenity: "veterinary", brand: "Petcenter", "contact:phone": "601-555-1234" },
    },
    { type: "node", id: 3, lat: 4.653, lon: -74.063, tags: { amenity: "veterinary", phone: "llamar" } },
    { type: "node", id: 1, lat: 4.651, lon: -74.061, tags: { name: "Repetida" } },
    { type: "relation", id: 4, tags: { name: "Sin coordenadas" } },
  ],
};

describe("lectura de Overpass", () => {
  it("nodos y edificios, dirección, teléfono, horario y sin repetir", () => {
    const vets = leerOverpass(RESPUESTA);
    expect(vets.map((v) => v.osmId)).toEqual(["node/1", "way/2", "node/3"]);
    expect(vets[0]).toEqual({
      osmId: "node/1",
      nombre: "Repetida", // el último con el mismo id gana
      lat: 4.651,
      lng: -74.061,
    });
    expect(leerOverpass({ elements: [RESPUESTA.elements[0]] })[0]).toEqual({
      osmId: "node/1",
      nombre: "Veterinaria Patitas",
      lat: 4.651,
      lng: -74.061,
      direccion: "Calle 72 # 10-20, Bogotá",
      telefono: "+573001234567",
      horario: "Mo-Fr 08:00-18:00",
      sitioWeb: "https://patitas.co",
    });
    expect(vets[1]).toMatchObject({ nombre: "Petcenter", lat: 4.652, telefono: "6015551234" });
    expect(vets[2]).toEqual({ osmId: "node/3", nombre: "Veterinaria", lat: 4.653, lng: -74.063 });
    expect(leerOverpass(null)).toEqual([]);
  });

  it("teléfonos", () => {
    expect(normalizarTelefono("(601) 555-1234")).toBe("6015551234");
    expect(normalizarTelefono("abc")).toBeUndefined();
    expect(normalizarTelefono(undefined)).toBeUndefined();
  });
});

describe("área y cuadros", () => {
  const bogota = { sur: 4.60, oeste: -74.10, norte: 4.70, este: -74.00 };

  it("valida el área y rechaza una muy grande", () => {
    expect(validarArea(bogota)).toEqual(bogota);
    for (const malo of [null, {}, { ...bogota, sur: 5 }, { ...bogota, este: "x" }, { ...bogota, norte: 95 }]) {
      expect(() => validarArea(malo)).toThrow(ErrorFuncion);
    }
    expect(() => validarArea({ sur: 4, oeste: -75, norte: 4.5, este: -74 })).toThrow(MENSAJE_ACERCA);
  });

  it("cuadros de 0.05° que cubren el área (también con coordenadas negativas)", () => {
    const cuadros = cuadrosDe(bogota);
    expect(cuadros).toHaveLength(3 * 3);
    expect(cuadros).toContain("92_-1482");
    const a = areaDeCuadro("92_-1482");
    expect(a.sur).toBeCloseTo(4.6);
    expect(a.oeste).toBeCloseTo(-74.1);
  });

  it("consulta Overpass QL", () => {
    expect(consultaOverpass(bogota)).toBe(
      '[out:json][timeout:45];nwr["amenity"="veterinary"](4.60000,-74.10000,4.70000,-74.00000);out center tags;',
    );
  });
});

describe("veterinariasEnArea (Edge Function)", () => {
  const AHORA = new Date("2026-11-01T15:00:00Z");
  const area = { sur: 4.645, oeste: -74.065, norte: 4.655, este: -74.055 };
  let cache: Map<string, EntradaCache>;
  let consultas: string[];
  let intentos: string[];
  let permitido: boolean;
  let guardado: Map<string, VeterinariaOsm[]> | null;
  let pendientes: string[];
  let deps: DependenciasOsm;

  beforeEach(() => {
    cache = new Map();
    consultas = [];
    intentos = [];
    permitido = true;
    guardado = null;
    pendientes = [];
    deps = {
      verificarToken: async (t) => {
        if (t !== "ok") throw new Error("token");
        return { uid: "ana" };
      },
      registrarConsulta: async (uid) => {
        intentos.push(uid);
        return { permitido, reintentarEnSegundos: permitido ? 0 : 90 };
      },
      leerCache: async (cuadros) => new Map([...cache].filter(([c]) => cuadros.includes(c))),
      guardarCache: async (e) => {
        guardado = e;
      },
      marcarPendientes: async (c) => {
        pendientes.push(...c);
      },
      consultarOverpass: async (q) => {
        consultas.push(q);
        return RESPUESTA;
      },
      ahora: () => AHORA,
    };
  });

  it("sin caché consulta Overpass una vez, guarda cada cuadro y filtra al área", async () => {
    const r = await veterinariasEnArea(deps, "Bearer ok", area);
    expect(consultas).toHaveLength(1);
    expect(intentos).toEqual(["ana"]);
    expect(r.veterinarias.map((v) => v.osmId).sort()).toEqual(["node/1", "node/3", "way/2"]);
    // Se guardan todos los cuadros consultados, también los vacíos.
    expect([...guardado!.keys()].sort()).toEqual(cuadrosDe(area).sort());
  });

  it("con caché vigente no consulta Overpass ni cuenta para el límite", async () => {
    for (const c of cuadrosDe(area)) {
      cache.set(c, { datos: [], actualizado: new Date(AHORA.getTime() - 60 * 60 * 1000) });
    }
    cache.set(cuadrosDe(area)[0], {
      datos: [{ osmId: "node/9", nombre: "En caché", lat: 4.65, lng: -74.06 }],
      actualizado: new Date(AHORA.getTime() - 60 * 60 * 1000),
    });
    const r = await veterinariasEnArea(deps, "Bearer ok", area);
    expect(consultas).toHaveLength(0);
    expect(intentos).toHaveLength(0);
    expect(r.veterinarias.map((v) => v.nombre)).toEqual(["En caché"]);
  });

  it("la caché vieja se sirve sin esperar a Overpass (la renueva la precarga)", async () => {
    for (const c of cuadrosDe(area)) {
      cache.set(c, { datos: [], actualizado: new Date(AHORA.getTime() - 5 * 24 * 60 * 60 * 1000) });
    }
    await veterinariasEnArea(deps, "Bearer ok", area);
    expect(consultas).toHaveLength(0);
  });

  it("un cuadro pendiente se vuelve a pedir", async () => {
    for (const c of cuadrosDe(area)) {
      cache.set(c, { datos: [], actualizado: AHORA, pendiente: true });
    }
    const r = await veterinariasEnArea(deps, "Bearer ok", area);
    expect(consultas).toHaveLength(1);
    expect(r.veterinarias).toHaveLength(3);
  });

  it("si Overpass falla sin caché: marca pendientes y responde el error", async () => {
    deps.consultarOverpass = async () => {
      throw new Error("timeout");
    };
    const e = await veterinariasEnArea(deps, "Bearer ok", area).catch((x) => x);
    expect(e).toBeInstanceOf(ErrorFuncion);
    expect(e.codigo).toBe("internal");
    expect(e.message).toBe(MENSAJE_NO_DISPONIBLE);
    expect(pendientes.sort()).toEqual(cuadrosDe(area).sort());
  });

  it("si Overpass falla con parte en caché: responde lo que hay, incompleto", async () => {
    const [primero, ...resto] = cuadrosDe(area);
    cache.set(primero, {
      datos: [{ osmId: "node/9", nombre: "En caché", lat: 4.65, lng: -74.06 }],
      actualizado: AHORA,
    });
    deps.consultarOverpass = async () => {
      throw new Error("502");
    };
    const r = await veterinariasEnArea(deps, "Bearer ok", area);
    expect(r.incompleto).toBe(true);
    expect(r.veterinarias.map((v) => v.nombre)).toEqual(["En caché"]);
    expect(pendientes.sort()).toEqual(resto.sort());
  });

  it("límite por usuario, sesión y área muy grande", async () => {
    permitido = false;
    const e = await veterinariasEnArea(deps, "Bearer ok", area).catch((x) => x);
    expect(e).toBeInstanceOf(ErrorFuncion);
    expect(e.codigo).toBe("resource-exhausted");
    expect(e.message).toBe("Muchas búsquedas seguidas. Intenta de nuevo en 2 minutos.");
    expect(consultas).toHaveLength(0);

    expect((await veterinariasEnArea(deps, null, area).catch((x) => x)).codigo).toBe("unauthenticated");
    expect((await veterinariasEnArea(deps, "Bearer malo", area).catch((x) => x)).codigo).toBe("unauthenticated");
    const lejos = { sur: 4, oeste: -75, norte: 4.5, este: -74 };
    expect((await veterinariasEnArea(deps, "Bearer ok", lejos).catch((x) => x)).message).toBe(MENSAJE_ACERCA);
  });

  it("si no se puede guardar la caché, igual responde", async () => {
    deps.guardarCache = async () => {
      throw new Error("postgres caído");
    };
    const r = await veterinariasEnArea(deps, "Bearer ok", area);
    expect(r.veterinarias).toHaveLength(3);
  });
});

describe("precarga (tarea programada)", () => {
  const AHORA = new Date("2026-11-01T15:00:00Z");
  const HORA = 60 * 60 * 1000;
  let cache: Map<string, EntradaCache>;
  let consultas: string[];
  let guardados: string[];
  let reloj: number;
  let deps: DependenciasPrecarga;

  beforeEach(() => {
    cache = new Map();
    consultas = [];
    guardados = [];
    reloj = AHORA.getTime();
    deps = {
      clinicas: async () => [],
      cuadrosPorRenovar: async (antes) =>
        [...cache].filter(([, e]) => e.pendiente || e.actualizado < antes).map(([c]) => c),
      leerCache: async (cuadros) => new Map([...cache].filter(([c]) => cuadros.includes(c))),
      guardarCache: async (e) => {
        guardados.push(...e.keys());
      },
      consultarOverpass: async (q) => {
        consultas.push(q);
        return RESPUESTA;
      },
      ahora: () => new Date(reloj),
    };
  });

  /** Todos los cuadros de las ciudades, recién actualizados. */
  function ciudadesAlDia() {
    for (const p of CIUDADES) {
      for (const c of cuadrosAlrededor(p)) cache.set(c, { datos: [], actualizado: AHORA });
    }
  }

  it("llena los alrededores de las clínicas y las ciudades, por bloques", async () => {
    const r = await precargarVeterinarias(deps);
    const esperados = new Set(CIUDADES.flatMap((p) => cuadrosAlrededor(p)));
    expect(r.porRenovar).toBe(esperados.size);
    expect(new Set(guardados)).toEqual(esperados);
    // Una consulta por bloque de 4×4 cuadros, no una por cuadro.
    expect(r.consultas).toBe(consultas.length);
    expect(consultas.length).toBeLessThan(esperados.size / 3);
    expect(consultas[0]).toContain("[timeout:90]");
    expect(r.quedan).toBe(0);
  });

  it("no repite lo vigente; renueva lo vencido y lo pendiente primero", async () => {
    ciudadesAlDia();
    const clinica = { lat: 2.5, lng: -76.6 };
    deps.clinicas = async () => [clinica];
    for (const c of cuadrosAlrededor(clinica)) cache.set(c, { datos: [], actualizado: AHORA });
    cache.set("1_1", { datos: [], actualizado: new Date(AHORA.getTime() - 21 * HORA) });
    cache.set("9_9", { datos: [], actualizado: AHORA, pendiente: true });

    const r = await precargarVeterinarias(deps);
    expect(r.porRenovar).toBe(2);
    expect(guardados).toEqual(["9_9", "1_1"]);
  });

  it("para al acabarse el tiempo y deja el resto para la próxima vuelta", async () => {
    deps.consultarOverpass = async (q) => {
      consultas.push(q);
      reloj += 60_000;
      return RESPUESTA;
    };
    const r = await precargarVeterinarias(deps, 110_000);
    expect(r.consultas).toBe(2);
    expect(r.quedan).toBe(r.porRenovar - r.actualizados);
    expect(r.quedan).toBeGreaterThan(0);
  });

  it("si Overpass está caído, para tras 3 fallos seguidos", async () => {
    deps.consultarOverpass = async (q) => {
      consultas.push(q);
      throw new Error("502");
    };
    deps.clinicas = async () => {
      throw new Error("firestore");
    };
    const r = await precargarVeterinarias(deps);
    expect(consultas).toHaveLength(3);
    expect(r.errores).toBe(3);
    expect(r.actualizados).toBe(0);
    expect(r.quedan).toBe(r.porRenovar);
  });
});
